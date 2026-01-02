# SignalOps - Production-Grade Analytics Dashboard
# Main Application Entry Point

# Load global configuration and modules
source("global.R")

# Define UI
ui <- function(request) {
  tagList(
    # HTML Head
    tags$head(
      tags$meta(charset = "UTF-8"),
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
      tags$title("SignalOps | Analytics Dashboard"),
      tags$link(rel = "stylesheet", href = "styles.css"),
      tags$link(rel = "icon", type = "image/svg+xml", href = "logo.svg"),
      # Font imports
      tags$link(
        rel = "stylesheet",
        href = "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Manrope:wght@400;500;600;700&display=swap"
      )
    ),
    
    # Use shinyjs for JavaScript interactivity
    shinyjs::useShinyjs(),
    
    # Use waiter for loading screens
    waiter::useWaiter(),
    waiter::useHostess(),
    
    # Main container
    div(
      class = "app-container",
      
      # Application content
      uiOutput("app_content")
    ),
    
    # Global keyboard shortcuts and handlers
    tags$script(HTML("
      // Enter key on password field triggers login
      $(document).on('keypress', 'input[type=password]', function(e) {
        if (e.which == 13) {
          var loginBtn = $(this).closest('.login-form').find('.btn-login');
          if (loginBtn.length) {
            loginBtn.click();
          }
        }
      });
      
      // Add loading state to buttons on click
      $(document).on('click', '.btn-primary, .btn-secondary', function() {
        var btn = $(this);
        if (!btn.hasClass('btn-icon')) {
          btn.addClass('loading');
          setTimeout(function() {
            btn.removeClass('loading');
          }, 3000);
        }
      });
    "))
  )
}

# Define Server
server <- function(input, output, session) {
  
  # Session data (shared state)
  session_data <- reactiveValues(
    logged_in = FALSE,
    user = NULL,
    session_token = NULL,
    session_id = NULL
  )
  
  # Check for existing session (cookie-based persistence would go here)
  observe({
    # In production, check for session cookie and validate
    # For demo, start fresh each time
  })
  
  # Global error handler
  options(shiny.error = function() {
    log_app_error("Shiny error", 
                  error = geterrmessage(),
                  user_id = session_data$user$id)
  })
  
  # Render main content based on auth state
  output$app_content <- renderUI({
    if (session_data$logged_in) {
      # Authenticated: show main app
      mod_nav_ui("nav")
    } else {
      # Not authenticated: show login
      mod_login_ui("login")
    }
  })
  
  # Initialize login module
  mod_login_server("login", db_pool, session_data)
  
  # Initialize navigation module (handles all sub-modules)
  observe({
    req(session_data$logged_in)
    mod_nav_server("nav", db_pool, session_data)
  })
  
  # Session timeout handling
  session_timeout <- reactiveTimer(60000)  # Check every minute
  
  observeEvent(session_timeout(), {
    if (session_data$logged_in && !is.null(session_data$session_token)) {
      # Validate session is still active
      user_info <- validate_session(db_pool, session_data$session_token)
      
      if (is.null(user_info)) {
        # Session expired
        session_data$logged_in <- FALSE
        session_data$user <- NULL
        session_data$session_token <- NULL
        session_data$session_id <- NULL
        
        showNotification(
          "Your session has expired. Please log in again.",
          type = "warning",
          duration = NULL
        )
      }
    }
  })
  
  # Clean up on session end
  session$onSessionEnded(function() {
    isolate({
      if (!is.null(session_data$session_id)) {
        logout_user(db_pool, session_data$session_id, 
                    session_data$user$id, session_data$user$tenant_id)
      }
    })
    log_app_info("User session ended")
  })
}

# Run the application
shinyApp(ui = ui, server = server)
