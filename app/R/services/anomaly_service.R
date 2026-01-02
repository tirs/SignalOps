# SignalOps Anomaly Detection Service
# Statistical anomaly detection and baseline computation

#' Calculate anomaly baselines for metrics
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param window_days Number of days for baseline window
#' @return Number of baselines computed
compute_baselines <- function(pool, tenant_id, window_days = 30) {
  # Get distinct metric/dimension combinations
  metrics <- safe_query(pool, "
    SELECT DISTINCT 
      metric_name,
      team,
      region
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date >= DATE_SUB(CURDATE(), INTERVAL $2 DAY)
  ", params = list(tenant_id, window_days))
  
  if (is.null(metrics) || nrow(metrics) == 0) {
    return(0)
  }
  
  computed <- 0
  
  for (i in seq_len(nrow(metrics))) {
    metric <- metrics[i, ]
    
    # Create dimensions hash
    dims <- list(team = metric$team, region = metric$region)
    dims_hash <- digest::digest(dims, algo = "md5")
    
    # Get historical values
    values <- safe_query(pool, "
      SELECT metric_value
      FROM metrics_data
      WHERE tenant_id = $1
        AND metric_name = $2
        AND (team = $3 OR ($3 IS NULL AND team IS NULL))
        AND (region = $4 OR ($4 IS NULL AND region IS NULL))
        AND metric_date >= DATE_SUB(CURDATE(), INTERVAL $5 DAY)
      ORDER BY metric_date
    ", params = list(tenant_id, metric$metric_name, metric$team, 
                     metric$region, window_days))
    
    if (is.null(values) || nrow(values) < 7) {
      next  # Not enough data points
    }
    
    vals <- values$metric_value
    
    # Calculate statistics
    baseline_mean <- mean(vals, na.rm = TRUE)
    baseline_std <- sd(vals, na.rm = TRUE)
    baseline_median <- median(vals, na.rm = TRUE)
    baseline_mad <- mad(vals, na.rm = TRUE)
    
    # MySQL uses INSERT ... ON DUPLICATE KEY UPDATE
    safe_execute(pool, "
      INSERT INTO anomaly_baselines 
        (id, tenant_id, metric_name, dimensions_hash, dimensions, 
         baseline_mean, baseline_std, baseline_median, baseline_mad,
         data_points, window_start, window_end, calculated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 
              DATE_SUB(CURDATE(), INTERVAL $11 DAY), CURDATE(), NOW())
      ON DUPLICATE KEY UPDATE
        baseline_mean = VALUES(baseline_mean),
        baseline_std = VALUES(baseline_std),
        baseline_median = VALUES(baseline_median),
        baseline_mad = VALUES(baseline_mad),
        data_points = VALUES(data_points),
        window_start = VALUES(window_start),
        window_end = VALUES(window_end),
        calculated_at = NOW()
    ", params = list(
      generate_id(),
      tenant_id,
      metric$metric_name,
      dims_hash,
      jsonlite::toJSON(dims, auto_unbox = TRUE),
      baseline_mean,
      baseline_std,
      baseline_median,
      baseline_mad,
      nrow(values),
      window_days
    ))
    
    computed <- computed + 1
  }
  
  log_app_info("Baselines computed", tenant_id = tenant_id, count = computed)
  computed
}

#' Detect anomalies in recent data
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param config Anomaly detection configuration
#' @return Number of anomalies detected
detect_anomalies <- function(pool, tenant_id, config = NULL) {
  if (is.null(config)) {
    config <- list(
      zscore_threshold_low = 2.0,
      zscore_threshold_medium = 3.0,
      zscore_threshold_high = 4.0
    )
  }
  
  # Get recent metrics with baselines (MySQL compatible)
  metrics <- safe_query(pool, "
    SELECT 
      m.id,
      m.metric_date,
      m.metric_name,
      m.metric_value,
      m.team,
      m.region,
      b.baseline_mean,
      b.baseline_std,
      b.baseline_median,
      b.baseline_mad,
      b.data_points
    FROM metrics_data m
    LEFT JOIN anomaly_baselines b ON 
      b.tenant_id = m.tenant_id
      AND b.metric_name = m.metric_name
      AND b.dimensions_hash = MD5(
        CONCAT(COALESCE(m.team, ''), '|', COALESCE(m.region, ''))
      )
    WHERE m.tenant_id = $1
      AND m.metric_date >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)
      AND b.id IS NOT NULL
      AND b.baseline_std > 0
  ", params = list(tenant_id))
  
  if (is.null(metrics) || nrow(metrics) == 0) {
    return(0)
  }
  
  detected <- 0
  
  for (i in seq_len(nrow(metrics))) {
    m <- metrics[i, ]
    
    # Calculate z-score
    zscore <- (m$metric_value - m$baseline_mean) / m$baseline_std
    abs_zscore <- abs(zscore)
    
    # Determine severity
    severity <- NULL
    if (abs_zscore >= config$zscore_threshold_high) {
      severity <- "high"
    } else if (abs_zscore >= config$zscore_threshold_medium) {
      severity <- "medium"
    } else if (abs_zscore >= config$zscore_threshold_low) {
      severity <- "low"
    }
    
    if (!is.null(severity)) {
      # Check if anomaly already exists
      existing <- safe_query(pool, "
        SELECT id FROM anomalies 
        WHERE metric_id = $1
      ", params = list(m$id))
      
      if (!is.null(existing) && nrow(existing) > 0) {
        next  # Already detected
      }
      
      # Calculate thresholds
      threshold_low <- m$baseline_mean - 
        (config$zscore_threshold_low * m$baseline_std)
      threshold_high <- m$baseline_mean + 
        (config$zscore_threshold_low * m$baseline_std)
      
      # Generate explanation
      direction <- if (zscore > 0) "above" else "below"
      explanation <- sprintf(
        "Value %.2f is %.1f standard deviations %s the baseline (mean: %.2f)",
        m$metric_value, abs_zscore, direction, m$baseline_mean
      )
      
      # Insert anomaly
      safe_execute(pool, "
        INSERT INTO anomalies 
          (id, tenant_id, metric_id, detection_date, metric_name, metric_value,
           baseline_value, threshold_low, threshold_high, zscore, severity,
           detection_method, explanation, dimensions)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 
                'zscore', $12, $13)
      ", params = list(
        generate_id(),
        tenant_id,
        m$id,
        m$metric_date,
        m$metric_name,
        m$metric_value,
        m$baseline_mean,
        threshold_low,
        threshold_high,
        zscore,
        severity,
        explanation,
        jsonlite::toJSON(list(team = m$team, region = m$region), auto_unbox = TRUE)
      ))
      
      detected <- detected + 1
    }
  }
  
  log_app_info("Anomalies detected", tenant_id = tenant_id, count = detected)
  detected
}

#' Get anomalies for display
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date filter
#' @param end_date End date filter
#' @param severity Severity filter
#' @param acknowledged Filter by acknowledgment status
#' @param limit Max records
#' @return Data frame of anomalies
get_anomalies <- function(pool, tenant_id, start_date = NULL, end_date = NULL,
                          severity = NULL, acknowledged = NULL, limit = 100) {
  query <- "
    SELECT 
      a.id,
      a.detection_date,
      a.metric_name,
      a.metric_value,
      a.baseline_value,
      a.threshold_low,
      a.threshold_high,
      a.zscore,
      a.severity,
      a.explanation,
      a.dimensions,
      a.is_acknowledged,
      a.created_at,
      u.email as acknowledged_by_email
    FROM anomalies a
    LEFT JOIN users u ON a.acknowledged_by = u.id
    WHERE a.tenant_id = $1
  "
  
  params <- list(tenant_id)
  param_idx <- 1
  
  if (!is.null(start_date)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND a.detection_date >= $", param_idx)
    params[[param_idx]] <- start_date
  }
  
  if (!is.null(end_date)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND a.detection_date <= $", param_idx)
    params[[param_idx]] <- end_date
  }
  
  if (!is.null(severity)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND a.severity = $", param_idx)
    params[[param_idx]] <- severity
  }
  
  if (!is.null(acknowledged)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND a.is_acknowledged = $", param_idx)
    params[[param_idx]] <- acknowledged
  }
  
  query <- paste0(query, " ORDER BY a.created_at DESC LIMIT ", limit)
  
  safe_query(pool, query, params = params)
}

#' Acknowledge an anomaly
#' @param pool Database pool
#' @param anomaly_id Anomaly ID
#' @param user_id User acknowledging
acknowledge_anomaly <- function(pool, anomaly_id, user_id) {
  safe_execute(pool, "
    UPDATE anomalies 
    SET is_acknowledged = TRUE, 
        acknowledged_by = $1, 
        acknowledged_at = NOW()
    WHERE id = $2
  ", params = list(user_id, anomaly_id))
}

#' Get anomaly trend data for charts
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param days Number of days
#' @return Data frame with daily anomaly counts
get_anomaly_trend <- function(pool, tenant_id, days = 30) {
  safe_query(pool, "
    SELECT 
      detection_date,
      severity,
      COUNT(*) as count
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date >= DATE_SUB(CURDATE(), INTERVAL $2 DAY)
    GROUP BY detection_date, severity
    ORDER BY detection_date
  ", params = list(tenant_id, days))
}

#' Get anomaly summary statistics
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param days Number of days
#' @return List with anomaly stats
get_anomaly_stats <- function(pool, tenant_id, days = 30) {
  # MySQL compatible - use SUM(CASE WHEN) instead of COUNT(*) FILTER
  stats <- safe_query(pool, "
    SELECT 
      COUNT(*) as total,
      SUM(CASE WHEN severity = 'high' THEN 1 ELSE 0 END) as high_count,
      SUM(CASE WHEN severity = 'medium' THEN 1 ELSE 0 END) as medium_count,
      SUM(CASE WHEN severity = 'low' THEN 1 ELSE 0 END) as low_count,
      SUM(CASE WHEN is_acknowledged = TRUE THEN 1 ELSE 0 END) 
        as acknowledged_count,
      SUM(CASE WHEN is_acknowledged = FALSE THEN 1 ELSE 0 END) 
        as unacknowledged_count
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date >= DATE_SUB(CURDATE(), INTERVAL $2 DAY)
  ", params = list(tenant_id, days))
  
  by_metric <- safe_query(pool, "
    SELECT 
      metric_name,
      COUNT(*) as count,
      AVG(ABS(zscore)) as avg_zscore
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date >= DATE_SUB(CURDATE(), INTERVAL $2 DAY)
    GROUP BY metric_name
    ORDER BY count DESC
    LIMIT 10
  ", params = list(tenant_id, days))
  
  list(
    summary = if (!is.null(stats) && nrow(stats) > 0) stats[1, ] else NULL,
    by_metric = by_metric
  )
}
