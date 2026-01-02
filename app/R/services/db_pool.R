# SignalOps Database Pool Service
# Connection pooling and database utilities for MySQL

#' Initialize database connection pool
#' @param config Database configuration list
#' @return Database pool object
init_db_pool <- function(config) {
  pool::dbPool(
    drv = RMariaDB::MariaDB(),
    host = config$host,
    port = config$port,
    dbname = config$name,
    username = config$user,
    password = config$password,
    minSize = 1,
    maxSize = config$pool_size %||% 5,
    idleTimeout = config$idle_timeout %||% 60000
  )
}

#' Check database connection health
#' @param pool Database pool
#' @return List with status and latency
check_db_health <- function(pool) {
  start_time <- Sys.time()
  tryCatch({
    result <- DBI::dbGetQuery(pool, "SELECT 1 as `check`")
    latency_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
    list(
      status = "healthy",
      latency_ms = round(latency_ms, 2),
      message = "Database connection OK"
    )
  }, error = function(e) {
    list(
      status = "unhealthy",
      latency_ms = NA,
      message = e$message
    )
  })
}

#' Execute a parameterized query safely
#' @param pool Database pool
#' @param query SQL query string
#' @param params Named list of parameters
#' @return Query result or NULL on error
safe_query <- function(pool, query, params = list()) {
  tryCatch({
    if (length(params) > 0) {
      # MySQL uses ? placeholders, convert from $1, $2... format
      query <- convert_params_to_mysql(query, length(params))
      DBI::dbGetQuery(pool, query, params = unname(params))
    } else {
      DBI::dbGetQuery(pool, query)
    }
  }, error = function(e) {
    log_app_error("Database query failed", 
                  error = e$message, 
                  query = substr(query, 1, 200))
    NULL
  })
}

#' Convert PostgreSQL-style parameters ($1, $2) to MySQL-style (?)
#' @param query SQL query string
#' @param num_params Number of parameters
#' @return Converted query
convert_params_to_mysql <- function(query, num_params) {
  # Convert in reverse order to avoid $1 matching $10, $11, etc.
  for (i in rev(seq_len(num_params))) {
    query <- gsub(paste0("\\$", i, "\\b"), "?", query, perl = TRUE)
  }
  query
}

#' Execute a statement (INSERT, UPDATE, DELETE)
#' @param pool Database pool
#' @param query SQL statement
#' @param params Named list of parameters
#' @return Number of affected rows or -1 on error
safe_execute <- function(pool, query, params = list()) {
  tryCatch({
    conn <- pool::poolCheckout(pool)
    on.exit(pool::poolReturn(conn))
    
    if (length(params) > 0) {
      converted_query <- convert_params_to_mysql(query, length(params))
      result <- DBI::dbExecute(conn, converted_query, params = unname(params))
    } else {
      result <- DBI::dbExecute(conn, query)
    }
    result
  }, error = function(e) {
    converted <- if (length(params) > 0) convert_params_to_mysql(query, length(params)) else query
    log_app_error("Database execute failed", 
                  error = e$message, 
                  query = substr(converted, 1, 300),
                  param_count = length(params),
                  param_classes = paste(sapply(params, class), collapse = ", "))
    -1
  })
}

#' Execute a transaction with rollback on error
#' @param pool Database pool
#' @param fn Function containing transaction logic
#' @return Result of fn or NULL on error
with_transaction <- function(pool, fn) {
  conn <- pool::poolCheckout(pool)
  on.exit(pool::poolReturn(conn))
  
  tryCatch({
    DBI::dbBegin(conn)
    result <- fn(conn)
    DBI::dbCommit(conn)
    result
  }, error = function(e) {
    DBI::dbRollback(conn)
    log_app_error("Transaction failed and rolled back", error = e$message)
    NULL
  })
}

#' Get table row count
#' @param pool Database pool
#' @param table Table name
#' @param where Optional WHERE clause
#' @return Row count
get_row_count <- function(pool, table, where = NULL) {
  query <- paste0("SELECT COUNT(*) as n FROM `", table, "`")
  if (!is.null(where)) {
    query <- paste0(query, " WHERE ", where)
  }
  result <- safe_query(pool, query)
  if (is.null(result)) 0 else result$n
}

#' Get paginated results
#' @param pool Database pool
#' @param query Base query (without LIMIT/OFFSET)
#' @param params Query parameters
#' @param page Page number (1-indexed)
#' @param page_size Number of rows per page
#' @return List with data, total, page, page_size, total_pages
get_paginated <- function(pool, query, params = list(), page = 1, page_size = 25) {
  # Get total count
  count_query <- paste0("SELECT COUNT(*) as n FROM (", query, ") as subq")
  total <- safe_query(pool, count_query, params)$n %||% 0
  
  # Get page data
  offset <- (page - 1) * page_size
  page_query <- paste0(query, " LIMIT ", page_size, " OFFSET ", offset)
  data <- safe_query(pool, page_query, params)
  
  list(
    data = data,
    total = total,
    page = page,
    page_size = page_size,
    total_pages = ceiling(total / page_size)
  )
}

#' Bulk insert data efficiently
#' @param pool Database pool
#' @param table Table name
#' @param data Data frame to insert
#' @param chunk_size Number of rows per insert
#' @return Number of rows inserted or -1 on error
bulk_insert <- function(pool, table, data, chunk_size = 1000) {
  if (nrow(data) == 0) return(0)
  
  tryCatch({
    conn <- pool::poolCheckout(pool)
    on.exit(pool::poolReturn(conn))
    
    total_inserted <- 0
    chunks <- split(data, ceiling(seq_len(nrow(data)) / chunk_size))
    
    DBI::dbBegin(conn)
    for (chunk in chunks) {
      DBI::dbWriteTable(conn, table, chunk, append = TRUE, row.names = FALSE)
      total_inserted <- total_inserted + nrow(chunk)
    }
    DBI::dbCommit(conn)
    
    log_app_info("Bulk insert completed", 
                 table = table, 
                 rows = total_inserted)
    total_inserted
  }, error = function(e) {
    log_app_error("Bulk insert failed", 
                  table = table, 
                  error = e$message)
    -1
  })
}

#' Generate UUID for MySQL (since MySQL doesn't have native UUID generation in all versions)
#' @return UUID string
generate_uuid <- function() {
  uuid::UUIDgenerate()
}
