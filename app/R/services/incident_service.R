# SignalOps Incident Service
# Incident workflow management and tracking

#' Create an incident from an anomaly
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param anomaly_id Anomaly ID (optional)
#' @param title Incident title
#' @param description Incident description
#' @param severity Severity level
#' @param created_by User ID creating the incident
#' @param assigned_to User ID to assign (optional)
#' @param sla_hours SLA deadline in hours (optional)
#' @return Incident ID or NULL
create_incident <- function(pool, tenant_id, anomaly_id = NULL, title, 
                            description = NULL, severity = "medium", 
                            created_by, assigned_to = NULL, sla_hours = NULL) {
  sla_due_at <- if (!is.null(sla_hours)) {
    Sys.time() + (sla_hours * 3600)
  } else {
    NULL
  }
  
  incident_id <- generate_id()
  rows <- safe_execute(pool, "
    INSERT INTO incidents 
      (id, tenant_id, anomaly_id, title, description, status, severity, 
       created_by, assigned_to, sla_due_at)
    VALUES ($1, $2, $3, $4, $5, 'open', $6, $7, $8, $9)
  ", params = list(
    incident_id,
    tenant_id,
    anomaly_id,
    title,
    description,
    severity,
    created_by,
    assigned_to,
    sla_due_at
  ))
  
  if (rows > 0) {
    
    # Create audit log
    create_audit_log(pool, "incident_create",
                     user_id = created_by,
                     tenant_id = tenant_id,
                     entity_type = "incident",
                     entity_id = incident_id,
                     new_values = list(
                       title = title,
                       severity = severity,
                       assigned_to = assigned_to
                     ))
    
    # If linked to anomaly, mark it as acknowledged
    if (!is.null(anomaly_id)) {
      acknowledge_anomaly(pool, anomaly_id, created_by)
    }
    
    log_app_info("Incident created", 
                 incident_id = incident_id, 
                 title = title)
    
    incident_id
  } else {
    NULL
  }
}

#' Update incident status
#' @param pool Database pool
#' @param incident_id Incident ID
#' @param new_status New status
#' @param user_id User making the change
#' @param notes Notes for the status change
#' @return TRUE if successful
update_incident_status <- function(pool, incident_id, new_status, 
                                   user_id, notes = NULL) {
  # Get current status
  current <- safe_query(pool, "
    SELECT status, tenant_id FROM incidents WHERE id = $1
  ", params = list(incident_id))
  
  if (is.null(current) || nrow(current) == 0) {
    return(FALSE)
  }
  
  old_status <- current$status[1]
  tenant_id <- current$tenant_id[1]
  
  # Update status
  if (new_status == "closed") {
    safe_execute(pool, "
      UPDATE incidents 
      SET status = $1, resolved_at = NOW()
      WHERE id = $2
    ", params = list(new_status, incident_id))
  } else {
    safe_execute(pool, "
      UPDATE incidents SET status = $1 WHERE id = $2
    ", params = list(new_status, incident_id))
  }
  
  # Add status history note
  if (!is.null(notes)) {
    safe_execute(pool, "
      UPDATE incident_status_history 
      SET notes = $1, user_id = $2
      WHERE incident_id = $3 
        AND old_status = $4 
        AND new_status = $5
        AND notes IS NULL
      ORDER BY created_at DESC
      LIMIT 1
    ", params = list(notes, user_id, incident_id, old_status, new_status))
  }
  
  # Audit log
  create_audit_log(pool, "incident_update",
                   user_id = user_id,
                   tenant_id = tenant_id,
                   entity_type = "incident",
                   entity_id = incident_id,
                   old_values = list(status = old_status),
                   new_values = list(status = new_status))
  
  log_app_info("Incident status updated",
               incident_id = incident_id,
               old_status = old_status,
               new_status = new_status)
  
  TRUE
}

#' Assign incident to a user
#' @param pool Database pool
#' @param incident_id Incident ID
#' @param assigned_to User ID to assign
#' @param assigned_by User ID making assignment
#' @return TRUE if successful
assign_incident <- function(pool, incident_id, assigned_to, assigned_by) {
  current <- safe_query(pool, "
    SELECT assigned_to, tenant_id FROM incidents WHERE id = $1
  ", params = list(incident_id))
  
  if (is.null(current) || nrow(current) == 0) {
    return(FALSE)
  }
  
  old_assigned <- current$assigned_to[1]
  tenant_id <- current$tenant_id[1]
  
  safe_execute(pool, "
    UPDATE incidents SET assigned_to = $1 WHERE id = $2
  ", params = list(assigned_to, incident_id))
  
  create_audit_log(pool, "incident_assign",
                   user_id = assigned_by,
                   tenant_id = tenant_id,
                   entity_type = "incident",
                   entity_id = incident_id,
                   old_values = list(assigned_to = old_assigned),
                   new_values = list(assigned_to = assigned_to))
  
  TRUE
}

#' Add a comment to an incident
#' @param pool Database pool
#' @param incident_id Incident ID
#' @param user_id User adding comment
#' @param content Comment content
#' @param is_internal Whether comment is internal only
#' @return Comment ID or NULL
add_incident_comment <- function(pool, incident_id, user_id, content, 
                                 is_internal = FALSE) {
  comment_id <- generate_id()
  rows <- safe_execute(pool, "
    INSERT INTO incident_comments (id, incident_id, user_id, content, is_internal)
    VALUES ($1, $2, $3, $4, $5)
  ", params = list(comment_id, incident_id, user_id, content, is_internal))
  
  if (rows > 0) {
    # Get tenant_id for audit
    incident <- safe_query(pool, "SELECT tenant_id FROM incidents WHERE id = $1", 
                           params = list(incident_id))
    
    create_audit_log(pool, "comment_add",
                     user_id = user_id,
                     tenant_id = incident$tenant_id[1],
                     entity_type = "incident",
                     entity_id = incident_id,
                     metadata = list(comment_id = comment_id))
    
    comment_id
  } else {
    NULL
  }
}

#' Get incident details with comments and history
#' @param pool Database pool
#' @param incident_id Incident ID
#' @return List with incident, comments, and history
get_incident_details <- function(pool, incident_id) {
  # MySQL compatible - use CONCAT instead of ||
  incident <- safe_query(pool, "
    SELECT 
      i.*,
      u_assigned.email as assigned_to_email,
      CONCAT(u_assigned.first_name, ' ', u_assigned.last_name) as assigned_to_name,
      u_created.email as created_by_email,
      CONCAT(u_created.first_name, ' ', u_created.last_name) as created_by_name,
      a.metric_name as anomaly_metric,
      a.metric_value as anomaly_value,
      a.zscore as anomaly_zscore
    FROM incidents i
    LEFT JOIN users u_assigned ON i.assigned_to = u_assigned.id
    LEFT JOIN users u_created ON i.created_by = u_created.id
    LEFT JOIN anomalies a ON i.anomaly_id = a.id
    WHERE i.id = $1
  ", params = list(incident_id))
  
  if (is.null(incident) || nrow(incident) == 0) {
    return(NULL)
  }
  
  comments <- safe_query(pool, "
    SELECT 
      c.id,
      c.content,
      c.is_internal,
      c.created_at,
      u.email as user_email,
      CONCAT(u.first_name, ' ', u.last_name) as user_name
    FROM incident_comments c
    LEFT JOIN users u ON c.user_id = u.id
    WHERE c.incident_id = $1
    ORDER BY c.created_at ASC
  ", params = list(incident_id))
  
  history <- safe_query(pool, "
    SELECT 
      h.old_status,
      h.new_status,
      h.notes,
      h.created_at,
      u.email as user_email,
      CONCAT(u.first_name, ' ', u.last_name) as user_name
    FROM incident_status_history h
    LEFT JOIN users u ON h.user_id = u.id
    WHERE h.incident_id = $1
    ORDER BY h.created_at ASC
  ", params = list(incident_id))
  
  list(
    incident = incident[1, ],
    comments = comments,
    history = history
  )
}

#' Get incidents for dashboard
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param status Status filter
#' @param severity Severity filter
#' @param assigned_to User ID filter
#' @param limit Max records
#' @return Data frame of incidents
get_incidents <- function(pool, tenant_id, status = NULL, severity = NULL,
                          assigned_to = NULL, limit = 100) {
  # MySQL compatible query
  query <- "
    SELECT 
      i.id,
      i.title,
      i.status,
      i.severity,
      i.created_at,
      i.sla_due_at,
      CASE 
        WHEN i.sla_due_at < NOW() AND i.status NOT IN ('closed', 'false_positive') 
        THEN TRUE 
        ELSE FALSE 
      END as sla_breached,
      TIMESTAMPDIFF(SECOND, i.created_at, NOW()) / 3600 as age_hours,
      u_assigned.email as assigned_to_email,
      CONCAT(COALESCE(u_assigned.first_name, ''), ' ', 
             COALESCE(u_assigned.last_name, '')) as assigned_to_name,
      u_created.email as created_by_email,
      (SELECT COUNT(*) FROM incident_comments ic WHERE ic.incident_id = i.id) 
        as comment_count
    FROM incidents i
    LEFT JOIN users u_assigned ON i.assigned_to = u_assigned.id
    LEFT JOIN users u_created ON i.created_by = u_created.id
    WHERE i.tenant_id = $1
  "
  
  params <- list(tenant_id)
  param_idx <- 1
  
  if (!is.null(status)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND i.status = $", param_idx)
    params[[param_idx]] <- status
  }
  
  if (!is.null(severity)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND i.severity = $", param_idx)
    params[[param_idx]] <- severity
  }
  
  if (!is.null(assigned_to)) {
    param_idx <- param_idx + 1
    query <- paste0(query, " AND i.assigned_to = $", param_idx)
    params[[param_idx]] <- assigned_to
  }
  
  query <- paste0(query, " ORDER BY i.created_at DESC LIMIT ", limit)
  
  safe_query(pool, query, params = params)
}

#' Get incident summary statistics
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @return List with incident stats
get_incident_stats <- function(pool, tenant_id) {
  # MySQL compatible - use SUM(CASE WHEN) instead of COUNT(*) FILTER
  stats <- safe_query(pool, "
    SELECT 
      COUNT(*) as total,
      SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) as open_count,
      SUM(CASE WHEN status = 'investigating' THEN 1 ELSE 0 END) 
        as investigating_count,
      SUM(CASE WHEN status = 'mitigated' THEN 1 ELSE 0 END) as mitigated_count,
      SUM(CASE WHEN status = 'closed' THEN 1 ELSE 0 END) as closed_count,
      SUM(CASE WHEN sla_due_at < NOW() 
               AND status NOT IN ('closed', 'false_positive') 
          THEN 1 ELSE 0 END) as sla_breached_count,
      AVG(CASE WHEN status IN ('closed', 'false_positive') 
          THEN TIMESTAMPDIFF(SECOND, created_at, 
                             COALESCE(resolved_at, NOW())) / 3600 
          ELSE NULL END) as avg_resolution_hours
    FROM incidents
    WHERE tenant_id = $1
  ", params = list(tenant_id))
  
  by_severity <- safe_query(pool, "
    SELECT 
      severity,
      status,
      COUNT(*) as count
    FROM incidents
    WHERE tenant_id = $1
    GROUP BY severity, status
  ", params = list(tenant_id))
  
  list(
    summary = if (!is.null(stats) && nrow(stats) > 0) stats[1, ] else NULL,
    by_severity_status = by_severity
  )
}

#' Update incident resolution details
#' @param pool Database pool
#' @param incident_id Incident ID
#' @param resolution_notes Resolution notes
#' @param root_cause Root cause analysis
#' @param impact Impact description
#' @param user_id User making update
update_incident_resolution <- function(pool, incident_id, resolution_notes = NULL,
                                       root_cause = NULL, impact = NULL, user_id) {
  incident <- safe_query(pool, "SELECT tenant_id FROM incidents WHERE id = $1",
                         params = list(incident_id))
  
  if (is.null(incident) || nrow(incident) == 0) {
    return(FALSE)
  }
  
  safe_execute(pool, "
    UPDATE incidents 
    SET resolution_notes = COALESCE($1, resolution_notes),
        root_cause = COALESCE($2, root_cause),
        impact = COALESCE($3, impact)
    WHERE id = $4
  ", params = list(resolution_notes, root_cause, impact, incident_id))
  
  create_audit_log(pool, "incident_update",
                   user_id = user_id,
                   tenant_id = incident$tenant_id[1],
                   entity_type = "incident",
                   entity_id = incident_id,
                   new_values = list(
                     resolution_notes = resolution_notes,
                     root_cause = root_cause,
                     impact = impact
                   ))
  
  TRUE
}
