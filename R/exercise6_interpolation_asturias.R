# exercise6_interpolation_asturias.R
# Ejercicio 6 - interpolación espacial de precipitación en Asturias (2007)
#
# Pasos:
#   1. Extraer datos de estaciones en Asturias para 2007
#   2. Obtener límite de Asturias (mapSpain) y crear grid 500m
#   3. Interpolar precipitación cada día con IDW leave-one-out
#   4. Calcular bias medio (predicho - observado)
#   5. Comparar con datos oficiales interpolados
#   6. ¿Cuál tiene menos bias?
#
# Datos oficiales: un parquet por día → YYYYMMDD.parquet, geom en EPSG:25830

library(sf)
library(terra)
library(duckdb)
library(DBI)
library(dplyr)
library(purrr)
library(gstat)
library(mapSpain)
library(here)

parquet_url  <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
official_base <- "https://data-emf.creaf.cat/public/parquet/daily_interpolated_meteo/"
local_file   <- here::here("data", "meteo_stations_2000_2024.parquet")

if (!file.exists(local_file)) {
  message("Descargando parquet de estaciones...")
  download.file(parquet_url, destfile = local_file, mode = "wb", quiet = FALSE)
}

# ============================================================
# 1. Datos de estaciones Asturias 2007
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

cat("Estaciones únicas:", n_distinct(asturias_data$stationID), "\n")
cat("Días disponibles:", n_distinct(asturias_data$dates), "\n")

# ============================================================
# 2. Límite de Asturias y grid 500m
# ============================================================

asturias_prov <- mapSpain::esp_get_prov(prov = "Asturias") |>
  st_transform(25830)

grid_rast <- terra::rast(terra::ext(terra::vect(asturias_prov)),
                          res = 500, crs = "EPSG:25830")
grid_pts  <- as.data.frame(grid_rast, xy = TRUE) |>
  st_as_sf(coords = c("x", "y"), crs = 25830)
grid_pts  <- grid_pts[asturias_prov, ]

cat("Puntos del grid:", nrow(grid_pts), "\n")

# ============================================================
# 3. IDW leave-one-out: bias de mi interpolación
# ============================================================

compute_loo_bias <- function(day_str, asturias_data) {
  day_data <- asturias_data |>
    filter(dates == day_str, !is.na(Precipitation), !is.na(lon), !is.na(lat))
  if (nrow(day_data) < 4)
    return(tibble(dates = day_str, mean_bias = NA_real_, n_stations = nrow(day_data)))

  stations_sf <- st_as_sf(day_data, coords = c("lon", "lat"), crs = 4326) |>
    st_transform(25830)

  predicted <- map_dbl(seq_len(nrow(stations_sf)), function(i) {
    tryCatch({
      idw_res <- gstat::idw(Precipitation ~ 1, stations_sf[-i, ],
                             stations_sf[i, , drop = FALSE],
                             idp = 2, debug.level = 0)
      idw_res$var1.pred
    }, error = function(e) NA_real_)
  })

  tibble(
    dates      = day_str,
    mean_bias  = mean(predicted - stations_sf$Precipitation, na.rm = TRUE),
    n_stations = nrow(stations_sf)
  )
}

dates_2007 <- sort(unique(asturias_data$dates))
message("Interpolando ", length(dates_2007), " días (LOO IDW)...")

bias_results <- purrr::map(dates_2007, compute_loo_bias,
                            asturias_data = asturias_data, .progress = TRUE)
bias_df <- bind_rows(bias_results)

mean_bias_mine <- mean(bias_df$mean_bias, na.rm = TRUE)
cat("Bias medio mi interpolación IDW (2007):", round(mean_bias_mine, 3), "mm/día\n")
saveRDS(bias_df, here::here("results", "exercise6_loo_bias_2007.rds"))

# ============================================================
# 4. Datos oficiales: extraer en ubicaciones de estaciones
# ============================================================
# archivos individuales: YYYYMMDD.parquet, geom en EPSG:25830

# 15 días de muestra
set.seed(9473)
sample_dates <- sort(sample(dates_2007, 15))
cat("\n15 días de muestra:\n"); print(sample_dates)

# preparo estaciones en EPSG:25830 para el join espacial
stations_unique <- asturias_data |>
  distinct(stationID, lon, lat) |>
  filter(!is.na(lon), !is.na(lat)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  st_transform(25830)

# bbox de Asturias en EPSG:25830 (para filtrar el grid oficial)
asturias_bbox <- st_bbox(asturias_prov)

get_official_bias_for_day <- function(day_str, stations_sf, obs_data, bbox) {
  # construyo la URL con formato YYYYMMDD
  day_url <- paste0(official_base, format(as.Date(day_str), "%Y%m%d"), ".parquet")

  tryCatch({
    con <- dbConnect(duckdb())
    dbExecute(con, "LOAD httpfs; LOAD spatial;")

    # leo solo los puntos dentro del bbox de Asturias
    official_day <- dbGetQuery(con, paste0(
      "SELECT Precipitation,
              ST_X(geom) AS x_etrs, ST_Y(geom) AS y_etrs
       FROM read_parquet('", day_url, "')
       WHERE ST_Within(geom, ST_MakeEnvelope(",
         bbox["xmin"], ", ", bbox["ymin"], ", ",
         bbox["xmax"], ", ", bbox["ymax"], "))"
    ))
    dbDisconnect(con, shutdown = TRUE)

    if (nrow(official_day) == 0) return(NULL)

    # convierto a sf
    official_sf <- st_as_sf(official_day,
                             coords = c("x_etrs", "y_etrs"), crs = 25830)

    # para cada estación, encuentro el pixel oficial más cercano
    nearest_idx <- st_nearest_feature(stations_sf, official_sf)
    official_prec <- official_sf$Precipitation[nearest_idx]

    # combino con observaciones de ese día
    obs_day <- obs_data |>
      filter(dates == day_str, !is.na(Precipitation)) |>
      arrange(stationID)
    stations_in_obs <- stations_sf |>
      filter(stationID %in% obs_day$stationID)

    if (nrow(stations_in_obs) == 0) return(NULL)

    nearest_idx2 <- st_nearest_feature(stations_in_obs, official_sf)
    official_at_stations <- official_sf$Precipitation[nearest_idx2]

    tibble(
      dates         = day_str,
      mean_bias_off = mean(official_at_stations - obs_day$Precipitation, na.rm = TRUE),
      n_stations    = nrow(stations_in_obs)
    )
  }, error = function(e) {
    cat("Error en día", day_str, ":", conditionMessage(e), "\n")
    NULL
  })
}

message("Extrayendo datos oficiales para 15 días de muestra...")
official_bias_list <- purrr::map(
  sample_dates,
  get_official_bias_for_day,
  stations_sf = stations_unique,
  obs_data    = asturias_data,
  bbox        = asturias_bbox,
  .progress   = TRUE
)

official_bias_df  <- bind_rows(official_bias_list)
mean_bias_official <- mean(official_bias_df$mean_bias_off, na.rm = TRUE)

cat("\n=== Resultados finales ===\n")
cat("Días con datos oficiales recuperados:", nrow(official_bias_df), "de 15\n")
cat("Bias medio mi interpolación IDW  :", round(mean_bias_mine, 3), "mm/día\n")
cat("Bias medio interpolación oficial :", round(mean_bias_official, 3), "mm/día\n")

saveRDS(official_bias_df, here::here("results", "exercise6_official_bias_15days.rds"))

# ============================================================
# 5. Conclusión: ¿cuál tiene menos bias?
# ============================================================

# La interpolación con menos bias (más cercana a cero) es:
if (abs(mean_bias_official) < abs(mean_bias_mine)) {
  cat("La interpolación OFICIAL tiene menos bias en valor absoluto.\n")
  cat("Esto tiene sentido: usa un grid denso de toda España con múltiples\n")
  cat("redes de observación y métodos de interpolación más sofisticados.\n")
  cat("Mi IDW con pocas estaciones locales es una aproximación razonable\n")
  cat("pero no puede competir con un producto de análisis oficial.\n")
} else {
  cat("Mi interpolación IDW tiene menos bias en este caso.\n")
  cat("Posiblemente el bias del oficial refleja el método distinto:\n")
  cat("el oficial interpola a un grid y yo evalúo en las propias estaciones,\n")
  cat("lo que podría sesgar la comparación.\n")
}
