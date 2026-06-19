# exercise2_ourense_benchmark.R
# Ejercicio 2.1 - extraer y resumir datos meteorológicos diarios de Ourense (2020)
# temperaturas, humedad relativa y precipitación
#
# Comparo tres formas de leer/procesar el archivo:
#   A. duckdb leyendo directamente desde la URL
#   B. duckdb leyendo en local (con descarga incluida en el tiempo)
#   C. arrow leyendo en local (con descarga incluida en el tiempo)
#
# Datos: https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet

library(duckdb)
library(DBI)
library(arrow)
library(dplyr)
library(bench)
library(here)

parquet_url <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
local_file  <- here::here("data", "meteo_stations_2000_2024.parquet")

# miro el esquema primero (columnas reales del archivo)
con_explore <- dbConnect(duckdb())
dbExecute(con_explore, "INSTALL httpfs; LOAD httpfs;")
print(dbGetQuery(con_explore,
  paste0("DESCRIBE SELECT * FROM read_parquet('", parquet_url, "') LIMIT 1")))
print(dbGetQuery(con_explore,
  paste0("SELECT * FROM read_parquet('", parquet_url, "') LIMIT 3")))
dbDisconnect(con_explore, shutdown = TRUE)

# Columnas del archivo (verificado):
#   station_province  → nombre de provincia
#   year              → año (integer)
#   dates             → fecha (VARCHAR)
#   stationID         → id de estación
#   MaxTemperature, MinTemperature, MeanTemperature  → temperaturas (°C)
#   MeanRelativeHumidity  → humedad relativa (%)
#   Precipitation         → precipitación (mm)

ourense_sql <- function(src) {
  paste0(
    "SELECT dates, stationID, station_province,
            MaxTemperature, MinTemperature, MeanTemperature,
            MeanRelativeHumidity, Precipitation
     FROM read_parquet('", src, "')
     WHERE station_province = 'Ourense' AND year = 2020
     ORDER BY stationID, dates"
  )
}

# benchmark (tarda bastante por las descargas en B y C)
bm <- bench::mark(

  # A - duckdb remoto, sin descarga
  duckdb_remote = {
    con <- dbConnect(duckdb())
    dbExecute(con, "LOAD httpfs;")
    result <- dbGetQuery(con, ourense_sql(parquet_url))
    dbDisconnect(con, shutdown = TRUE)
    result
  },

  # B - duckdb local, descarga incluida en el tiempo
  duckdb_local = {
    tmp <- tempfile(fileext = ".parquet")
    download.file(parquet_url, destfile = tmp, mode = "wb", quiet = TRUE)
    con <- dbConnect(duckdb())
    result <- dbGetQuery(con, ourense_sql(tmp))
    dbDisconnect(con, shutdown = TRUE)
    file.remove(tmp)
    result
  },

  # C - arrow local, descarga incluida en el tiempo
  arrow_local = {
    tmp <- tempfile(fileext = ".parquet")
    download.file(parquet_url, destfile = tmp, mode = "wb", quiet = TRUE)
    result <- arrow::open_dataset(tmp) |>
      filter(station_province == "Ourense", year == 2020) |>
      select(dates, stationID, station_province,
             MaxTemperature, MinTemperature, MeanTemperature,
             MeanRelativeHumidity, Precipitation) |>
      arrange(stationID, dates) |>
      collect()
    file.remove(tmp)
    result
  },

  iterations = 3,
  check      = FALSE,
  memory     = TRUE
)

print(bm)
print(bm[order(bm$median), c("expression", "median", "mem_alloc")])

saveRDS(bm, here::here("results", "exercise2_benchmark_results.rds"))

# resumen de los datos (si tengo el archivo local)
if (file.exists(local_file)) {
  con <- dbConnect(duckdb())
  resumen <- dbGetQuery(con, paste0(
    "SELECT stationID,
            COUNT(*) AS n_dias,
            ROUND(AVG(MaxTemperature), 2) AS media_tmax,
            ROUND(AVG(MinTemperature), 2) AS media_tmin,
            ROUND(AVG(MeanTemperature), 2) AS media_tmean,
            ROUND(AVG(MeanRelativeHumidity), 2) AS media_hr,
            ROUND(SUM(Precipitation), 1) AS pcp_total_mm
     FROM read_parquet('", local_file, "')
     WHERE station_province = 'Ourense' AND year = 2020
     GROUP BY stationID ORDER BY stationID"
  ))
  dbDisconnect(con, shutdown = TRUE)
  print(resumen)
}
