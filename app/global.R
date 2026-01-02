# SignalOps Global Configuration
# This file is sourced before the Shiny app starts

# Load required packages
library(shiny)
library(bslib)
library(DBI)
library(pool)
library(RMariaDB)
library(dplyr)
library(dbplyr)
library(ggplot2)
library(plotly)
library(DT)
library(sodium)
library(config)
library(jsonlite)
library(lubridate)
library(purrr)
library(tibble)
library(tidyr)
library(readr)
library(stringr)
library(glue)
library(memoise)
library(cachem)
library(logger)
library(uuid)
library(shinyjs)
library(shinyWidgets)
library(waiter)
library(htmltools)
library(promises)
library(future)

# Set up async processing
plan(multisession)

# Load configuration
app_config <- config::get(file = "config.yml")

# Set up logging
log_threshold(switch(
  app_config$logging$level,
  "DEBUG" = DEBUG,
  "INFO" = INFO,
  "WARN" = WARN,
  "ERROR" = ERROR,
  INFO
))

log_layout(layout_json())
log_appender(appender_tee(file = app_config$logging$file))

log_info("SignalOps starting", version = app_config$app$version)

# Source all R files
source_dir <- function(path) {
  files <- list.files(path, pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  for (file in files) {
    source(file, local = FALSE)
    log_debug("Sourced", file = basename(file))
  }
}

# Source services first, then modules
source_dir("R/utils")
source_dir("R/services")
source_dir("R/modules")

# Initialize database pool
db_pool <- NULL
tryCatch({
  db_pool <- init_db_pool(app_config$database)
  log_info("Database pool initialized")
}, error = function(e) {
  log_error("Failed to initialize database pool", error = e$message)
})

# Initialize cache
app_cache <- NULL
if (app_config$cache$enabled) {
  app_cache <- cache_mem(
    max_size = app_config$cache$max_size_mb * 1024^2,
    max_age = app_config$cache$ttl_seconds
  )
  log_info("Cache initialized")
}

# Global options
options(
  shiny.maxRequestSize = app_config$app$max_upload_mb * 1024^2,
  DT.options = list(
    pageLength = 25,
    language = list(
      emptyTable = "No data available",
      zeroRecords = "No matching records found"
    )
  )
)

# Helper to check permissions
has_permission <- function(user_role, required_roles) {
  role_hierarchy <- c("viewer" = 1, "analyst" = 2, "admin" = 3)
  user_level <- role_hierarchy[user_role]
  required_level <- min(role_hierarchy[required_roles])
  user_level >= required_level
}

# Cleanup on app stop
onStop(function() {
  if (!is.null(db_pool)) {
    poolClose(db_pool)
    log_info("Database pool closed")
  }
  log_info("SignalOps stopped")
})

log_info("Global initialization complete")
