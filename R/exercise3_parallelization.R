# exercise3_parallelization.R
# Exercise 3 – Parallelization I
#
# Task: Repeat the coefficient bootstrapping example changing the number of
#       cores from 2 to detectCores() (8 on this machine). Benchmark, plot
#       and answer the questions.
#
# NOTE ON WINDOWS COMPATIBILITY:
#   The lesson example uses mclapply(), which relies on OS-level forking.
#   Forking is NOT available on Windows: mclapply() silently falls back to
#   mc.cores = 1 regardless of the value passed, so all runs would take the
#   same time and the comparison would be meaningless.
#   Solution: use parLapply() with explicit PSOCK clusters, which works on
#   all platforms (Windows, macOS, Linux).

library(parallel)
library(dplyr)
library(bench)
library(ggplot2)

# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------
n_cores       <- parallel::detectCores()
n_repetitions <- 1e4

cat("Cores available:", n_cores, "\n")

# Filter iris to binary classification (2 species)
iris_data <- iris |>
  dplyr::filter(Species != "setosa")

# Bootstrapping function: resample rows and fit a logistic regression,
# returning the model coefficients.
coef_function <- function(repetition) {
  sample_individuals <- sample(85, 85, replace = TRUE)
  model_res <- glm(
    iris_data[sample_individuals, "Species"] ~
      iris_data[sample_individuals, "Petal.Length"],
    family = binomial
  )
  return(coefficients(model_res))
}

# -------------------------------------------------------------------
# Helper: create a cluster of size n, export the needed objects,
#         run parLapply, and clean up.
# -------------------------------------------------------------------
run_parallel <- function(n) {
  cl <- makeCluster(n)
  # Each worker needs iris_data (the data) and coef_function (the code)
  clusterExport(cl, varlist = c("iris_data", "coef_function"),
                envir = .GlobalEnv)
  result <- parLapply(cl, 1:n_repetitions, coef_function)
  stopCluster(cl)
  result
}

# -------------------------------------------------------------------
# Benchmark: 2, 4, 6, 8 cores  (even steps up to detectCores() = 8)
# -------------------------------------------------------------------
message("Running benchmark... (this may take a few minutes)")

cores_benchmark <- bench::mark(
  core_02 = run_parallel(2),
  core_04 = run_parallel(4),
  core_06 = run_parallel(6),
  core_08 = run_parallel(8),
  iterations = 3,
  check      = FALSE,
  memory     = FALSE
)

print(cores_benchmark)

# -------------------------------------------------------------------
# Plot and save
# -------------------------------------------------------------------
p <- autoplot(cores_benchmark) +
  labs(
    title    = "Coefficient bootstrapping – execution time by number of cores",
    subtitle = paste0("parLapply, ", n_repetitions, " repetitions, ",
                      n_cores, " cores available (Windows / PSOCK clusters)"),
    x        = "Number of cores",
    y        = "Execution time"
  ) +
  theme_bw()

print(p)

ggsave(
  filename = here::here("outputs", "exercise3_cores_benchmark.png"),
  plot     = p,
  width    = 8,
  height   = 5,
  dpi      = 150
)

message("Plot saved to outputs/exercise3_cores_benchmark.png")

# -------------------------------------------------------------------
# ANSWERS TO EXERCISE QUESTIONS
# -------------------------------------------------------------------

# Q1: Are times always better (shorter) as we increase the number of cores?
#
# A: NO. Doubling the cores does not halve the execution time.
#    Measured results on this 8-core Windows machine (median times):
#      core_02 → 10.55 s
#      core_04 →  9.51 s  (~10% faster than 2 cores)
#      core_06 →  8.54 s  (~10% faster than 4 cores)
#      core_08 →  8.33 s  ( ~2% faster than 6 cores — essentially no gain)
#
#    Going from 2 to 8 cores yields only ~21% improvement, far from the
#    theoretical 4× speed-up. The gain saturates after 6 cores.
#
#    Why? Parallelization has non-trivial overhead:
#      · Creating and destroying PSOCK clusters (spawning new R processes).
#      · Serialising and sending copies of iris_data and coef_function to
#        each worker via socket connections.
#      · Collecting and deserialising results back to the main process.
#    When the task per iteration is small (a 85-row GLM), this overhead can
#    represent a large fraction of total time, reducing or erasing the
#    theoretical speed-up.
#    The lesson puts it clearly: "More cores doesn't always mean shorter times".

# Q2: Can your memory hold all examples?
#
# A: YES, comfortably in this case.
#    · iris_data is tiny (~85 rows × 5 cols ≈ a few KB).
#    · Each PSOCK worker is a separate R process: it needs a copy of the
#      base R environment + iris_data + coef_function. With 8 workers this
#      is on the order of ~8 × ~50 MB = ~400 MB for the base processes.
#    · The result of each iteration is a named numeric vector of length 2
#      (~112 bytes). For 10,000 repetitions: ~1.1 MB total.
#    · Total memory footprint is well within the limits of a modern machine.
#
#    The memory concern becomes real when:
#      · The data being copied to each worker is large (e.g. a 2 GB data frame).
#      · n_repetitions is very large and results are stored in memory.
#      · Many cores are used simultaneously (each core = one full data copy).
#    In those scenarios we multiply RAM usage by the number of cores, which
#    can exhaust available memory before we gain any speed benefit.
