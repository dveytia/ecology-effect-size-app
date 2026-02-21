# ============================================================
# R/effectsize.R — Effect size computation engine
# ============================================================
# NO Shiny dependencies. Pure R functions tested with testthat.
# Implemented fully in Phase 8.
# Phase 1 stub provided so app.R can source without error.

#' Compute effect size from reviewer-entered statistics
#'
#' @param input_list  Named list of field values from the review UI
#' @return  List: r, z, var_z, effect_status, effect_warnings
compute_effect_size <- function(input_list) {
  # STUB — full implementation in Phase 8
  list(
    r               = NULL,
    z               = NULL,
    var_z           = NULL,
    effect_status   = "insufficient_data",
    effect_warnings = character(0)
  )
}

# --- Design-specific helpers (stubs) -------------------------

es_control_treatment <- function(input) {
  # Phase 8: Hedges g, SE/CI/IQR conversion, t-stat fallback
  list(r = NULL, status = "insufficient_data", warnings = character(0))
}

es_correlation <- function(input) {
  # Phase 8: direct r, covariance path, t-stat path
  list(r = NULL, status = "insufficient_data", warnings = character(0))
}

es_regression <- function(input) {
  # Phase 8: t-stat path, beta * SD path, multiple_predictors handling
  list(r = NULL, status = "insufficient_data", warnings = character(0))
}

es_interaction_a <- function(input) {
  # Phase 8: explicit interaction term
  list(r = NULL, status = "insufficient_data", warnings = character(0))
}

es_interaction_b <- function(input_a, input_b) {
  # Phase 8: difference-in-differences
  list(r = NULL, z = NULL, var_z = NULL,
       status = "insufficient_data", warnings = character(0))
}

#' Convert variability statistic to SD
#' @param var_value  Numeric value
#' @param var_type   One of "SD", "SE", "95% CI", "IQR"
#' @param n          Sample size (needed for SE conversion)
#' @return           List: sd (numeric), warnings (character vector)
convert_var_to_sd <- function(var_value, var_type, n = NULL) {
  # Phase 8 implementation
  list(sd = NA_real_, warnings = character(0))
}

#' Apply Fisher Z transformation
#' @param r    Pearson r
#' @param n    Sample size (for var_z)
#' @param se_r SE of r (fallback for var_z)
#' @return     List: z, var_z
fisher_z <- function(r, n = NULL, se_r = NULL) {
  if (is.null(r) || is.na(r)) return(list(z = NULL, var_z = NULL))
  z <- atanh(r)
  var_z <- if (!is.null(n) && !is.na(n) && n > 3) 1 / (n - 3)
           else if (!is.null(se_r) && !is.na(se_r)) (se_r / (1 - r^2))^2
           else NULL
  list(z = z, var_z = var_z)
}
