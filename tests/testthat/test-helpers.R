# SignalOps Unit Tests - Helper Functions
# Tests for utility functions in helpers.R

library(testthat)

# Source the helpers file (adjust path as needed)
# source("../../app/R/utils/helpers.R")

test_that("format_number handles various inputs", {
  expect_equal(format_number(1234567), "1,234,567")
  expect_equal(format_number(1234.567, digits = 2), "1,234.57")
  expect_equal(format_number(0), "0")
  expect_equal(format_number(NULL), "")
  expect_equal(format_number(NA), "")
})

test_that("format_percent handles various inputs", {
  expect_equal(format_percent(0.5), "50.0%")
  expect_equal(format_percent(0.123, digits = 2), "12.30%")
  expect_equal(format_percent(50, scale = FALSE), "50.0%")
  expect_equal(format_percent(NULL), "")
  expect_equal(format_percent(NA), "")
})

test_that("format_bytes converts correctly", {
  expect_equal(format_bytes(500), "500 B")
  expect_equal(format_bytes(1024), "1 KB")
  expect_equal(format_bytes(1048576), "1 MB")
  expect_equal(format_bytes(1073741824), "1 GB")
  expect_equal(format_bytes(NULL), "")
})

test_that("format_duration handles various durations", {
  expect_equal(format_duration(30), "30s")
  expect_equal(format_duration(90), "1m 30s")
  expect_equal(format_duration(3661), "1h 1m")
  expect_equal(format_duration(NULL), "")
})

test_that("is_valid_email validates correctly", {
  expect_true(is_valid_email("test@example.com"))
  expect_true(is_valid_email("user.name+tag@domain.co.uk"))
  expect_false(is_valid_email("invalid"))
  expect_false(is_valid_email("@domain.com"))
  expect_false(is_valid_email("user@"))
  expect_false(is_valid_email(""))
  expect_false(is_valid_email(NULL))
})

test_that("slugify creates valid slugs", {
  expect_equal(slugify("Hello World"), "hello-world")
  expect_equal(slugify("Test 123 ABC"), "test-123-abc")
  expect_equal(slugify("Multiple   Spaces"), "multiple-spaces")
  expect_equal(slugify("Special!@#Characters"), "specialcharacters")
  expect_equal(slugify(""), "")
  expect_equal(slugify(NULL), "")
})

test_that("truncate_text works correctly", {
  expect_equal(truncate_text("short", 10), "short")
  expect_equal(truncate_text("this is a longer text", 10), "this is...")
  expect_equal(truncate_text("test", 10, suffix = "---"), "test")
  expect_equal(truncate_text(NULL, 10), "")
})

test_that("calc_pct_change calculates correctly", {
  expect_equal(calc_pct_change(110, 100), 10)
  expect_equal(calc_pct_change(90, 100), -10)
  expect_equal(calc_pct_change(100, 100), 0)
  expect_true(is.na(calc_pct_change(100, 0)))
  expect_true(is.na(calc_pct_change(100, NULL)))
})

test_that("null coalescing operator works", {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  
  expect_equal(NULL %||% "default", "default")
  expect_equal("value" %||% "default", "value")
  expect_equal(0 %||% "default", 0)
  expect_equal("" %||% "default", "")
})

test_that("safe_json_parse handles various inputs", {
  expect_equal(safe_json_parse('{"a": 1}'), list(a = 1))
  expect_equal(safe_json_parse('invalid json', default = list()), list())
  expect_equal(safe_json_parse(NULL), list())
  expect_equal(safe_json_parse(""), list())
})

test_that("sanitize_string removes special characters", {
  expect_equal(sanitize_string("hello_world"), "hello_world")
  expect_equal(sanitize_string("test-123"), "test-123")
  expect_equal(sanitize_string("file.txt"), "file.txt")
  expect_equal(sanitize_string("no spaces!@#"), "nospaces")
  expect_equal(sanitize_string(NULL), "")
})
