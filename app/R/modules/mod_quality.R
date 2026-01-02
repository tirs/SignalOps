# SignalOps Data Quality Module
# CSV upload, validation, and quality monitoring

#' Quality Module UI
#' @param id Module namespace ID
mod_quality_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-quality",
    
    # Page Header
    div(
      class = "page-header",
      h1("Data Quality"),
      div(
        class = "header-actions",
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # Quality Stats
    div(
      class = "quality-stats",
      uiOutput(ns("quality_kpis"))
    ),
    
    # Main Content Tabs
    div(
      class = "quality-tabs",
      tabsetPanel(
        id = ns("quality_tabset"),
        
        # Upload Tab
        tabPanel(
          "Upload Data",
          value = "upload",
          div(
            class = "upload-section",
            div(
              class = "upload-zone",
              fileInput(
                ns("file_upload"),
                label = NULL,
                accept = c(".csv", ".txt"),
                buttonLabel = "Choose CSV File",
                placeholder = "No file selected",
                width = "100%"
              ),
              div(
                class = "upload-instructions",
                h4("Upload Requirements"),
                tags$ul(
                  tags$li("CSV format with headers"),
                  tags$li("Required columns: metric_date, metric_name, metric_value"),
                  tags$li("Optional: team, region, channel, product"),
                  tags$li("Maximum file size: 50MB")
                )
              )
            ),
            
            # Upload Preview
            div(
              class = "upload-preview panel",
              div(class = "panel-header", h3("File Preview")),
              div(class = "panel-body", uiOutput(ns("upload_preview")))
            ),
            
            # Validation Results
            div(
              class = "validation-results panel",
              div(class = "panel-header", h3("Validation Results")),
              div(class = "panel-body", uiOutput(ns("validation_results")))
            ),
            
            # Action Buttons
            div(
              class = "upload-actions",
              actionButton(ns("validate_btn"), "Validate Data", 
                           class = "btn-secondary", disabled = TRUE),
              actionButton(ns("commit_btn"), "Commit Valid Rows", 
                           class = "btn-primary", disabled = TRUE)
            )
          )
        ),
        
        # Import History Tab
        tabPanel(
          "Import History",
          value = "history",
          div(
            class = "history-section",
            DTOutput(ns("import_history_table"))
          )
        ),
        
        # Validation Rules Tab
        tabPanel(
          "Validation Rules",
          value = "rules",
          div(
            class = "rules-section",
            div(
              class = "rules-header",
              actionButton(ns("add_rule_btn"), "Add Rule", 
                           icon = icon("plus"), class = "btn-primary")
            ),
            DTOutput(ns("rules_table"))
          )
        ),
        
        # Error Analysis Tab
        tabPanel(
          "Error Analysis",
          value = "errors",
          div(
            class = "errors-section",
            div(
              class = "errors-charts",
              div(
                class = "chart-container",
                div(class = "chart-header", h3("Errors by Type")),
                plotlyOutput(ns("errors_by_type_chart"), height = "300px")
              ),
              div(
                class = "chart-container",
                div(class = "chart-header", h3("Errors by Column")),
                plotlyOutput(ns("errors_by_column_chart"), height = "300px")
              )
            ),
            div(
              class = "errors-table panel",
              div(class = "panel-header", 
                  h3("Top Failing Rows"),
                  actionButton(ns("export_errors_btn"), "Export Errors", 
                               icon = icon("download"), class = "btn-secondary")),
              div(class = "panel-body", DTOutput(ns("errors_table")))
            )
          )
        )
      )
    )
  )
}

#' Quality Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_quality_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Local state
    rv <- reactiveValues(
      upload_data = NULL,
      import_id = NULL,
      validation_result = NULL,
      selected_import = NULL
    )
    
    # Quality KPIs
    output$quality_kpis <- renderUI({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      stats <- get_validation_stats(pool, tenant_id, days = 30)
      
      if (is.null(stats$summary)) {
        return(div(class = "no-stats", "No import data available"))
      }
      
      s <- stats$summary
      
      tagList(
        div(
          class = "kpi-card",
          div(class = "kpi-icon", icon("upload")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$total_imports %||% 0)),
              div(class = "kpi-label", "Total Imports"))
        ),
        div(
          class = "kpi-card",
          div(class = "kpi-icon", icon("database")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$total_rows %||% 0)),
              div(class = "kpi-label", "Total Rows"))
        ),
        div(
          class = paste("kpi-card", if ((s$avg_valid_pct %||% 100) >= 95) "success" else "warning"),
          div(class = "kpi-icon", icon("check-circle")),
          div(class = "kpi-content",
              div(class = "kpi-value", paste0(round(s$avg_valid_pct %||% 100, 1), "%")),
              div(class = "kpi-label", "Avg Valid Rate"))
        ),
        div(
          class = paste("kpi-card", if ((s$total_errors %||% 0) == 0) "success" else "danger"),
          div(class = "kpi-icon", icon("exclamation-circle")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$total_errors %||% 0)),
              div(class = "kpi-label", "Total Errors"))
        )
      )
    })
    
    # Handle file upload
    observeEvent(input$file_upload, {
      req(input$file_upload)
      
      file <- input$file_upload
      
      # Parse CSV
      result <- parse_csv_file(file$datapath)
      
      if (!result$success) {
        showNotification(paste("Failed to parse file:", result$error), type = "error")
        return()
      }
      
      rv$upload_data <- result$data
      rv$import_id <- NULL
      rv$validation_result <- NULL
      
      # Enable validate button
      shinyjs::enable("validate_btn")
      shinyjs::disable("commit_btn")
      
      showNotification(paste("File loaded:", result$row_count, "rows,", 
                             result$col_count, "columns"), type = "message")
    })
    
    # Upload preview
    output$upload_preview <- renderUI({
      if (is.null(rv$upload_data)) {
        return(div(class = "no-preview", "Upload a file to see preview"))
      }
      
      data <- head(rv$upload_data, 10)
      
      tagList(
        p(class = "preview-info", 
          paste("Showing first 10 of", nrow(rv$upload_data), "rows")),
        renderDT({
          datatable(
            data,
            options = list(
              dom = "t",
              scrollX = TRUE,
              paging = FALSE
            ),
            rownames = FALSE,
            class = "compact stripe"
          )
        })
      )
    })
    
    # Validate data
    observeEvent(input$validate_btn, {
      req(rv$upload_data, session_data$user)
      
      tenant_id <- session_data$user$tenant_id
      user_id <- session_data$user$id
      
      showNotification("Starting validation...", type = "message", id = "validate_progress")
      
      # Create import record
      import_id <- create_import(
        pool, tenant_id, user_id,
        filename = paste0("import_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"),
        original_filename = input$file_upload$name,
        file_size = input$file_upload$size
      )
      
      if (is.null(import_id)) {
        showNotification("Failed to create import record", type = "error")
        return()
      }
      
      rv$import_id <- import_id
      
      # Stage data
      update_import_status(pool, import_id, "processing")
      staged <- stage_import_data(pool, import_id, rv$upload_data)
      
      if (staged < 0) {
        showNotification("Failed to stage data", type = "error")
        update_import_status(pool, import_id, "failed", "Staging failed")
        return()
      }
      
      # Run validation
      result <- validate_import_data(pool, import_id, tenant_id)
      rv$validation_result <- result
      
      # Update status
      if (result$valid > 0) {
        update_import_status(pool, import_id, "validated")
        shinyjs::enable("commit_btn")
      } else {
        update_import_status(pool, import_id, "failed", "No valid rows")
      }
      
      removeNotification("validate_progress")
      showNotification(
        paste("Validation complete:", result$valid, "valid,", 
              result$invalid, "invalid rows"),
        type = if (result$invalid > 0) "warning" else "message"
      )
    })
    
    # Validation results display
    output$validation_results <- renderUI({
      if (is.null(rv$validation_result)) {
        return(div(class = "no-results", "Run validation to see results"))
      }
      
      result <- rv$validation_result
      
      tagList(
        div(
          class = "validation-summary",
          div(
            class = "validation-stat success",
            span(class = "stat-value", format_number(result$valid)),
            span(class = "stat-label", "Valid Rows")
          ),
          div(
            class = "validation-stat danger",
            span(class = "stat-value", format_number(result$invalid)),
            span(class = "stat-label", "Invalid Rows")
          ),
          div(
            class = "validation-stat warning",
            span(class = "stat-value", format_number(result$error_count)),
            span(class = "stat-label", "Total Errors")
          ),
          div(
            class = "validation-stat",
            span(class = "stat-value", 
                 format_percent(result$valid / result$total)),
            span(class = "stat-label", "Valid Rate")
          )
        )
      )
    })
    
    # Commit valid rows
    observeEvent(input$commit_btn, {
      req(rv$import_id, rv$validation_result, session_data$user)
      
      if (rv$validation_result$valid == 0) {
        showNotification("No valid rows to commit", type = "warning")
        return()
      }
      
      tenant_id <- session_data$user$tenant_id
      
      showNotification("Committing data...", type = "message", id = "commit_progress")
      
      committed <- commit_import_data(pool, rv$import_id, tenant_id)
      
      # Clean up staging
      delete_staging_data(pool, rv$import_id)
      
      removeNotification("commit_progress")
      
      if (committed > 0) {
        showNotification(paste("Successfully committed", committed, "rows"), type = "message")
        
        # Reset state
        rv$upload_data <- NULL
        rv$import_id <- NULL
        rv$validation_result <- NULL
        shinyjs::disable("validate_btn")
        shinyjs::disable("commit_btn")
      } else {
        showNotification("Failed to commit data", type = "error")
      }
    })
    
    # Import history table
    output$import_history_table <- renderDT({
      req(session_data$user)
      input$refresh_btn  # Trigger refresh
      
      tenant_id <- session_data$user$tenant_id
      history <- get_import_history(pool, tenant_id)
      
      if (is.null(history) || nrow(history) == 0) {
        return(datatable(
          data.frame(Message = "No import history"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- history %>%
        mutate(
          file = truncate_text(original_filename, 40),
          size = format_bytes(file_size_bytes),
          rows = paste0(format_number(valid_row_count %||% 0), " / ", 
                        format_number(row_count %||% 0)),
          errors = format_number(error_count %||% 0),
          date = format_datetime(created_at, "%Y-%m-%d %H:%M")
        ) %>%
        select(file, size, rows, errors, status, uploaded_by, date)
      
      datatable(
        display_data,
        options = list(
          pageLength = 15,
          dom = "frtip",
          order = list(list(6, "desc"))
        ),
        rownames = FALSE,
        colnames = c("File", "Size", "Valid/Total", "Errors", "Status", "Uploaded By", "Date"),
        selection = "single",
        class = "compact stripe"
      )
    }, server = TRUE)
    
    # Validation rules table
    output$rules_table <- renderDT({
      req(session_data$user)
      
      tenant_id <- session_data$user$tenant_id
      rules <- get_validation_rules(pool, tenant_id)
      
      if (is.null(rules) || nrow(rules) == 0) {
        return(datatable(
          data.frame(Message = "No validation rules configured"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- rules %>%
        select(name, column_name, rule_type, severity, description)
      
      datatable(
        display_data,
        options = list(
          pageLength = 15,
          dom = "frtip"
        ),
        rownames = FALSE,
        colnames = c("Rule Name", "Column", "Type", "Severity", "Description"),
        selection = "single",
        class = "compact stripe"
      )
    })
    
    # Errors by type chart
    output$errors_by_type_chart <- renderPlotly({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      stats <- get_validation_stats(pool, tenant_id, days = 30)
      
      if (is.null(stats$errors_by_type) || nrow(stats$errors_by_type) == 0) {
        return(plot_ly() %>% 
                 layout(title = "No error data", paper_bgcolor = "transparent"))
      }
      
      data <- stats$errors_by_type %>%
        group_by(error_type) %>%
        summarise(count = sum(count)) %>%
        arrange(desc(count))
      
      plot_ly(data, x = ~error_type, y = ~count, type = "bar",
              marker = list(color = "#ef4444")) %>%
        layout(
          xaxis = list(title = ""),
          yaxis = list(title = "Count"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8")
        )
    })
    
    # Errors by column chart
    output$errors_by_column_chart <- renderPlotly({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      stats <- get_validation_stats(pool, tenant_id, days = 30)
      
      if (is.null(stats$errors_by_type) || nrow(stats$errors_by_type) == 0) {
        return(plot_ly() %>% 
                 layout(title = "No error data", paper_bgcolor = "transparent"))
      }
      
      data <- stats$errors_by_type %>%
        group_by(column_name) %>%
        summarise(count = sum(count)) %>%
        arrange(desc(count))
      
      plot_ly(data, x = ~column_name, y = ~count, type = "bar",
              marker = list(color = "#f59e0b")) %>%
        layout(
          xaxis = list(title = ""),
          yaxis = list(title = "Count"),
          paper_bgcolor = "transparent",
          plot_bgcolor = "transparent",
          font = list(color = "#94a3b8")
        )
    })
  })
}
