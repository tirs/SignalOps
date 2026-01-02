# SignalOps Overview Module
# Main dashboard with KPIs and trend visualizations

#' Overview Module UI
#' @param id Module namespace ID
mod_overview_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-overview",
    
    # Page Header
    div(
      class = "page-header",
      h1("Dashboard Overview"),
      div(
        class = "header-actions",
        selectInput(
          ns("date_range"),
          label = NULL,
          choices = c(
            "Last 7 Days" = "7",
            "Last 14 Days" = "14",
            "Last 30 Days" = "30",
            "Last 90 Days" = "90"
          ),
          selected = "30",
          width = "150px"
        ),
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # KPI Cards Row
    div(
      class = "kpi-grid",
      uiOutput(ns("kpi_cards"))
    ),
    
    # Charts Row
    div(
      class = "charts-row",
      div(
        class = "chart-container large",
        div(class = "chart-header", h3("Metrics Trend")),
        div(class = "chart-body", plotlyOutput(ns("trend_chart"), height = "300px"))
      ),
      div(
        class = "chart-container",
        div(class = "chart-header", h3("Anomalies by Severity")),
        div(class = "chart-body", plotlyOutput(ns("anomaly_chart"), height = "300px"))
      )
    ),
    
    # Bottom Row
    div(
      class = "dashboard-row",
      div(
        class = "panel",
        div(class = "panel-header", 
            h3("Recent Anomalies"),
            actionLink(ns("view_all_anomalies"), "View All", class = "panel-action")),
        div(class = "panel-body", DTOutput(ns("recent_anomalies_table")))
      ),
      div(
        class = "panel",
        div(class = "panel-header", 
            h3("Open Incidents"),
            actionLink(ns("view_all_incidents"), "View All", class = "panel-action")),
        div(class = "panel-body", DTOutput(ns("open_incidents_table")))
      )
    ),
    
    # Activity Row
    div(
      class = "dashboard-row single",
      div(
        class = "panel wide",
        div(class = "panel-header", h3("Recent Activity")),
        div(class = "panel-body", uiOutput(ns("activity_feed")))
      )
    )
  )
}

#' Overview Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_overview_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Reactive data
    date_range <- reactive({
      days <- as.integer(input$date_range %||% "30")
      list(
        start = Sys.Date() - days,
        end = Sys.Date()
      )
    })
    
    # Trigger refresh
    refresh_trigger <- reactiveVal(0)
    observeEvent(input$refresh_btn, {
      refresh_trigger(refresh_trigger() + 1)
    })
    
    # KPI Data
    kpi_data <- reactive({
      refresh_trigger()
      req(session_data$user)
      
      tenant_id <- session_data$user$tenant_id
      dates <- date_range()
      
      # Total data points
      metrics_count <- safe_query(pool, "
        SELECT COUNT(*) as total, COUNT(DISTINCT metric_name) as metrics
        FROM metrics_data
        WHERE tenant_id = $1 AND metric_date >= $2
      ", params = list(tenant_id, dates$start))
      
      # Anomaly count
      anomaly_count <- safe_query(pool, "
        SELECT 
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE severity = 'high') as high
        FROM anomalies
        WHERE tenant_id = $1 AND detection_date >= $2
      ", params = list(tenant_id, dates$start))
      
      # Open incidents
      incident_count <- safe_query(pool, "
        SELECT 
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE sla_due_at < CURRENT_TIMESTAMP) as breached
        FROM incidents
        WHERE tenant_id = $1 AND status NOT IN ('closed', 'false_positive')
      ", params = list(tenant_id))
      
      # Data quality
      quality_stats <- safe_query(pool, "
        SELECT 
          COALESCE(AVG(
            CASE WHEN row_count > 0 
            THEN valid_row_count::float / row_count * 100 
            ELSE 100 END
          ), 100) as avg_valid_pct
        FROM data_imports
        WHERE tenant_id = $1 AND created_at >= $2 AND status = 'completed'
      ", params = list(tenant_id, dates$start))
      
      list(
        data_points = metrics_count$total[1] %||% 0,
        metrics = metrics_count$metrics[1] %||% 0,
        anomalies = anomaly_count$total[1] %||% 0,
        high_anomalies = anomaly_count$high[1] %||% 0,
        incidents = incident_count$total[1] %||% 0,
        sla_breached = incident_count$breached[1] %||% 0,
        quality_pct = quality_stats$avg_valid_pct[1] %||% 100
      )
    })
    
    # Render KPI Cards
    output$kpi_cards <- renderUI({
      kpis <- kpi_data()
      
      tagList(
        div(
          class = "kpi-card",
          div(class = "kpi-icon", icon("database")),
          div(
            class = "kpi-content",
            div(class = "kpi-value", format_number(kpis$data_points)),
            div(class = "kpi-label", "Data Points"),
            div(class = "kpi-sub", paste(kpis$metrics, "metrics tracked"))
          )
        ),
        div(
          class = paste("kpi-card", if (kpis$high_anomalies > 0) "warning" else ""),
          div(class = "kpi-icon", icon("exclamation-triangle")),
          div(
            class = "kpi-content",
            div(class = "kpi-value", format_number(kpis$anomalies)),
            div(class = "kpi-label", "Anomalies"),
            div(class = "kpi-sub", paste(kpis$high_anomalies, "high severity"))
          )
        ),
        div(
          class = paste("kpi-card", if (kpis$sla_breached > 0) "danger" else ""),
          div(class = "kpi-icon", icon("flag")),
          div(
            class = "kpi-content",
            div(class = "kpi-value", format_number(kpis$incidents)),
            div(class = "kpi-label", "Open Incidents"),
            div(class = "kpi-sub", 
                if (kpis$sla_breached > 0) {
                  paste(kpis$sla_breached, "SLA breached")
                } else {
                  "All within SLA"
                })
          )
        ),
        div(
          class = paste("kpi-card", 
                        if (kpis$quality_pct >= 95) "success" 
                        else if (kpis$quality_pct >= 80) "warning" 
                        else "danger"),
          div(class = "kpi-icon", icon("check-circle")),
          div(
            class = "kpi-content",
            div(class = "kpi-value", paste0(round(kpis$quality_pct, 1), "%")),
            div(class = "kpi-label", "Data Quality"),
            div(class = "kpi-sub", "Average validation rate")
          )
        )
      )
    })
    
    # Metrics Trend Chart
    output$trend_chart <- renderPlotly({
      req(session_data$user)
      dates <- date_range()
      tenant_id <- session_data$user$tenant_id
      
      trend_data <- safe_query(pool, "
        SELECT 
          metric_date,
          metric_name,
          SUM(metric_value) as total_value
        FROM metrics_data
        WHERE tenant_id = $1 
          AND metric_date BETWEEN $2 AND $3
        GROUP BY metric_date, metric_name
        ORDER BY metric_date
      ", params = list(tenant_id, dates$start, dates$end))
      
      if (is.null(trend_data) || nrow(trend_data) == 0) {
        return(
          plot_ly() %>%
            layout(
              title = list(text = "No data available", x = 0.5),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            )
        )
      }
      
      # Get top 5 metrics
      top_metrics <- trend_data %>%
        group_by(metric_name) %>%
        summarise(total = sum(total_value, na.rm = TRUE)) %>%
        arrange(desc(total)) %>%
        head(5) %>%
        pull(metric_name)
      
      plot_data <- trend_data %>%
        filter(metric_name %in% top_metrics)
      
      plot_ly(plot_data, x = ~metric_date, y = ~total_value, 
              color = ~metric_name, type = "scatter", mode = "lines+markers",
              colors = c("#00d9ff", "#a855f7", "#22c55e", "#f59e0b", "#ef4444")) %>%
        layout(
          xaxis = list(title = "", gridcolor = "rgba(255,255,255,0.1)"),
          yaxis = list(title = "Value", gridcolor = "rgba(255,255,255,0.1)"),
          legend = list(orientation = "h", y = -0.2),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8"),
          margin = list(t = 20, r = 20, b = 60, l = 60)
        )
    })
    
    # Anomaly Chart
    output$anomaly_chart <- renderPlotly({
      req(session_data$user)
      dates <- date_range()
      tenant_id <- session_data$user$tenant_id
      
      anomaly_data <- safe_query(pool, "
        SELECT severity, COUNT(*) as count
        FROM anomalies
        WHERE tenant_id = $1 AND detection_date >= $2
        GROUP BY severity
      ", params = list(tenant_id, dates$start))
      
      if (is.null(anomaly_data) || nrow(anomaly_data) == 0) {
        return(
          plot_ly() %>%
            layout(
              title = list(text = "No anomalies detected", x = 0.5),
              paper_bgcolor = "transparent",
              plot_bgcolor = "transparent"
            )
        )
      }
      
      colors <- c("low" = "#22c55e", "medium" = "#f59e0b", "high" = "#ef4444", "critical" = "#7c3aed")
      
      plot_ly(anomaly_data, 
              labels = ~severity, 
              values = ~count, 
              type = "pie",
              marker = list(colors = colors[anomaly_data$severity]),
              textinfo = "label+value",
              hoverinfo = "label+value+percent") %>%
        layout(
          showlegend = FALSE,
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8"),
          margin = list(t = 20, r = 20, b = 20, l = 20)
        )
    })
    
    # Recent Anomalies Table
    output$recent_anomalies_table <- renderDT({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      anomalies <- get_anomalies(pool, tenant_id, limit = 5)
      
      if (is.null(anomalies) || nrow(anomalies) == 0) {
        return(datatable(
          data.frame(Message = "No anomalies detected"),
          options = list(dom = "t", paging = FALSE),
          rownames = FALSE
        ))
      }
      
      display_data <- anomalies %>%
        select(detection_date, metric_name, severity, zscore) %>%
        mutate(
          detection_date = format(detection_date, "%Y-%m-%d"),
          zscore = round(zscore, 2)
        )
      
      datatable(
        display_data,
        options = list(
          dom = "t",
          paging = FALSE,
          ordering = FALSE,
          columnDefs = list(
            list(className = "dt-center", targets = "_all")
          )
        ),
        rownames = FALSE,
        colnames = c("Date", "Metric", "Severity", "Z-Score"),
        class = "compact stripe"
      )
    })
    
    # Open Incidents Table
    output$open_incidents_table <- renderDT({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      incidents <- get_incidents(pool, tenant_id, 
                                 status = c("open", "investigating", "mitigated"),
                                 limit = 5)
      
      if (is.null(incidents) || nrow(incidents) == 0) {
        return(datatable(
          data.frame(Message = "No open incidents"),
          options = list(dom = "t", paging = FALSE),
          rownames = FALSE
        ))
      }
      
      display_data <- incidents %>%
        select(title, severity, status, age_hours) %>%
        mutate(
          title = truncate_text(title, 30),
          age = format_duration(age_hours * 3600)
        ) %>%
        select(title, severity, status, age)
      
      datatable(
        display_data,
        options = list(
          dom = "t",
          paging = FALSE,
          ordering = FALSE
        ),
        rownames = FALSE,
        colnames = c("Title", "Severity", "Status", "Age"),
        class = "compact stripe"
      )
    })
    
    # Activity Feed
    output$activity_feed <- renderUI({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      activity <- get_audit_logs(pool, tenant_id = tenant_id, limit = 10)
      
      if (is.null(activity) || nrow(activity) == 0) {
        return(p(class = "no-activity", "No recent activity"))
      }
      
      activity_items <- lapply(seq_len(nrow(activity)), function(i) {
        a <- activity[i, ]
        
        action_text <- switch(a$action,
          "login" = "logged in",
          "logout" = "logged out",
          "data_import" = "imported data",
          "incident_create" = "created an incident",
          "incident_update" = "updated an incident",
          "comment_add" = "added a comment",
          a$action
        )
        
        div(
          class = "activity-item",
          div(class = "activity-icon", icon(
            switch(a$action,
              "login" = "sign-in-alt",
              "logout" = "sign-out-alt",
              "data_import" = "upload",
              "incident_create" = "plus",
              "incident_update" = "edit",
              "comment_add" = "comment",
              "circle"
            )
          )),
          div(
            class = "activity-content",
            span(class = "activity-user", a$user_email %||% "System"),
            span(class = "activity-action", action_text),
            span(class = "activity-time", format_datetime(a$created_at, "%b %d, %H:%M"))
          )
        )
      })
      
      div(class = "activity-feed", activity_items)
    })
  })
}
