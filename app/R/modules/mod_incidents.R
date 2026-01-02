# SignalOps Incidents Module
# Incident workflow management

#' Incidents Module UI
#' @param id Module namespace ID
mod_incidents_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-incidents",
    
    # Page Header
    div(
      class = "page-header",
      h1("Incident Management"),
      div(
        class = "header-actions",
        actionButton(ns("create_incident_btn"), "New Incident", 
                     icon = icon("plus"), class = "btn-primary"),
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # Incident Stats
    div(
      class = "incident-stats",
      uiOutput(ns("incident_kpis"))
    ),
    
    # Filters
    div(
      class = "filters-panel compact",
      div(
        class = "filter-row",
        selectInput(ns("status_filter"), "Status",
                    choices = c("All" = "", "Open" = "open", 
                                "Investigating" = "investigating",
                                "Mitigated" = "mitigated", "Closed" = "closed"),
                    width = "140px"),
        selectInput(ns("severity_filter"), "Severity",
                    choices = c("All" = "", "Low" = "low", "Medium" = "medium", 
                                "High" = "high", "Critical" = "critical"),
                    width = "120px"),
        selectInput(ns("assignee_filter"), "Assignee",
                    choices = c("All" = "", "Unassigned" = "unassigned"),
                    width = "150px"),
        actionButton(ns("apply_filters"), "Apply", class = "btn-secondary")
      )
    ),
    
    # Main Content
    div(
      class = "incidents-content",
      
      # Incidents List
      div(
        class = "incidents-list panel",
        div(class = "panel-header", h3("Incidents")),
        div(class = "panel-body", DTOutput(ns("incidents_table")))
      ),
      
      # Incident Detail Panel
      div(
        class = "incident-detail panel",
        div(class = "panel-header", 
            h3("Incident Details"),
            uiOutput(ns("detail_actions"))),
        div(class = "panel-body", uiOutput(ns("incident_detail")))
      )
    ),
    
    # Create Incident Modal
    div(
      id = ns("create_modal"),
      class = "modal-overlay hidden",
      div(
        class = "modal-content",
        div(
          class = "modal-header",
          h3("Create New Incident"),
          actionButton(ns("close_create_modal"), icon("times"), 
                       class = "btn-icon modal-close")
        ),
        div(
          class = "modal-body",
          textInput(ns("new_title"), "Title", width = "100%"),
          textAreaInput(ns("new_description"), "Description", 
                        rows = 3, width = "100%"),
          div(
            class = "form-row",
            selectInput(ns("new_severity"), "Severity",
                        choices = c("Low" = "low", "Medium" = "medium", 
                                    "High" = "high", "Critical" = "critical"),
                        selected = "medium"),
            selectInput(ns("new_assignee"), "Assign To",
                        choices = c("Unassigned" = ""))
          ),
          numericInput(ns("new_sla_hours"), "SLA (hours)", 
                       value = 24, min = 1, max = 720)
        ),
        div(
          class = "modal-footer",
          actionButton(ns("cancel_create"), "Cancel", class = "btn-secondary"),
          actionButton(ns("confirm_create"), "Create Incident", class = "btn-primary")
        )
      )
    ),
    
    # Add Comment Modal
    div(
      id = ns("comment_modal"),
      class = "modal-overlay hidden",
      div(
        class = "modal-content",
        div(
          class = "modal-header",
          h3("Add Comment"),
          actionButton(ns("close_comment_modal"), icon("times"), 
                       class = "btn-icon modal-close")
        ),
        div(
          class = "modal-body",
          textAreaInput(ns("comment_content"), "Comment", rows = 4, width = "100%"),
          checkboxInput(ns("comment_internal"), "Internal comment (not visible to external users)")
        ),
        div(
          class = "modal-footer",
          actionButton(ns("cancel_comment"), "Cancel", class = "btn-secondary"),
          actionButton(ns("confirm_comment"), "Add Comment", class = "btn-primary")
        )
      )
    )
  )
}

#' Incidents Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_incidents_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Local state
    rv <- reactiveValues(
      selected_incident_id = NULL,
      incident_detail = NULL
    )
    
    # Populate assignee dropdown
    observe({
      req(session_data$user)
      
      users <- get_tenant_users(pool, session_data$user$tenant_id)
      
      if (!is.null(users) && nrow(users) > 0) {
        choices <- c("Unassigned" = "", setNames(users$id, users$email))
        updateSelectInput(session, "new_assignee", choices = choices)
        updateSelectInput(session, "assignee_filter", 
                          choices = c("All" = "", "Unassigned" = "unassigned", 
                                      setNames(users$id, users$email)))
      }
    })
    
    # Incident data
    incident_data <- reactive({
      req(session_data$user)
      input$apply_filters
      input$refresh_btn
      
      tenant_id <- session_data$user$tenant_id
      
      status <- if (!is.null(input$status_filter) && input$status_filter != "") {
        input$status_filter
      } else NULL
      
      severity <- if (!is.null(input$severity_filter) && input$severity_filter != "") {
        input$severity_filter
      } else NULL
      
      assigned_to <- if (!is.null(input$assignee_filter) && input$assignee_filter != "" &&
                         input$assignee_filter != "unassigned") {
        input$assignee_filter
      } else NULL
      
      get_incidents(pool, tenant_id, 
                    status = status, 
                    severity = severity,
                    assigned_to = assigned_to)
    })
    
    # Incident KPIs
    output$incident_kpis <- renderUI({
      req(session_data$user)
      
      stats <- get_incident_stats(pool, session_data$user$tenant_id)
      
      if (is.null(stats$summary)) {
        return(div(class = "no-stats", "No incident data"))
      }
      
      s <- stats$summary
      
      tagList(
        div(
          class = "kpi-card danger",
          div(class = "kpi-icon", icon("exclamation-circle")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$open_count %||% 0)),
              div(class = "kpi-label", "Open"))
        ),
        div(
          class = "kpi-card warning",
          div(class = "kpi-icon", icon("search")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$investigating_count %||% 0)),
              div(class = "kpi-label", "Investigating"))
        ),
        div(
          class = paste("kpi-card", if ((s$sla_breached_count %||% 0) > 0) "danger" else "success"),
          div(class = "kpi-icon", icon("clock")),
          div(class = "kpi-content",
              div(class = "kpi-value", format_number(s$sla_breached_count %||% 0)),
              div(class = "kpi-label", "SLA Breached"))
        ),
        div(
          class = "kpi-card",
          div(class = "kpi-icon", icon("hourglass-half")),
          div(class = "kpi-content",
              div(class = "kpi-value", 
                  if (!is.na(s$avg_resolution_hours)) {
                    paste0(round(s$avg_resolution_hours, 1), "h")
                  } else "-"),
              div(class = "kpi-label", "Avg Resolution"))
        )
      )
    })
    
    # Incidents table
    output$incidents_table <- renderDT({
      data <- incident_data()
      
      if (is.null(data) || nrow(data) == 0) {
        return(datatable(
          data.frame(Message = "No incidents found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- data %>%
        mutate(
          title = truncate_text(title, 40),
          age = format_duration(age_hours * 3600),
          assigned = assigned_to_email %||% "Unassigned",
          sla = if_else(sla_breached, "BREACHED", "OK")
        ) %>%
        select(title, severity, status, assigned, age, sla)
      
      datatable(
        display_data,
        options = list(
          pageLength = 15,
          dom = "frtip",
          columnDefs = list(
            list(className = "dt-center", targets = c(1, 2, 4, 5))
          )
        ),
        rownames = FALSE,
        colnames = c("Title", "Severity", "Status", "Assigned To", "Age", "SLA"),
        selection = "single",
        class = "compact stripe"
      )
    }, server = TRUE)
    
    # Row selection
    observeEvent(input$incidents_table_rows_selected, {
      data <- incident_data()
      row_idx <- input$incidents_table_rows_selected
      
      if (!is.null(row_idx) && length(row_idx) > 0) {
        rv$selected_incident_id <- data$id[row_idx]
        rv$incident_detail <- get_incident_details(pool, rv$selected_incident_id)
      }
    })
    
    # Detail actions
    output$detail_actions <- renderUI({
      if (is.null(rv$incident_detail)) return(NULL)
      
      i <- rv$incident_detail$incident
      
      tagList(
        actionButton(ns("add_comment_btn"), "Add Comment", 
                     icon = icon("comment"), class = "btn-secondary btn-sm"),
        if (i$status != "closed") {
          actionButton(ns("update_status_btn"), "Update Status",
                       icon = icon("edit"), class = "btn-secondary btn-sm")
        }
      )
    })
    
    # Incident detail
    output$incident_detail <- renderUI({
      if (is.null(rv$incident_detail)) {
        return(div(class = "no-selection", 
                   icon("mouse-pointer"), 
                   p("Select an incident to view details")))
      }
      
      detail <- rv$incident_detail
      i <- detail$incident
      
      tagList(
        # Header
        div(
          class = "incident-header",
          h4(i$title),
          div(
            class = "incident-badges",
            severity_badge(i$severity),
            status_badge(i$status),
            if (!is.null(i$sla_due_at) && i$sla_due_at < Sys.time() && 
                !(i$status %in% c("closed", "false_positive"))) {
              span(class = "badge bg-danger", "SLA BREACHED")
            }
          )
        ),
        
        # Meta info
        div(
          class = "incident-meta",
          div(class = "meta-item",
              icon("user"), 
              span("Created by: ", i$created_by_email %||% "Unknown")),
          div(class = "meta-item",
              icon("user-check"), 
              span("Assigned to: ", i$assigned_to_email %||% "Unassigned")),
          div(class = "meta-item",
              icon("calendar"), 
              span("Created: ", format_datetime(i$created_at))),
          if (!is.null(i$sla_due_at)) {
            div(class = "meta-item",
                icon("clock"), 
                span("SLA Due: ", format_datetime(i$sla_due_at)))
          }
        ),
        
        # Description
        if (!is.null(i$description) && i$description != "") {
          div(
            class = "incident-description",
            h5("Description"),
            p(i$description)
          )
        },
        
        # Related anomaly
        if (!is.null(i$anomaly_metric)) {
          div(
            class = "incident-anomaly",
            h5("Related Anomaly"),
            p(paste("Metric:", i$anomaly_metric, 
                    "| Value:", format_number(i$anomaly_value, 2),
                    "| Z-Score:", round(i$anomaly_zscore, 2)))
          )
        },
        
        # Status history
        if (!is.null(detail$history) && nrow(detail$history) > 0) {
          div(
            class = "incident-history",
            h5("Status History"),
            div(
              class = "history-timeline",
              lapply(seq_len(nrow(detail$history)), function(idx) {
                h <- detail$history[idx, ]
                div(
                  class = "history-item",
                  div(class = "history-marker"),
                  div(
                    class = "history-content",
                    span(class = "history-status",
                         if (!is.na(h$old_status)) {
                           paste(h$old_status, "->", h$new_status)
                         } else {
                           h$new_status
                         }),
                    span(class = "history-by", h$user_email %||% "System"),
                    span(class = "history-time", format_datetime(h$created_at, "%b %d, %H:%M"))
                  )
                )
              })
            )
          )
        },
        
        # Comments
        div(
          class = "incident-comments",
          h5("Comments"),
          if (!is.null(detail$comments) && nrow(detail$comments) > 0) {
            div(
              class = "comments-list",
              lapply(seq_len(nrow(detail$comments)), function(idx) {
                c <- detail$comments[idx, ]
                div(
                  class = paste("comment-item", if (c$is_internal) "internal" else ""),
                  div(
                    class = "comment-header",
                    span(class = "comment-author", c$user_name %||% c$user_email),
                    span(class = "comment-time", format_datetime(c$created_at, "%b %d, %H:%M")),
                    if (c$is_internal) span(class = "badge bg-secondary", "Internal")
                  ),
                  div(class = "comment-body", c$content)
                )
              })
            )
          } else {
            p(class = "no-comments", "No comments yet")
          }
        )
      )
    })
    
    # Create incident modal
    observeEvent(input$create_incident_btn, {
      shinyjs::removeClass("create_modal", "hidden")
    })
    
    observeEvent(input$close_create_modal, {
      shinyjs::addClass("create_modal", "hidden")
    })
    
    observeEvent(input$cancel_create, {
      shinyjs::addClass("create_modal", "hidden")
    })
    
    observeEvent(input$confirm_create, {
      req(session_data$user)
      
      title <- trimws(input$new_title)
      if (title == "") {
        showNotification("Title is required", type = "error")
        return()
      }
      
      assigned_to <- if (input$new_assignee != "") input$new_assignee else NULL
      
      incident_id <- create_incident(
        pool,
        tenant_id = session_data$user$tenant_id,
        title = title,
        description = input$new_description,
        severity = input$new_severity,
        created_by = session_data$user$id,
        assigned_to = assigned_to,
        sla_hours = input$new_sla_hours
      )
      
      if (!is.null(incident_id)) {
        showNotification("Incident created", type = "message")
        shinyjs::addClass("create_modal", "hidden")
        
        # Clear form
        updateTextInput(session, "new_title", value = "")
        updateTextAreaInput(session, "new_description", value = "")
        updateSelectInput(session, "new_severity", selected = "medium")
        updateSelectInput(session, "new_assignee", selected = "")
        updateNumericInput(session, "new_sla_hours", value = 24)
      } else {
        showNotification("Failed to create incident", type = "error")
      }
    })
    
    # Add comment modal
    observeEvent(input$add_comment_btn, {
      shinyjs::removeClass("comment_modal", "hidden")
    })
    
    observeEvent(input$close_comment_modal, {
      shinyjs::addClass("comment_modal", "hidden")
    })
    
    observeEvent(input$cancel_comment, {
      shinyjs::addClass("comment_modal", "hidden")
    })
    
    observeEvent(input$confirm_comment, {
      req(rv$selected_incident_id, session_data$user)
      
      content <- trimws(input$comment_content)
      if (content == "") {
        showNotification("Comment cannot be empty", type = "error")
        return()
      }
      
      comment_id <- add_incident_comment(
        pool,
        rv$selected_incident_id,
        session_data$user$id,
        content,
        input$comment_internal
      )
      
      if (!is.null(comment_id)) {
        showNotification("Comment added", type = "message")
        shinyjs::addClass("comment_modal", "hidden")
        updateTextAreaInput(session, "comment_content", value = "")
        updateCheckboxInput(session, "comment_internal", value = FALSE)
        
        # Refresh detail
        rv$incident_detail <- get_incident_details(pool, rv$selected_incident_id)
      } else {
        showNotification("Failed to add comment", type = "error")
      }
    })
    
    # Update status
    observeEvent(input$update_status_btn, {
      req(rv$incident_detail)
      
      current_status <- rv$incident_detail$incident$status
      
      next_statuses <- switch(current_status,
        "open" = c("investigating", "closed", "false_positive"),
        "investigating" = c("mitigated", "closed", "false_positive"),
        "mitigated" = c("closed", "investigating"),
        c("closed")
      )
      
      showModal(modalDialog(
        title = "Update Status",
        selectInput(ns("new_status"), "New Status",
                    choices = setNames(next_statuses, 
                                       gsub("_", " ", tools::toTitleCase(next_statuses)))),
        textAreaInput(ns("status_notes"), "Notes (optional)", rows = 2),
        footer = tagList(
          actionButton(ns("cancel_status"), "Cancel", class = "btn-secondary"),
          actionButton(ns("confirm_status"), "Update", class = "btn-primary")
        )
      ))
    })
    
    observeEvent(input$cancel_status, {
      removeModal()
    })
    
    observeEvent(input$confirm_status, {
      req(rv$selected_incident_id, session_data$user)
      
      success <- update_incident_status(
        pool,
        rv$selected_incident_id,
        input$new_status,
        session_data$user$id,
        if (input$status_notes != "") input$status_notes else NULL
      )
      
      if (success) {
        showNotification("Status updated", type = "message")
        removeModal()
        rv$incident_detail <- get_incident_details(pool, rv$selected_incident_id)
      } else {
        showNotification("Failed to update status", type = "error")
      }
    })
  })
}
