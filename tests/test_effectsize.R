# ============================================================
# tests/test_effectsize.R — Unit tests for effect size engine
# ============================================================
# Run with: testthat::test_file("tests/test_effectsize.R")
# All tests implemented in Phase 8.

library(testthat)
source("R/effectsize.R")

# ---- Smoke test: stub returns insufficient_data -------------
test_that("stub returns insufficient_data", {
  result <- compute_effect_size(list())
  expect_equal(result$effect_status, "insufficient_data")
  expect_null(result$r)
})

# ---- Phase 8 tests (to be uncommmented/added in Phase 8) ----
# t-statistic path
# test_that("t-stat path: t=2.5, df=30 -> r=0.4152", {
#   result <- compute_effect_size(list(
#     study_design = "correlation",
#     t_stat = 2.5, df = 30, n = 32
#   ))
#   expect_equal(round(result$r, 4), 0.4152)
# })

# ... (remaining 10 test cases from spec Section 8.11)
