# SignalOps Login Module
# User authentication UI and server logic

#' Login Module UI
#' @param id Module namespace ID
mod_login_ui <- function(id) {
  ns <- NS(id)
  
  div(
    class = "login-container",
    div(
      class = "login-card",
      div(
        class = "login-header",
        tags$img(src = "logo.svg", class = "login-logo", alt = "SignalOps"),
        h1("SignalOps"),
        p(class = "login-subtitle", "Analytics & Operations Dashboard")
      ),
      
      div(
        class = "login-form",
        # Login Form
        div(
          id = ns("login_form_container"),
          textInput(
            ns("email"),
            label = NULL,
            placeholder = "Email address",
            width = "100%"
          ),
          passwordInput(
            ns("password"),
            label = NULL,
            placeholder = "Password",
            width = "100%"
          ),
          div(
            class = "login-actions",
            actionButton(
              ns("login_btn"),
              "Sign In",
              class = "btn-login",
              width = "100%"
            )
          ),
          div(
            class = "login-links",
            actionLink(ns("forgot_password"), "Forgot password?")
          )
        ),
        
        # Password Reset Form (hidden by default)
        shinyjs::hidden(
          div(
            id = ns("reset_form_container"),
            p(class = "reset-instructions", 
              "Enter your email address to receive a password reset link."),
            textInput(
              ns("reset_email"),
              label = NULL,
              placeholder = "Email address",
              width = "100%"
            ),
            div(
              class = "login-actions",
              actionButton(
                ns("reset_btn"),
                "Send Reset Link",
                class = "btn-login",
                width = "100%"
              )
            ),
            div(
              class = "login-links",
              actionLink(ns("back_to_login"), "Back to login")
            )
          )
        ),
        
        # Error/Success messages
        div(
          id = ns("message_container"),
          class = "login-message",
          uiOutput(ns("login_message"))
        )
      ),
      
      div(
        class = "login-footer",
        p("Demo credentials: admin@signalops.io / admin123")
      )
    )
  )
}

#' Login Module Server
#' @param id Module namespace ID
#' @param pool Database connection pool
#' @param session_data Reactive values for session management
mod_login_server <- function(id, pool, session_data) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Local state
    rv <- reactiveValues(
      message = NULL,
      message_type = NULL,
      show_reset = FALSE
    )
    
    # Toggle between login and reset forms
    observeEvent(input$forgot_password, {
      shinyjs::hide("login_form_container")
      shinyjs::show("reset_form_container")
      rv$message <- NULL
    })
    
    observeEvent(input$back_to_login, {
      shinyjs::show("login_form_container")
      shinyjs::hide("reset_form_container")
      rv$message <- NULL
    })
    
    # Handle login
    observeEvent(input$login_btn, {
      req(input$email, input$password)
      
      email <- trimws(input$email)
      password <- input$password
      
      # Validate inputs
      if (email == "" || !is_valid_email(email)) {
        rv$message <- "Please enter a valid email address"
        rv$message_type <- "error"
        return()
      }
      
      if (password == "") {
        rv$message <- "Please enter your password"
        rv$message_type <- "error"
        return()
      }
      
      # Attempt authentication
      result <- authenticate_user(
        pool,
        email,
        password,
        ip_address = get_client_ip(session),
        user_agent = get_user_agent(session)
      )
      
      if (result$success) {
        # Store session data
        session_data$logged_in <- TRUE
        session_data$user <- result$user
        session_data$session_token <- result$session$token
        session_data$session_id <- result$session$id
        
        rv$message <- NULL
        log_app_info("User login successful", 
                     user_id = result$user$id,
                     email = result$user$email)
      } else {
        rv$message <- result$error
        rv$message_type <- "error"
      }
    })
    
    # Handle password reset request
    observeEvent(input$reset_btn, {
      req(input$reset_email)
      
      email <- trimws(input$reset_email)
      
      if (!is_valid_email(email)) {
        rv$message <- "Please enter a valid email address"
        rv$message_type <- "error"
        return()
      }
      
      result <- initiate_password_reset(pool, email)
      
      rv$message <- result$message
      rv$message_type <- "success"
      
      # In production, the token would be sent via email
      # For demo, show it in the message
      if (!is.null(result$token)) {
        rv$message <- paste0(result$message, " (Demo token: ", result$token, ")")
      }
    })
    
    # Render message
    output$login_message <- renderUI({
      if (is.null(rv$message)) return(NULL)
      
      class <- if (rv$message_type == "error") "alert-error" else "alert-success"
      
      div(
        class = paste("alert", class),
        rv$message
      )
    })
    
    # Handle Enter key
    observeEvent(input$password, {
      if (!is.null(input$password) && nchar(input$password) > 0) {
        # Trigger login on Enter (handled by JavaScript)
      }
    }, ignoreInit = TRUE)
  })
}
