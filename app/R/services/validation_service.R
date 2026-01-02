# SignalOps Validation Service
# Data quality rules engine and validation logic

#' Get active validation rules for a tenant
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @return Data frame of validation rules
get_validation_rules <- function(pool, tenant_id) {
  safe_query(pool, "
    SELECT id, name, description, rule_type, column_name, parameters, severity
    FROM validation_rules
    WHERE tenant_id = $1 AND is_active = TRUE
    ORDER BY column_name, rule_type
  ", params = list(tenant_id))
}

#' Validate a single value against a rule
#' @param value Value to validate
#' @param rule Rule definition (list)
#' @return List with is_valid and error message
validate_value <- function(value, rule) {
  rule_type <- rule$rule_type
  params <- if (is.character(rule$parameters)) {
    jsonlite::fromJSON(rule$parameters)
  } else {
    rule$parameters
  }
  
  # Handle NULL/NA values
  is_empty <- is.null(value) || is.na(value) || 
    (is.character(value) && stringr::str_trim(value) == "")
  
  result <- switch(rule_type,
    "required" = {
      if (is_empty) {
        list(is_valid = FALSE, message = paste(rule$column_name, "is required"))
      } else {
        list(is_valid = TRUE)
      }
    },
    
    "type_numeric" = {
      if (is_empty) {
        list(is_valid = TRUE)  # Empty handled by required rule
      } else if (suppressWarnings(is.na(as.numeric(value)))) {
        list(is_valid = FALSE, message = paste(rule$column_name, "must be numeric"))
      } else {
        list(is_valid = TRUE)
      }
    },
    
    "type_date" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        format <- params$format %||% "%Y-%m-%d"
        parsed <- tryCatch({
          as.Date(value, format = format)
        }, error = function(e) NA)
        
        if (is.na(parsed)) {
          list(is_valid = FALSE, message = paste(rule$column_name, "must be a valid date (", format, ")"))
        } else {
          list(is_valid = TRUE)
        }
      }
    },
    
    "type_integer" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        num <- suppressWarnings(as.numeric(value))
        if (is.na(num) || num != floor(num)) {
          list(is_valid = FALSE, message = paste(rule$column_name, "must be an integer"))
        } else {
          list(is_valid = TRUE)
        }
      }
    },
    
    "range" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        num <- suppressWarnings(as.numeric(value))
        if (is.na(num)) {
          list(is_valid = TRUE)  # Type check done by type_numeric
        } else {
          min_val <- params$min
          max_val <- params$max
          
          if (!is.null(min_val) && num < min_val) {
            list(is_valid = FALSE, message = paste(rule$column_name, "must be >=", min_val))
          } else if (!is.null(max_val) && num > max_val) {
            list(is_valid = FALSE, message = paste(rule$column_name, "must be <=", max_val))
          } else {
            list(is_valid = TRUE)
          }
        }
      }
    },
    
    "allowed_values" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        allowed <- params$values
        if (is.null(allowed)) {
          list(is_valid = TRUE)
        } else if (!(value %in% allowed)) {
          list(is_valid = FALSE, 
               message = paste(rule$column_name, "must be one of:", paste(allowed, collapse = ", ")))
        } else {
          list(is_valid = TRUE)
        }
      }
    },
    
    "regex" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        pattern <- params$pattern
        if (is.null(pattern)) {
          list(is_valid = TRUE)
        } else if (!grepl(pattern, value)) {
          list(is_valid = FALSE, 
               message = paste(rule$column_name, "does not match required pattern"))
        } else {
          list(is_valid = TRUE)
        }
      }
    },
    
    "max_length" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        max_len <- params$max
        if (is.null(max_len)) {
          list(is_valid = TRUE)
        } else if (nchar(as.character(value)) > max_len) {
          list(is_valid = FALSE, 
               message = paste(rule$column_name, "exceeds max length of", max_len))
        } else {
          list(is_valid = TRUE)
        }
      }
    },
    
    # Default: unknown rule type
    list(is_valid = TRUE)
  )
  
  result$severity <- rule$severity %||% "error"
  result
}

#' Validate all staged data for an import
#' @param pool Database pool
#' @param import_id Import ID
#' @param tenant_id Tenant ID
#' @param chunk_size Rows to process per batch
#' @return List with validation summary
validate_import_data <- function(pool, import_id, tenant_id, chunk_size = 500) {
  # Get validation rules
  rules <- get_validation_rules(pool, tenant_id)
  
  if (is.null(rules) || nrow(rules) == 0) {
    log_app_warn("No validation rules found", tenant_id = tenant_id)
    # Mark all as valid if no rules
    safe_execute(pool, "
      UPDATE staging_data SET is_valid = TRUE WHERE import_id = $1
    ", params = list(import_id))
    return(list(total = 0, valid = 0, errors = 0))
  }
  
  # Get staging data count
  total_rows <- safe_query(pool, "
    SELECT COUNT(*) as n FROM staging_data WHERE import_id = $1
  ", params = list(import_id))$n
  
  valid_count <- 0
  error_count <- 0
  
  # Process in chunks
  offset <- 0
  while (offset < total_rows) {
    staging_chunk <- safe_query(pool, "
      SELECT id, row_num, raw_data
      FROM staging_data
      WHERE import_id = $1
      ORDER BY row_num
      LIMIT $2 OFFSET $3
    ", params = list(import_id, chunk_size, offset))
    
    if (is.null(staging_chunk) || nrow(staging_chunk) == 0) break
    
    for (i in seq_len(nrow(staging_chunk))) {
      row <- staging_chunk[i, ]
      row_data <- jsonlite::fromJSON(row$raw_data)
      
      row_errors <- list()
      has_error <- FALSE
      
      # Apply each rule
      for (j in seq_len(nrow(rules))) {
        rule <- as.list(rules[j, ])
        column <- rule$column_name
        value <- row_data[[column]]
        
        result <- validate_value(value, rule)
        
        if (!result$is_valid) {
          row_errors <- c(row_errors, list(list(
            rule_id = rule$id,
            column_name = column,
            error_type = rule$rule_type,
            error_message = result$message,
            actual_value = as.character(value),
            severity = result$severity
          )))
          
          if (result$severity == "error") {
            has_error <- TRUE
          }
        }
      }
      
      # Store validation results
      if (length(row_errors) > 0) {
        for (err in row_errors) {
          safe_execute(pool, "
            INSERT INTO validation_results 
              (import_id, rule_id, staging_row_id, row_num, column_name, 
               error_type, error_message, actual_value)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
          ", params = list(
            import_id,
            err$rule_id,
            row$id,
            row$row_num,
            err$column_name,
            err$error_type,
            err$error_message,
            err$actual_value
          ))
        }
        error_count <- error_count + length(row_errors)
      }
      
      # Update staging row validity
      is_valid <- !has_error
      safe_execute(pool, "
        UPDATE staging_data 
        SET is_valid = $1, validation_errors = $2
        WHERE id = $3
      ", params = list(
        is_valid,
        jsonlite::toJSON(row_errors, auto_unbox = TRUE),
        row$id
      ))
      
      if (is_valid) valid_count <- valid_count + 1
    }
    
    offset <- offset + chunk_size
  }
  
  # Update import error count
  safe_execute(pool, "
    UPDATE data_imports SET error_count = $1 WHERE id = $2
  ", params = list(error_count, import_id))
  
  log_app_info("Validation completed",
               import_id = import_id,
               total = total_rows,
               valid = valid_count,
               errors = error_count)
  
  list(
    total = total_rows,
    valid = valid_count,
    invalid = total_rows - valid_count,
    error_count = error_count
  )
}

#' Create a new validation rule
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param name Rule name
#' @param description Rule description
#' @param rule_type Type of rule
#' @param column_name Target column
#' @param parameters Rule parameters (list)
#' @param severity Error severity
#' @return Rule ID or NULL
create_validation_rule <- function(pool, tenant_id, name, description, rule_type,
                                   column_name, parameters = list(), severity = "error") {
  rule_id <- generate_id()
  rows <- safe_execute(pool, "
    INSERT INTO validation_rules 
      (id, tenant_id, name, description, rule_type, column_name, parameters, severity)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
  ", params = list(
    rule_id,
    tenant_id,
    name,
    description,
    rule_type,
    column_name,
    jsonlite::toJSON(parameters, auto_unbox = TRUE),
    severity
  ))
  
  if (rows > 0) {
    log_app_info("Validation rule created", rule_id = rule_id, name = name)
    rule_id
  } else {
    NULL
  }
}

#' Update a validation rule
#' @param pool Database pool
#' @param rule_id Rule ID
#' @param ... Fields to update
update_validation_rule <- function(pool, rule_id, ...) {
  updates <- list(...)
  if (length(updates) == 0) return(FALSE)
  
  # Build update query
  set_clauses <- character()
  params <- list()
  param_idx <- 0
  
  for (field in names(updates)) {
    param_idx <- param_idx + 1
    set_clauses <- c(set_clauses, paste0(field, " = $", param_idx))
    
    value <- updates[[field]]
    if (field == "parameters" && is.list(value)) {
      value <- jsonlite::toJSON(value, auto_unbox = TRUE)
    }
    params[[param_idx]] <- value
  }
  
  param_idx <- param_idx + 1
  params[[param_idx]] <- rule_id
  
  query <- paste0(
    "UPDATE validation_rules SET ",
    paste(set_clauses, collapse = ", "),
    " WHERE id = $", param_idx
  )
  
  result <- safe_execute(pool, query, params = params)
  result > 0
}

#' Delete a validation rule
#' @param pool Database pool
#' @param rule_id Rule ID
delete_validation_rule <- function(pool, rule_id) {
  result <- safe_execute(pool, "
    DELETE FROM validation_rules WHERE id = $1
  ", params = list(rule_id))
  result > 0
}

#' Get validation summary statistics
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param days Number of days to look back
#' @return List with validation stats
get_validation_stats <- function(pool, tenant_id, days = 30) {
  stats <- safe_query(pool, "
    SELECT 
      COUNT(*) as total_imports,
      SUM(row_count) as total_rows,
      SUM(valid_row_count) as valid_rows,
      SUM(error_count) as total_errors,
      AVG(CASE WHEN row_count > 0 
          THEN (valid_row_count::float / row_count * 100) 
          ELSE 0 END) as avg_valid_pct
    FROM data_imports
    WHERE tenant_id = $1 
      AND status = 'completed'
      AND created_at >= CURRENT_DATE - $2
  ", params = list(tenant_id, days))
  
  error_by_type <- safe_query(pool, "
    SELECT 
      vr.error_type,
      vr.column_name,
      COUNT(*) as count
    FROM validation_results vr
    JOIN data_imports di ON vr.import_id = di.id
    WHERE di.tenant_id = $1
      AND di.created_at >= CURRENT_DATE - $2
    GROUP BY vr.error_type, vr.column_name
    ORDER BY count DESC
    LIMIT 10
  ", params = list(tenant_id, days))
  
  list(
    summary = if (!is.null(stats) && nrow(stats) > 0) stats[1, ] else NULL,
    errors_by_type = error_by_type
  )
}
