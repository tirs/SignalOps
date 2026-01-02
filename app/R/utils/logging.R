# SignalOps Logging Utilities
# Structured logging with context

#' Log an info message with context
#' @param message The log message
#' @param ... Additional context as named arguments
log_app_info <- function(message, ...) {
  context <- list(...)
  context$timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  context$app <- "signalops"
  logger::log_info(message, .topenv = parent.frame())
}

#' Log a warning message with context
#' @param message The log message
#' @param ... Additional context as named arguments
log_app_warn <- function(message, ...) {
  context <- list(...)
  context$timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  context$app <- "signalops"
  logger::log_warn(message, .topenv = parent.frame())
}
#' Log an error message with context
#' @param message The log message
#' @param ... Additional context as named arguments
log_app_error <- function(message, ...) {
  context <- list(...)
  context$timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  context$app <- "signalops"
  logger::log_error(message, .topenv = parent.frame())
}

#' Log a debug message with context
#' @param message The log message
#' @param ... Additional context as named arguments
log_app_debug <- function(message, ...) {
  context <- list(...)
  context$timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  context$app <- "signalops"
  logger::log_debug(message, .topenv = parent.frame())
}

#' Create an audit log entry
#' @param pool Database pool
#' @param action The action type
#' @param user_id User performing the action
#' @param tenant_id Tenant ID
#' @param entity_type Type of entity affected
#' @param entity_id ID of entity affected
#' @param old_values Previous values (JSONB)
#' @param new_values New values (JSONB)
#' @param session_id Current session ID
#' @param ip_address Client IP address
#' @param user_agent Client user agent
#' @param metadata Additional metadata
create_audit_log <- function(pool, action, user_id = NULL, tenant_id = NULL,
                             entity_type = NULL, entity_id = NULL,
                             old_values = NULL, new_values = NULL,
                             session_id = NULL, ip_address = NULL,
                             user_agent = NULL, metadata = list()) {
  tryCatch({
    query <- "
      INSERT INTO audit_logs 
        (tenant_id, user_id, session_id, action, entity_type, entity_id,
         old_values, new_values, ip_address, user_agent, metadata)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING id
    "
    
    result <- dbGetQuery(pool, query, params = list(
      tenant_id,
      user_id,
      session_id,
      action,
      entity_type,
      entity_id,
      if (!is.null(old_values)) toJSON(old_values, auto_unbox = TRUE) else NULL,
      if (!is.null(new_values)) toJSON(new_values, auto_unbox = TRUE) else NULL,
      ip_address,
      user_agent,
      toJSON(metadata, auto_unbox = TRUE)
    ))
    
    log_app_debug("Audit log created", 
                  audit_id = result$id, 
                  action = action, 
                  user_id = user_id)
    
    invisible(result$id)
  }, error = function(e) {
    log_app_error("Failed to create audit log", 
                  error = e$message, 
                  action = action)
    invisible(NULL)
  })
}

#' Get audit logs with filtering
#' @param pool Database pool
#' @param tenant_id Tenant ID filter
#' @param user_id User ID filter
#' @param action Action type filter
#' @param start_date Start date filter
#' @param end_date End date filter
#' @param limit Maximum number of records
#' @param offset Offset for pagination
get_audit_logs <- function(pool, tenant_id = NULL, user_id = NULL,
                           action = NULL, start_date = NULL, end_date = NULL,
                           limit = 100, offset = 0) {
  query <- "
    SELECT 
      al.id,
      al.action,
      al.entity_type,
      al.entity_id,
      al.old_values,
      al.new_values,
      al.ip_address,
      al.metadata,
      al.created_at,
      u.email as user_email,
      u.first_name,
      u.last_name
    FROM audit_logs al
    LEFT JOIN users u ON al.user_id = u.id
    WHERE 1=1
  "
  
  params <- list()
  param_count <- 0
  
  if (!is.null(tenant_id)) {
    param_count <- param_count + 1
    query <- paste0(query, " AND al.tenant_id = $", param_count)
    params[[param_count]] <- tenant_id
  }
  
  if (!is.null(user_id)) {
    param_count <- param_count + 1
    query <- paste0(query, " AND al.user_id = $", param_count)
    params[[param_count]] <- user_id
  }
  
  if (!is.null(action)) {
    param_count <- param_count + 1
    query <- paste0(query, " AND al.action = $", param_count)
    params[[param_count]] <- action
  }
  
  if (!is.null(start_date)) {
    param_count <- param_count + 1
    query <- paste0(query, " AND al.created_at >= $", param_count)
    params[[param_count]] <- start_date
  }
  
  if (!is.null(end_date)) {
    param_count <- param_count + 1
    query <- paste0(query, " AND al.created_at <= $", param_count)
    params[[param_count]] <- end_date
  }
  
  query <- paste0(query, " ORDER BY al.created_at DESC LIMIT ", limit, " OFFSET ", offset)
  
  dbGetQuery(pool, query, params = params)
}
