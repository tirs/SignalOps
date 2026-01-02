# SignalOps Helper Utilities
# Common utility functions used across the application

#' Generate a unique identifier
#' @return A UUID string
generate_id <- function() {
  uuid::UUIDgenerate()
}

#' Format a date for display
#' @param date Date or POSIXt object
#' @param format Output format string
#' @return Formatted date string
format_date <- function(date, format = "%Y-%m-%d") {
  if (is.null(date) || is.na(date)) return("")
  format(date, format)
}

#' Format a datetime for display
#' @param datetime POSIXt object
#' @param format Output format string
#' @return Formatted datetime string
format_datetime <- function(datetime, format = "%Y-%m-%d %H:%M:%S") {
  if (is.null(datetime) || is.na(datetime)) return("")
  format(datetime, format)
}

#' Format a number with thousands separator
#' @param x Numeric value
#' @param digits Number of decimal places
#' @return Formatted number string
format_number <- function(x, digits = 0) {
  if (is.null(x) || is.na(x)) return("")
  format(round(x, digits), big.mark = ",", scientific = FALSE)
}

#' Format a percentage
#' @param x Numeric value (0-1 or 0-100 scale)
#' @param digits Number of decimal places
#' @param scale Whether input is 0-1 (TRUE) or 0-100 (FALSE)
#' @return Formatted percentage string
format_percent <- function(x, digits = 1, scale = TRUE) {
  if (is.null(x) || is.na(x)) return("")
  if (scale) x <- x * 100
  paste0(format(round(x, digits), nsmall = digits), "%")
}

#' Format bytes to human-readable size
#' @param bytes Number of bytes
#' @return Formatted size string
format_bytes <- function(bytes) {
  if (is.null(bytes) || is.na(bytes)) return("")
  units <- c("B", "KB", "MB", "GB", "TB")
  i <- 1
  while (bytes >= 1024 && i < length(units)) {
    bytes <- bytes / 1024
    i <- i + 1
  }
  paste0(round(bytes, 2), " ", units[i])
}

#' Format duration in seconds to human-readable format
#' @param seconds Duration in seconds
#' @return Formatted duration string
format_duration <- function(seconds) {
  if (is.null(seconds) || is.na(seconds)) return("")
  if (seconds < 60) {
    return(paste0(round(seconds, 1), "s"))
  } else if (seconds < 3600) {
    mins <- floor(seconds / 60)
    secs <- round(seconds %% 60)
    return(paste0(mins, "m ", secs, "s"))
  } else {
    hours <- floor(seconds / 3600)
    mins <- floor((seconds %% 3600) / 60)
    return(paste0(hours, "h ", mins, "m"))
  }
}

#' Safely parse JSON
#' @param json_string JSON string to parse
#' @param default Default value if parsing fails
#' @return Parsed object or default
safe_json_parse <- function(json_string, default = list()) {
  if (is.null(json_string) || is.na(json_string) || json_string == "") {
    return(default)
  }
  tryCatch({
    jsonlite::fromJSON(json_string)
  }, error = function(e) {
    default
  })
}

#' Truncate text to specified length
#' @param text Text to truncate
#' @param max_length Maximum length
#' @param suffix Suffix to add if truncated
#' @return Truncated text
truncate_text <- function(text, max_length = 100, suffix = "...") {
  if (is.null(text) || is.na(text)) return("")
  if (nchar(text) <= max_length) return(text)
  paste0(substr(text, 1, max_length - nchar(suffix)), suffix)
}

#' Sanitize a string for use in SQL
#' @param x String to sanitize
#' @return Sanitized string
sanitize_string <- function(x) {
  if (is.null(x) || is.na(x)) return("")
  gsub("[^a-zA-Z0-9_\\-\\.]", "", x)
}

#' Validate email format
#' @param email Email string to validate
#' @return TRUE if valid, FALSE otherwise
is_valid_email <- function(email) {
  if (is.null(email) || is.na(email) || email == "") return(FALSE)
  grepl("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email)
}

#' Create a slug from a string
#' @param text Text to convert
#' @return URL-safe slug
slugify <- function(text) {
  if (is.null(text) || is.na(text)) return("")
  text <- tolower(text)
  text <- gsub("[^a-z0-9\\s-]", "", text)
  text <- gsub("\\s+", "-", text)
  text <- gsub("-+", "-", text)
  gsub("^-|-$", "", text)
}

#' Get client IP from Shiny session
#' @param session Shiny session object
#' @return IP address string
get_client_ip <- function(session) {
  if (is.null(session)) return(NULL)
  
  # Try different methods to get IP
  ip <- session$request$HTTP_X_FORWARDED_FOR
  if (!is.null(ip) && ip != "") {
    # Take first IP if multiple (proxy chain)
    return(strsplit(ip, ",")[[1]][1])
  }
  
  ip <- session$request$HTTP_X_REAL_IP
  if (!is.null(ip) && ip != "") return(ip)
  
  ip <- session$request$REMOTE_ADDR
  if (!is.null(ip) && ip != "") return(ip)
  
  "unknown"
}

#' Get user agent from Shiny session
#' @param session Shiny session object
#' @return User agent string
get_user_agent <- function(session) {
  if (is.null(session)) return(NULL)
  session$request$HTTP_USER_AGENT
}

#' Calculate percentage change
#' @param current Current value
#' @param previous Previous value
#' @return Percentage change
calc_pct_change <- function(current, previous) {
  if (is.null(previous) || is.na(previous) || previous == 0) return(NA)
  ((current - previous) / abs(previous)) * 100
}

#' Create severity badge HTML
#' @param severity Severity level (low, medium, high, critical)
#' @return HTML span element
severity_badge <- function(severity) {
  colors <- list(
    low = "success",
    medium = "warning",
    high = "danger",
    critical = "dark"
  )
  color <- colors[[tolower(severity)]] %||% "secondary"
  htmltools::span(
    class = paste0("badge bg-", color),
    toupper(severity)
  )
}

#' Create status badge HTML
#' @param status Status value
#' @return HTML span element
status_badge <- function(status) {
  colors <- list(
    open = "danger",
    investigating = "warning",
    mitigated = "info",
    closed = "success",
    false_positive = "secondary",
    pending = "warning",
    running = "primary",
    completed = "success",
    failed = "danger",
    cancelled = "secondary",
    active = "success",
    inactive = "secondary",
    locked = "danger"
  )
  color <- colors[[tolower(status)]] %||% "secondary"
  htmltools::span(
    class = paste0("badge bg-", color),
    gsub("_", " ", toupper(status))
  )
}

#' Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Empty string coalescing
`%empty%` <- function(x, y) {
  if (is.null(x) || is.na(x) || x == "") y else x
}
