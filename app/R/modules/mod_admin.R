# SignalOps Admin Module
# System administration, user management, and monitoring

#' Admin Module UI
#' @param id Module namespace ID
mod_admin_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "page-admin",
    
    # Page Header
    div(
      class = "page-header",
      h1("Administration"),
      div(
        class = "header-actions",
        actionButton(ns("refresh_btn"), icon("sync"), class = "btn-icon")
      )
    ),
    
    # Admin Tabs
    tabsetPanel(
      id = ns("admin_tabs"),
      
      # System Status Tab
      tabPanel(
        "System Status",
        value = "status",
        div(
          class = "admin-section",
          
          # Health Cards
          div(
            class = "health-cards",
            uiOutput(ns("system_health"))
          ),
          
          # Active Sessions
          div(
            class = "panel",
            div(class = "panel-header", h3("Active Sessions")),
            div(class = "panel-body", DTOutput(ns("active_sessions_table")))
          ),
          
          # Recent Jobs
          div(
            class = "panel",
            div(class = "panel-header", h3("Recent Jobs")),
            div(class = "panel-body", DTOutput(ns("recent_jobs_table")))
          )
        )
      ),
      
      # User Management Tab
      tabPanel(
        "Users",
        value = "users",
        div(
          class = "admin-section",
          div(
            class = "section-header",
            h3("User Management"),
            actionButton(ns("add_user_btn"), "Add User", 
                         icon = icon("plus"), class = "btn-primary")
          ),
          DTOutput(ns("users_table"))
        )
      ),
      
      # Audit Log Tab
      tabPanel(
        "Audit Log",
        value = "audit",
        div(
          class = "admin-section",
          div(
            class = "filters-panel compact",
            div(
              class = "filter-row",
              dateRangeInput(ns("audit_date_range"), "Date Range",
                             start = Sys.Date() - 7, end = Sys.Date()),
              selectInput(ns("audit_action_filter"), "Action",
                          choices = c("All" = "", "login", "logout", "data_import",
                                      "incident_create", "incident_update", "export_data")),
              actionButton(ns("apply_audit_filters"), "Apply", class = "btn-secondary")
            )
          ),
          DTOutput(ns("audit_table"))
        )
      ),
      
      # Settings Tab
      tabPanel(
        "Settings",
        value = "settings",
        div(
          class = "admin-section",
          div(
            class = "settings-grid",
            
            # Anomaly Detection Settings
            div(
              class = "settings-card",
              h4("Anomaly Detection"),
              numericInput(ns("zscore_low"), "Low Threshold (Z-Score)", 
                           value = 2.0, min = 1, max = 5, step = 0.1),
              numericInput(ns("zscore_medium"), "Medium Threshold (Z-Score)", 
                           value = 3.0, min = 1, max = 6, step = 0.1),
              numericInput(ns("zscore_high"), "High Threshold (Z-Score)", 
                           value = 4.0, min = 2, max = 8, step = 0.1),
              numericInput(ns("baseline_window"), "Baseline Window (Days)", 
                           value = 30, min = 7, max = 90),
              actionButton(ns("save_anomaly_settings"), "Save", class = "btn-primary")
            ),
            
            # Session Settings
            div(
              class = "settings-card",
              h4("Session Settings"),
              numericInput(ns("session_timeout"), "Session Timeout (Hours)", 
                           value = 24, min = 1, max = 168),
              numericInput(ns("max_login_attempts"), "Max Login Attempts", 
                           value = 5, min = 3, max = 10),
              numericInput(ns("lockout_duration"), "Lockout Duration (Minutes)", 
                           value = 15, min = 5, max = 60),
              actionButton(ns("save_session_settings"), "Save", class = "btn-primary")
            ),
            
            # Data Import Settings
            div(
              class = "settings-card",
              h4("Data Import"),
              numericInput(ns("max_upload_size"), "Max Upload Size (MB)", 
                           value = 50, min = 1, max = 500),
              numericInput(ns("chunk_size"), "Processing Chunk Size", 
                           value = 1000, min = 100, max = 10000),
              actionButton(ns("save_import_settings"), "Save", class = "btn-primary")
            ),
            
            # Cache Settings
            div(
              class = "settings-card",
              h4("Cache"),
              checkboxInput(ns("cache_enabled"), "Enable Cache", value = TRUE),
              numericInput(ns("cache_ttl"), "Cache TTL (Seconds)", 
                           value = 300, min = 60, max = 3600),
              actionButton(ns("clear_cache_btn"), "Clear Cache", class = "btn-secondary"),
              actionButton(ns("save_cache_settings"), "Save", class = "btn-primary")
            )
          )
        )
      )
    ),
    
    # Add User Modal
    div(
      id = ns("user_modal"),
      class = "modal-overlay hidden",
      div(
        class = "modal-content",
        div(
          class = "modal-header",
          h3("Add New User"),
          actionButton(ns("close_user_modal"), icon("times"), 
                       class = "btn-icon modal-close")
        ),
        div(
          class = "modal-body",
          textInput(ns("new_email"), "Email", width = "100%"),
          textInput(ns("new_first_name"), "First Name", width = "100%"),
          textInput(ns("new_last_name"), "Last Name", width = "100%"),
          passwordInput(ns("new_password"), "Initial Password", width = "100%"),
          selectInput(ns("new_role"), "Role",
                      choices = c("Viewer" = "viewer", "Analyst" = "analyst", 
                                  "Admin" = "admin"),
                      selected = "viewer")
        ),
        div(
          class = "modal-footer",
          actionButton(ns("cancel_user"), "Cancel", class = "btn-secondary"),
          actionButton(ns("confirm_user"), "Create User", class = "btn-primary")
        )
      )
    )
  )
}

#' Admin Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Session data reactive values
mod_admin_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # System health
    output$system_health <- renderUI({
      input$refresh_btn  # Trigger refresh
      
      # Database health
      db_health <- check_db_health(pool)
      
      # Cache stats
      cache_info <- cache_stats(app_cache)
      
      # Active sessions count
      sessions <- safe_query(pool, "
        SELECT COUNT(*) as count FROM sessions 
        WHERE is_active = TRUE AND expires_at > CURRENT_TIMESTAMP
      ")
      
      # Recent job stats
      job_stats <- safe_query(pool, "
        SELECT 
          COUNT(*) FILTER (WHERE status = 'pending') as pending,
          COUNT(*) FILTER (WHERE status = 'running') as running,
          COUNT(*) FILTER (WHERE status = 'failed' AND created_at > CURRENT_TIMESTAMP - INTERVAL '24 hours') as failed_24h
        FROM jobs
      ")
      
      tagList(
        div(
          class = paste("health-card", if (db_health$status == "healthy") "success" else "danger"),
          div(class = "health-icon", icon("database")),
          div(
            class = "health-content",
            h4("Database"),
            span(class = "health-status", db_health$status),
            if (!is.na(db_health$latency_ms)) {
              span(class = "health-detail", paste0(db_health$latency_ms, "ms"))
            }
          )
        ),
        div(
          class = "health-card",
          div(class = "health-icon", icon("users")),
          div(
            class = "health-content",
            h4("Active Sessions"),
            span(class = "health-status", sessions$count %||% 0)
          )
        ),
        div(
          class = paste("health-card", 
                        if ((job_stats$failed_24h %||% 0) > 0) "warning" else "success"),
          div(class = "health-icon", icon("tasks")),
          div(
            class = "health-content",
            h4("Jobs"),
            span(class = "health-status", 
                 paste0("Running: ", job_stats$running %||% 0)),
            span(class = "health-detail", 
                 paste0("Failed (24h): ", job_stats$failed_24h %||% 0))
          )
        ),
        div(
          class = paste("health-card", if (cache_info$enabled) "success" else "secondary"),
          div(class = "health-icon", icon("bolt")),
          div(
            class = "health-content",
            h4("Cache"),
            span(class = "health-status", 
                 if (cache_info$enabled) "Enabled" else "Disabled"),
            if (cache_info$enabled) {
              span(class = "health-detail", 
                   paste0(cache_info$n_objects %||% 0, " objects"))
            }
          )
        )
      )
    })
    
    # Active sessions table
    output$active_sessions_table <- renderDT({
      input$refresh_btn
      
      sessions <- safe_query(pool, "
        SELECT 
          s.id,
          u.email,
          u.role,
          s.ip_address,
          s.created_at,
          s.expires_at
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        WHERE s.is_active = TRUE 
          AND s.expires_at > CURRENT_TIMESTAMP
        ORDER BY s.created_at DESC
        LIMIT 50
      ")
      
      if (is.null(sessions) || nrow(sessions) == 0) {
        return(datatable(
          data.frame(Message = "No active sessions"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- sessions %>%
        mutate(
          started = format_datetime(created_at, "%Y-%m-%d %H:%M"),
          expires = format_datetime(expires_at, "%Y-%m-%d %H:%M")
        ) %>%
        select(email, role, ip_address, started, expires)
      
      datatable(
        display_data,
        options = list(
          pageLength = 10,
          dom = "rtip"
        ),
        rownames = FALSE,
        colnames = c("User", "Role", "IP Address", "Started", "Expires"),
        class = "compact stripe"
      )
    })
    
    # Recent jobs table
    output$recent_jobs_table <- renderDT({
      input$refresh_btn
      
      jobs <- safe_query(pool, "
        SELECT 
          j.id,
          j.job_type,
          j.status,
          j.progress,
          j.error_message,
          j.started_at,
          j.completed_at,
          u.email
        FROM jobs j
        LEFT JOIN users u ON j.user_id = u.id
        ORDER BY j.created_at DESC
        LIMIT 50
      ")
      
      if (is.null(jobs) || nrow(jobs) == 0) {
        return(datatable(
          data.frame(Message = "No jobs found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- jobs %>%
        mutate(
          type = gsub("_", " ", tools::toTitleCase(job_type)),
          progress = paste0(progress, "%"),
          duration = if_else(
            !is.na(completed_at) & !is.na(started_at),
            format_duration(as.numeric(difftime(completed_at, started_at, units = "secs"))),
            "-"
          ),
          started = format_datetime(started_at, "%Y-%m-%d %H:%M")
        ) %>%
        select(type, status, progress, duration, email, started)
      
      datatable(
        display_data,
        options = list(
          pageLength = 10,
          dom = "rtip"
        ),
        rownames = FALSE,
        colnames = c("Type", "Status", "Progress", "Duration", "User", "Started"),
        class = "compact stripe"
      )
    })
    
    # Users table
    output$users_table <- renderDT({
      req(session_data$user)
      input$refresh_btn
      
      users <- get_tenant_users(pool, session_data$user$tenant_id)
      
      if (is.null(users) || nrow(users) == 0) {
        return(datatable(
          data.frame(Message = "No users found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- users %>%
        mutate(
          name = paste(first_name, last_name),
          last_login = if_else(
            !is.na(last_login_at),
            format_datetime(last_login_at, "%Y-%m-%d %H:%M"),
            "Never"
          ),
          created = format_datetime(created_at, "%Y-%m-%d")
        ) %>%
        select(email, name, role, status, last_login, created)
      
      datatable(
        display_data,
        options = list(
          pageLength = 15,
          dom = "frtip"
        ),
        rownames = FALSE,
        colnames = c("Email", "Name", "Role", "Status", "Last Login", "Created"),
        selection = "single",
        class = "compact stripe"
      )
    })
    
    # Add user modal
    observeEvent(input$add_user_btn, {
      shinyjs::removeClass("user_modal", "hidden")
    })
    
    observeEvent(input$close_user_modal, {
      shinyjs::addClass("user_modal", "hidden")
    })
    
    observeEvent(input$cancel_user, {
      shinyjs::addClass("user_modal", "hidden")
    })
    
    observeEvent(input$confirm_user, {
      req(session_data$user)
      
      email <- trimws(input$new_email)
      if (!is_valid_email(email)) {
        showNotification("Invalid email address", type = "error")
        return()
      }
      
      if (trimws(input$new_password) == "" || nchar(input$new_password) < 8) {
        showNotification("Password must be at least 8 characters", type = "error")
        return()
      }
      
      result <- create_user(
        pool,
        session_data$user$tenant_id,
        email,
        input$new_password,
        trimws(input$new_first_name),
        trimws(input$new_last_name),
        input$new_role,
        session_data$user$id
      )
      
      if (result$success) {
        showNotification("User created successfully", type = "message")
        shinyjs::addClass("user_modal", "hidden")
        
        # Clear form
        updateTextInput(session, "new_email", value = "")
        updateTextInput(session, "new_first_name", value = "")
        updateTextInput(session, "new_last_name", value = "")
        updateTextInput(session, "new_password", value = "")
        updateSelectInput(session, "new_role", selected = "viewer")
      } else {
        showNotification(result$error, type = "error")
      }
    })
    
    # Audit log table
    output$audit_table <- renderDT({
      req(session_data$user)
      input$apply_audit_filters
      
      action_filter <- if (input$audit_action_filter != "") {
        input$audit_action_filter
      } else NULL
      
      logs <- get_audit_logs(
        pool,
        tenant_id = session_data$user$tenant_id,
        action = action_filter,
        start_date = input$audit_date_range[1],
        end_date = input$audit_date_range[2],
        limit = 500
      )
      
      if (is.null(logs) || nrow(logs) == 0) {
        return(datatable(
          data.frame(Message = "No audit logs found"),
          options = list(dom = "t"),
          rownames = FALSE
        ))
      }
      
      display_data <- logs %>%
        mutate(
          user = user_email %||% "System",
          action = gsub("_", " ", action),
          entity = paste(entity_type %||% "-", 
                         substr(entity_id %||% "-", 1, 8)),
          timestamp = format_datetime(created_at, "%Y-%m-%d %H:%M:%S")
        ) %>%
        select(timestamp, user, action, entity, ip_address)
      
      datatable(
        display_data,
        options = list(
          pageLength = 25,
          dom = "frtip",
          order = list(list(0, "desc"))
        ),
        rownames = FALSE,
        colnames = c("Timestamp", "User", "Action", "Entity", "IP Address"),
        class = "compact stripe"
      )
    }, server = TRUE)
    
    # Clear cache
    observeEvent(input$clear_cache_btn, {
      clear_cache(app_cache)
      showNotification("Cache cleared", type = "message")
    })
    
    # Save settings handlers (in production, these would persist to DB/config)
    observeEvent(input$save_anomaly_settings, {
      showNotification("Anomaly settings saved", type = "message")
    })
    
    observeEvent(input$save_session_settings, {
      showNotification("Session settings saved", type = "message")
    })
    
    observeEvent(input$save_import_settings, {
      showNotification("Import settings saved", type = "message")
    })
    
    observeEvent(input$save_cache_settings, {
      showNotification("Cache settings saved", type = "message")
    })
  })
}
