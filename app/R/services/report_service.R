# SignalOps Report Service
# Report generation and export functionality

#' Generate KPI summary data for reports
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @return List with KPI data
get_kpi_report_data <- function(pool, tenant_id, start_date, end_date) {
  # Overall metrics
  metrics_summary <- safe_query(pool, "
    SELECT 
      COUNT(DISTINCT metric_name) as metric_count,
      COUNT(*) as data_points,
      MIN(metric_date) as date_min,
      MAX(metric_date) as date_max
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
  ", params = list(tenant_id, start_date, end_date))
  
  # By metric
  by_metric <- safe_query(pool, "
    SELECT 
      metric_name,
      COUNT(*) as data_points,
      AVG(metric_value) as avg_value,
      MIN(metric_value) as min_value,
      MAX(metric_value) as max_value,
      STDDEV(metric_value) as std_value
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
    GROUP BY metric_name
    ORDER BY data_points DESC
  ", params = list(tenant_id, start_date, end_date))
  
  # Daily trend
  daily_trend <- safe_query(pool, "
    SELECT 
      metric_date,
      metric_name,
      SUM(metric_value) as total_value,
      AVG(metric_value) as avg_value,
      COUNT(*) as count
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
    GROUP BY metric_date, metric_name
    ORDER BY metric_date, metric_name
  ", params = list(tenant_id, start_date, end_date))
  
  # By dimension
  by_team <- safe_query(pool, "
    SELECT 
      COALESCE(team, 'Unassigned') as team,
      COUNT(*) as data_points,
      SUM(metric_value) as total_value
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
    GROUP BY team
    ORDER BY total_value DESC
  ", params = list(tenant_id, start_date, end_date))
  
  by_region <- safe_query(pool, "
    SELECT 
      COALESCE(region, 'Unknown') as region,
      COUNT(*) as data_points,
      SUM(metric_value) as total_value
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
    GROUP BY region
    ORDER BY total_value DESC
  ", params = list(tenant_id, start_date, end_date))
  
  list(
    summary = if (!is.null(metrics_summary)) metrics_summary[1, ] else NULL,
    by_metric = by_metric,
    daily_trend = daily_trend,
    by_team = by_team,
    by_region = by_region
  )
}

#' Generate anomaly report data
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @return List with anomaly data
get_anomaly_report_data <- function(pool, tenant_id, start_date, end_date) {
  summary <- safe_query(pool, "
    SELECT 
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE severity = 'high') as high_count,
      COUNT(*) FILTER (WHERE severity = 'medium') as medium_count,
      COUNT(*) FILTER (WHERE severity = 'low') as low_count,
      COUNT(*) FILTER (WHERE is_acknowledged) as acknowledged_count
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date BETWEEN $2 AND $3
  ", params = list(tenant_id, start_date, end_date))
  
  by_metric <- safe_query(pool, "
    SELECT 
      metric_name,
      severity,
      COUNT(*) as count,
      AVG(ABS(zscore)) as avg_zscore
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date BETWEEN $2 AND $3
    GROUP BY metric_name, severity
    ORDER BY count DESC
  ", params = list(tenant_id, start_date, end_date))
  
  timeline <- safe_query(pool, "
    SELECT 
      detection_date,
      severity,
      COUNT(*) as count
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date BETWEEN $2 AND $3
    GROUP BY detection_date, severity
    ORDER BY detection_date
  ", params = list(tenant_id, start_date, end_date))
  
  top_anomalies <- safe_query(pool, "
    SELECT 
      detection_date,
      metric_name,
      metric_value,
      baseline_value,
      zscore,
      severity,
      explanation
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date BETWEEN $2 AND $3
    ORDER BY ABS(zscore) DESC
    LIMIT 20
  ", params = list(tenant_id, start_date, end_date))
  
  list(
    summary = if (!is.null(summary)) summary[1, ] else NULL,
    by_metric = by_metric,
    timeline = timeline,
    top_anomalies = top_anomalies
  )
}

#' Generate incident report data
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @return List with incident data
get_incident_report_data <- function(pool, tenant_id, start_date, end_date) {
  summary <- safe_query(pool, "
    SELECT 
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE status = 'open') as open_count,
      COUNT(*) FILTER (WHERE status = 'investigating') as investigating_count,
      COUNT(*) FILTER (WHERE status = 'closed') as closed_count,
      COUNT(*) FILTER (WHERE sla_due_at < CURRENT_TIMESTAMP AND status NOT IN ('closed', 'false_positive')) as sla_breached,
      AVG(EXTRACT(EPOCH FROM (COALESCE(resolved_at, CURRENT_TIMESTAMP) - created_at)) / 3600) 
        FILTER (WHERE status = 'closed') as avg_resolution_hours
    FROM incidents
    WHERE tenant_id = $1
      AND created_at::date BETWEEN $2 AND $3
  ", params = list(tenant_id, start_date, end_date))
  
  by_severity <- safe_query(pool, "
    SELECT 
      severity,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE status = 'closed') as closed,
      AVG(EXTRACT(EPOCH FROM (COALESCE(resolved_at, CURRENT_TIMESTAMP) - created_at)) / 3600) 
        FILTER (WHERE status = 'closed') as avg_resolution_hours
    FROM incidents
    WHERE tenant_id = $1
      AND created_at::date BETWEEN $2 AND $3
    GROUP BY severity
  ", params = list(tenant_id, start_date, end_date))
  
  by_assignee <- safe_query(pool, "
    SELECT 
      COALESCE(u.email, 'Unassigned') as assignee,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE i.status = 'closed') as closed
    FROM incidents i
    LEFT JOIN users u ON i.assigned_to = u.id
    WHERE i.tenant_id = $1
      AND i.created_at::date BETWEEN $2 AND $3
    GROUP BY u.email
    ORDER BY total DESC
  ", params = list(tenant_id, start_date, end_date))
  
  recent <- safe_query(pool, "
    SELECT 
      i.id,
      i.title,
      i.severity,
      i.status,
      i.created_at,
      i.resolved_at,
      u.email as assigned_to
    FROM incidents i
    LEFT JOIN users u ON i.assigned_to = u.id
    WHERE i.tenant_id = $1
      AND i.created_at::date BETWEEN $2 AND $3
    ORDER BY i.created_at DESC
    LIMIT 50
  ", params = list(tenant_id, start_date, end_date))
  
  list(
    summary = if (!is.null(summary)) summary[1, ] else NULL,
    by_severity = by_severity,
    by_assignee = by_assignee,
    recent = recent
  )
}

#' Export metrics data to CSV
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @param metric_names Optional metric name filter
#' @return Data frame for export
export_metrics_csv <- function(pool, tenant_id, start_date, end_date, metric_names = NULL) {
  query <- "
    SELECT 
      metric_date,
      team,
      region,
      channel,
      product,
      metric_name,
      metric_value,
      created_at
    FROM metrics_data
    WHERE tenant_id = $1
      AND metric_date BETWEEN $2 AND $3
  "
  
  params <- list(tenant_id, start_date, end_date)
  
  if (!is.null(metric_names) && length(metric_names) > 0) {
    placeholders <- paste0("$", seq_along(metric_names) + 3, collapse = ", ")
    query <- paste0(query, " AND metric_name IN (", placeholders, ")")
    params <- c(params, as.list(metric_names))
  }
  
  query <- paste0(query, " ORDER BY metric_date, metric_name")
  
  safe_query(pool, query, params = params)
}

#' Export anomalies to CSV
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @return Data frame for export
export_anomalies_csv <- function(pool, tenant_id, start_date, end_date) {
  safe_query(pool, "
    SELECT 
      detection_date,
      metric_name,
      metric_value,
      baseline_value,
      threshold_low,
      threshold_high,
      zscore,
      severity,
      detection_method,
      explanation,
      is_acknowledged,
      created_at
    FROM anomalies
    WHERE tenant_id = $1
      AND detection_date BETWEEN $2 AND $3
    ORDER BY detection_date DESC, severity DESC
  ", params = list(tenant_id, start_date, end_date))
}

#' Export incidents to CSV
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param start_date Start date
#' @param end_date End date
#' @return Data frame for export
export_incidents_csv <- function(pool, tenant_id, start_date, end_date) {
  safe_query(pool, "
    SELECT 
      i.id,
      i.title,
      i.description,
      i.status,
      i.severity,
      u_assigned.email as assigned_to,
      u_created.email as created_by,
      i.sla_due_at,
      i.resolved_at,
      i.resolution_notes,
      i.root_cause,
      i.impact,
      i.created_at
    FROM incidents i
    LEFT JOIN users u_assigned ON i.assigned_to = u_assigned.id
    LEFT JOIN users u_created ON i.created_by = u_created.id
    WHERE i.tenant_id = $1
      AND i.created_at::date BETWEEN $2 AND $3
    ORDER BY i.created_at DESC
  ", params = list(tenant_id, start_date, end_date))
}

#' Create job record for report generation
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param user_id User requesting report
#' @param report_type Type of report
#' @param parameters Report parameters
#' @return Job ID
create_report_job <- function(pool, tenant_id, user_id, report_type, parameters) {
  result <- safe_query(pool, "
    INSERT INTO jobs (tenant_id, user_id, job_type, status, payload)
    VALUES ($1, $2, 'report_generation', 'pending', $3)
    RETURNING id
  ", params = list(
    tenant_id,
    user_id,
    jsonlite::toJSON(list(report_type = report_type, parameters = parameters), auto_unbox = TRUE)
  ))
  
  if (!is.null(result) && nrow(result) > 0) {
    create_audit_log(pool, "report_generate",
                     user_id = user_id,
                     tenant_id = tenant_id,
                     entity_type = "job",
                     entity_id = result$id,
                     metadata = list(report_type = report_type))
    result$id
  } else {
    NULL
  }
}
