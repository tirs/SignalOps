# SignalOps End-to-End Test - Login Flow
# Tests the complete login -> dashboard flow

library(shinytest2)

test_that("Login flow works correctly", {
  # Skip if shinytest2 not available
  skip_if_not_installed("shinytest2")
  
  # Start app
  app <- AppDriver$new(
    app_dir = "../../app",
    name = "login-test",
    seed = 12345,
    height = 800,
    width = 1200
  )
  
  # Wait for login page to load
  app$wait_for_idle()
  
  # Verify login page is displayed
  expect_true(app$get_text(".login-header h1") == "SignalOps")
  
  # Enter credentials
  app$set_inputs(
    `login-email` = "admin@signalops.io",
    `login-password` = "admin123"
  )
  
  # Click login button
  app$click("login-login_btn")
  
  # Wait for navigation
  app$wait_for_idle(timeout = 5000)
  
  # Verify dashboard is displayed
  expect_true(app$get_text(".page-header h1") == "Dashboard Overview")
  
  # Verify user info is shown
  user_info <- app$get_text(".user-info .user-name")
  expect_true(nchar(user_info) > 0)
  
  # Clean up
  app$stop()
})

test_that("Invalid login shows error", {
  skip_if_not_installed("shinytest2")
  
  app <- AppDriver$new(
    app_dir = "../../app",
    name = "login-error-test",
    seed = 12345
  )
  
  app$wait_for_idle()
  
  # Enter invalid credentials
  app$set_inputs(
    `login-email` = "invalid@example.com",
    `login-password` = "wrongpassword"
  )
  
  app$click("login-login_btn")
  app$wait_for_idle(timeout = 3000)
  
  # Verify error message is displayed
  error_msg <- app$get_text(".alert-error")
  expect_true(nchar(error_msg) > 0)
  
  # Verify still on login page
  expect_true(app$get_text(".login-header h1") == "SignalOps")
  
  app$stop()
})
