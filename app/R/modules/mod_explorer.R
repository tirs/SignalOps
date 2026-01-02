# SignalOps Explorer Module
# Data exploration with filtering, search, and pagination

#' Explorer Module UI
#' @param id Module namespace ID
mod_explorer_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-explorer",
    
    # Page Header
    div(
      class = "page-header",
      h1("Data Explorer"),
      div(
        class = "header-actions",
        actionButton(ns("export_btn"), "Export CSV", icon = icon("download"), 
                     class = "btn-secondary"),
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # Filters Panel
    div(
      class = "filters-panel",
      div(
        class = "filter-row",
        div(
          class = "filter-group",
          dateRangeInput(
            ns("date_range"),
            label = "Date Range",
            start = Sys.Date() - 30,
            end = Sys.Date(),
            width = "100%"
          )
        ),
        div(
          class = "filter-group",
          selectInput(
            ns("metric_filter"),
            label = "Metric",
            choices = c("All Metrics" = ""),
            width = "100%"
          )
        ),
        div(
          class = "filter-group",
          selectInput(
            ns("team_filter"),
            label = "Team",
            choices = c("All Teams" = ""),
            width = "100%"
          )
        ),
        div(
          class = "filter-group",
          selectInput(
            ns("region_filter"),
            label = "Region",
            choices = c("All Regions" = ""),
            width = "100%"
          )
        ),
        div(
          class = "filter-group",
          textInput(
            ns("search_input"),
            label = "Search",
            placeholder = "Search metrics...",
            width = "100%"
          )
        ),
        div(
          class = "filter-actions",
          actionButton(ns("apply_filters"), "Apply", class = "btn-primary"),
          actionButton(ns("reset_filters"), "Reset", class = "btn-secondary")
        )
      )
    ),
    
    # Summary Stats
    div(
      class = "explorer-stats",
      uiOutput(ns("stats_summary"))
    ),
    
    # Data Table
    div(
      class = "explorer-table panel",
      div(class = "panel-header", h3("Metrics Data")),
      div(class = "panel-body", DTOutput(ns("data_table")))
    ),
    
    # Detail View Modal
    div(
      id = ns("detail_modal"),
      class = "modal-overlay hidden",
      div(
        class = "modal-content",
        div(
          class = "modal-header",
          h3("Metric Details"),
          actionButton(ns("close_modal"), icon("times"), class = "btn-icon modal-close")
        ),
        div(
          class = "modal-body",
          uiOutput(ns("detail_content"))
        )
      )
    )
  )
}

#' Explorer Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_explorer_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Local state
    rv <- reactiveValues(
      selected_row = NULL,
      filters_applied = FALSE
    )
    
    # Populate filter dropdowns
    observe({
      req(session_data$user)
      tenant_id <- session_data$user$tenant_id
      
      # Get distinct values
      metrics <- safe_query(pool, "
        SELECT DISTINCT metric_name FROM metrics_data 
        WHERE tenant_id = $1 ORDER BY metric_name
      ", params = list(tenant_id))
      
      teams <- safe_query(pool, "
        SELECT DISTINCT team FROM metrics_data 
        WHERE tenant_id = $1 AND team IS NOT NULL ORDER BY team
      ", params = list(tenant_id))
      
      regions <- safe_query(pool, "
        SELECT DISTINCT region FROM metrics_data 
        WHERE tenant_id = $1 AND region IS NOT NULL ORDER BY region
      ", params = list(tenant_id))
      
      updateSelectInput(session, "metric_filter",
                        choices = c("All Metrics" = "", metrics$metric_name))
      updateSelectInput(session, "team_filter",
                        choices = c("All Teams" = "", teams$team))
      updateSelectInput(session, "region_filter",
                        choices = c("All Regions" = "", regions$region))
    })
    
    # Reset filters
    observeEvent(input$reset_filters, {
      updateDateRangeInput(session, "date_range",
                           start = Sys.Date() - 30, end = Sys.Date())
      updateSelectInput(session, "metric_filter", selected = "")
      updateSelectInput(session, "team_filter", selected = "")
      updateSelectInput(session, "region_filter", selected = "")
      updateTextInput(session, "search_input", value = "")
      rv$filters_applied <- FALSE
    })
    
    # Apply filters trigger
    observeEvent(input$apply_filters, {
      rv$filters_applied <- TRUE
    })
    
    # Build query based on filters
    filtered_data <- reactive({
      req(session_data$user)
      input$apply_filters  # Trigger on apply
      input$refresh_btn    # Trigger on refresh
      
      tenant_id <- session_data$user$tenant_id
      
      # Build dynamic query
      query <- "
        SELECT 
          id,
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
      "
      
      params <- list(tenant_id)
      param_idx <- 1
      
      # Date range filter
      if (!is.null(input$date_range)) {
        param_idx <- param_idx + 1
        query <- paste0(query, " AND metric_date >= $", param_idx)
        params[[param_idx]] <- input$date_range[1]
        
        param_idx <- param_idx + 1
        query <- paste0(query, " AND metric_date <= $", param_idx)
        params[[param_idx]] <- input$date_range[2]
      }
      
      # Metric filter
      if (!is.null(input$metric_filter) && input$metric_filter != "") {
        param_idx <- param_idx + 1
        query <- paste0(query, " AND metric_name = $", param_idx)
        params[[param_idx]] <- input$metric_filter
      }
      
      # Team filter
      if (!is.null(input$team_filter) && input$team_filter != "") {
        param_idx <- param_idx + 1
        query <- paste0(query, " AND team = $", param_idx)
        params[[param_idx]] <- input$team_filter
      }
      
      # Region filter
      if (!is.null(input$region_filter) && input$region_filter != "") {
        param_idx <- param_idx + 1
        query <- paste0(query, " AND region = $", param_idx)
        params[[param_idx]] <- input$region_filter
      }
      
      # Search filter
      if (!is.null(input$search_input) && input$search_input != "") {
        param_idx <- param_idx + 1
        search_term <- paste0("%", input$search_input, "%")
        query <- paste0(query, " AND (metric_name ILIKE $", param_idx, 
                        " OR team ILIKE $", param_idx,
                        " OR region ILIKE $", param_idx, ")")
        params[[param_idx]] <- search_term
      }
      
      query <- paste0(query, " ORDER BY metric_date DESC, metric_name LIMIT 1000")
      
      safe_query(pool, query, params = params)
    })
    
    # Stats Summary
    output$stats_summary <- renderUI({
      data <- filtered_data()
      
      if (is.null(data) || nrow(data) == 0) {
        return(div(class = "stats-empty", "No data matching filters"))
      }
      
      tagList(
        div(
          class = "stat-item",
          span(class = "stat-value", format_number(nrow(data))),
          span(class = "stat-label", "Records")
        ),
        div(
          class = "stat-item",
          span(class = "stat-value", format_number(length(unique(data$metric_name)))),
          span(class = "stat-label", "Metrics")
        ),
        div(
          class = "stat-item",
          span(class = "stat-value", format_number(sum(data$metric_value, na.rm = TRUE))),
          span(class = "stat-label", "Total Value")
        ),
        div(
          class = "stat-item",
          span(class = "stat-value", format_number(mean(data$metric_value, na.rm = TRUE), 2)),
          span(class = "stat-label", "Avg Value")
        )
      )
    })
    
    # Data Table
    output$data_table <- renderDT({
      data <- filtered_data()
      
      if (is.null(data) || nrow(data) == 0) {
        return(datatable(
          data.frame(Message = "No data found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- data %>%
        mutate(
          metric_date = format(metric_date, "%Y-%m-%d"),
          metric_value = format_number(metric_value, 2),
          team = team %||% "-",
          region = region %||% "-",
          channel = channel %||% "-",
          product = product %||% "-"
        ) %>%
        select(metric_date, metric_name, metric_value, team, region, channel, product)
      
      datatable(
        display_data,
        options = list(
          pageLength = 25,
          lengthMenu = c(10, 25, 50, 100),
          dom = "Blfrtip",
          scrollX = TRUE,
          columnDefs = list(
            list(className = "dt-right", targets = 2)
          )
        ),
        rownames = FALSE,
        colnames = c("Date", "Metric", "Value", "Team", "Region", "Channel", "Product"),
        selection = "single",
        class = "compact stripe hover"
      )
    }, server = TRUE)
    
    # Export CSV
    observeEvent(input$export_btn, {
      data <- filtered_data()
      
      if (!is.null(data) && nrow(data) > 0) {
        # Create temporary file
        temp_file <- tempfile(fileext = ".csv")
        readr::write_csv(data, temp_file)
        
        # Trigger download
        shinyjs::runjs(sprintf("
          var link = document.createElement('a');
          link.href = '%s';
          link.download = 'metrics_export_%s.csv';
          link.click();
        ", temp_file, format(Sys.time(), "%Y%m%d_%H%M%S")))
      }
    })
    
    # Row selection for detail view
    observeEvent(input$data_table_rows_selected, {
      data <- filtered_data()
      row_idx <- input$data_table_rows_selected
      
      if (!is.null(row_idx) && length(row_idx) > 0) {
        rv$selected_row <- data[row_idx, ]
        shinyjs::removeClass("detail_modal", "hidden")
      }
    })
    
    # Close modal
    observeEvent(input$close_modal, {
      shinyjs::addClass("detail_modal", "hidden")
      rv$selected_row <- NULL
    })
    
    # Detail content
    output$detail_content <- renderUI({
      req(rv$selected_row)
      row <- rv$selected_row
      
      tagList(
        div(
          class = "detail-grid",
          div(class = "detail-item",
              span(class = "detail-label", "Date"),
              span(class = "detail-value", format_date(row$metric_date))),
          div(class = "detail-item",
              span(class = "detail-label", "Metric"),
              span(class = "detail-value", row$metric_name)),
          div(class = "detail-item",
              span(class = "detail-label", "Value"),
              span(class = "detail-value", format_number(row$metric_value, 4))),
          div(class = "detail-item",
              span(class = "detail-label", "Team"),
              span(class = "detail-value", row$team %||% "-")),
          div(class = "detail-item",
              span(class = "detail-label", "Region"),
              span(class = "detail-value", row$region %||% "-")),
          div(class = "detail-item",
              span(class = "detail-label", "Channel"),
              span(class = "detail-value", row$channel %||% "-")),
          div(class = "detail-item",
              span(class = "detail-label", "Product"),
              span(class = "detail-value", row$product %||% "-")),
          div(class = "detail-item",
              span(class = "detail-label", "Created"),
              span(class = "detail-value", format_datetime(row$created_at)))
        )
      )
    })
  })
}
