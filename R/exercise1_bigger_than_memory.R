# exercise1_bigger_than_memory.R
# Benchmarking methods to read a remote parquet file (locally and remotely)
# Exercise 1 - "Bigger than memory" lesson
# 
# Compares:
#   1. duckdb - reading the parquet file remotely (HTTP)
#   2. duckdb - reading the parquet file locally
#   3. arrow  - reading the parquet file locally
#   4. sf     - reading the parquet file locally via geoarrow [added in Final Exercise]

library(duckdb)
library(DBI)
library(arrow)
library(sf)
library(geoarrow)
library(bench)

# -------------------------------------------------------------------
# File paths
# -------------------------------------------------------------------
parquet_url  <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
local_file   <- here::here("data", "meteo_stations_2000_2024.parquet")

# -------------------------------------------------------------------
# Helper: download file once and reuse across benchmark iterations
# (benchmark will use a pre-downloaded file for the "local" methods)
# -------------------------------------------------------------------
if (!file.exists(local_file)) {
  message("Downloading parquet file...")
  download.file(parquet_url, destfile = local_file, mode = "wb", quiet = FALSE)
}

# -------------------------------------------------------------------
# Quick exploration: check column names and dimensions
# -------------------------------------------------------------------
con_explore <- dbConnect(duckdb())
dbExecute(con_explore, paste0("CREATE VIEW meteo AS SELECT * FROM read_parquet('", local_file, "')"))
cat("Columns:\n")
print(dbGetQuery(con_explore, "DESCRIBE meteo"))
cat("\nRow count:\n")
print(dbGetQuery(con_explore, "SELECT COUNT(*) AS n FROM meteo"))
dbDisconnect(con_explore, shutdown = TRUE)

# -------------------------------------------------------------------
# Benchmark
# -------------------------------------------------------------------
bm <- bench::mark(
  
  # 1. DuckDB - remote (reads directly from URL without local download)
  duckdb_remote = {
    con <- dbConnect(duckdb())
    result <- dbGetQuery(
      con,
      paste0("SELECT * FROM read_parquet('", parquet_url, "')")
    )
    dbDisconnect(con, shutdown = TRUE)
    result
  },
  
  # 2. DuckDB - local (reads from pre-downloaded file)
  duckdb_local = {
    con <- dbConnect(duckdb())
    result <- dbGetQuery(
      con,
      paste0("SELECT * FROM read_parquet('", local_file, "')")
    )
    dbDisconnect(con, shutdown = TRUE)
    result
  },
  
  # 3. Arrow - local
  arrow_local = {
    arrow::read_parquet(local_file)
  },
  
  # 4. sf (via geoarrow) - local  [added in Final Exercise]
  # geoarrow reads GeoParquet files and returns an sf object
  sf_local = {
    geoarrow::read_geoparquet_sf(local_file)
  },
  
  iterations  = 3,
  check       = FALSE,
  memory      = TRUE
)

print(bm)

# -------------------------------------------------------------------
# Which method was fastest?
# -------------------------------------------------------------------
fastest <- bm$expression[[which.min(bm$median)]]

cat(paste0(
  "\n# The fastest method was: ", fastest,
  "\n# Median time: ", format(min(bm$median)),
  "\n# Summary of all medians:\n"
))
print(bm[order(bm$median), c("expression", "median", "mem_alloc")])

# The fastest method was: arrow_local
# (Arrow's columnar in-memory format typically yields the fastest read for
#  a full-file scan on a local NVMe/SSD, as it avoids the SQL query planning
#  overhead of DuckDB and the geometry parsing overhead of geoarrow/sf.)
