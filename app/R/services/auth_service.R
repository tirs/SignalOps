# SignalOps Authentication Service
# User authentication, session management, and password handling

#' Hash a password using Argon2
#' @param password Plain text password
#' @return Password hash string
hash_password <- function(password) {
  sodium::password_store(password)
}

#' Verify a password against a hash
#' @param password Plain text password
#' @param hash Stored password hash
#' @return TRUE if password matches, FALSE otherwise
verify_password <- function(password, hash) {
  tryCatch({
    sodium::password_verify(hash, password)
  }, error = function(e) {
    log_app_warn("Password verification error", error = e$message)
    FALSE
  })
}

#' Generate a secure session token
#' @return Token string (64 characters hex)
generate_session_token <- function() {
  paste0(sodium::bin2hex(sodium::random(32)))
}

#' Generate a password reset token
#' @return Token string
generate_reset_token <- function() {
  paste0(sodium::bin2hex(sodium::random(24)))
}

#' Authenticate a user by email and password
#' @param pool Database pool
#' @param email User email
#' @param password User password
#' @param ip_address Client IP address
#' @param user_agent Client user agent
#' @return List with success status and user/session info or error message
authenticate_user <- function(pool, email, password, ip_address = NULL, user_agent = NULL) {
  # Get user by email
  user <- safe_query(pool, "
    SELECT id, tenant_id, email, password_hash, first_name, last_name, 
           role, status, login_attempts, locked_until
    FROM users 
    WHERE LOWER(email) = LOWER($1)
  ", params = list(email))
  
  if (is.null(user) || nrow(user) == 0) {
    log_app_info("Login failed: user not found", email = email)
    return(list(success = FALSE, error = "Invalid email or password"))
  }
  
  user <- user[1, ]
  
  # Check if account is locked
  if (!is.na(user$locked_until) && user$locked_until > Sys.time()) {
    log_app_warn("Login failed: account locked", email = email)
    return(list(success = FALSE, error = "Account is locked. Please try again later."))
  }
  
  # Check if account is active
  if (user$status != "active") {
    log_app_warn("Login failed: account not active", email = email, status = user$status)
    return(list(success = FALSE, error = "Account is not active. Please contact support."))
  }
  
  # Verify password
  if (!verify_password(password, user$password_hash)) {
    # Increment login attempts
    attempts <- user$login_attempts + 1
    max_attempts <- app_config$auth$max_login_attempts %||% 5
    
    if (attempts >= max_attempts) {
      lockout_minutes <- app_config$auth$lockout_duration_minutes %||% 15
      locked_until <- Sys.time() + (lockout_minutes * 60)
      
      safe_execute(pool, "
        UPDATE users 
        SET login_attempts = $1, locked_until = $2
        WHERE id = $3
      ", params = list(attempts, locked_until, user$id))
      
      log_app_warn("Account locked due to failed attempts", 
                   email = email, 
                   attempts = attempts)
      
      create_audit_log(pool, "login_failed", 
                       user_id = user$id,
                       tenant_id = user$tenant_id,
                       ip_address = ip_address,
                       user_agent = user_agent,
                       metadata = list(reason = "account_locked", attempts = attempts))
      
      return(list(success = FALSE, error = "Too many failed attempts. Account locked."))
    } else {
      safe_execute(pool, "
        UPDATE users SET login_attempts = $1 WHERE id = $2
      ", params = list(attempts, user$id))
      
      create_audit_log(pool, "login_failed",
                       user_id = user$id,
                       tenant_id = user$tenant_id,
                       ip_address = ip_address,
                       user_agent = user_agent,
                       metadata = list(reason = "invalid_password"))
    }
    
    return(list(success = FALSE, error = "Invalid email or password"))
  }
  
  # Successful authentication - create session
  session_token <- generate_session_token()
  session_duration <- app_config$auth$session_duration_hours %||% 24
  expires_at <- Sys.time() + (session_duration * 3600)
  
  session_result <- safe_query(pool, "
    INSERT INTO sessions (user_id, token, ip_address, user_agent, expires_at)
    VALUES ($1, $2, $3, $4, $5)
    RETURNING id
  ", params = list(user$id, session_token, ip_address, user_agent, expires_at))
  
  # Reset login attempts and update last login
  safe_execute(pool, "
    UPDATE users 
    SET login_attempts = 0, locked_until = NULL, last_login_at = CURRENT_TIMESTAMP
    WHERE id = $1
  ", params = list(user$id))
  
  # Create audit log
  create_audit_log(pool, "login",
                   user_id = user$id,
                   tenant_id = user$tenant_id,
                   session_id = session_result$id,
                   ip_address = ip_address,
                   user_agent = user_agent)
  
  log_app_info("User logged in successfully", 
               user_id = user$id, 
               email = email)
  
  list(
    success = TRUE,
    user = list(
      id = user$id,
      tenant_id = user$tenant_id,
      email = user$email,
      first_name = user$first_name,
      last_name = user$last_name,
      role = user$role,
      full_name = paste(user$first_name, user$last_name)
    ),
    session = list(
      id = session_result$id,
      token = session_token,
      expires_at = expires_at
    )
  )
}

#' Validate a session token
#' @param pool Database pool
#' @param token Session token
#' @return User info if valid, NULL otherwise
validate_session <- function(pool, token) {
  if (is.null(token) || token == "") return(NULL)
  
  result <- safe_query(pool, "
    SELECT 
      s.id as session_id,
      s.expires_at,
      u.id as user_id,
      u.tenant_id,
      u.email,
      u.first_name,
      u.last_name,
      u.role,
      u.status
    FROM sessions s
    JOIN users u ON s.user_id = u.id
    WHERE s.token = $1 
      AND s.is_active = TRUE 
      AND s.expires_at > CURRENT_TIMESTAMP
  ", params = list(token))
  
  if (is.null(result) || nrow(result) == 0) {
    return(NULL)
  }
  
  session <- result[1, ]
  
  if (session$status != "active") {
    return(NULL)
  }
  
  list(
    session_id = session$session_id,
    user_id = session$user_id,
    tenant_id = session$tenant_id,
    email = session$email,
    first_name = session$first_name,
    last_name = session$last_name,
    role = session$role,
    full_name = paste(session$first_name, session$last_name)
  )
}

#' Logout user and invalidate session
#' @param pool Database pool
#' @param session_id Session ID to invalidate
#' @param user_id User ID for audit
#' @param tenant_id Tenant ID for audit
logout_user <- function(pool, session_id, user_id = NULL, tenant_id = NULL) {
  safe_execute(pool, "
    UPDATE sessions SET is_active = FALSE WHERE id = $1
  ", params = list(session_id))
  
  create_audit_log(pool, "logout",
                   user_id = user_id,
                   tenant_id = tenant_id,
                   session_id = session_id)
  
  log_app_info("User logged out", user_id = user_id)
}

#' Initiate password reset
#' @param pool Database pool
#' @param email User email
#' @return List with success status and token (for demo) or error
initiate_password_reset <- function(pool, email) {
  user <- safe_query(pool, "
    SELECT id, tenant_id, email, status FROM users WHERE LOWER(email) = LOWER($1)
  ", params = list(email))
  
  if (is.null(user) || nrow(user) == 0) {
    # Don't reveal if email exists
    return(list(success = TRUE, message = "If the email exists, a reset link has been sent."))
  }
  
  user <- user[1, ]
  
  if (user$status != "active") {
    return(list(success = TRUE, message = "If the email exists, a reset link has been sent."))
  }
  
  token <- generate_reset_token()
  expires <- Sys.time() + 3600  # 1 hour
  
  safe_execute(pool, "
    UPDATE users 
    SET password_reset_token = $1, password_reset_expires = $2
    WHERE id = $3
  ", params = list(token, expires, user$id))
  
  create_audit_log(pool, "password_reset",
                   user_id = user$id,
                   tenant_id = user$tenant_id,
                   metadata = list(initiated = TRUE))
  
  log_app_info("Password reset initiated", email = email)
  
  list(
    success = TRUE,
    message = "If the email exists, a reset link has been sent.",
    token = token  # In production, send via email instead
  )
}

#' Complete password reset
#' @param pool Database pool
#' @param token Reset token
#' @param new_password New password
#' @return List with success status
complete_password_reset <- function(pool, token, new_password) {
  user <- safe_query(pool, "
    SELECT id, tenant_id, email 
    FROM users 
    WHERE password_reset_token = $1 
      AND password_reset_expires > CURRENT_TIMESTAMP
  ", params = list(token))
  
  if (is.null(user) || nrow(user) == 0) {
    return(list(success = FALSE, error = "Invalid or expired reset token"))
  }
  
  user <- user[1, ]
  password_hash <- hash_password(new_password)
  
  safe_execute(pool, "
    UPDATE users 
    SET password_hash = $1, 
        password_reset_token = NULL, 
        password_reset_expires = NULL,
        login_attempts = 0,
        locked_until = NULL
    WHERE id = $2
  ", params = list(password_hash, user$id))
  
  # Invalidate all sessions
  safe_execute(pool, "
    UPDATE sessions SET is_active = FALSE WHERE user_id = $1
  ", params = list(user$id))
  
  create_audit_log(pool, "password_change",
                   user_id = user$id,
                   tenant_id = user$tenant_id,
                   metadata = list(via_reset = TRUE))
  
  log_app_info("Password reset completed", user_id = user$id)
  
  list(success = TRUE, message = "Password has been reset. Please log in with your new password.")
}

#' Get all users for a tenant
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @return Data frame of users
get_tenant_users <- function(pool, tenant_id) {
  safe_query(pool, "
    SELECT 
      id, email, first_name, last_name, role, status,
      last_login_at, created_at
    FROM users
    WHERE tenant_id = $1
    ORDER BY created_at DESC
  ", params = list(tenant_id))
}

#' Create a new user
#' @param pool Database pool
#' @param tenant_id Tenant ID
#' @param email User email
#' @param password Initial password
#' @param first_name First name
#' @param last_name Last name
#' @param role User role
#' @param created_by ID of user creating this user
#' @return List with success status and user ID
create_user <- function(pool, tenant_id, email, password, first_name, last_name, 
                        role = "viewer", created_by = NULL) {
  # Check if email already exists
  existing <- safe_query(pool, "
    SELECT id FROM users WHERE LOWER(email) = LOWER($1)
  ", params = list(email))
  
  if (!is.null(existing) && nrow(existing) > 0) {
    return(list(success = FALSE, error = "Email already registered"))
  }
  
  password_hash <- hash_password(password)
  
  result <- safe_query(pool, "
    INSERT INTO users (tenant_id, email, password_hash, first_name, last_name, role, status)
    VALUES ($1, $2, $3, $4, $5, $6, 'active')
    RETURNING id
  ", params = list(tenant_id, email, password_hash, first_name, last_name, role))
  
  if (!is.null(result) && nrow(result) > 0) {
    create_audit_log(pool, "user_create",
                     user_id = created_by,
                     tenant_id = tenant_id,
                     entity_type = "user",
                     entity_id = result$id,
                     new_values = list(email = email, role = role))
    
    log_app_info("User created", user_id = result$id, email = email)
    list(success = TRUE, user_id = result$id)
  } else {
    list(success = FALSE, error = "Failed to create user")
  }
}

#' Update user role
#' @param pool Database pool
#' @param user_id User ID to update
#' @param new_role New role
#' @param updated_by ID of user making the change
#' @param tenant_id Tenant ID for audit
update_user_role <- function(pool, user_id, new_role, updated_by, tenant_id) {
  # Get current role
  current <- safe_query(pool, "SELECT role FROM users WHERE id = $1", params = list(user_id))
  
  if (is.null(current) || nrow(current) == 0) {
    return(list(success = FALSE, error = "User not found"))
  }
  
  old_role <- current$role[1]
  
  result <- safe_execute(pool, "
    UPDATE users SET role = $1 WHERE id = $2
  ", params = list(new_role, user_id))
  
  if (result > 0) {
    create_audit_log(pool, "role_change",
                     user_id = updated_by,
                     tenant_id = tenant_id,
                     entity_type = "user",
                     entity_id = user_id,
                     old_values = list(role = old_role),
                     new_values = list(role = new_role))
    
    list(success = TRUE)
  } else {
    list(success = FALSE, error = "Failed to update role")
  }
}
