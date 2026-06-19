# main_script.R
# Load required libraries (install if not present)

required_packages <- c(
  "data.table",
  "purrr",
  "parallel",
  "mirai",
  "sf",
  "terra",
  "arrow",
  "geoarrow",
  "duckdb"
)

# Install any missing packages
missing_packages <- required_packages[!required_packages %in% rownames(installed.packages())]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, type = "binary")
}

# Load libraries
library(data.table)
library(purrr)
library(parallel)
library(mirai)
library(sf)
library(terra)
library(arrow)
library(geoarrow)
library(duckdb)
