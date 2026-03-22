# ============================================================
# R/effectsize.R — Effect size computation engine
# ============================================================
# NO Shiny dependencies. Pure R functions tested with testthat.
# Phase 8 full implementation.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Null-coalescing operator: returns `a` if non-NULL, else `b`
# Works for scalars and vectors alike.
`%||%` <- function(a, b) {
  if (!is.null(a)) a else b
}

# Safely extract a numeric scalar from a list; returns NULL if absent/NA/non-numeric
get_num <- function(lst, key) {
  v <- lst[[key]]
  if (is.null(v) || (length(v) == 1 && is.na(v))) return(NULL)
  v <- suppressWarnings(as.numeric(v))
  if (length(v) == 0 || is.na(v)) return(NULL)
  v
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Compute effect size from reviewer-entered statistics
#'
#' @param input_list  Named list of field values from the review UI.
#'   Must contain `study_design` (one of "control_treatment", "correlation",
#'   "regression", "interaction", "time_trend").
#'   For interaction: also `interaction_pathway` ("A" or "B").
#'   For Pathway B: also `group_a` and `group_b` (named lists with their own
#'   `study_design` and relevant fields).
#' @return Named list: r, z, var_z, effect_status, effect_warnings
compute_effect_size <- function(input_list) {
  design <- input_list$study_design
  # time_trend uses the same computation as regression
  if (!is.null(design) && design == "time_trend") design <- "regression"

  if (is.null(design)) {
    return(list(
      r = NULL, z = NULL, var_z = NULL,
      effect_status   = "insufficient_data",
      effect_warnings = character(0)
    ))
  }

  res <- switch(design,
    control_treatment = es_control_treatment(input_list),
    correlation       = es_correlation(input_list),
    regression        = es_regression(input_list),
    interaction = {
      pathway <- input_list$interaction_pathway %||% "A"
      if (pathway == "B") {
        es_interaction_b(input_list$group_a, input_list$group_b)
      } else {
        es_interaction_a(input_list)
      }
    },
    # Unknown design
    list(r = NULL, n = NULL, se_r = NULL,
         status = "insufficient_data", warnings = character(0))
  )

  r        <- res$r
  warnings <- res$warnings %||% character(0)
  effect_type <- res$effect_type %||% "zero_order"

  # Pathway B returns pre-computed z / var_z; use them directly
  if (!is.null(res$z)) {
    z     <- res$z
    var_z <- res$var_z
  } else if (!is.null(r) && !is.na(r)) {
    # Determine effective sample size for Fisher Z variance
    n <- res$n %||% NULL
    if (is.null(n) && !is.null(get_num(input_list, "n_control")) &&
        !is.null(get_num(input_list, "n_treatment"))) {
      n <- get_num(input_list, "n_control") + get_num(input_list, "n_treatment")
    }
    se_r <- res$se_r %||% NULL
    fz   <- fisher_z(r, n = n, se_r = se_r)
    z     <- fz$z
    var_z <- fz$var_z
  } else {
    z     <- NULL
    var_z <- NULL
  }

  status <- res$status %||% "insufficient_data"
  if (!is.null(r) && !is.na(r) && status == "insufficient_data") {
    status <- "calculated"
  }

  list(
    r               = r,
    z               = z,
    var_z           = var_z,
    effect_status   = status,
    effect_warnings = warnings,
    effect_type     = effect_type
  )
}

# ---------------------------------------------------------------------------
# Design-specific helpers
# Each returns: list(r, n, se_r, status, warnings)
# Pathway B additionally returns: list(r, z, var_z, n, se_r, status, warnings)
# ---------------------------------------------------------------------------

#' Control / Treatment design
#' Pathway: Hedges g (with SE/CI/IQR/SD conversion) → r;
#'          fallback via t-stat or F-stat.
es_control_treatment <- function(input) {
  warnings <- character(0)
  status   <- "calculated"

  m1       <- get_num(input, "mean_control")
  m2       <- get_num(input, "mean_treatment")
  n1       <- get_num(input, "n_control")
  n2       <- get_num(input, "n_treatment")
  var_type <- input$var_statistic_type
  var_ctrl <- get_num(input, "var_value_control")
  var_trt  <- get_num(input, "var_value_treatment")
  t_stat   <- get_num(input, "t_stat")
  f_stat   <- get_num(input, "F_stat")
  df       <- get_num(input, "df")

  n_total <- if (!is.null(n1) && !is.null(n2)) n1 + n2 else NULL

  # -- Primary path: means + variability statistic --
  if (!is.null(m1) && !is.null(m2) &&
      !is.null(n1) && !is.null(n2) &&
      !is.null(var_type) &&
      !is.null(var_ctrl) && !is.null(var_trt)) {

    cv1  <- convert_var_to_sd(var_ctrl, var_type, n1)
    cv2  <- convert_var_to_sd(var_trt,  var_type, n2)
    sd1  <- cv1$sd
    sd2  <- cv2$sd
    warnings <- c(warnings, cv1$warnings, cv2$warnings)

    if (!is.null(var_type) && var_type == "IQR") status <- "iqr_sd_used"

    if (!is.na(sd1) && !is.na(sd2) && sd1 > 0 && sd2 > 0) {
      df_pool <- n1 + n2 - 2
      sd_pool <- sqrt(((n1 - 1) * sd1^2 + (n2 - 1) * sd2^2) / df_pool)
      g       <- (m2 - m1) / sd_pool
      J       <- 1 - (3 / (4 * df_pool - 1))   # Hedges small-sample correction
      g_c     <- g * J
      # Convert Hedges g to Pearson r
      r <- g_c / sqrt(g_c^2 + (n1 + n2)^2 / (n1 * n2))
      return(list(r = r, n = n_total, se_r = NULL,
                  status = status, warnings = warnings))
    }
  }

  # -- Small SD approximation (explicit opt-in) --
  if (!is.null(m1) && !is.null(m2) &&
      !is.null(n1) && !is.null(n2) &&
      isTRUE(input$use_small_sd_approx)) {
    sd1 <- 0.01 * abs(m1)
    sd2 <- 0.01 * abs(m2)
    # Protect against zero means
    if (sd1 == 0) sd1 <- 0.01 * abs(m2)
    if (sd2 == 0) sd2 <- 0.01 * abs(m1)
    if (!is.na(sd1) && !is.na(sd2) && sd1 > 0 && sd2 > 0) {
      df_pool <- n1 + n2 - 2
      sd_pool <- sqrt(((n1 - 1) * sd1^2 + (n2 - 1) * sd2^2) / df_pool)
      g       <- (m2 - m1) / sd_pool
      J       <- 1 - (3 / (4 * df_pool - 1))
      g_c     <- g * J
      r <- g_c / sqrt(g_c^2 + (n1 + n2)^2 / (n1 * n2))
      return(list(r = r, n = n_total, se_r = NULL,
                  status   = "small_sd_used",
                  warnings = c(warnings, "Small SD approximation used (SD = 0.01 \u00d7 mean)")))
    }
  }

  # -- Fallback: t-statistic --
  if (!is.null(t_stat) && !is.null(df)) {
    r <- t_stat / sqrt(t_stat^2 + df)
    # If df is provided but n1/n2 were not, infer n_total from df
    # For independent samples t-test: df = n_total - 2, so n_total = df + 2
    effective_n <- if (is.null(n_total) && df > 0) df + 2 else n_total
    return(list(r = r, n = effective_n, se_r = NULL,
                status = "calculated", warnings = warnings))
  }

  # -- Fallback: F-statistic (single df numerator; convert to t) --
  if (!is.null(f_stat) && !is.null(df)) {
    t_eq <- sqrt(abs(f_stat)) * sign(f_stat)
    r    <- t_eq / sqrt(t_eq^2 + df)
    # If df is provided but n1/n2 were not, infer n_total from df
    effective_n <- if (is.null(n_total) && df > 0) df + 2 else n_total
    return(list(r = r, n = effective_n, se_r = NULL,
                status = "calculated", warnings = warnings))
  }

  list(r = NULL, n = n_total, se_r = NULL,
       status = "insufficient_data", warnings = warnings)
}

#' Correlation design
#' Pathway: direct r → covariance path → t-stat path.
es_correlation <- function(input) {
  warnings <- character(0)

  r_rep  <- get_num(input, "r_reported")
  cov_xy <- get_num(input, "covariance_XY")
  sd_x   <- get_num(input, "sd_X")
  sd_y   <- get_num(input, "sd_Y")
  t_stat <- get_num(input, "t_stat")
  df     <- get_num(input, "df")
  n      <- get_num(input, "n")
  se_r   <- get_num(input, "se_r")

  if (!is.null(r_rep)) {
    return(list(r = r_rep, n = n, se_r = se_r,
                status = "calculated", warnings = warnings))
  }

  if (!is.null(cov_xy) && !is.null(sd_x) && !is.null(sd_y) &&
      sd_x > 0 && sd_y > 0) {
    r <- cov_xy / (sd_x * sd_y)
    return(list(r = r, n = n, se_r = se_r,
                status = "calculated", warnings = warnings))
  }

  if (!is.null(t_stat) && !is.null(df)) {
    r <- t_stat / sqrt(t_stat^2 + df)
    return(list(r = r, n = n, se_r = se_r,
                status = "calculated", warnings = warnings))
  }

  list(r = NULL, n = n, se_r = se_r,
       status = "insufficient_data", warnings = warnings)
}

#' Regression (and time trend) design
#' Pathways vary by simple vs multiple regression:
#'
#' Simple regression (multiple_predictors = FALSE):
#'   1. Standardised beta: r = beta
#'   2. Unstandardised beta + SDs: r = beta * (sd_X / sd_Y)
#'   3. t-stat + df: r = t / sqrt(t^2 + df)
#'   4. beta + SE -> t -> r (df = N - 2)
#'   5. beta + p-value + N -> recover t -> r (df = N - 2)
#'
#' Multiple regression (multiple_predictors = TRUE):
#'   1. t-stat + df: r_partial = t / sqrt(t^2 + df)
#'   2. beta + SE -> t -> r_partial (df = N - k - 1)
#'   3. beta + p + N + k -> recover t -> r_partial
#'   4. Unstandardised beta + SDs: approximate r_partial
#'   ✗ Standardised beta alone: cannot convert
es_regression <- function(input) {
  warnings <- character(0)

  beta      <- get_num(input, "beta")
  beta_type <- input$beta_type %||% "unstandardized"
  n         <- get_num(input, "n")
  t_stat    <- get_num(input, "t_stat")
  df        <- get_num(input, "df")
  sd_x      <- get_num(input, "sd_X")
  sd_y      <- get_num(input, "sd_Y")
  se_beta   <- get_num(input, "se_beta")
  p_value   <- get_num(input, "p_value")
  multi     <- isTRUE(input$multiple_predictors)
  k         <- get_num(input, "n_predictors")  # number of predictors

  # Determine effect type

  effect_type <- if (multi) "partial" else "zero_order"
  if (multi) warnings <- c(warnings, "Partial r from multiple predictor model")

  # ---- Simple regression pathways ----
  if (!multi) {

    # Pathway 1: Standardised beta -> r = beta
    if (!is.null(beta) && beta_type == "standardized") {
      return(list(r = beta, n = n, se_r = NULL,
                  status = "calculated", warnings = warnings,
                  effect_type = effect_type))
    }

    # Pathway 2: Unstandardised beta + SDs -> r = beta * (sd_X / sd_Y)
    if (!is.null(beta) && !is.null(sd_x) && !is.null(sd_y) && sd_y > 0) {
      r <- beta * (sd_x / sd_y)
      return(list(r = r, n = n, se_r = NULL,
                  status = "calculated", warnings = warnings,
                  effect_type = effect_type))
    }

    # Pathway 5 (prioritised): t-stat + df -> r
    if (!is.null(t_stat) && !is.null(df)) {
      r <- t_stat / sqrt(t_stat^2 + df)
      return(list(r = r, n = n, se_r = NULL,
                  status = "calculated", warnings = warnings,
                  effect_type = effect_type))
    }

    # Pathway 3: beta + SE -> derive t -> r
    if (!is.null(beta) && !is.null(se_beta) && se_beta != 0) {
      t_derived <- beta / se_beta
      df_val <- df %||% (if (!is.null(n)) n - 2 else NULL)
      if (!is.null(df_val) && df_val > 0) {
        r <- t_derived / sqrt(t_derived^2 + df_val)
        warnings <- c(warnings, "t-statistic derived from \u03b2 / SE(\u03b2)")
        return(list(r = r, n = n, se_r = NULL,
                    status = "calculated", warnings = warnings,
                    effect_type = effect_type))
      }
    }

    # Pathway 4: beta + p-value + N -> recover t -> r
    if (!is.null(beta) && !is.null(p_value) && !is.null(n) && p_value > 0 && p_value < 1) {
      df_val <- df %||% (n - 2)
      if (df_val > 0) {
        t_recovered <- stats::qt(1 - p_value / 2, df_val)
        t_recovered <- sign(beta) * abs(t_recovered)
        r <- t_recovered / sqrt(t_recovered^2 + df_val)
        warnings <- c(warnings, "t-statistic recovered from p-value")
        return(list(r = r, n = n, se_r = NULL,
                    status = "calculated", warnings = warnings,
                    effect_type = effect_type))
      }
    }

  } else {
    # ---- Multiple regression pathways ----

    # Pathway 1: t-stat + df -> r_partial
    if (!is.null(t_stat) && !is.null(df)) {
      r <- t_stat / sqrt(t_stat^2 + df)
      return(list(r = r, n = n, se_r = NULL,
                  status = "calculated", warnings = warnings,
                  effect_type = effect_type))
    }

    # Pathway 2: beta + SE -> derive t -> r_partial
    if (!is.null(beta) && !is.null(se_beta) && se_beta != 0) {
      t_derived <- beta / se_beta
      # df: use reported df, else derive from N - k - 1
      df_val <- df
      if (is.null(df_val) && !is.null(n) && !is.null(k)) {
        df_val <- n - k - 1
      }
      if (!is.null(df_val) && df_val > 0) {
        r <- t_derived / sqrt(t_derived^2 + df_val)
        warnings <- c(warnings, "t-statistic derived from \u03b2 / SE(\u03b2)")
        return(list(r = r, n = n, se_r = NULL,
                    status = "calculated", warnings = warnings,
                    effect_type = effect_type))
      }
    }

    # Pathway 3: beta + p-value + N + k -> recover t -> r_partial
    if (!is.null(beta) && !is.null(p_value) && p_value > 0 && p_value < 1) {
      df_val <- df
      if (is.null(df_val) && !is.null(n) && !is.null(k)) {
        df_val <- n - k - 1
      }
      if (!is.null(df_val) && df_val > 0) {
        t_recovered <- stats::qt(1 - p_value / 2, df_val)
        t_recovered <- sign(beta) * abs(t_recovered)
        r <- t_recovered / sqrt(t_recovered^2 + df_val)
        warnings <- c(warnings, "t-statistic recovered from p-value")
        return(list(r = r, n = n, se_r = NULL,
                    status = "calculated", warnings = warnings,
                    effect_type = effect_type))
      }
    }

    # Pathway 4: Unstandardised beta + SDs (approximation)
    if (!is.null(beta) && beta_type != "standardized" &&
        !is.null(sd_x) && !is.null(sd_y) && sd_y > 0) {
      r <- beta * (sd_x / sd_y)
      warnings <- c(warnings,
        "Partial r approximated from \u03b2 \u00d7 (SD_X / SD_Y) in multiple regression; interpret with caution")
      return(list(r = r, n = n, se_r = NULL,
                  status = "calculated", warnings = warnings,
                  effect_type = effect_type))
    }

    # Cannot convert standardised beta from multiple regression
    if (!is.null(beta) && beta_type == "standardized") {
      warnings <- c(warnings,
        "Standardised \u03b2 from multiple regression cannot be directly converted to r; provide t-stat, SE, or p-value instead")
      return(list(r = NULL, n = n, se_r = NULL,
                  status = "insufficient_data", warnings = warnings,
                  effect_type = effect_type))
    }
  }

  list(r = NULL, n = n, se_r = NULL,
       status = "insufficient_data", warnings = warnings,
       effect_type = effect_type)
}

#' Interaction Pathway A: explicit interaction term
es_interaction_a <- function(input) {
  warnings <- character(0)

  t_stat           <- get_num(input, "t_stat")
  df               <- get_num(input, "df")
  n                <- get_num(input, "n")
  interaction_term <- get_num(input, "interaction_term")
  se_interaction   <- get_num(input, "se_interaction")

  # Compute t from interaction_term / se_interaction if not provided directly
  if (is.null(t_stat) && !is.null(interaction_term) && !is.null(se_interaction) &&
      se_interaction != 0) {
    t_stat <- interaction_term / se_interaction
    warnings <- c(warnings, "t-statistic derived from interaction term / SE")
  }

  if (!is.null(t_stat) && !is.null(df)) {
    r <- t_stat / sqrt(t_stat^2 + df)
    return(list(r = r, n = n, se_r = NULL,
                status = "calculated", warnings = warnings))
  }

  list(r = NULL, n = n, se_r = NULL,
       status = "insufficient_data", warnings = warnings)
}

#' Interaction Pathway B: difference-in-differences
#' @param input_a Named list for Group A (must include `study_design` and fields)
#' @param input_b Named list for Group B
es_interaction_b <- function(input_a, input_b) {
  warnings <- character(0)

  if (is.null(input_a) || is.null(input_b)) {
    return(list(r = NULL, z = NULL, var_z = NULL, n = NULL, se_r = NULL,
                status = "insufficient_data", warnings = warnings))
  }

  res_a <- compute_effect_size(input_a)
  res_b <- compute_effect_size(input_b)

  r_a <- res_a$r
  r_b <- res_b$r
  z_a <- res_a$z
  z_b <- res_b$z

  if (is.null(r_a) || is.null(r_b) || is.na(r_a) || is.na(r_b)) {
    return(list(r = NULL, z = NULL, var_z = NULL, n = NULL, se_r = NULL,
                status = "insufficient_data",
                warnings = c(warnings,
                             res_a$effect_warnings,
                             res_b$effect_warnings)))
  }

  # Use pre-computed Fisher Z values from each sub-effect
  if (is.null(z_a)) z_a <- atanh(r_a)
  if (is.null(z_b)) z_b <- atanh(r_b)

  z_diff    <- z_a - z_b
  r_diff    <- tanh(z_diff)

  vz_a      <- res_a$var_z
  vz_b      <- res_b$var_z
  var_z_diff <- if (!is.null(vz_a) && !is.null(vz_b)) vz_a + vz_b else NULL

  list(r = r_diff, z = z_diff, var_z = var_z_diff, n = NULL, se_r = NULL,
       status   = "calculated_relative",
       warnings = c(warnings, res_a$effect_warnings, res_b$effect_warnings))
}

# ---------------------------------------------------------------------------
# Shared utilities
# ---------------------------------------------------------------------------

#' Convert a variability statistic to SD
#'
#' @param var_value  Numeric value as reported (SD / SE / CI half-width / IQR)
#' @param var_type   One of "SD", "SE", "95% CI", "IQR"
#' @param n          Sample size (required for SE → SD conversion)
#' @return           List: sd (numeric, NA if cannot convert), warnings (character)
convert_var_to_sd <- function(var_value, var_type, n = NULL) {
  warnings <- character(0)

  if (is.null(var_value) || is.na(var_value) || is.null(var_type)) {
    return(list(sd = NA_real_, warnings = warnings))
  }

  sd <- switch(var_type,
    "SD"     = var_value,
    "SE"     = {
      if (!is.null(n) && !is.na(n) && n > 0) {
        var_value * sqrt(n)
      } else {
        NA_real_
      }
    },
    "95% CI" = var_value / 1.96,
    "IQR"    = {
      warnings <- c(warnings, "IQR used for SD")
      var_value / 1.35
    },
    NA_real_
  )

  if (!is.na(sd) && sd <= 0) sd <- NA_real_

  list(sd = sd, warnings = warnings)
}

#' Apply Fisher Z transformation
#'
#' @param r    Pearson r (numeric scalar)
#' @param n    Sample size; used to compute var_z = 1/(n-3)
#' @param se_r SE of r; fallback for var_z when n is unavailable
#' @return     List: z (Fisher Z), var_z (variance of Z; NULL if not computable)
fisher_z <- function(r, n = NULL, se_r = NULL) {
  if (is.null(r) || is.na(r)) return(list(z = NULL, var_z = NULL))

  z     <- atanh(r)
  var_z <- if (!is.null(n) && !is.na(n) && n > 3) {
             1 / (n - 3)
           } else if (!is.null(se_r) && !is.na(se_r)) {
             (se_r / (1 - r^2))^2
           } else {
             NULL
           }

  list(z = z, var_z = var_z)
}
