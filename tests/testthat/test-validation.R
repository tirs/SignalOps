# SignalOps Unit Tests - Validation Service
# Tests for data validation rules engine

library(testthat)

# Mock validate_value function for testing
validate_value <- function(value, rule) {
  rule_type <- rule$rule_type
  params <- if (is.character(rule$parameters)) {
    jsonlite::fromJSON(rule$parameters)
  } else {
    rule$parameters
  }
  
  is_empty <- is.null(value) || is.na(value) || 
    (is.character(value) && trimws(value) == "")
  
  result <- switch(rule_type,
    "required" = {
      if (is_empty) {
        list(is_valid = FALSE, message = paste(rule$column_name, "is required"))
      } else {
        list(is_valid = TRUE)
      }
    },
    
    "type_numeric" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else if (suppressWarnings(is.na(as.numeric(value)))) {
        list(is_valid = FALSE, message = paste(rule$column_name, "must be numeric"))
      } else {
        list(is_valid = TRUE)
      }
    },
    
    "range" = {
      if (is_empty) {
        list(is_valid = TRUE)
      } else {
        num <- suppressWarnings(as.numeric(value))
        if (is.na(num)) {
          list(is_valid = TRUE)
        } else {
          min_val <- params$min
          max_val <- params$max
          
          if (!is.null(min_val) && num < min_val) {
            list(is_valid = FALSE, message = paste(rule$column_name, "must be >=", min_val))
          } else if (!is.null(max_val) && num > max_val) {
            list(is_valid = FALSE, message = paste(rule$column_name, "must be <=", max_val))
          } else {
            list(is_valid = TRUE)
          }
        }
      }
    },
    
    list(is_valid = TRUE)
  )
  
  result$severity <- rule$severity %||% "error"
  result
}

`%||%` <- function(x, y) if (is.null(x)) y else x

test_that("required rule validates empty values", {
  rule <- list(
    rule_type = "required",
    column_name = "test_field",
    parameters = list(),
    severity = "error"
  )
  
  # Empty values should fail
  expect_false(validate_value(NULL, rule)$is_valid)
  expect_false(validate_value(NA, rule)$is_valid)
  expect_false(validate_value("", rule)$is_valid)
  expect_false(validate_value("   ", rule)$is_valid)
  
  # Non-empty values should pass
  expect_true(validate_value("test", rule)$is_valid)
  expect_true(validate_value(0, rule)$is_valid)
  expect_true(validate_value(123, rule)$is_valid)
})

test_that("type_numeric rule validates numeric values", {
  rule <- list(
    rule_type = "type_numeric",
    column_name = "amount",
    parameters = list(),
    severity = "error"
  )
  
  # Valid numeric values
  expect_true(validate_value(123, rule)$is_valid)
  expect_true(validate_value("456", rule)$is_valid)
  expect_true(validate_value(12.34, rule)$is_valid)
  expect_true(validate_value("-100", rule)$is_valid)
  expect_true(validate_value(0, rule)$is_valid)
  
  # Invalid non-numeric values
  expect_false(validate_value("abc", rule)$is_valid)
  expect_false(validate_value("12abc", rule)$is_valid)
  
  # Empty values pass (handled by required rule)
  expect_true(validate_value(NULL, rule)$is_valid)
  expect_true(validate_value("", rule)$is_valid)
})

test_that("range rule validates numeric ranges", {
  rule <- list(
    rule_type = "range",
    column_name = "value",
    parameters = list(min = 0, max = 100),
    severity = "error"
  )
  
  # Within range
  expect_true(validate_value(50, rule)$is_valid)
  expect_true(validate_value(0, rule)$is_valid)
  expect_true(validate_value(100, rule)$is_valid)
  
  # Outside range
  expect_false(validate_value(-1, rule)$is_valid)
  expect_false(validate_value(101, rule)$is_valid)
  
  # Empty values pass
  expect_true(validate_value(NULL, rule)$is_valid)
})

test_that("range rule with only min", {
  rule <- list(
    rule_type = "range",
    column_name = "value",
    parameters = list(min = 0),
    severity = "warning"
  )
  
  expect_true(validate_value(0, rule)$is_valid)
  expect_true(validate_value(1000, rule)$is_valid)
  expect_false(validate_value(-1, rule)$is_valid)
})

test_that("range rule with only max", {
  rule <- list(
    rule_type = "range",
    column_name = "value",
    parameters = list(max = 100),
    severity = "warning"
  )
  
  expect_true(validate_value(-100, rule)$is_valid)
  expect_true(validate_value(100, rule)$is_valid)
  expect_false(validate_value(101, rule)$is_valid)
})

test_that("validation result includes severity", {
  rule <- list(
    rule_type = "required",
    column_name = "field",
    parameters = list(),
    severity = "warning"
  )
  
  result <- validate_value(NULL, rule)
  expect_equal(result$severity, "warning")
})

test_that("unknown rule type passes validation", {
  rule <- list(
    rule_type = "unknown_type",
    column_name = "field",
    parameters = list(),
    severity = "error"
  )
  
  expect_true(validate_value("anything", rule)$is_valid)
})
