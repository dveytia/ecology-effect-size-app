# ============================================================
# tests/test_effectsize.R — Unit tests for effect size engine
# ============================================================
# Run with: testthat::test_file("tests/test_effectsize.R")
# All 11 tests from spec Section 8.11 plus a smoke test.

library(testthat)
# resolve path relative to tests/ directory when run via test_file()
source(file.path(dirname(getwd()), "R", "effectsize.R"), chdir = FALSE)

# ============================================================
# Smoke test (kept from stub phase)
# ============================================================
test_that("stub-compatible: empty input returns insufficient_data", {
  result <- compute_effect_size(list())
  expect_equal(result$effect_status, "insufficient_data")
  expect_null(result$r)
})

# ============================================================
# Test 1 — t-statistic path (correlation design)
# t=2.5, df=30, n=32  →  r = 0.4152, var_z ≈ 1/29
# ============================================================
test_that("t-stat path: t=2.5, df=30 -> r=0.4152", {
  result <- compute_effect_size(list(
    study_design = "correlation",
    t_stat = 2.5, df = 30, n = 32
  ))
  expect_equal(round(result$r, 4), 0.4152)
  expect_equal(result$effect_status, "calculated")
  expect_equal(round(result$var_z, 4), round(1 / 29, 4))
})

# ============================================================
# Test 2 — Means + SD path (control/treatment, Hedges g)
# m1=5, m2=3, sd1=2, sd2=2, n1=20, n2=20  →  |r| ≈ 0.44
# (exact value with Hedges J correction ≈ -0.4401)
# ============================================================
test_that("Means + SD path (Hedges g): r magnitude ~0.44", {
  result <- compute_effect_size(list(
    study_design         = "control_treatment",
    mean_control         = 5,
    mean_treatment       = 3,
    var_statistic_type   = "SD",
    var_value_control    = 2,
    var_value_treatment  = 2,
    n_control            = 20,
    n_treatment          = 20
  ))
  # Exact formula check
  sd_pool  <- sqrt(((19 * 4) + (19 * 4)) / 38)      # = 2
  g        <- (3 - 5) / sd_pool                       # = -1
  J        <- 1 - (3 / (4 * 38 - 1))
  g_c      <- g * J
  expected_r <- g_c / sqrt(g_c^2 + 40^2 / (20 * 20))

  expect_equal(round(result$r, 4), round(expected_r, 4))
  expect_equal(result$effect_status, "calculated")
  # Magnitude should be close to spec's ~0.4472 approximation
  expect_true(abs(abs(result$r) - 0.4472) < 0.02)
})

# ============================================================
# Test 3 — Correlation direct
# r=0.35, n=50  →  r=0.3500, var_z=0.0213
# ============================================================
test_that("Correlation direct: r=0.35, n=50 -> var_z=0.0213", {
  result <- compute_effect_size(list(
    study_design = "correlation",
    r_reported   = 0.35,
    n            = 50
  ))
  expect_equal(result$r, 0.35)
  expect_equal(result$effect_status, "calculated")
  expect_equal(round(result$var_z, 4), 0.0213)
})

# ============================================================
# Test 4 — Covariance path
# cov=0.6, sd_X=1.2, sd_Y=2.0  →  r=0.2500
# ============================================================
test_that("Covariance path: cov=0.6, sd_X=1.2, sd_Y=2.0 -> r=0.2500", {
  result <- compute_effect_size(list(
    study_design   = "correlation",
    covariance_XY  = 0.6,
    sd_X           = 1.2,
    sd_Y           = 2.0
  ))
  expect_equal(round(result$r, 4), 0.2500)
  expect_equal(result$effect_status, "calculated")
})

# ============================================================
# Test 5 — Regression: unstandardised beta + SDs (simple)
# beta=0.4, sd_X=1.5, sd_Y=2.0  →  r=0.3000 (zero-order)
# ============================================================
test_that("Regression beta + SDs: beta=0.4, sd_X=1.5, sd_Y=2.0 -> r=0.3000", {
  result <- compute_effect_size(list(
    study_design = "regression",
    beta         = 0.4,
    beta_type    = "unstandardized",
    sd_X         = 1.5,
    sd_Y         = 2.0
  ))
  expect_equal(round(result$r, 4), 0.3000)
  expect_equal(result$effect_status, "calculated")
  expect_equal(result$effect_type, "zero_order")
})

# ============================================================
# Test 5a — Regression: standardised beta (simple)
# beta=0.35, standardized  →  r=0.35 (zero-order)
# ============================================================
test_that("Std beta simple regression: r = beta directly", {
  result <- compute_effect_size(list(
    study_design = "regression",
    beta         = 0.35,
    beta_type    = "standardized",
    multiple_predictors = FALSE
  ))
  expect_equal(result$r, 0.35)
  expect_equal(result$effect_status, "calculated")
  expect_equal(result$effect_type, "zero_order")
})

# ============================================================
# Test 5b — Regression: beta + SE (simple, derive t)
# beta=1.5, se_beta=0.6, n=32  →  t=2.5, df=30, r≈0.4152
# ============================================================
test_that("Beta + SE simple regression: derive t -> r", {
  result <- compute_effect_size(list(
    study_design = "regression",
    beta         = 1.5,
    se_beta      = 0.6,
    n            = 32,
    beta_type    = "unstandardized",
    multiple_predictors = FALSE
  ))
  t_derived <- 1.5 / 0.6   # 2.5
  df_val    <- 32 - 2       # 30
  expected_r <- t_derived / sqrt(t_derived^2 + df_val)
  expect_equal(round(result$r, 4), round(expected_r, 4))
  expect_equal(result$effect_status, "calculated")
  expect_equal(result$effect_type, "zero_order")
  expect_true(any(grepl("derived from", result$effect_warnings)))
})

# ============================================================
# Test 5c — Regression: beta + p-value + N (simple)
# beta=1.5, p_value=0.019, n=32  →  recover t, r (zero-order)
# ============================================================
test_that("Beta + p + N simple regression: recover t -> r", {
  result <- compute_effect_size(list(
    study_design = "regression",
    beta         = 1.5,
    p_value      = 0.019,
    n            = 32,
    beta_type    = "unstandardized",
    multiple_predictors = FALSE
  ))
  df_val    <- 32 - 2
  t_recov   <- stats::qt(1 - 0.019 / 2, df_val)
  expected_r <- t_recov / sqrt(t_recov^2 + df_val)
  expect_equal(round(result$r, 4), round(expected_r, 4))
  expect_equal(result$effect_status, "calculated")
  expect_equal(result$effect_type, "zero_order")
  expect_true(any(grepl("recovered from p-value", result$effect_warnings)))
})

# ============================================================
# Test 5d — Regression: t + df (multiple) → partial r
# t=2.5, df=27, n=31, k=3  →  partial r
# ============================================================
test_that("Multiple regression: t + df -> partial r", {
  result <- compute_effect_size(list(
    study_design        = "regression",
    t_stat              = 2.5,
    df                  = 27,
    n                   = 31,
    n_predictors        = 3,
    multiple_predictors = TRUE
  ))
  expected_r <- 2.5 / sqrt(2.5^2 + 27)
  expect_equal(round(result$r, 4), round(expected_r, 4))
  expect_equal(result$effect_type, "partial")
  expect_true(any(grepl("Partial r", result$effect_warnings)))
})

# ============================================================
# Test 5e — Regression: standardised β (multiple, no t)
# Cannot convert → insufficient_data
# ============================================================
test_that("Std beta multiple regression: insufficient_data", {
  result <- compute_effect_size(list(
    study_design        = "regression",
    beta                = 0.35,
    beta_type           = "standardized",
    multiple_predictors = TRUE
  ))
  expect_equal(result$effect_status, "insufficient_data")
  expect_null(result$r)
  expect_equal(result$effect_type, "partial")
  expect_true(any(grepl("cannot be directly converted", result$effect_warnings)))
})

# ============================================================
# Test 6 — Interaction Pathway B (difference-in-differences)
# r_A=0.5, n_A=30; r_B=0.2, n_B=30
# z_diff = atanh(0.5) - atanh(0.2); var_z_diff = 1/27 + 1/27
# ============================================================
test_that("Interaction Pathway B: z_diff and var_z_diff correct", {
  result <- compute_effect_size(list(
    study_design         = "interaction",
    interaction_pathway  = "B",
    group_a = list(study_design = "correlation", r_reported = 0.5, n = 30),
    group_b = list(study_design = "correlation", r_reported = 0.2, n = 30)
  ))

  expected_z    <- atanh(0.5) - atanh(0.2)
  expected_varz <- 1 / 27 + 1 / 27

  expect_equal(round(result$z,     6), round(expected_z,    6))
  expect_equal(round(result$var_z, 6), round(expected_varz, 6))
  expect_equal(result$effect_status, "calculated_relative")
  expect_equal(round(result$r, 6), round(tanh(expected_z), 6))
})

# ============================================================
# Test 7 — SE to SD conversion
# se=0.5, n=25  →  SD=2.5
# ============================================================
test_that("SE to SD conversion: se=0.5, n=25 -> SD=2.5", {
  res <- convert_var_to_sd(0.5, "SE", n = 25)
  expect_equal(res$sd, 2.5)
  expect_length(res$warnings, 0)
})

# ============================================================
# Test 8 — 95% CI to SD conversion
# ci_half_width=1.96  →  SD=1.0
# ============================================================
test_that("95% CI to SD: ci_half_width=1.96 -> SD=1.0", {
  res <- convert_var_to_sd(1.96, "95% CI")
  expect_equal(res$sd, 1.0)
  expect_length(res$warnings, 0)
})

# ============================================================
# Test 9 — IQR to SD conversion + effect_status flag
# IQR=2.7  →  SD=2.0, effect_status=iqr_sd_used
# ============================================================
test_that("IQR to SD: IQR=2.7 -> SD=2.0 and iqr_sd_used flag", {
  # Test convert_var_to_sd directly
  res <- convert_var_to_sd(2.7, "IQR")
  expect_equal(res$sd, 2.0)
  expect_true("IQR used for SD" %in% res$warnings)

  # Test full pipeline sets correct effect_status
  result <- compute_effect_size(list(
    study_design         = "control_treatment",
    mean_control         = 10,
    mean_treatment       = 12,
    var_statistic_type   = "IQR",
    var_value_control    = 2.7,
    var_value_treatment  = 2.7,
    n_control            = 30,
    n_treatment          = 30
  ))
  expect_equal(result$effect_status, "iqr_sd_used")
  expect_false(is.null(result$r))
  expect_true(any(grepl("IQR", result$effect_warnings)))
})

# ============================================================
# Test 10 — Small SD approximation flag
# mean=100 (no SD, no test stats), use_small_sd_approx=TRUE
# →  effect_status=small_sd_used
# ============================================================
test_that("Small SD flag: means-only with approx -> small_sd_used", {
  result <- compute_effect_size(list(
    study_design         = "control_treatment",
    mean_control         = 100,
    mean_treatment       = 120,
    n_control            = 20,
    n_treatment          = 20,
    use_small_sd_approx  = TRUE
    # No var_statistic_type, no var values, no t/F stats
  ))
  expect_equal(result$effect_status, "small_sd_used")
  expect_false(is.null(result$r))
  expect_true(any(grepl("Small SD", result$effect_warnings)))
})

test_that("Small SD flag still works when both means are zero", {
  result <- compute_effect_size(list(
    study_design         = "control_treatment",
    mean_control         = 0,
    mean_treatment       = 0,
    n_control            = 20,
    n_treatment          = 20,
    use_small_sd_approx  = TRUE
  ))
  expect_equal(result$effect_status, "small_sd_used")
  expect_equal(result$r, 0)
  expect_true(any(grepl("absolute floor", result$effect_warnings)))
})

test_that("Small SD can replace only the invalid arm when one SD is zero", {
  result <- compute_effect_size(list(
    study_design         = "control_treatment",
    mean_control         = 0,
    mean_treatment       = 0.4967,
    var_statistic_type   = "SD",
    var_value_control    = 0,
    var_value_treatment  = 0.1369,
    n_control            = 3,
    n_treatment          = 3,
    use_small_sd_approx  = TRUE
  ))
  expect_equal(result$effect_status, "small_sd_used")
  expect_false(is.null(result$r))
  expect_true(any(grepl("control arm", result$effect_warnings)))
})

# ============================================================
# Test 11 — Insufficient data
# Only p_value=0.03 provided  →  r=NULL, effect_status=insufficient_data
# ============================================================
test_that("Insufficient data: p_value only -> insufficient_data", {
  result <- compute_effect_size(list(
    study_design = "control_treatment",
    p_value      = 0.03
  ))
  expect_equal(result$effect_status, "insufficient_data")
  expect_null(result$r)
  expect_null(result$z)
  expect_null(result$var_z)
})

# ============================================================
# Bonus — time_trend treated as regression
# ============================================================
test_that("time_trend routes to regression engine", {
  result <- compute_effect_size(list(
    study_design = "time_trend",
    t_stat       = 3.0,
    df           = 48,
    n            = 50
  ))
  expected_r <- 3.0 / sqrt(3.0^2 + 48)
  expect_equal(round(result$r, 4), round(expected_r, 4))
  expect_equal(result$effect_status, "calculated")
})

# ============================================================
# Bonus — infer N from df and k for multiple regression
# ============================================================
test_that("Multiple regression infers N from df and k", {
  result <- compute_effect_size(list(
    study_design        = "regression",
    multiple_predictors = TRUE,
    n_predictors        = 3,
    t_stat              = 2.2,
    df                  = 27
  ))
  # N should be inferred as df + k + 1 = 31, so var_z = 1/(31-3)
  expect_equal(round(result$var_z, 6), round(1 / 28, 6))
  expect_true(any(grepl("inferred", result$effect_warnings)))
})

# ============================================================
# Bonus — bounds check for invalid correlation values
# ============================================================
test_that("Out-of-bounds r throws clear error", {
  expect_error(
    compute_effect_size(list(
      study_design = "correlation",
      r_reported   = 1.2,
      n            = 40
    )),
    "out of bounds"
  )
})

