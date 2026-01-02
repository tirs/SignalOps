# SignalOps Navigation Module
# Main application navigation and layout

#' Navigation Module UI
#' @param id Module namespace ID
mod_nav_ui <- function(id) {
  ns <- NS(id)
  
  tagList(
    # Top Navigation Bar
    tags$nav(
      class = "top-nav",
      div(
        class = "nav-brand",
        tags$img(src = "logo.svg", class = "nav-logo", alt = "SignalOps"),
        span("SignalOps")
      ),
      div(
        class = "nav-actions",
        uiOutput(ns("user_info")),
        actionButton(ns("logout_btn"), "Sign Out", class = "btn-nav-action")
      )
    ),
    
    # Main Layout with Sidebar
    div(
      class = "main-layout",
      
      # Sidebar Navigation
      tags$aside(
        class = "sidebar",
        div(
          class = "sidebar-nav",
          actionLink(ns("nav_overview"), 
                     div(class = "nav-item", icon("chart-line"), span("Overview")),
                     class = "nav-link active"),
          actionLink(ns("nav_explorer"), 
                     div(class = "nav-item", icon("table"), span("Explorer")),
                     class = "nav-link"),
          actionLink(ns("nav_quality"), 
                     div(class = "nav-item", icon("check-circle"), span("Data Quality")),
                     class = "nav-link"),
          actionLink(ns("nav_anomalies"), 
                     div(class = "nav-item", icon("exclamation-triangle"), span("Anomalies")),
                     class = "nav-link"),
          actionLink(ns("nav_incidents"), 
                     div(class = "nav-item", icon("flag"), span("Incidents")),
                     class = "nav-link"),
          actionLink(ns("nav_reports"), 
                     div(class = "nav-item", icon("file-alt"), span("Reports")),
                     class = "nav-link"),
          
          # Admin section (conditional)
          uiOutput(ns("admin_nav"))
        ),
        
        # Sidebar footer
        div(
          class = "sidebar-footer",
          uiOutput(ns("system_status"))
        )
      ),
      
      # Main Content Area
      tags$main(
        class = "main-content",
        uiOutput(ns("page_content"))
      )
    )
  )
}

#' Navigation Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Reactive values for session management
mod_nav_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Current page state
    current_page <- reactiveVal("overview")
    
    # Navigation handlers
    observeEvent(input$nav_overview, { current_page("overview") })
    observeEvent(input$nav_explorer, { current_page("explorer") })
    observeEvent(input$nav_quality, { current_page("quality") })
    observeEvent(input$nav_anomalies, { current_page("anomalies") })
    observeEvent(input$nav_incidents, { current_page("incidents") })
    observeEvent(input$nav_reports, { current_page("reports") })
    observeEvent(input$nav_admin, { current_page("admin") })
    
    # Update active nav link
    observe({
      page <- current_page()
      
      # Remove active class from all links
      shinyjs::runjs(sprintf("
        document.querySelectorAll('.sidebar .nav-link').forEach(function(el) {
          el.classList.remove('active');
        });
        document.querySelector('#%s').classList.add('active');
      ", ns(paste0("nav_", page))))
    })
    
    # Handle logout
    observeEvent(input$logout_btn, {
      logout_user(
        pool,
        session_data$session_id,
        session_data$user$id,
        session_data$user$tenant_id
      )
      
      session_data$logged_in <- FALSE
      session_data$user <- NULL
      session_data$session_token <- NULL
      session_data$session_id <- NULL
      
      log_app_info("User logged out")
    })
    
    # User info display
    output$user_info <- renderUI({
      req(session_data$user)
      user <- session_data$user
      
      div(
        class = "user-info",
        span(class = "user-name", user$full_name),
        span(class = "user-role", toupper(user$role))
      )
    })
    
    # Admin navigation (only for admin users)
    output$admin_nav <- renderUI({
      req(session_data$user)
      
      if (session_data$user$role == "admin") {
        div(
          class = "nav-section",
          div(class = "nav-section-title", "Administration"),
          actionLink(ns("nav_admin"), 
                     div(class = "nav-item", icon("cog"), span("Admin")),
                     class = "nav-link")
        )
      }
    })
    
    # System status indicator
    output$system_status <- renderUI({
      # Check database health
      db_health <- check_db_health(pool)
      
      status_class <- if (db_health$status == "healthy") "status-healthy" else "status-unhealthy"
      
      div(
        class = "system-status",
        div(
          class = paste("status-indicator", status_class),
          span(class = "status-dot"),
          span(class = "status-text", 
               if (db_health$status == "healthy") "System Online" else "System Issues")
        ),
        if (db_health$status == "healthy") {
          span(class = "status-latency", paste0(db_health$latency_ms, "ms"))
        }
      )
    })
    
    # Page content router
    output$page_content <- renderUI({
      page <- current_page()
      user <- session_data$user
      
      # Permission check
      page_permissions <- list(
        overview = c("viewer", "analyst", "admin"),
        explorer = c("viewer", "analyst", "admin"),
        quality = c("analyst", "admin"),
        anomalies = c("analyst", "admin"),
        incidents = c("analyst", "admin"),
        reports = c("viewer", "analyst", "admin"),
        admin = c("admin")
      )
      
      required <- page_permissions[[page]] %||% c("admin")
      
      if (!has_permission(user$role, required)) {
        return(div(
          class = "access-denied",
          icon("lock", class = "access-icon"),
          h2("Access Denied"),
          p("You do not have permission to view this page.")
        ))
      }
      
      # Render appropriate module
      switch(page,
        overview = mod_overview_ui(ns("overview")),
        explorer = mod_explorer_ui(ns("explorer")),
        quality = mod_quality_ui(ns("quality")),
        anomalies = mod_anomalies_ui(ns("anomalies")),
        incidents = mod_incidents_ui(ns("incidents")),
        reports = mod_reports_ui(ns("reports")),
        admin = mod_admin_ui(ns("admin")),
        div(class = "error-page", h2("Page Not Found"))
      )
    })
    
    # Initialize submodules
    mod_overview_server("overview", pool, session_data)
    mod_explorer_server("explorer", pool, session_data)
    mod_quality_server("quality", pool, session_data)
    mod_anomalies_server("anomalies", pool, session_data)
    mod_incidents_server("incidents", pool, session_data)
    mod_reports_server("reports", pool, session_data)
    mod_admin_server("admin", pool, session_data)
    
    # Return current page for external use
    return(list(
      current_page = current_page
    ))
  })
}
