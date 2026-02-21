# ============================================================
# tests/test_export.R — Unit tests for export functions
# ============================================================
# Run with: testthat::test_file("tests/test_export.R")
# Full tests implemented in Phase 10.

library(testthat)
source("R/export.R")

# ---- Smoke tests (stubs pass trivially) ---------------------
test_that("build_full_export returns data frame", {
  result <- build_full_export("fake-project-id")
  expect_true(is.data.frame(result))
})

test_that("build_meta_export returns data frame", {
  result <- build_meta_export("fake-project-id")
  expect_true(is.data.frame(result))
})

# ---- Phase 10: column naming tests --------------------------
# test_that("meta export has yi and vi columns", { ... })
# test_that("unnest_labels expands group instances into rows", { ... })
