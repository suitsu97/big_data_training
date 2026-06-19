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

# primero miro el esquema para saber exactamente cómo se llaman las columnas
# (ajustar los nombres en la query si son diferentes)
con_explore <- dbConnect(duckdb())
print(dbGetQuery(con_explore,
  paste0("DESCRIBE SELECT * FROM read_parquet('", parquet_url, "') LIMIT 1")))
print(dbGetQuery(con_explore,
  paste0("SELECT * FROM read_parquet('", parquet_url, "') LIMIT 5")))
dbDisconnect(con_explore, shutdown = TRUE)

# query para filtrar Ourense 2020 - adaptar nombres de columna si hace falta
ourense_sql <- function(src) {
  paste0(
    "SELECT date, stationID, province, tmax, tmin, tmean, hr, pcp
     FROM read_parquet('", src, "')
     WHERE province = 'Ourense' AND year(date) = 2020
     ORDER BY stationID, date"
  )
}

# benchmark (tarda bastante por las descargas en B y C)
bm <- bench::mark(

  # A - duckdb remoto, sin descarga
  duckdb_remote = {
    con <- dbConnect(duckdb())
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
      filter(province == "Ourense", year(date) == 2020) |>
      select(date, stationID, province, tmax, tmin, tmean, hr, pcp) |>
      arrange(stationID, date) |>
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

# resumen de los datos extraídos (si tengo el archivo en local)
if (file.exists(local_file)) {
  con <- dbConnect(duckdb())
  resumen <- dbGetQuery(con, paste0(
    "SELECT stationID,
            COUNT(*) AS n_dias,
            ROUND(AVG(tmax), 2) AS media_tmax,
            ROUND(AVG(tmin), 2) AS media_tmin,
            ROUND(AVG(tmean), 2) AS media_tmean,
            ROUND(AVG(hr), 2) AS media_hr,
            ROUND(SUM(pcp), 1) AS pcp_total_mm
     FROM read_parquet('", local_file, "')
     WHERE province = 'Ourense' AND year(date) = 2020
     GROUP BY stationID ORDER BY stationID"
  ))
  dbDisconnect(con, shutdown = TRUE)
  print(resumen)
}
