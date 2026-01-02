# SignalOps Anomalies Module
# Anomaly detection display and management

#' Anomalies Module UI
#' @param id Module namespace ID
mod_anomalies_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-anomalies",
    
    # Page Header
    div(
      class = "page-header",
      h1("Anomaly Detection"),
      div(
        class = "header-actions",
        actionButton(ns("run_detection_btn"), "Run Detection", 
                     icon = icon("search"), class = "btn-primary"),
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # Anomaly Stats
    div(
      class = "anomaly-stats",
      uiOutput(ns("anomaly_kpis"))
    ),
    
    # Filters
    div(
      class = "filters-panel compact",
      div(
        class = "filter-row",
        dateRangeInput(ns("date_range"), "Date Range",
                       start = Sys.Date() - 30, end = Sys.Date(), width = "200px"),
        selectInput(ns("severity_filter"), "Severity",
                    choices = c("All" = "", "Low" = "low", "Medium" = "medium", 
                                "High" = "high", "Critical" = "critical"),
                    width = "120px"),
        selectInput(ns("ack_filter"), "Status",
                    choices = c("All" = "", "Unacknowledged" = "FALSE", 
                                "Acknowledged" = "TRUE"),
                    width = "150px"),
        actionButton(ns("apply_filters"), "Apply", class = "btn-secondary")
      )
    ),
    
    # Charts Row
    div(
      class = "charts-row",
      div(
        class = "chart-container large",
        div(class = "chart-header", h3("Anomaly Timeline")),
        plotlyOutput(ns("timeline_chart"), height = "250px")
      ),
      div(
        class = "chart-container",
        div(class = "chart-header", h3("By Metric")),
        plotlyOutput(ns("by_metric_chart"), height = "250px")
      )
    ),
    
    # Anomalies Table
    div(
      class = "anomalies-table panel",
      div(class = "panel-header", h3("Detected Anomalies")),
      div(class = "panel-body", DTOutput(ns("anomalies_table")))
    ),
    
    # Detail Modal
    div(
      id = ns("detail_modal"),
      class = "modal-overlay hidden",
      div(
        class = "modal-content wide",
        div(
          class = "modal-header",
          h3("Anomaly Details"),
          actionButton(ns("close_modal"), icon("times"), class = "btn-icon modal-close")
        ),
        div(
          class = "modal-body",
          uiOutput(ns("anomaly_detail"))
        ),
        div(
          class = "modal-footer",
          actionButton(ns("acknowledge_btn"), "Acknowledge", class = "btn-secondary"),
          actionButton(ns("create_incident_btn"), "Create Incident", class = "btn-primary")
        )
      )
    )
  )
}

#' Anomalies Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_anomalies_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Local state
    rv <- reactiveValues(
      selected_anomaly = NULL
    )
    
    # Run anomaly detection
    observeEvent(input$run_detection_btn, {
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      showNotification("Computing baselines...", type = "message", id = "detection_progress")
      
      # Compute baselines
      baselines_computed <- compute_baselines(pool, tenant_id)
      
      showNotification("Running detection...", type = "message", id = "detection_progress")
      
      # Detect anomalies
      config <- list(
        zscore_threshold_low = app_config$anomaly$zscore_threshold_low %||% 2.0,
        zscore_threshold_medium = app_config$anomaly$zscore_threshold_medium %||% 3.0,
        zscore_threshold_high = app_config$anomaly$zscore_threshold_high %||% 4.0
      )
      
      detected <- detect_anomalies(pool, tenant_id, config)
      
      removeNotification("detection_progress")
      showNotification(
        paste("Detection complete:", detected, "anomalies found"),
        type = if (detected > 0) "warning" else "message"
      )
    })
    
    # Anomaly data
    anomaly_data <- reactive({
      req(session_data$user)
      input$apply_filters
      input$refresh_btn
      
      tenant_id <- session_data$user$tenant_id
      
      severity <- if (!is.null(input$severity_filter) && input$severity_filter != "") {
        input$severity_filter
      } else NULL
      
      acknowledged <- if (!is.null(input$ack_filter) && input$ack_filter != "") {
        as.logical(input$ack_filter)
      } else NULL
      
      get_anomalies(
        pool, tenant_id,
        start_date = input$date_range[1],
        end_date = input$date_range[2],
        severity = severity,
        acknowledged = acknowledged,
        limit = 500
      )
    })
    
    # Anomaly KPIs
    output$anomaly_kpis <- renderUI({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      stats <- get_anomaly_stats(pool, tenant_id, days = 30)
      
      if (is.null(stats$summary)) {
        return(div(class = "no-stats", "No anomaly data"))
      }
      
      s <- stats$summary
      
      tagList(
        div(
          class = "kpi-card",
          div(class = "kpi-icon", icon("exclamation-triangle")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$total %||% 0)),
              div(class = "kpi-label", "Total Anomalies"))
        ),
        div(
          class = "kpi-card danger",
          div(class = "kpi-icon", icon("fire")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$high_count %||% 0)),
              div(class = "kpi-label", "High Severity"))
        ),
        div(
          class = "kpi-card warning",
          div(class = "kpi-icon", icon("clock")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$unacknowledged_count %||% 0)),
              div(class = "kpi-label", "Unacknowledged"))
        ),
        div(
          class = "kpi-card success",
          div(class = "kpi-icon", icon("check")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$acknowledged_count %||% 0)),
              div(class = "kpi-label", "Acknowledged"))
        )
      )
    })
    
    # Timeline chart
    output$timeline_chart <- renderPlotly({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      trend <- get_anomaly_trend(pool, tenant_id, days = 30)
      
      if (is.null(trend) || nrow(trend) == 0) {
        return(plot_ly() %>% 
                 layout(title = "No anomaly data", paper_bgcolor = "transparent"))
      }
      
      # Pivot for stacked bars
      colors <- c("low" = "#22c55e", "medium" = "#f59e0b", "high" = "#ef4444")
      
      plot_ly(trend, x = ~detection_date, y = ~count, color = ~severity,
              type = "bar", colors = colors) %>%
        layout(
          barmode = "stack",
          xaxis = list(title = ""),
          yaxis = list(title = "Count"),
          legend = list(orientation = "h", y = -0.2),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8")
        )
    })
    
    # By metric chart
    output$by_metric_chart <- renderPlotly({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      stats <- get_anomaly_stats(pool, tenant_id, days = 30)
      
      if (is.null(stats$by_metric) || nrow(stats$by_metric) == 0) {
        return(plot_ly() %>% 
                 layout(title = "No data", paper_bgcolor = "transparent"))
      }
      
      data <- head(stats$by_metric, 10)
      
      plot_ly(data, x = ~count, y = ~reorder(metric_name, count), type = "bar",
              orientation = "h", marker = list(color = "#a855f7")) %>%
        layout(
          xaxis = list(title = "Count"),
          yaxis = list(title = ""),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8"),
          margin = list(l = 150)
        )
    })
    
    # Anomalies table
    output$anomalies_table <- renderDT({
      data <- anomaly_data()
      
      if (is.null(data) || nrow(data) == 0) {
        return(datatable(
          data.frame(Message = "No anomalies found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- data %>%
        mutate(
          date = format(detection_date, "%Y-%m-%d"),
          value = format_number(metric_value, 2),
          baseline = format_number(baseline_value, 2),
          zscore = round(zscore, 2),
          status = if_else(is_acknowledged, "Acknowledged", "Open")
        ) %>%
        select(date, metric_name, value, baseline, zscore, severity, status)
      
      datatable(
        display_data,
        options = list(
          pageLength = 15,
          dom = "frtip",
          order = list(list(4, "desc"))
        ),
        rownames = FALSE,
        colnames = c("Date", "Metric", "Value", "Baseline", "Z-Score", "Severity", "Status"),
        selection = "single",
        class = "compact stripe"
      )
    }, server = TRUE)
    
    # Row selection
    observeEvent(input$anomalies_table_rows_selected, {
      data <- anomaly_data()
      row_idx <- input$anomalies_table_rows_selected
      
      if (!is.null(row_idx) && length(row_idx) > 0) {
        rv$selected_anomaly <- data[row_idx, ]
        shinyjs::removeClass("detail_modal", "hidden")
      }
    })
    
    # Close modal
    observeEvent(input$close_modal, {
      shinyjs::addClass("detail_modal", "hidden")
      rv$selected_anomaly <- NULL
    })
    
    # Anomaly detail
    output$anomaly_detail <- renderUI({
      req(rv$selected_anomaly)
      a <- rv$selected_anomaly
      
      tagList(
        div(
          class = "detail-section",
          h4("Detection Info"),
          div(
            class = "detail-grid",
            div(class = "detail-item",
                span(class = "detail-label", "Date"),
                span(class = "detail-value", format_date(a$detection_date))),
            div(class = "detail-item",
                span(class = "detail-label", "Metric"),
                span(class = "detail-value", a$metric_name)),
            div(class = "detail-item",
                span(class = "detail-label", "Severity"),
                severity_badge(a$severity)),
            div(class = "detail-item",
                span(class = "detail-label", "Status"),
                span(class = "detail-value", 
                     if (a$is_acknowledged) "Acknowledged" else "Open"))
          )
        ),
        div(
          class = "detail-section",
          h4("Values"),
          div(
            class = "detail-grid",
            div(class = "detail-item",
                span(class = "detail-label", "Actual Value"),
                span(class = "detail-value", format_number(a$metric_value, 4))),
            div(class = "detail-item",
                span(class = "detail-label", "Baseline"),
                span(class = "detail-value", format_number(a$baseline_value, 4))),
            div(class = "detail-item",
                span(class = "detail-label", "Z-Score"),
                span(class = "detail-value", round(a$zscore, 2))),
            div(class = "detail-item",
                span(class = "detail-label", "Thresholds"),
                span(class = "detail-value", 
                     paste(format_number(a$threshold_low, 2), "-",
                           format_number(a$threshold_high, 2))))
          )
        ),
        div(
          class = "detail-section",
          h4("Explanation"),
          p(class = "detail-explanation", a$explanation)
        )
      )
    })
    
    # Acknowledge anomaly
    observeEvent(input$acknowledge_btn, {
      req(rv$selected_anomaly, session_data$user)
      
      acknowledge_anomaly(pool, rv$selected_anomaly$id, session_data$user$id)
      
      showNotification("Anomaly acknowledged", type = "message")
      shinyjs::addClass("detail_modal", "hidden")
      rv$selected_anomaly <- NULL
    })
    
    # Create incident from anomaly
    observeEvent(input$create_incident_btn, {
      req(rv$selected_anomaly, session_data$user)
      
      a <- rv$selected_anomaly
      
      incident_id <- create_incident(
        pool,
        tenant_id = session_data$user$tenant_id,
        anomaly_id = a$id,
        title = paste("Anomaly:", a$metric_name, "-", a$severity, "severity"),
        description = a$explanation,
        severity = a$severity,
        created_by = session_data$user$id
      )
      
      if (!is.null(incident_id)) {
        showNotification("Incident created successfully", type = "message")
        shinyjs::addClass("detail_modal", "hidden")
        rv$selected_anomaly <- NULL
      } else {
        showNotification("Failed to create incident", type = "error")
      }
    })
  })
}
