# main_script.R
# Load required libraries (install if not present)

required_packages <- c(
  "data.table",
  "dplyr",
  "purrr",
  "furrr",
  "future",
  "parallel",
  "foreach",
  "doParallel",
  "mirai",
  "sf",
  "terra",
  "arrow",
  "geoarrow",
  "duckdb",
  "DBI",
  "bench",
  "ggplot2",
  "ggbeeswarm",
  "mapSpain",
  "gstat",
  "here"
)

# Install any missing packages
missing_packages <- required_packages[!required_packages %in% rownames(installed.packages())]
if (length(missing_packages) > 0) {
  install.packages(missing_packages, type = "binary")
}

# Load libraries
library(data.table)
library(dplyr)
library(purrr)
library(furrr)
library(future)
library(parallel)
library(foreach)
library(doParallel)
library(mirai)
library(sf)
library(terra)
library(arrow)
library(geoarrow)
library(duckdb)
library(DBI)
library(bench)
library(ggplot2)
library(ggbeeswarm)
library(mapSpain)
library(gstat)
library(here)
