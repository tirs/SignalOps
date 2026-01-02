# SignalOps Caching Utilities
# Performance optimization through intelligent caching

#' Create a cache key from parameters
#' @param prefix Cache key prefix
#' @param ... Parameters to include in key
#' @return Cache key string
make_cache_key <- function(prefix, ...) {
  params <- list(...)
  param_str <- paste(sapply(params, function(x) {
    if (is.null(x)) "NULL"
    else if (is.list(x)) digest::digest(x)
    else as.character(x)
  }), collapse = "_")
  paste0(prefix, "_", param_str)
}

#' Get value from cache with automatic refresh
#' @param cache Cache object
#' @param key Cache key
#' @param compute_fn Function to compute value if not cached
#' @param ttl Time-to-live in seconds (overrides default)
#' @return Cached or computed value
get_cached <- function(cache, key, compute_fn, ttl = NULL) {
  if (is.null(cache)) {
    return(compute_fn())
  }
  
  cached <- cache$get(key)
  if (!is.null(cached)) {
    log_app_debug("Cache hit", key = key)
    return(cached)
  }
  
  log_app_debug("Cache miss, computing", key = key)
  value <- compute_fn()
  cache$set(key, value)
  value
}

#' Invalidate cache entries by prefix
#' @param cache Cache object
#' @param prefix Key prefix to invalidate
invalidate_cache_prefix <- function(cache, prefix) {
  if (is.null(cache)) return(invisible())
  
  # Note: cachem doesn't support prefix deletion directly
  # For production, consider Redis or other cache backends
  log_app_debug("Cache prefix invalidation requested", prefix = prefix)
  invisible()
}

#' Create a memoised function with custom cache
#' @param fn Function to memoise
#' @param cache Cache object (optional)
#' @return Memoised function
create_memoised <- function(fn, cache = NULL) {
  if (!is.null(cache)) {
    memoise::memoise(fn, cache = cache)
  } else {
    memoise::memoise(fn)
  }
}

#' Clear all cache entries
#' @param cache Cache object
clear_cache <- function(cache) {
  if (is.null(cache)) return(invisible())
  cache$reset()
  log_app_info("Cache cleared")
  invisible()
}

#' Get cache statistics
#' @param cache Cache object
#' @return List with cache stats
cache_stats <- function(cache) {
  if (is.null(cache)) {
    return(list(enabled = FALSE))
  }
  
  # cachem provides info method
  info <- cache$info()
  list(
    enabled = TRUE,
    current_size = info$current_size %||% 0,
    max_size = info$max_size %||% 0,
    n_objects = info$n %||% 0
  )
}

# Query result caching with automatic key generation
#' Cache a database query result
#' @param pool Database pool
#' @param cache Cache object
#' @param query SQL query string
#' @param params Query parameters
#' @param prefix Cache key prefix
#' @param ttl Time-to-live in seconds
#' @return Query result
cached_query <- function(pool, cache, query, params = list(), prefix = "query", ttl = NULL) {
  key <- make_cache_key(prefix, digest::digest(query), digest::digest(params))
  
  get_cached(cache, key, function() {
    if (length(params) > 0) {
      DBI::dbGetQuery(pool, query, params = params)
    } else {
      DBI::dbGetQuery(pool, query)
    }
  }, ttl = ttl)
}

#' Cache KPI computation
#' @param cache Cache object
#' @param tenant_id Tenant identifier
#' @param metric_name Metric name
#' @param period Time period
#' @param compute_fn Function to compute KPI
#' @return KPI value
cached_kpi <- function(cache, tenant_id, metric_name, period, compute_fn) {
  key <- make_cache_key("kpi", tenant_id, metric_name, period)
  get_cached(cache, key, compute_fn)
}

#' Cache dashboard data
#' @param cache Cache object
#' @param tenant_id Tenant identifier
#' @param dashboard_id Dashboard identifier
#' @param filters Applied filters
#' @param compute_fn Function to compute dashboard data
#' @return Dashboard data
cached_dashboard <- function(cache, tenant_id, dashboard_id, filters, compute_fn) {
  key <- make_cache_key("dashboard", tenant_id, dashboard_id, digest::digest(filters))
  get_cached(cache, key, compute_fn)
}
