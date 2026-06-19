# exercise5_municipality_purrr.R
# Ejercicio 5 - procesar datos meteorológicos 2020 para todos los municipios
# usando purrr::map y luego en paralelo con furrr/mirai
#
# Estrategia: dividir por provincias (50), procesar cada una con map(),
# luego join espacial con municipios de mapSpain para nivel municipal.

library(duckdb)
library(DBI)
library(arrow)
library(sf)
library(purrr)
library(furrr)
library(future)
library(mirai)
library(dplyr)
library(mapSpain)
library(bench)
library(here)

parquet_url <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
local_file  <- here::here("data", "meteo_stations_2000_2024.parquet")

# descargo si no está
if (!file.exists(local_file)) {
  message("Descargando parquet...")
  download.file(parquet_url, destfile = local_file, mode = "wb", quiet = FALSE)
}

# lista de provincias en el archivo
con <- dbConnect(duckdb())
provinces <- dbGetQuery(con,
  paste0("SELECT DISTINCT station_province
          FROM read_parquet('", local_file, "')
          WHERE station_province IS NOT NULL
          ORDER BY station_province")
)$station_province
dbDisconnect(con, shutdown = TRUE)

cat("Provincias encontradas:", length(provinces), "\n")

# función que procesa una provincia: datos 2020, resumen diario por estación
# lf se pasa explícitamente para que funcione también en workers de mirai
process_province <- function(prov, lf) {
  con <- dbConnect(duckdb())
  result <- dbGetQuery(con, paste0(
    "SELECT dates, stationID, station_province,
            AVG(MaxTemperature) AS mean_tmax,
            AVG(MinTemperature) AS mean_tmin,
            AVG(MeanTemperature) AS mean_tmean,
            AVG(MeanRelativeHumidity) AS mean_hr,
            SUM(Precipitation) AS total_pcp
     FROM read_parquet('", lf, "')
     WHERE station_province = '", prov, "' AND year = 2020
     GROUP BY dates, stationID, station_province
     ORDER BY stationID, dates"
  ))
  dbDisconnect(con, shutdown = TRUE)
  result
}

# versión secuencial con purrr::map
message("purrr::map secuencial...")
t_seq <- system.time({
  results_seq <- purrr::map(provinces, process_province, lf = local_file)
})
data_2020 <- bind_rows(results_seq)
cat("Filas totales:", nrow(data_2020), "| Tiempo:", round(t_seq["elapsed"], 1), "s\n")

# versión paralela con furrr
message("furrr::future_map...")
t_furrr <- system.time({
  plan(multisession, workers = parallel::detectCores())
  results_furrr <- future_map(provinces, process_province, lf = local_file)
  plan(sequential)
})
cat("furrr:", round(t_furrr["elapsed"], 1), "s\n")

# versión paralela con mirai
# local_file se pasa como argumento (mirai no copia el entorno global)
message("mirai_map...")
t_mirai <- system.time({
  daemons(parallel::detectCores())
  results_mirai <- mirai_map(provinces, process_province, lf = local_file)[]
  daemons(0)
})
cat("mirai:", round(t_mirai["elapsed"], 1), "s\n")

cat("\nResumen de tiempos:\n")
cat("  secuencial:", round(t_seq["elapsed"], 1), "s\n")
cat("  furrr     :", round(t_furrr["elapsed"], 1), "s\n")
cat("  mirai     :", round(t_mirai["elapsed"], 1), "s\n")

# ¿beneficio de paralelizar?
# El cuello de botella aquí es la lectura del disco (I/O), no el cómputo.
# Si el disco es SSD y soporta lecturas paralelas, furrr/mirai pueden ayudar.
# Si el parquet estuviera en remoto, las descargas paralelas serían muy beneficiosas.

# join espacial para nivel municipal
message("Join espacial con municipios...")

# límites municipales (mapSpain)
municipios <- mapSpain::esp_get_munic() |>
  st_transform(4326) |>
  select(LAU_CODE, NAME_LAU, cpro)

# coordenadas de estaciones desde el campo geom
# necesita la extensión spatial de duckdb
con <- dbConnect(duckdb())
dbExecute(con, "INSTALL spatial; LOAD spatial;")
stations_meta <- dbGetQuery(con, paste0(
  "SELECT DISTINCT stationID, station_province,
          ST_X(geom) AS lon, ST_Y(geom) AS lat
   FROM read_parquet('", local_file, "')
   WHERE year = 2020 AND geom IS NOT NULL"
))
dbDisconnect(con, shutdown = TRUE)

stations_sf <- st_as_sf(stations_meta,
                        coords = c("lon", "lat"),
                        crs = 4326)

# asignación estación → municipio (point-in-polygon)
stations_munic <- st_join(stations_sf, municipios, join = st_within)
cat("Estaciones asignadas:", sum(!is.na(stations_munic$LAU_CODE)), "/", nrow(stations_sf), "\n")

# join con los datos y agrego por municipio-día
daily_by_munic <- data_2020 |>
  left_join(st_drop_geometry(stations_munic), by = c("stationID", "station_province")) |>
  filter(!is.na(LAU_CODE)) |>
  group_by(LAU_CODE, NAME_LAU, dates) |>
  summarise(
    mean_tmax  = mean(mean_tmax,  na.rm = TRUE),
    mean_tmin  = mean(mean_tmin,  na.rm = TRUE),
    mean_tmean = mean(mean_tmean, na.rm = TRUE),
    mean_hr    = mean(mean_hr,    na.rm = TRUE),
    total_pcp  = mean(total_pcp,  na.rm = TRUE),
    n_stations = n(),
    .groups = "drop"
  )

cat("Municipios con datos:", n_distinct(daily_by_munic$LAU_CODE), "\n")
cat("Filas resultado:", nrow(daily_by_munic), "\n")
print(head(daily_by_munic))

arrow::write_parquet(daily_by_munic,
  here::here("data", "daily_summary_municipalities_2020.parquet"))
message("Guardado: data/daily_summary_municipalities_2020.parquet")
