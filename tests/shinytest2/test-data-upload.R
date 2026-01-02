# SignalOps End-to-End Test - Data Upload Flow
# Tests the upload -> validate -> commit flow

library(shinytest2)

test_that("Data upload and validation works", {
  skip_if_not_installed("shinytest2")
  
  # Create test CSV file
  test_data <- data.frame(
    metric_date = c("2024-01-01", "2024-01-02", "2024-01-03"),
    metric_name = c("revenue", "revenue", "revenue"),
    metric_value = c(1000, 1500, 1200),
    team = c("Sales", "Sales", "Sales"),
    region = c("North America", "North America", "North America")
  )
  
  temp_file <- tempfile(fileext = ".csv")
  write.csv(test_data, temp_file, row.names = FALSE)
  
  # Start app and login
  app <- AppDriver$new(
    app_dir = "../../app",
    name = "upload-test",
    seed = 12345,
    height = 800,
    width = 1200
  )
  
  app$wait_for_idle()
  
  # Login first
  app$set_inputs(
    `login-email` = "analyst@signalops.io",
    `login-password` = "admin123"
  )
  app$click("login-login_btn")
  app$wait_for_idle(timeout = 5000)
  
  # Navigate to Data Quality
  app$click("nav-nav_quality")
  app$wait_for_idle()
  
  # Verify on quality page
  expect_true(app$get_text(".page-header h1") == "Data Quality")
  
  # Upload file
  app$upload_file(`nav-quality-file_upload` = temp_file)
  app$wait_for_idle(timeout = 3000)
  
  # Verify preview is shown
  preview_text <- app$get_text(".upload-preview")
  expect_true(grepl("revenue", preview_text))
  
  # Click validate
  app$click("nav-quality-validate_btn")
  app$wait_for_idle(timeout = 10000)
  
  # Verify validation results
  validation_text <- app$get_text(".validation-summary")
  expect_true(grepl("Valid", validation_text))
  
  # Clean up
  unlink(temp_file)
  app$stop()
})

test_that("Invalid data shows validation errors", {
  skip_if_not_installed("shinytest2")
  
  # Create test CSV with invalid data
  test_data <- data.frame(
    metric_date = c("2024-01-01", "invalid-date", "2024-01-03"),
    metric_name = c("revenue", "", "revenue"),
    metric_value = c(1000, "not-a-number", 1200)
  )
  
  temp_file <- tempfile(fileext = ".csv")
  write.csv(test_data, temp_file, row.names = FALSE)
  
  app <- AppDriver$new(
    app_dir = "../../app",
    name = "validation-error-test",
    seed = 12345
  )
  
  app$wait_for_idle()
  
  # Login
  app$set_inputs(
    `login-email` = "analyst@signalops.io",
    `login-password` = "admin123"
  )
  app$click("login-login_btn")
  app$wait_for_idle(timeout = 5000)
  
  # Navigate to Data Quality
  app$click("nav-nav_quality")
  app$wait_for_idle()
  
  # Upload invalid file
  app$upload_file(`nav-quality-file_upload` = temp_file)
  app$wait_for_idle(timeout = 3000)
  
  # Validate
  app$click("nav-quality-validate_btn")
  app$wait_for_idle(timeout = 10000)
  
  # Verify errors are shown
  validation_text <- app$get_text(".validation-summary")
  expect_true(grepl("Invalid", validation_text) || grepl("Error", validation_text))
  
  # Clean up
  unlink(temp_file)
  app$stop()
})
