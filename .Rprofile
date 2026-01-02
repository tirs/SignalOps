# SignalOps R Profile
# Activate renv for dependency management
source("renv/activate.R")

# Set options for the session
options(
  shiny.port = 3838,
  shiny.host = "0.0.0.0",
  shiny.autoreload = TRUE,
  warn = 1,
  encoding = "UTF-8"
)

# Configure logger
if (requireNamespace("logger", quietly = TRUE)) {
  logger::log_threshold(logger::INFO)
}

# Print startup message
message("SignalOps environment loaded")
