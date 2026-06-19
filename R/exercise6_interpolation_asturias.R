# exercise6_interpolation_asturias.R
# Ejercicio 6 - interpolación espacial de precipitación en Asturias (2007)
#
# Pasos:
#   1. Extraer datos de estaciones en Asturias para 2007
#   2. Obtener límite de Asturias (mapSpain)
#   3. Crear grid de 500m
#   4. Interpolar precipitación cada día con IDW (gstat)
#   5. Calcular bias medio (predicho - observado, leave-one-out)
#   6. Comparar con los datos oficiales interpolados
#   7. ¿Cuál tiene menos bias, el mío o el oficial?

library(sf)
library(terra)
library(duckdb)
library(DBI)
library(dplyr)
library(purrr)
library(gstat)
library(mapSpain)
library(arrow)
library(here)

parquet_url  <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
official_url <- "https://data-emf.creaf.cat/public/parquet/daily_interpolated_meteo/"
local_file   <- here::here("data", "meteo_stations_2000_2024.parquet")

# descargo si no está
if (!file.exists(local_file)) {
  message("Descargando parquet de estaciones...")
  download.file(parquet_url, destfile = local_file, mode = "wb", quiet = FALSE)
}

# ============================================================
# 1. Extraer datos Asturias 2007
# ============================================================

con <- dbConnect(duckdb())
dbExecute(con, "INSTALL spatial; LOAD spatial;")

asturias_data <- dbGetQuery(con, paste0(
  "SELECT stationID, station_name, dates,
          ST_X(geom) AS lon, ST_Y(geom) AS lat,
          Precipitation
   FROM read_parquet('", local_file, "')
   WHERE station_province = 'Asturias'
     AND year = 2007
     AND Precipitation IS NOT NULL
   ORDER BY stationID, dates"
))
dbDisconnect(con, shutdown = TRUE)

cat("Estaciones únicas en Asturias 2007:", n_distinct(asturias_data$stationID), "\n")
cat("Días disponibles:", n_distinct(asturias_data$dates), "\n")
print(head(asturias_data))

# ============================================================
# 2. Límite de Asturias y grid 500m
# ============================================================

asturias_prov <- mapSpain::esp_get_prov(prov = "Asturias") |>
  st_transform(25830)  # ETRS89 / UTM zone 30N, unidades en metros

# grid de puntos cada 500m dentro de Asturias
grid_rast <- terra::rast(terra::ext(terra::vect(asturias_prov)),
                          res = 500, crs = "EPSG:25830")
grid_pts  <- as.data.frame(grid_rast, xy = TRUE) |>
  st_as_sf(coords = c("x", "y"), crs = 25830)
# me quedo solo con los puntos dentro de Asturias
grid_pts <- grid_pts[asturias_prov, ]

cat("Puntos del grid dentro de Asturias:", nrow(grid_pts), "\n")

# ============================================================
# 3. Función de interpolación IDW para un día (leave-one-out bias)
# ============================================================

# el bias se calcula como leave-one-out:
# para cada estación, interpolo desde las demás y comparo con observado

compute_loo_bias <- function(day_str, asturias_data, asturias_prov) {
  day_data <- asturias_data |> filter(dates == day_str)

  # necesito al menos 4 estaciones con datos
  day_data <- day_data |> filter(!is.na(Precipitation) & !is.na(lon) & !is.na(lat))
  if (nrow(day_data) < 4) return(tibble(dates = day_str, mean_bias = NA_real_,
                                         n_stations = nrow(day_data)))

  # convierto a sf y proyecto
  stations_sf <- st_as_sf(day_data, coords = c("lon", "lat"), crs = 4326) |>
    st_transform(25830)

  # leave-one-out: predigo en cada estación usando las demás
  predicted <- map_dbl(seq_len(nrow(stations_sf)), function(i) {
    train <- stations_sf[-i, ]
    test  <- stations_sf[i, , drop = FALSE]
    tryCatch({
      idw_res <- gstat::idw(Precipitation ~ 1, train, test,
                             idp = 2, debug.level = 0)
      idw_res$var1.pred
    }, error = function(e) NA_real_)
  })

  bias_vals <- predicted - stations_sf$Precipitation
  tibble(
    dates      = day_str,
    mean_bias  = mean(bias_vals, na.rm = TRUE),
    n_stations = nrow(stations_sf)
  )
}

# ============================================================
# 4. Aplicar sobre todos los días de 2007 con purrr::map
#    (aplico lo aprendido en ejercicio 5)
# ============================================================

dates_2007 <- unique(asturias_data$dates)
cat("Procesando", length(dates_2007), "días con IDW leave-one-out...\n")
message("Esto puede tardar varios minutos")

bias_results <- purrr::map(
  dates_2007,
  compute_loo_bias,
  asturias_data = asturias_data,
  asturias_prov = asturias_prov,
  .progress = TRUE
)

bias_df <- bind_rows(bias_results)

mean_bias_mine <- mean(bias_df$mean_bias, na.rm = TRUE)
cat("\nBias medio de mi interpolación IDW (2007):",
    round(mean_bias_mine, 3), "mm/día\n")

print(summary(bias_df$mean_bias))

# guardo resultados intermedios
saveRDS(bias_df, here::here("results", "exercise6_loo_bias_2007.rds"))

# ============================================================
# 5. Datos oficiales interpolados
# ============================================================

# exploro la estructura del parquet oficial
con <- dbConnect(duckdb())
dbExecute(con, "INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial;")

cat("\n=== Esquema datos oficiales ===\n")
tryCatch({
  schema_off <- dbGetQuery(con, paste0(
    "DESCRIBE SELECT * FROM read_parquet('", official_url, "**') LIMIT 1"))
  print(schema_off)

  sample_off <- dbGetQuery(con, paste0(
    "SELECT * FROM read_parquet('", official_url, "**') LIMIT 3"))
  print(sample_off)
}, error = function(e) {
  cat("Error al leer datos oficiales:", conditionMessage(e), "\n")
  cat("Comprueba que la URL es accesible y el formato del path es correcto.\n")
})
dbDisconnect(con, shutdown = TRUE)

# ============================================================
# 6. Comparar bias en 15 días de muestra
# ============================================================

set.seed(9473)
sample_dates <- sample(dates_2007, 15)
cat("\n15 días de muestra para comparar con datos oficiales:\n")
print(sort(sample_dates))

# extraigo las coordenadas de las estaciones de Asturias (para consultar
# los valores oficiales en esas localizaciones)
stations_asturias <- asturias_data |>
  distinct(stationID, station_name, lon, lat)

# consulta a los datos oficiales en las localizaciones de las estaciones
# (ajustar nombres de columna según el esquema real del archivo oficial)
get_official_at_stations <- function(day_str) {
  tryCatch({
    # leo datos oficiales para ese día filtrado por bbox de Asturias
    # ajustar columnas según esquema verificado arriba
    con <- dbConnect(duckdb())
    dbExecute(con, "LOAD httpfs; LOAD spatial;")
    official_day <- dbGetQuery(con, paste0(
      "SELECT * FROM read_parquet('", official_url, "**')
       WHERE date = '", day_str, "'"
    ))
    dbDisconnect(con, shutdown = TRUE)
    if (nrow(official_day) == 0) return(NULL)

    # hago un join espacial: encuentro el pixel más cercano a cada estación
    # (nombre de columnas a adaptar según esquema)
    official_day
  }, error = function(e) {
    cat("Error en día", day_str, ":", conditionMessage(e), "\n")
    NULL
  })
}

official_samples <- purrr::map(sample_dates, get_official_at_stations)

# calculo bias oficial vs observado (cuando los datos estén disponibles)
# bias_oficial = valor_oficial - valor_observado_en_estacion

# de momento muestro lo que se obtuvo
cat("\nDatos oficiales recuperados para",
    sum(!sapply(official_samples, is.null)), "de 15 días\n")

# ============================================================
# 7. Conclusión: ¿cuál tiene menos bias?
# ============================================================

# en base a los resultados de bias_df (mi IDW):
cat("\n=== Resumen final ===\n")
cat("Bias medio mi interpolación IDW :", round(mean_bias_mine, 3), "mm/día\n")
# cat("Bias medio interpolación oficial:", round(mean_bias_official, 3), "mm/día\n")

# La interpolación oficial probablemente tiene menos bias porque usa métodos
# más sofisticados (kriging con anisotropía, corrección topográfica, etc.)
# y un mayor número de estaciones de distintas redes.
# Mi IDW simple con las estaciones de una sola red da un resultado razonable
# pero suele sobreestimar en zonas con pocas estaciones y subestimar en valles.
