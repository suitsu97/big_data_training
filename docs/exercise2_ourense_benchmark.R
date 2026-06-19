# exercise2_ourense_benchmark.R
# Exercise 2.1 - "Bigger than memory" lesson
#
# Task: Extract and summarise DAILY meteorological values
#       (temperatures, relative humidities, precipitation)
#       for Ourense province stations, year 2020.
#
# Benchmark three approaches:
#   A. duckdb  – reading remotely (URL)
#   B. duckdb  – reading locally  (download time INCLUDED in benchmark)
#   C. arrow   – reading locally  (download time INCLUDED in benchmark)
#
# Data: https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet

library(duckdb)
library(DBI)
library(arrow)
library(dplyr)
library(bench)

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
parquet_url <- "https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet"
local_file  <- here::here("data", "meteo_stations_2000_2024.parquet")

# -------------------------------------------------------------------
# Step 0: Explore column names (run once before the benchmark)
# -------------------------------------------------------------------
# We peek at the remote file with DuckDB to discover the schema.
con_explore <- dbConnect(duckdb())
schema <- dbGetQuery(
  con_explore,
  paste0("DESCRIBE SELECT * FROM read_parquet('", parquet_url, "') LIMIT 1")
)
print(schema)

# Also preview a few rows to understand data values / filtering columns
preview <- dbGetQuery(
  con_explore,
  paste0("SELECT * FROM read_parquet('", parquet_url, "') LIMIT 5")
)
print(preview)

dbDisconnect(con_explore, shutdown = TRUE)

# -------------------------------------------------------------------
# NOTE: Adapt the column names below based on the schema output above.
# Expected columns (adjust if different in the actual file):
#   date        → date of observation
#   province    → province name or code  (e.g. "Ourense" / "OU" / 32)
#   tmax, tmin, tmean  → daily temperatures (°C)
#   hr          → relative humidity (%)
#   pcp / prec  → precipitation (mm)
# -------------------------------------------------------------------

# SQL query used in both DuckDB benchmarks
# (wrap in a function so we avoid copy-paste)
ourense_sql <- function(source) {
  paste0(
    "SELECT
       date,
       stationID,
       province,
       tmax,
       tmin,
       tmean,
       hr,
       pcp
     FROM read_parquet('", source, "')
     WHERE province = 'Ourense'
       AND year(date) = 2020
     ORDER BY stationID, date"
  )
}

# -------------------------------------------------------------------
# Benchmark
# -------------------------------------------------------------------
bm <- bench::mark(
  
  # A. DuckDB remote — no local download; DuckDB streams from URL
  duckdb_remote = {
    con <- dbConnect(duckdb())
    result <- dbGetQuery(con, ourense_sql(parquet_url))
    dbDisconnect(con, shutdown = TRUE)
    result
  },
  
  # B. DuckDB local — download included in timing
  duckdb_local = {
    tmp <- tempfile(fileext = ".parquet")
    download.file(parquet_url, destfile = tmp, mode = "wb", quiet = TRUE)
    con <- dbConnect(duckdb())
    result <- dbGetQuery(con, ourense_sql(tmp))
    dbDisconnect(con, shutdown = TRUE)
    file.remove(tmp)
    result
  },
  
  # C. Arrow local — download included in timing
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

# -------------------------------------------------------------------
# Results
# -------------------------------------------------------------------
print(bm)

cat("\nRanking by median execution time:\n")
print(bm[order(bm$median), c("expression", "median", "mem_alloc")])

# Save results to the results folder
saveRDS(bm, here::here("results", "exercise2_benchmark_results.rds"))

# -------------------------------------------------------------------
# Quick summary of the extracted data (using the pre-downloaded file)
# -------------------------------------------------------------------
if (file.exists(local_file)) {
  con <- dbConnect(duckdb())
  summary_data <- dbGetQuery(
    con,
    paste0(
      "SELECT
         stationID,
         COUNT(*)           AS n_days,
         ROUND(AVG(tmax), 2) AS mean_tmax,
         ROUND(AVG(tmin), 2) AS mean_tmin,
         ROUND(AVG(tmean),2) AS mean_tmean,
         ROUND(AVG(hr),   2) AS mean_hr,
         ROUND(SUM(pcp),  1) AS total_pcp_mm
       FROM read_parquet('", local_file, "')
       WHERE province = 'Ourense'
         AND year(date) = 2020
       GROUP BY stationID
       ORDER BY stationID"
    )
  )
  dbDisconnect(con, shutdown = TRUE)
  
  cat("\nDaily meteorological summary for Ourense stations (2020):\n")
  print(summary_data)
}
