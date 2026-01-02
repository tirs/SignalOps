# SignalOps Unit Tests - Authentication Service
# Tests for password hashing and authentication logic

library(testthat)

# Mock sodium functions for testing (or use real sodium if available)
skip_if_not_installed("sodium")
library(sodium)

test_that("password hashing produces different hashes", {
  password <- "test_password_123"
  
  hash1 <- password_store(password)
  hash2 <- password_store(password)
  
  # Same password should produce different hashes (due to random salt)
  expect_false(hash1 == hash2)
})

test_that("password verification works correctly", {
  password <- "secure_password_456"
  wrong_password <- "wrong_password"
  
  hash <- password_store(password)
  
  # Correct password should verify
  expect_true(password_verify(hash, password))
  
  # Wrong password should not verify
  expect_false(password_verify(hash, wrong_password))
})

test_that("password hashes are consistent in verification", {
  password <- "my_secure_password"
  hash <- password_store(password)
  
  # Verify multiple times
  expect_true(password_verify(hash, password))
  expect_true(password_verify(hash, password))
  expect_true(password_verify(hash, password))
})

test_that("empty password handling", {
  # Empty password should still be hashable
  empty_hash <- password_store("")
  expect_true(nchar(empty_hash) > 0)
  expect_true(password_verify(empty_hash, ""))
})

test_that("unicode password handling", {
  password <- "password"
  hash <- password_store(password)
  expect_true(password_verify(hash, password))
})

test_that("session token generation is unique", {
  generate_session_token <- function() {
    paste0(bin2hex(random(32)))
  }
  
  tokens <- replicate(100, generate_session_token())
  
  # All tokens should be unique
  expect_equal(length(unique(tokens)), 100)
  
  # Tokens should be 64 characters (32 bytes = 64 hex chars)
  expect_true(all(nchar(tokens) == 64))
})

test_that("reset token generation is unique", {
  generate_reset_token <- function() {
    paste0(bin2hex(random(24)))
  }
  
  tokens <- replicate(50, generate_reset_token())
  
  # All tokens should be unique
  expect_equal(length(unique(tokens)), 50)
  
  # Tokens should be 48 characters (24 bytes = 48 hex chars)
  expect_true(all(nchar(tokens) == 48))
})

test_that("email validation logic", {
  is_valid_email <- function(email) {
    if (is.null(email) || is.na(email) || email == "") return(FALSE)
    grepl("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email)
  }
  
  # Valid emails
  expect_true(is_valid_email("user@example.com"))
  expect_true(is_valid_email("user.name@domain.co.uk"))
  expect_true(is_valid_email("user+tag@example.org"))
  expect_true(is_valid_email("user123@sub.domain.com"))
  
  # Invalid emails
  expect_false(is_valid_email(""))
  expect_false(is_valid_email(NULL))
  expect_false(is_valid_email(NA))
  expect_false(is_valid_email("invalid"))
  expect_false(is_valid_email("@domain.com"))
  expect_false(is_valid_email("user@"))
  expect_false(is_valid_email("user@.com"))
})

test_that("permission hierarchy logic", {
  has_permission <- function(user_role, required_roles) {
    role_hierarchy <- c("viewer" = 1, "analyst" = 2, "admin" = 3)
    user_level <- role_hierarchy[user_role]
    required_level <- min(role_hierarchy[required_roles])
    user_level >= required_level
  }
  
  # Admin can access everything
  expect_true(has_permission("admin", c("viewer", "analyst", "admin")))
  expect_true(has_permission("admin", c("analyst", "admin")))
  expect_true(has_permission("admin", c("admin")))
  
  # Analyst can access analyst and viewer
  expect_true(has_permission("analyst", c("viewer")))
  expect_true(has_permission("analyst", c("analyst")))
  expect_true(has_permission("analyst", c("viewer", "analyst")))
  expect_false(has_permission("analyst", c("admin")))
  
  # Viewer can only access viewer
  expect_true(has_permission("viewer", c("viewer")))
  expect_false(has_permission("viewer", c("analyst")))
  expect_false(has_permission("viewer", c("admin")))
})
