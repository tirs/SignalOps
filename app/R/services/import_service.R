# SignalOps Import Service
# CSV upload, staging, validation, and data persistence

#' Create a new import record
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param user_id User ID
#' @param filename Stored filename
#' @param original_filename Original filename from upload
#' @param file_size File size in bytes
#' @return Import ID
create_import <- function(pool, tenant_id, user_id, filename, original_filename, file_size) {
  import_id <- generate_id()
  rows <- safe_execute(pool, "
    INSERT INTO data_imports (id, tenant_id, user_id, filename, original_filename, file_size_bytes, status)
    VALUES ($1, $2, $3, $4, $5, $6, 'pending')
  ", params = list(import_id, tenant_id, user_id, filename, original_filename, file_size))
  
  if (rows > 0) {
    create_audit_log(pool, "data_import",
                     user_id = user_id,
                     tenant_id = tenant_id,
                     entity_type = "import",
                     entity_id = import_id,
                     new_values = list(filename = original_filename, size = file_size))
    
    log_app_info("Import created", import_id = import_id, filename = original_filename)
    import_id
  } else {
    NULL
  }
}

#' Update import status
#' @param pool Database pool
#' @param import_id Import ID
#' @param status New status
#' @param error_message Optional error message
update_import_status <- function(pool, import_id, status, error_message = NULL) {
  if (status == "processing") {
    safe_execute(pool, "
      UPDATE data_imports 
      SET status = $1, started_at = CURRENT_TIMESTAMP
      WHERE id = $2
    ", params = list(status, import_id))
  } else if (status %in% c("completed", "failed")) {
    safe_execute(pool, "
      UPDATE data_imports 
      SET status = $1, completed_at = CURRENT_TIMESTAMP, error_message = $2
      WHERE id = $3
    ", params = list(status, error_message, import_id))
  } else {
    safe_execute(pool, "
      UPDATE data_imports SET status = $1 WHERE id = $2
    ", params = list(status, import_id))
  }
}

#' Parse and validate CSV file
#' @param file_path Path to CSV file
#' @param max_rows Maximum rows to read (NULL for all)
#' @return List with data and any parsing errors
parse_csv_file <- function(file_path, max_rows = NULL) {
  tryCatch({
    # Read with readr for better parsing
    data <- readr::read_csv(
      file_path,
      n_max = max_rows %||% Inf,
      show_col_types = FALSE,
      locale = readr::locale(encoding = "UTF-8")
    )
    
    # Get parsing problems
    problems <- readr::problems(data)
    
    list(
      success = TRUE,
      data = data,
      row_count = nrow(data),
      col_count = ncol(data),
      columns = names(data),
      problems = if (nrow(problems) > 0) problems else NULL
    )
  }, error = function(e) {
    list(
      success = FALSE,
      error = e$message
    )
  })
}

#' Load data into staging table
#' @param pool Database pool
#' @param import_id Import ID
#' @param data Data frame to stage
#' @param chunk_size Rows per chunk
#' @return Number of rows staged
stage_import_data <- function(pool, import_id, data, chunk_size = 1000) {
  total_staged <- 0
  
  tryCatch({
    # Process in chunks
    for (i in seq(1, nrow(data), by = chunk_size)) {
      end_row <- min(i + chunk_size - 1, nrow(data))
      chunk <- data[i:end_row, ]
      
      # Prepare staging records
      staging_records <- purrr::map_dfr(seq_len(nrow(chunk)), function(row_idx) {
        row_data <- as.list(chunk[row_idx, ])
        tibble::tibble(
          id = uuid::UUIDgenerate(),
          import_id = import_id,
          row_num = i + row_idx - 1,
          raw_data = jsonlite::toJSON(row_data, auto_unbox = TRUE)
        )
      })
      
      # Insert chunk
      conn <- pool::poolCheckout(pool)
      on.exit(pool::poolReturn(conn), add = TRUE)
      
      for (j in seq_len(nrow(staging_records))) {
        DBI::dbExecute(conn, "
          INSERT INTO staging_data (id, import_id, row_num, raw_data)
          VALUES ($1, $2, $3, $4)
        ", params = list(
          staging_records$id[j],
          staging_records$import_id[j],
          staging_records$row_num[j],
          staging_records$raw_data[j]
        ))
      }
      
      total_staged <- total_staged + nrow(chunk)
    }
    
    # Update import with row count
    safe_execute(pool, "
      UPDATE data_imports SET row_count = $1 WHERE id = $2
    ", params = list(total_staged, import_id))
    
    log_app_info("Data staged", import_id = import_id, rows = total_staged)
    total_staged
  }, error = function(e) {
    log_app_error("Staging failed", import_id = import_id, error = e$message)
    -1
  })
}

#' Commit validated data from staging to metrics table
#' @param pool Database pool
#' @param import_id Import ID
#' @param tenant_id Tenant ID
#' @return Number of rows committed
commit_import_data <- function(pool, import_id, tenant_id) {
  result <- with_transaction(pool, function(conn) {
    # Get valid staged rows
    valid_rows <- DBI::dbGetQuery(conn, "
      SELECT id, raw_data 
      FROM staging_data 
      WHERE import_id = $1 AND is_valid = TRUE
    ", params = list(import_id))
    
    if (nrow(valid_rows) == 0) {
      return(0)
    }
    
    committed <- 0
    for (i in seq_len(nrow(valid_rows))) {
      row_data <- jsonlite::fromJSON(valid_rows$raw_data[i])
      
      # Parse and insert
      metric_date <- as.Date(row_data$metric_date %||% row_data$date)
      metric_name <- row_data$metric_name %||% row_data$metric
      metric_value <- as.numeric(row_data$metric_value %||% row_data$value)
      
      DBI::dbExecute(conn, "
        INSERT INTO metrics_data 
          (tenant_id, import_id, metric_date, team, region, channel, product, 
           metric_name, metric_value, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ", params = list(
        tenant_id,
        import_id,
        metric_date,
        row_data$team,
        row_data$region,
        row_data$channel,
        row_data$product,
        metric_name,
        metric_value,
        jsonlite::toJSON(row_data, auto_unbox = TRUE)
      ))
      
      committed <- committed + 1
    }
    
    # Update import with valid count
    DBI::dbExecute(conn, "
      UPDATE data_imports 
      SET valid_row_count = $1, status = 'completed', completed_at = CURRENT_TIMESTAMP
      WHERE id = $2
    ", params = list(committed, import_id))
    
    committed
  })
  
  if (!is.null(result)) {
    log_app_info("Import committed", import_id = import_id, rows = result)
    result
  } else {
    0
  }
}

#' Get import history for a tenant
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param limit Maximum records
#' @return Data frame of imports
get_import_history <- function(pool, tenant_id, limit = 50) {
  safe_query(pool, "
    SELECT 
      di.id,
      di.original_filename,
      di.file_size_bytes,
      di.row_count,
      di.valid_row_count,
      di.error_count,
      di.status,
      di.started_at,
      di.completed_at,
      di.error_message,
      di.created_at,
      u.email as uploaded_by
    FROM data_imports di
    LEFT JOIN users u ON di.user_id = u.id
    WHERE di.tenant_id = $1
    ORDER BY di.created_at DESC
    LIMIT $2
  ", params = list(tenant_id, limit))
}

#' Get import details with validation summary
#' @param pool Database pool
#' @param import_id Import ID
#' @return Import details with error summary
get_import_details <- function(pool, import_id) {
  import <- safe_query(pool, "
    SELECT * FROM data_imports WHERE id = $1
  ", params = list(import_id))
  
  if (is.null(import) || nrow(import) == 0) {
    return(NULL)
  }
  
  # Get error summary by rule
  error_summary <- safe_query(pool, "
    SELECT 
      error_type,
      column_name,
      COUNT(*) as error_count
    FROM validation_results
    WHERE import_id = $1
    GROUP BY error_type, column_name
    ORDER BY error_count DESC
  ", params = list(import_id))
  
  # Get top failing rows
  failing_rows <- safe_query(pool, "
    SELECT 
      sd.row_num,
      sd.raw_data,
      ARRAY_AGG(vr.error_message) as errors
    FROM staging_data sd
    JOIN validation_results vr ON sd.id = vr.staging_row_id
    WHERE sd.import_id = $1 AND sd.is_valid = FALSE
    GROUP BY sd.row_num, sd.raw_data
    ORDER BY sd.row_num
    LIMIT 100
  ", params = list(import_id))
  
  list(
    import = import[1, ],
    error_summary = error_summary,
    failing_rows = failing_rows
  )
}

#' Delete staging data for an import
#' @param pool Database pool
#' @param import_id Import ID
delete_staging_data <- function(pool, import_id) {
  safe_execute(pool, "DELETE FROM staging_data WHERE import_id = $1", params = list(import_id))
}

#' Export validation errors as CSV
#' @param pool Database pool
#' @param import_id Import ID
#' @return Data frame of errors
export_validation_errors <- function(pool, import_id) {
  safe_query(pool, "
    SELECT 
      vr.row_num,
      vr.column_name,
      vr.error_type,
      vr.error_message,
      vr.actual_value,
      vr.expected_value
    FROM validation_results vr
    WHERE vr.import_id = $1
    ORDER BY vr.row_num, vr.column_name
  ", params = list(import_id))
}
