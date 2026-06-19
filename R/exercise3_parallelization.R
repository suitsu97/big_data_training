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

# Respuestas a las preguntas del ejercicio:

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
