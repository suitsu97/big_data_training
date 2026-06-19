# exercise1_bigger_than_memory.R
# Benchmark de distintos métodos para leer un parquet
# duckdb remoto, duckdb local, arrow local, sf local (añadido en la actividad final)

library(duckdb)
library(DBI)
library(arrow)
library(sf)
library(geoarrow)
library(bench)
library(here)

parquet_url <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
local_file  <- here::here("data", "meteo_stations_2000_2024.parquet")

# descargo el archivo si no lo tengo ya (tarda un rato)
if (!file.exists(local_file)) {
  message("Descargando parquet...")
  download.file(parquet_url, destfile = local_file, mode = "wb", quiet = FALSE)
}

# miro primero el esquema para saber qué hay dentro
con_explore <- dbConnect(duckdb())
dbExecute(con_explore, paste0("CREATE VIEW meteo AS SELECT * FROM read_parquet('", local_file, "')"))
print(dbGetQuery(con_explore, "DESCRIBE meteo"))
print(dbGetQuery(con_explore, "SELECT COUNT(*) AS n FROM meteo"))
dbDisconnect(con_explore, shutdown = TRUE)

# benchmark - 3 iteraciones por método
bm <- bench::mark(

  duckdb_remote = {
    con <- dbConnect(duckdb())
    result <- dbGetQuery(con, paste0("SELECT * FROM read_parquet('", parquet_url, "')"))
    dbDisconnect(con, shutdown = TRUE)
    result
  },

  duckdb_local = {
    con <- dbConnect(duckdb())
    result <- dbGetQuery(con, paste0("SELECT * FROM read_parquet('", local_file, "')"))
    dbDisconnect(con, shutdown = TRUE)
    result
  },

  arrow_local = {
    arrow::read_parquet(local_file)
  },

  # sf añadido en la Actividad Final - lee GeoParquet y devuelve objeto sf
  sf_local = {
    geoarrow::read_geoparquet_sf(local_file)
  },

  iterations = 3,
  check      = FALSE,
  memory     = TRUE
)

print(bm)
print(bm[order(bm$median), c("expression", "median", "mem_alloc")])

fastest <- as.character(bm$expression[[which.min(bm$median)]])
cat("Método más rápido:", fastest, "\n")

# El más rápido suele ser arrow_local - evita el overhead de planificación SQL
# de duckdb y el parseo de geometría de geoarrow/sf
