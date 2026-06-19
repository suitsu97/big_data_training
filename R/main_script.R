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

# ---------------------------------------------------------------
# Generar fichero de información sobre las bases de datos usadas
# ---------------------------------------------------------------
writeLines(c(
  "BASES DE DATOS UTILIZADAS EN EL PROYECTO",
  "=========================================",
  "",
  "1. DATOS HISTÓRICOS DE ESTACIONES METEOROLÓGICAS",
  "-------------------------------------------------",
  "Archivo : meteo_stations_2000_2024.parquet",
  "Fuente  : EMF-CREAF (Ecological & Forest Applications Research Centre)",
  "URL     : https://data-emf.creaf.cat/public/parquet/stations_data_historical/meteo_stations_2000_2024.parquet",
  "Cobertura: España peninsular e islas, años 2000-2024",
  "Tamaño  : ~500 MB",
  "Formato : GeoParquet (columna geom en WGS84 / EPSG:4326)",
  "",
  "Principales variables:",
  "  stationID            - identificador único de la estación",
  "  station_name         - nombre de la estación",
  "  station_province     - provincia (e.g. 'Asturias', 'Ourense')",
  "  dates                - fecha de observación (VARCHAR, formato YYYY-MM-DD)",
  "  year / month / day   - componentes de la fecha (integer)",
  "  MaxTemperature       - temperatura máxima diaria (°C)",
  "  MinTemperature       - temperatura mínima diaria (°C)",
  "  MeanTemperature      - temperatura media diaria (°C)",
  "  MeanRelativeHumidity - humedad relativa media diaria (%)",
  "  Precipitation        - precipitación diaria acumulada (mm)",
  "  WindSpeed            - velocidad media del viento (m/s)",
  "  Radiation            - radiación solar (MJ/m2)",
  "  geom                 - geometría del punto (WKB, EPSG:4326)",
  "",
  "Uso en ejercicios: 1, 2, 5, 6",
  "",
  "",
  "2. DATOS OFICIALES INTERPOLADOS (GRID DIARIO)",
  "----------------------------------------------",
  "Archivo : YYYYMMDD.parquet (un fichero por día)",
  "Fuente  : EMF-CREAF",
  "URL base: https://data-emf.creaf.cat/public/parquet/daily_interpolated_meteo/",
  "Ejemplo : https://data-emf.creaf.cat/public/parquet/daily_interpolated_meteo/20070101.parquet",
  "Cobertura: España peninsular, 2000-2024 (un fichero por día)",
  "Tamaño  : ~220 MB por fichero (grid completo de España)",
  "Formato : GeoParquet (columna geom en ETRS89 UTM30N / EPSG:25830)",
  "",
  "Principales variables:",
  "  dates                - fecha (DATE)",
  "  Precipitation        - precipitación interpolada (mm)",
  "  MeanTemperature      - temperatura media interpolada (°C)",
  "  MaxTemperature       - temperatura máxima interpolada (°C)",
  "  MinTemperature       - temperatura mínima interpolada (°C)",
  "  MeanRelativeHumidity - humedad relativa interpolada (%)",
  "  Radiation            - radiación solar interpolada (MJ/m2)",
  "  elevation            - elevación del punto del grid (m)",
  "  geom                 - geometría del punto de grid (EPSG:25830)",
  "",
  "Uso en ejercicios: 6 (comparación bias interpolación propia vs oficial)",
  "",
  "",
  "3. DATASET IRIS (R base)",
  "------------------------",
  "Fuente  : Dataset clásico de R (Fisher, 1936)",
  "Acceso  : iris (disponible en cualquier sesión de R sin descarga)",
  "Tamaño  : 150 filas x 5 columnas",
  "",
  "Variables usadas:",
  "  Species      - especie de la flor (factor: setosa, versicolor, virginica)",
  "  Petal.Length - longitud del pétalo (cm)",
  "",
  "Uso: se filtra a las dos especies no-setosa (85 filas) para ajustar",
  "     regresiones logísticas en el benchmark de paralelización.",
  "Uso en ejercicios: 3, 4",
  "",
  "",
  "NOTAS SOBRE ACCESO A LOS DATOS",
  "--------------------------------",
  "- Los archivos .parquet del EMF-CREAF son públicos y no requieren autenticación.",
  "- DuckDB puede leerlos directamente desde la URL con la extensión httpfs.",
  "- Los archivos grandes (~500 MB) se descargan una vez a data/ y se reusan.",
  "- Los archivos diarios del grid oficial (~220 MB c/u) se leen remotamente",
  "  para no acumular decenas de GB en local.",
  paste0("- Fichero generado automáticamente por R/main_script.R el ", Sys.Date())
), here::here("data", "databases_info.txt"))

message("Fichero data/databases_info.txt generado.")
