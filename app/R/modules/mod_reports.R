# SignalOps Reports Module
# Report generation and data export

#' Reports Module UI
#' @param id Module namespace ID
mod_reports_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-reports",
    
    # Page Header
    div(
      class = "page-header",
      h1("Reports & Exports")
    ),
    
    # Report Cards
    div(
      class = "report-cards",
      
      # KPI Report
      div(
        class = "report-card",
        div(class = "report-icon", icon("chart-bar")),
        h3("KPI Summary Report"),
        p("Generate a comprehensive KPI report with metrics trends, 
           breakdowns by team/region, and period comparisons."),
        div(
          class = "report-params",
          dateRangeInput(ns("kpi_date_range"), "Date Range",
                         start = Sys.Date() - 30, end = Sys.Date()),
          selectInput(ns("kpi_format"), "Format",
                      choices = c("HTML" = "html", "PDF" = "pdf"))
        ),
        actionButton(ns("generate_kpi_btn"), "Generate Report", 
                     icon = icon("file-alt"), class = "btn-primary")
      ),
      
      # Anomaly Report
      div(
        class = "report-card",
        div(class = "report-icon", icon("exclamation-triangle")),
        h3("Anomaly Report"),
        p("Generate an anomaly detection report with severity breakdown,
           top anomalies, and trend analysis."),
        div(
          class = "report-params",
          dateRangeInput(ns("anomaly_date_range"), "Date Range",
                         start = Sys.Date() - 30, end = Sys.Date()),
          selectInput(ns("anomaly_format"), "Format",
                      choices = c("HTML" = "html", "PDF" = "pdf"))
        ),
        actionButton(ns("generate_anomaly_btn"), "Generate Report", 
                     icon = icon("file-alt"), class = "btn-primary")
      ),
      
      # Incident Report
      div(
        class = "report-card",
        div(class = "report-icon", icon("flag")),
        h3("Incident Report"),
        p("Generate an incident management report with status summary,
           resolution times, and assignee breakdown."),
        div(
          class = "report-params",
          dateRangeInput(ns("incident_date_range"), "Date Range",
                         start = Sys.Date() - 30, end = Sys.Date()),
          selectInput(ns("incident_format"), "Format",
                      choices = c("HTML" = "html", "PDF" = "pdf"))
        ),
        actionButton(ns("generate_incident_btn"), "Generate Report", 
                     icon = icon("file-alt"), class = "btn-primary")
      )
    ),
    
    # Export Section
    div(
      class = "export-section panel",
      div(class = "panel-header", h3("Data Exports")),
      div(
        class = "panel-body",
        div(
          class = "export-grid",
          
          # Metrics Export
          div(
            class = "export-item",
            h4("Metrics Data"),
            p("Export raw metrics data as CSV"),
            div(
              class = "export-params",
              dateRangeInput(ns("metrics_export_range"), "Date Range",
                             start = Sys.Date() - 30, end = Sys.Date()),
              selectInput(ns("metrics_export_metric"), "Metric",
                          choices = c("All Metrics" = ""))
            ),
            downloadButton(ns("download_metrics"), "Export CSV", 
                           class = "btn-secondary")
          ),
          
          # Anomalies Export
          div(
            class = "export-item",
            h4("Anomalies Data"),
            p("Export detected anomalies as CSV"),
            div(
              class = "export-params",
              dateRangeInput(ns("anomalies_export_range"), "Date Range",
                             start = Sys.Date() - 30, end = Sys.Date())
            ),
            downloadButton(ns("download_anomalies"), "Export CSV", 
                           class = "btn-secondary")
          ),
          
          # Incidents Export
          div(
            class = "export-item",
            h4("Incidents Data"),
            p("Export incidents as CSV"),
            div(
              class = "export-params",
              dateRangeInput(ns("incidents_export_range"), "Date Range",
                             start = Sys.Date() - 30, end = Sys.Date())
            ),
            downloadButton(ns("download_incidents"), "Export CSV", 
                           class = "btn-secondary")
          ),
          
          # Audit Log Export
          div(
            class = "export-item",
            h4("Audit Log"),
            p("Export audit trail as CSV"),
            div(
              class = "export-params",
              dateRangeInput(ns("audit_export_range"), "Date Range",
                             start = Sys.Date() - 7, end = Sys.Date())
            ),
            downloadButton(ns("download_audit"), "Export CSV", 
                           class = "btn-secondary")
          )
        )
      )
    ),
    
    # Recent Reports
    div(
      class = "recent-reports panel",
      div(class = "panel-header", h3("Recent Reports")),
      div(class = "panel-body", DTOutput(ns("recent_reports_table")))
    )
  )
}

#' Reports Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_reports_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Populate metric filter
    observe({
      req(session_data$user)
      
      metrics <- safe_query(pool, "
        SELECT DISTINCT metric_name FROM metrics_data 
        WHERE tenant_id = $1 ORDER BY metric_name
      ", params = list(session_data$user$tenant_id))
      
      if (!is.null(metrics) && nrow(metrics) > 0) {
        updateSelectInput(session, "metrics_export_metric",
                          choices = c("All Metrics" = "", metrics$metric_name))
      }
    })
    
    # Generate KPI Report
    observeEvent(input$generate_kpi_btn, {
      req(session_data$user)
      
      showNotification("Generating KPI report...", type = "message", id = "report_progress")
      
      tenant_id <- session_data$user$tenant_id
      start_date <- input$kpi_date_range[1]
      end_date <- input$kpi_date_range[2]
      
      # Get report data
      report_data <- get_kpi_report_data(pool, tenant_id, start_date, end_date)
      
      # Create job record
      job_id <- create_report_job(pool, tenant_id, session_data$user$id, 
                                  "kpi", list(start_date = start_date, end_date = end_date))
      
      removeNotification("report_progress")
      showNotification("Report generated successfully", type = "message")
      
      # In production, this would render an Rmd template
      # For now, show a summary
      showModal(modalDialog(
        title = "KPI Report Preview",
        size = "l",
        div(
          class = "report-preview",
          h4(paste("KPI Summary:", start_date, "to", end_date)),
          if (!is.null(report_data$summary)) {
            tagList(
              p(paste("Total Data Points:", format_number(report_data$summary$data_points))),
              p(paste("Unique Metrics:", format_number(report_data$summary$metric_count))),
              if (!is.null(report_data$by_metric) && nrow(report_data$by_metric) > 0) {
                tagList(
                  h5("Metrics Summary"),
                  renderDT({
                    datatable(
                      report_data$by_metric %>%
                        mutate(across(where(is.numeric), ~round(., 2))),
                      options = list(dom = "t", pageLength = 10),
                      rownames = FALSE
                    )
                  })
                )
              }
            )
          } else {
            p("No data available for the selected period.")
          }
        ),
        footer = modalButton("Close")
      ))
    })
    
    # Generate Anomaly Report
    observeEvent(input$generate_anomaly_btn, {
      req(session_data$user)
      
      showNotification("Generating anomaly report...", type = "message", id = "report_progress")
      
      tenant_id <- session_data$user$tenant_id
      start_date <- input$anomaly_date_range[1]
      end_date <- input$anomaly_date_range[2]
      
      report_data <- get_anomaly_report_data(pool, tenant_id, start_date, end_date)
      
      create_report_job(pool, tenant_id, session_data$user$id, 
                        "anomaly", list(start_date = start_date, end_date = end_date))
      
      removeNotification("report_progress")
      showNotification("Report generated successfully", type = "message")
      
      showModal(modalDialog(
        title = "Anomaly Report Preview",
        size = "l",
        div(
          class = "report-preview",
          h4(paste("Anomaly Summary:", start_date, "to", end_date)),
          if (!is.null(report_data$summary)) {
            tagList(
              div(
                class = "report-stats",
                p(paste("Total Anomalies:", format_number(report_data$summary$total))),
                p(paste("High Severity:", format_number(report_data$summary$high_count))),
                p(paste("Acknowledged:", format_number(report_data$summary$acknowledged_count)))
              )
            )
          } else {
            p("No anomalies found for the selected period.")
          }
        ),
        footer = modalButton("Close")
      ))
    })
    
    # Generate Incident Report
    observeEvent(input$generate_incident_btn, {
      req(session_data$user)
      
      showNotification("Generating incident report...", type = "message", id = "report_progress")
      
      tenant_id <- session_data$user$tenant_id
      start_date <- input$incident_date_range[1]
      end_date <- input$incident_date_range[2]
      
      report_data <- get_incident_report_data(pool, tenant_id, start_date, end_date)
      
      create_report_job(pool, tenant_id, session_data$user$id, 
                        "incident", list(start_date = start_date, end_date = end_date))
      
      removeNotification("report_progress")
      showNotification("Report generated successfully", type = "message")
      
      showModal(modalDialog(
        title = "Incident Report Preview",
        size = "l",
        div(
          class = "report-preview",
          h4(paste("Incident Summary:", start_date, "to", end_date)),
          if (!is.null(report_data$summary)) {
            tagList(
              div(
                class = "report-stats",
                p(paste("Total Incidents:", format_number(report_data$summary$total))),
                p(paste("Closed:", format_number(report_data$summary$closed_count))),
                p(paste("Avg Resolution:", 
                        if (!is.na(report_data$summary$avg_resolution_hours)) {
                          paste0(round(report_data$summary$avg_resolution_hours, 1), " hours")
                        } else "N/A"))
              )
            )
          } else {
            p("No incidents found for the selected period.")
          }
        ),
        footer = modalButton("Close")
      ))
    })
    
    # Download handlers
    output$download_metrics <- downloadHandler(
      filename = function() {
        paste0("metrics_export_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        tenant_id <- session_data$user$tenant_id
        metric_filter <- if (input$metrics_export_metric != "") {
          input$metrics_export_metric
        } else NULL
        
        data <- export_metrics_csv(
          pool, tenant_id,
          input$metrics_export_range[1],
          input$metrics_export_range[2],
          metric_filter
        )
        
        if (!is.null(data) && nrow(data) > 0) {
          readr::write_csv(data, file)
        } else {
          readr::write_csv(data.frame(message = "No data found"), file)
        }
        
        create_audit_log(pool, "export_data",
                         user_id = session_data$user$id,
                         tenant_id = tenant_id,
                         metadata = list(type = "metrics", rows = nrow(data)))
      }
    )
    
    output$download_anomalies <- downloadHandler(
      filename = function() {
        paste0("anomalies_export_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        tenant_id <- session_data$user$tenant_id
        
        data <- export_anomalies_csv(
          pool, tenant_id,
          input$anomalies_export_range[1],
          input$anomalies_export_range[2]
        )
        
        if (!is.null(data) && nrow(data) > 0) {
          readr::write_csv(data, file)
        } else {
          readr::write_csv(data.frame(message = "No data found"), file)
        }
        
        create_audit_log(pool, "export_data",
                         user_id = session_data$user$id,
                         tenant_id = tenant_id,
                         metadata = list(type = "anomalies", rows = nrow(data)))
      }
    )
    
    output$download_incidents <- downloadHandler(
      filename = function() {
        paste0("incidents_export_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        tenant_id <- session_data$user$tenant_id
        
        data <- export_incidents_csv(
          pool, tenant_id,
          input$incidents_export_range[1],
          input$incidents_export_range[2]
        )
        
        if (!is.null(data) && nrow(data) > 0) {
          readr::write_csv(data, file)
        } else {
          readr::write_csv(data.frame(message = "No data found"), file)
        }
        
        create_audit_log(pool, "export_data",
                         user_id = session_data$user$id,
                         tenant_id = tenant_id,
                         metadata = list(type = "incidents", rows = nrow(data)))
      }
    )
    
    output$download_audit <- downloadHandler(
      filename = function() {
        paste0("audit_log_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        tenant_id <- session_data$user$tenant_id
        
        data <- get_audit_logs(
          pool,
          tenant_id = tenant_id,
          start_date = input$audit_export_range[1],
          end_date = input$audit_export_range[2],
          limit = 10000
        )
        
        if (!is.null(data) && nrow(data) > 0) {
          readr::write_csv(data, file)
        } else {
          readr::write_csv(data.frame(message = "No data found"), file)
        }
      }
    )
    
    # Recent reports table
    output$recent_reports_table <- renderDT({
      req(session_data$user)
      
      reports <- safe_query(pool, "
        SELECT 
          j.id,
          j.job_type,
          j.payload->>'report_type' as report_type,
          j.status,
          j.created_at,
          u.email as created_by
        FROM jobs j
        LEFT JOIN users u ON j.user_id = u.id
        WHERE j.tenant_id = $1 AND j.job_type = 'report_generation'
        ORDER BY j.created_at DESC
        LIMIT 20
      ", params = list(session_data$user$tenant_id))
      
      if (is.null(reports) || nrow(reports) == 0) {
        return(datatable(
          data.frame(Message = "No reports generated yet"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- reports %>%
        mutate(
          report_type = tools::toTitleCase(gsub("_", " ", report_type %||% "Unknown")),
          date = format_datetime(created_at, "%Y-%m-%d %H:%M")
        ) %>%
        select(report_type, status, created_by, date)
      
      datatable(
        display_data,
        options = list(
          pageLength = 10,
          dom = "rtip"
        ),
        rownames = FALSE,
        colnames = c("Report Type", "Status", "Created By", "Date"),
        class = "compact stripe"
      )
    })
  })
}
