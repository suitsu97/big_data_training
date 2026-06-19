# big_data_training

Repositorio de la **Actividad Final** del módulo *4 – Aplicaciones y desarrollos en entorno R*
(Curso de Ciencia de Datos).

Contiene los scripts de los 6 ejercicios del módulo, organizados en carpetas siguiendo
la estructura estándar de proyecto R.

---

## Estructura del repositorio

```
big_data_training/
├── R/
│   ├── main_script.R                    # instalación de paquetes y carga de librerías
│   ├── exercise1_bigger_than_memory.R   # Ejercicio 1
│   ├── exercise2_ourense_benchmark.R    # Ejercicio 2
│   ├── exercise3_4_parallelization.R    # Ejercicios 3 y 4
│   ├── exercise5_municipality_purrr.R   # Ejercicio 5
│   └── exercise6_interpolation_asturias.R # Ejercicio 6
├── docs/
│   └── exercise2_municipality_design.txt  # Diseño del procesado municipal (Ej. 2.2)
├── data/
│   └── databases_info.txt               # Descripción de las bases de datos usadas
├── outputs/
│   └── exercise3_cores_benchmark.png    # Plot del benchmark de paralelización
├── results/                             # Resultados intermedios (.rds, generados al correr)
└── .gitignore
```

> Los archivos `.parquet` y `.rds` no se versionen (ver `.gitignore`).
> Se descargan o generan automáticamente al ejecutar los scripts.

---

## Ejercicios

### Ejercicio 1 – Bigger than memory: benchmark de lectura de parquet
[`R/exercise1_bigger_than_memory.R`](R/exercise1_bigger_than_memory.R)

Compara la velocidad de cuatro métodos para leer el archivo parquet de estaciones
meteorológicas (~500 MB):

| Método | Descripción |
|---|---|
| `duckdb_remote` | DuckDB lee directamente desde la URL sin descarga previa |
| `duckdb_local` | DuckDB lee desde archivo local |
| `arrow_local` | Arrow lee desde archivo local |
| `sf_local` | geoarrow lee el GeoParquet y devuelve un objeto sf *(añadido en la Actividad Final)* |

Resultado: `arrow_local` suele ser el más rápido al evitar el overhead de SQL y
el parseo de geometría.

---

### Ejercicio 2 – Bigger than memory: datos de Ourense 2020
[`R/exercise2_ourense_benchmark.R`](R/exercise2_ourense_benchmark.R) ·
[`docs/exercise2_municipality_design.txt`](docs/exercise2_municipality_design.txt)

**2.1** Benchmark para extraer y resumir datos meteorológicos diarios de las
estaciones de Ourense en 2020 (temperaturas, humedad relativa, precipitación).
Compara duckdb remoto, duckdb local con descarga y arrow local con descarga.

**2.2** Documento de diseño que describe los pasos necesarios para escalar el
procesado a todos los municipios de España, incluyendo join espacial estación→municipio,
estrategia de paralelización y estimación del coste computacional.

---

### Ejercicios 3 y 4 – Parallelization I: benchmarks de paralelización
[`R/exercise3_4_parallelization.R`](R/exercise3_4_parallelization.R)

**Ejercicio 3:** Bootstrap de coeficientes de regresión logística sobre el dataset
`iris`, variando el número de cores de 2 a 8. Se usa `foreach + doParallel` en
lugar de `mclapply` porque en Windows `mclapply` cae a 1 core sin avisar.

Resultados (Windows, 8 cores): la mejora de 2 a 8 cores es solo del ~30% debido
al overhead de comunicación entre procesos (PSOCK). 4 cores fue incluso más lento
que 2 en alguna ejecución.

**Ejercicio 4** *(añadido al mismo script según indica el enunciado)*: compara
los tres métodos de paralelización disponibles con el número óptimo de cores (8):

| Método | Tiempo mediano |
|---|---|
| `foreach + doParallel` | ~13 s |
| `furrr::future_map` | ~13 s |
| `mirai_map` | ~8.3 s ← más rápido |

`mirai` es ~36% más rápido porque usa `nng` (nanomsg) en lugar de sockets PSOCK.

El plot del benchmark se guarda en [`outputs/exercise3_cores_benchmark.png`](outputs/exercise3_cores_benchmark.png).

---

### Ejercicio 5 – Parallelization II: procesado municipal con purrr
[`R/exercise5_municipality_purrr.R`](R/exercise5_municipality_purrr.R)

Procesa los datos meteorológicos de 2020 para todos los municipios de España usando:

1. `purrr::map()` — iteración secuencial sobre las 50 provincias
2. `furrr::future_map()` — versión paralela (multisession)
3. `mirai_map()` — versión paralela con menor overhead

Incluye un join espacial (point-in-polygon) entre las estaciones y los límites
municipales de `mapSpain`, produciendo un resumen diario por municipio.

Conclusión: cuando el cuello de botella es I/O (lectura del parquet local),
la paralelización ofrece una mejora moderada; sería mayor con datos remotos.

---

### Ejercicio 6 – Interpolación espacial: precipitación en Asturias 2007
[`R/exercise6_interpolation_asturias.R`](R/exercise6_interpolation_asturias.R)

Interpola la precipitación diaria observada en las estaciones de Asturias (2007)
a un grid regular de 500 m usando IDW (*Inverse Distance Weighting*) con validación
leave-one-out (LOO):

1. Extrae datos de estaciones de Asturias 2007 del parquet histórico
2. Crea un grid de 500 m sobre Asturias (ETRS89 UTM30N, EPSG:25830) con `terra`
3. Para cada día del año aplica IDW LOO con `gstat::idw()` → calcula el bias medio
4. Lee los datos oficiales interpolados (un parquet por día: `YYYYMMDD.parquet`)
   para 15 días de muestra y extrae valores en las ubicaciones de las estaciones
5. Compara el bias de mi interpolación IDW vs. el de los datos oficiales

---

## Datos

Ver [`data/databases_info.txt`](data/databases_info.txt) para la descripción
completa de las fuentes de datos.

---

## Requisitos

```r
source("R/main_script.R")   # instala y carga todos los paquetes necesarios
```

Paquetes principales: `duckdb`, `arrow`, `geoarrow`, `sf`, `terra`, `purrr`,
`furrr`, `mirai`, `foreach`, `doParallel`, `mapSpain`, `gstat`, `bench`.
