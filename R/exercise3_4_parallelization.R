# exercise3_parallelization.R
# Ejercicio de paralelización: bootstrap de coeficientes con distinto nº de cores
# Uso foreach + doParallel porque mclapply no funciona en Windows
# (cae a 1 core sin avisar, así que el benchmark no tendría sentido)

library(parallel)
library(foreach)
library(doParallel)
library(dplyr)
library(bench)
library(ggplot2)
library(ggbeeswarm)
library(here)

n_cores       <- parallel::detectCores()
n_repetitions <- 1e4

cat("Cores disponibles:", n_cores, "\n")

iris_data <- iris |>
  dplyr::filter(Species != "setosa")

# función de bootstrapping: remuestrea y ajusta una regresión logística
run_dopar <- function(n) {
  cl <- makeCluster(n)
  registerDoParallel(cl)
  # .export necesario en Windows: las variables no se copian automáticamente
  result <- foreach(index = 1:n_repetitions, .export = "iris_data") %dopar% {
    sample_individuals <- sample(85, 85, replace = TRUE)
    model_res <- glm(
      iris_data[sample_individuals, "Species"] ~
        iris_data[sample_individuals, "Petal.Length"],
      family = binomial
    )
    coefficients(model_res)
  }
  stopCluster(cl)
  result
}

# benchmark de 2 a 8 cores (tarda varios minutos)
cores_benchmark <- bench::mark(
  core_02 = run_dopar(2),
  core_04 = run_dopar(4),
  core_06 = run_dopar(6),
  core_08 = run_dopar(8),
  iterations = 3,
  check      = FALSE,
  memory     = FALSE
)

print(cores_benchmark)

# guardo el plot en outputs/
p <- autoplot(cores_benchmark) +
  labs(
    title = "Bootstrapping: tiempo de ejecución según nº de cores",
    subtitle = paste0("foreach + doParallel, ", n_repetitions, " repeticiones, Windows"),
    x = "Nº de cores",
    y = "Tiempo"
  ) +
  theme_bw()

print(p)

ggsave(
  filename = here::here("outputs", "exercise3_cores_benchmark.png"),
  plot = p, width = 8, height = 5, dpi = 150
)

# Respuestas a las preguntas del ejercicio 3:

# ¿Más cores siempre implica menos tiempo?
# No. En mi máquina (8 cores, Windows):
#   2 cores: ~19s  /  4 cores: ~24s (peor que 2!)  /  6 cores: ~15s  /  8 cores: ~14s
# El salto de 2 a 8 cores solo mejora un ~30%, muy lejos del 4x teórico.
# El problema es el overhead: crear procesos, serializar datos, recoger resultados...
# Con tareas pequeñas como esta (GLM sobre 85 filas) ese overhead es dominante.
# Como dice el temario: más cores != menos tiempo.

# ¿La memoria aguanta todos los ejemplos?
# Sí, en este caso sí. iris_data son unos pocos KB y los resultados
# son 2 coeficientes x 10000 iteraciones = ~1MB, no hay problema.
# Con datos grandes sería otro tema: cada core necesita su propia copia
# en RAM, así que la memoria necesaria se multiplica con el nº de cores.


# ============================================================
# EJERCICIO 4 - comparar foreach+doParallel vs mirai vs furrr
# con el número óptimo de cores (8 en este caso)
# ============================================================

library(mirai)
library(furrr)
library(future)

# mirai: los workers son procesos ligeros conectados por nng (no PSOCK)
# hay que pasar iris_data como argumento porque no está en su entorno
run_mirai <- function(n) {
  daemons(n)
  r <- mirai_map(
    1:n_repetitions,
    function(i, data) {
      samp <- sample(85, 85, replace = TRUE)
      m <- glm(data[samp, "Species"] ~ data[samp, "Petal.Length"], family = binomial)
      coefficients(m)
    },
    data = iris_data
  )[]  # [] espera a que terminen todos
  daemons(0)
  r
}

# furrr: purrr en paralelo via future (multisession = PSOCK en Windows)
# exporta automáticamente el entorno global, no hace falta .export
run_furrr <- function(n) {
  plan(multisession, workers = n)
  r <- future_map(1:n_repetitions, function(i) {
    samp <- sample(85, 85, replace = TRUE)
    m <- glm(iris_data[samp, "Species"] ~ iris_data[samp, "Petal.Length"], family = binomial)
    coefficients(m)
  })
  plan(sequential)
  r
}

bm_ex4 <- bench::mark(
  dopar_8cores = run_dopar(n_cores),
  mirai_8cores = run_mirai(n_cores),
  furrr_8cores = run_furrr(n_cores),
  iterations   = 3,
  check        = FALSE,
  memory       = FALSE
)

print(bm_ex4)
print(bm_ex4[order(bm_ex4$median), c("expression", "median")])

# ¿Hay diferencias entre los tres métodos?
# Sí, bastante. Resultados en esta máquina (mediana):
#   dopar_8cores: ~13.0s
#   mirai_8cores:  ~8.3s  <- claramente el más rápido
#   furrr_8cores: ~12.9s
#
# mirai es ~36% más rápido que doParallel y furrr.
# La razón es que mirai usa nng (nanomsg) para comunicar con los workers,
# que es mucho más eficiente que los sockets PSOCK que usan tanto doParallel
# como furrr (multisession) en Windows.
# furrr y doParallel son prácticamente iguales porque ambos usan el mismo
# mecanismo de PSOCK por debajo.
