# ============================================================
# modules/mod_effect_size_ui.R — Effect size sub-form
# ============================================================
# Phase 9: Full implementation.
# - General fields (study_method, response_scale, etc.)
# - Study design selector with conditional panels
# - Control/treatment, correlation, regression, interaction, time_trend
# - Interaction Pathway A / B with full sub-forms
# - Small SD toggle (visible only when means present, other stats absent)
# - Effect size result display after Save
# ============================================================

# ---- Shared constants -------------------------------------------------------

.study_design_choices <- c(
 "-- select study design --" = "",
 "Control / Treatment"       = "control_treatment",
 "Correlation"               = "correlation",
 "Regression"                = "regression",
 "Interaction"               = "interaction",
 "Time trend"                = "time_trend"
)

.study_method_choices <- c(
 "-- select --"              = "",
 "Observational"             = "Observational",
 "Experimental (ex-situ)"    = "Experimental (ex-situ)",
 "Experimental (in-situ)"    = "Experimental (in-situ)",
 "Statistical model"         = "Statistical model",
 "Simulation"                = "Simulation"
)

.response_scale_choices <- c(
 "-- select --"              = "",
 "Ind. fitness or reproduction" = "Ind. fitness or reproduction",
 "Ind. health or growth"       = "Ind. health or growth",
 "Ind. behaviour"              = "Ind. behaviour",
 "Pop. size"                   = "Pop. size",
 "Pop. genetic"                = "Pop. genetic",
 "Sp. range"                   = "Sp. range",
 "Sp. loss"                    = "Sp. loss",
 "As. structure"               = "As. structure",
 "As. succession"              = "As. succession",
 "As. sound"                   = "As. sound",
 "Eco. prim. prod."            = "Eco. prim. prod.",
 "Eco. function"               = "Eco. function",
 "Eco. food web"               = "Eco. food web",
 "Eco. habitat"                = "Eco. habitat",
 "Abio. hydrology"             = "Abio. hydrology",
 "Abio. nutrient flux"         = "Abio. nutrient flux",
 "Abio. soil"                  = "Abio. soil",
 "Unclear"                     = "Unclear",
 "NA"                          = "NA"
)

.response_distribution_choices <- c(
 "-- select --"    = "",
 "Continuous"      = "Continuous",
 "Proportion"      = "Proportion",
 "Count"           = "Count",
 "Ordinal"         = "Ordinal"
)

.predictor_distribution_choices <- c(
 "-- select --"    = "",
 "Continuous"      = "Continuous",
 "Categorical"     = "Categorical",
 "Ordinal"         = "Ordinal",
 "Time"            = "Time"
)

.var_stat_type_choices <- c(
 "-- select --" = "",
 "SD"           = "SD",
 "SE"           = "SE",
 "95% CI"       = "95% CI",
 "IQR"          = "IQR"
)

# ---- UI function -----------------------------------------------------------

mod_effect_size_ui_ui <- function(id) {
  ns <- NS(id)
  div(class = "effect-size-block p-3",
    # Hidden token: changes each render so the server can detect UI re-creation
    div(style = "display:none;",
      textInput(ns("ui_render_token"), label = NULL,
                value = as.character(runif(1)))
    ),
    h5(icon("calculator"), " Effect Size"),

    # ---- General fields (all designs) ----
    div(class = "card mb-3",
      div(class = "card-header py-2 bg-light",
        strong("General Information")
      ),
      div(class = "card-body",
        div(class = "row g-2",
          div(class = "col-md-6",
            selectInput(ns("study_method"), "Study method",
                        choices = .study_method_choices)
          ),
          div(class = "col-md-6",
            selectInput(ns("response_scale"), "Response scale",
                        choices = .response_scale_choices)
          )
        ),
        div(class = "row g-2",
          div(class = "col-md-4",
            selectInput(ns("response_distribution"), "Response distribution",
                        choices = .response_distribution_choices)
          ),
          div(class = "col-md-4",
            textInput(ns("response_variable_name"), "Response variable name",
                      placeholder = "Name exactly as in paper")
          ),
          div(class = "col-md-4",
            textInput(ns("response_unit"), "Response unit",
                      placeholder = "e.g. kg/ha, individuals/m\u00b2")
          )
        ),
        div(class = "row g-2",
          div(class = "col-md-4",
            selectInput(ns("predictor_distribution"), "Predictor distribution",
                        choices = .predictor_distribution_choices)
          ),
          div(class = "col-md-4",
            textInput(ns("predictor_variable_name"), "Predictor variable name",
                      placeholder = "Name exactly as in paper")
          ),
          div(class = "col-md-4",
            textInput(ns("predictor_unit"), "Predictor unit",
                      placeholder = "e.g. \u00b0C, years")
          )
        ),
        checkboxInput(ns("interaction_effect"), "Interaction effect",
                      value = FALSE)
      )
    ),

    # ---- Study design selector ----
    div(class = "card mb-3",
      div(class = "card-header py-2 bg-light",
        strong("Study Design & Statistics")
      ),
      div(class = "card-body",
        # Study design dropdown (hidden when interaction_effect is checked)
        uiOutput(ns("study_design_panel")),

        # Conditional panels per design
        uiOutput(ns("design_fields"))
      )
    ),

    # ---- Calculate button ----
    div(class = "d-flex gap-2 mb-3",
      actionButton(ns("btn_calculate"),
                   tagList(icon("calculator"), " Calculate effect size"),
                   class = "btn btn-info")
    ),

    # ---- Effect size result display ----
    uiOutput(ns("es_result_display"))
  )
}

# ---- Pathway legend helper --------------------------------------------------
.pathway_legend <- function(pathways) {
  # pathways: named list like list("Pathway A" = "es-pathway-a", ...)
  div(class = "es-pathway-legend mb-2",
    tags$small(class = "fw-semibold", "Conversion pathways:"),
    do.call(tagList, lapply(names(pathways), function(nm) {
      tags$span(class = paste("es-legend-swatch", pathways[[nm]]),
        nm
      )
    }))
  )
}

# ---- Helper: render design-specific fields for a given prefix ---------------
# Used both at the top level and inside Pathway B sub-forms.
.render_ct_fields <- function(ns, prefix = "") {
  p <- function(x) ns(paste0(prefix, x))
  tagList(
    # Pathway legend
    .pathway_legend(list(
      "Primary: means + variability \u2192 Hedges g \u2192 r" = "es-pathway-a",
      "Fallback 1: t-stat + df \u2192 r"                    = "es-pathway-b",
      "Fallback 2: F-stat + df \u2192 t \u2192 r"           = "es-pathway-c"
    )),
    div(class = "row g-2",
      div(class = "col-md-6",
        textInput(p("control_description"), "Control description",
                  placeholder = "Brief description of control condition")
      ),
      div(class = "col-md-6",
        textInput(p("treatment_description"), "Treatment description",
                  placeholder = "Brief description of treatment condition")
      )
    ),
    # Primary pathway: means + variability + sample sizes
    div(class = "es-pathway-a",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("mean_control"), "Mean (control)", value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("mean_treatment"), "Mean (treatment)", value = NA_real_)
        )
      ),
      div(class = "row g-2",
        div(class = "col-md-4",
          selectInput(p("var_statistic_type"),
                      tagList("Variability type",
                        tooltip_icon("What type of variability is reported?")),
                      choices = .var_stat_type_choices)
        ),
        div(class = "col-md-4",
          numericInput(p("var_value_control"), "Variability (control)",
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("var_value_treatment"), "Variability (treatment)",
                       value = NA_real_)
        )
      ),
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("n_control"), "n (control)", value = NA_integer_,
                       step = 1)
        ),
        div(class = "col-md-6",
          numericInput(p("n_treatment"), "n (treatment)", value = NA_integer_,
                       step = 1)
        )
      )
    ),
    # Fallback 1: t-stat + df
    div(class = "es-pathway-b",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("t_stat"),
                       tagList("t-statistic",
                         tooltip_icon('Look for t = or a value in parentheses, e.g. t(24) = 2.3')),
                       value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("df"),
                       tagList("Degrees of freedom (df)",
                         tooltip_icon('Look for "df =", or the number in parentheses after t, e.g. t(24): df = 24. For F(1, 45): df = 45 (use the second number).')),
                       value = NA_real_)
        )
      )
    ),
    # Fallback 2: F-stat (shares df from above)
    div(class = "es-pathway-c",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("F_stat"),
                       tagList("F-statistic",
                         tooltip_icon("Look for F = in ANOVA tables")),
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("chi_square_stat"), "Chi\u00b2 statistic",
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("p_value"), "p-value", value = NA_real_)
        )
      )
    ),
    # Small SD toggle (visibility controlled by server)
    uiOutput(ns(paste0(prefix, "small_sd_panel")))
  )
}

.render_corr_fields <- function(ns, prefix = "") {
  p <- function(x) ns(paste0(prefix, x))
  tagList(
    .pathway_legend(list(
      "Primary: r (reported)"                = "es-pathway-a",
      "Fallback 1: covariance / (SD_X \u00d7 SD_Y)" = "es-pathway-b",
      "Fallback 2: t-stat + df \u2192 r"     = "es-pathway-c"
    )),
    # Primary: direct r
    div(class = "es-pathway-a",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("r_reported"),
                       tagList("r (reported)",
                         tooltip_icon("Pearson r or Spearman rho as reported. Range: -1 to 1")),
                       value = NA_real_, min = -1, max = 1, step = 0.01)
        ),
        div(class = "col-md-4",
          numericInput(p("se_r"), "SE of r", value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("n"), "Sample size (n)", value = NA_integer_, step = 1)
        )
      )
    ),
    # Fallback 1: covariance path
    div(class = "es-pathway-b",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("covariance_XY"), "Covariance (X, Y)",
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("sd_X"), "SD of X", value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("sd_Y"), "SD of Y", value = NA_real_)
        )
      )
    ),
    # Fallback 2: t-stat path
    div(class = "es-pathway-c",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("t_stat"),
                       tagList("t-statistic",
                         tooltip_icon('Look for t = or a value in parentheses')),
                       value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("df"),
                       tagList("Degrees of freedom",
                         tooltip_icon("For correlation tests, df is usually n \u2212 2.")),
                       value = NA_real_)
        )
      )
    )
  )
}

.render_regression_fields <- function(ns, prefix = "") {
  p <- function(x) ns(paste0(prefix, x))
  tagList(
    .pathway_legend(list(
      "Primary: std \u03b2 \u2192 r; or unstd \u03b2 \u00d7 (SD_X / SD_Y) \u2192 r" = "es-pathway-a",
      "Fallback 1: t-stat + df \u2192 r; or \u03b2 / SE \u2192 t \u2192 r"          = "es-pathway-b",
      "Fallback 2: \u03b2 + p + N \u2192 t \u2192 r"                                  = "es-pathway-c"
    )),
    # Beta type selector + beta value
    div(class = "row g-2",
      div(class = "col-md-4",
        selectInput(p("beta_type"), tagList("\u03b2 type",
          tooltip_icon("Standardised \u03b2 is unitless (reported as 'standardised' in the paper). Unstandardised \u03b2 has the same units as the response variable.")),
          choices = c(
            "-- select --"     = "",
            "Standardised"     = "standardized",
            "Unstandardised"   = "unstandardized"
          ))
      ),
      div(class = "col-md-4",
        numericInput(p("beta"), "Regression coefficient (\u03b2)",
                     value = NA_real_)
      ),
      div(class = "col-md-4",
        numericInput(p("n"), "Sample size (n)", value = NA_integer_, step = 1)
      )
    ),
    # Primary pathway: beta + SDs (for unstandardised)
    div(class = "es-pathway-a",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("sd_X"), "SD of predictor", value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("sd_Y"), "SD of response", value = NA_real_)
        )
      )
    ),
    # Fallback 1: t-stat + df; or beta/SE -> t
    div(class = "es-pathway-b",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("t_stat"),
                       tagList("t-statistic",
                         tooltip_icon("t-statistic for the coefficient")),
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("df"),
                       tagList("Residual df",
                         tooltip_icon('Look for df in regression output. For F(1, 45), use 45 (the second number). Simple regression: df = N \u2212 2. Multiple regression: df = N \u2212 k \u2212 1.')),
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("se_beta"),
                       tagList("SE of \u03b2",
                         tooltip_icon("Standard error of the coefficient. Used to derive t = \u03b2 / SE when t is not reported.")),
                       value = NA_real_)
        )
      )
    ),
    # Fallback 2: p-value path
    div(class = "es-pathway-c",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("p_value"),
                       tagList("p-value",
                         tooltip_icon("p-value for the coefficient. Used to recover t when t and SE are not available.")),
                       value = NA_real_)
        )
      )
    ),
    # Multiple predictors toggle + number of predictors
    checkboxInput(p("multiple_predictors"),
                  tagList("Multiple predictors",
                    tooltip_icon("Check if the model contains more than one predictor. Effect will be flagged as partial correlation.")),
                  value = FALSE),
    conditionalPanel(
      condition = paste0("input['", p("multiple_predictors"), "'] == true"),
      div(class = "row g-2 mb-2",
        div(class = "col-md-4",
          numericInput(p("n_predictors"),
                       tagList("Number of predictors (k)",
                         tooltip_icon("Number of predictors in the model. Used to compute df = N \u2212 k \u2212 1 when df is not reported directly.")),
                       value = NA_integer_, min = 2, step = 1)
        ),
        div(class = "col-md-8",
          div(class = "alert alert-info py-2 small mb-0 mt-4",
            icon("info-circle"),
            " Multiple regression produces a ",
            tags$strong("partial correlation"),
            ", not a zero-order r. Standardised \u03b2 alone cannot be converted; provide t, SE, or p-value."
          )
        )
      )
    )
  )
}

.render_interaction_a_fields <- function(ns, prefix = "") {
  p <- function(x) ns(paste0(prefix, x))
  tagList(
    .pathway_legend(list(
      "t-stat + df \u2192 r" = "es-pathway-a"
    )),
    div(class = "row g-2",
      div(class = "col-md-6",
        numericInput(p("interaction_term"), "Interaction term coefficient",
                     value = NA_real_)
      ),
      div(class = "col-md-6",
        numericInput(p("se_interaction"), "SE of interaction term",
                     value = NA_real_)
      )
    ),
    div(class = "es-pathway-a",
      div(class = "row g-2",
        div(class = "col-md-6",
          numericInput(p("t_stat"),
                       tagList("t-statistic",
                         tooltip_icon("t-statistic for the interaction term")),
                       value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("df"), "Degrees of freedom", value = NA_real_)
        )
      )
    )
  )
}


# ---- Server function ---------------------------------------------------------

mod_effect_size_ui_server <- function(id, session_rv, article_id_reactive,
                                       project_id_reactive,
                                       on_save_trigger = NULL,
                                       group_instance_id = NULL,
                                       prefetched_effects = NULL) {
  # Force evaluation of group_instance_id NOW so that each module instance
  # created inside a for-loop captures its own value (R lazy evaluation fix).
  force(group_instance_id)
  force(prefetched_effects)
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Stored result (from last save/load) ----
    es_result <- reactiveVal(NULL)
    # ---- Stored raw JSON (for repopulating after UI re-render) ----
    stored_raw <- reactiveVal(NULL)

    # ---- Load existing effect size data when article changes ----
    observeEvent(article_id_reactive(), {
      aid <- article_id_reactive()
      es_result(NULL)   # clear previous result
      stored_raw(NULL)  # clear previous raw data
      if (is.null(aid)) return()

      # ALWAYS reset all fields first to prevent stale data from the
      # previous article leaking through.  Fields are then populated from
      # the DB below (after the usual rendering delays).
      .reset_all_fields()

      tryCatch({
        # Use pre-fetched effect sizes if available (avoids N+1 queries
        # when multiple ES modules load simultaneously for the same article).
        all_rows <- if (!is.null(prefetched_effects)) {
          tryCatch(prefetched_effects(), error = function(e) data.frame())
        } else {
          tryCatch(
            sb_get("effect_sizes",
                    filters = list(article_id = aid),
                    token   = session_rv$token),
            error = function(e) data.frame()
          )
        }

        # Filter for this module's group_instance_id
        rows <- data.frame()
        if (is.data.frame(all_rows) && nrow(all_rows) > 0) {
          if (!is.null(group_instance_id)) {
            gi_match <- which(!is.na(all_rows$group_instance_id) &
                                all_rows$group_instance_id == group_instance_id)
            if (length(gi_match) > 0) {
              rows <- all_rows[gi_match, , drop = FALSE]
            }
          } else {
            # Top-level (no group): rows with NULL/NA group_instance_id
            gi_vals <- all_rows$group_instance_id
            na_match <- which(is.na(gi_vals) | gi_vals == "")
            if (length(na_match) > 0) {
              rows <- all_rows[na_match, , drop = FALSE]
            }
          }
        }

        # --- Positional fallback for articles saved with counter-based gi_ids ---
        # If no rows match the sequential gi_id (e.g., "study_site_1") but the
        # article HAS effect sizes under different gi_ids (e.g., "study_site_3"),
        # fall back to positional matching.
        if (nrow(rows) == 0 && !is.null(group_instance_id) &&
            is.data.frame(all_rows) && nrow(all_rows) > 0) {
          pos <- suppressWarnings(
            as.integer(sub(".*_(\\d+)$", "\\1", group_instance_id)))
          if (!is.na(pos)) {
            # Deduplicate: keep latest per gi_id
            deduped <- all_rows
            if ("computed_at" %in% names(deduped)) {
              ord  <- order(as.POSIXct(deduped$computed_at, tz = "UTC"),
                            decreasing = TRUE)
              deduped <- deduped[ord, , drop = FALSE]
              deduped <- deduped[!duplicated(deduped$group_instance_id),
                                 , drop = FALSE]
            }
            # Sort gi_ids numerically by trailing number
            gi_nums <- suppressWarnings(
              as.integer(sub(".*_(\\d+)$", "\\1",
                             deduped$group_instance_id)))
            gi_nums[is.na(gi_nums)] <- 0L
            deduped <- deduped[order(gi_nums), , drop = FALSE]
            if (pos <= nrow(deduped)) {
              rows <- deduped[pos, , drop = FALSE]
              message(sprintf(
                "[mod_effect_size_ui] Fallback: loaded position %d for %s (article %s)",
                pos, group_instance_id, aid))
            }
          }
        }

        if (is.data.frame(rows) && nrow(rows) > 0) {
          # If multiple rows (stale data), pick the latest by computed_at
          if (nrow(rows) > 1 && "computed_at" %in% names(rows)) {
            ct <- as.POSIXct(rows$computed_at, tz = "UTC")
            rows <- rows[order(ct, decreasing = TRUE), , drop = FALSE]
          }
          row <- rows[1, ]   # latest matching effect size row
          raw <- tryCatch({
            rj <- row$raw_effect_json
            # Unwrap list-column wrapper from single-row data frame access
            if (is.list(rj) && length(rj) == 1 &&
                (is.null(names(rj)) || identical(names(rj), ""))) {
              rj <- rj[[1]]
            }
            if (is.character(rj) && length(rj) == 1 && nchar(rj) > 0)
              jsonlite::fromJSON(rj, simplifyVector = FALSE)
            else if (is.list(rj))
              rj
            else
              list()
          }, error = function(e) {
            message("[mod_effect_size_ui] raw_effect_json parse error: ", e$message)
            list()
          })

          # Store raw data for repopulation after UI re-renders
          stored_raw(raw)

          # Show stored result immediately (doesn't need UI inputs)
          etype <- tryCatch(row$effect_type, error = function(e) NULL)
          ewarn <- tryCatch(row$effect_warnings, error = function(e) NULL)
          es_result(list(
            r               = row$r,
            z               = row$z,
            var_z           = row$var_z,
            effect_status   = row$effect_status,
            effect_type     = if (!is.null(etype)) etype else "zero_order",
            effect_warnings = if (is.character(ewarn))
                                ewarn
                              else if (is.list(ewarn))
                                unlist(ewarn)
                              else character(0)
          ))

          # --- Phase 1: General fields ---
          # Delay to ensure the module UI (including nested renderUI
          # outputs like study_design_panel) has been flushed to the
          # client. Dynamically-created grouped modules need extra time
          # because their parent renderUI hasn't sent the HTML yet.
          shinyjs::delay(600, {
            .update_input_safe("study_method",             raw$study_method)
            .update_input_safe("response_scale",           raw$response_scale)
            .update_input_safe("response_distribution",    raw$response_distribution)
            .update_input_safe("response_variable_name",   raw$response_variable_name)
            .update_input_safe("response_unit",            raw$response_unit)
            .update_input_safe("predictor_distribution",   raw$predictor_distribution)
            .update_input_safe("predictor_variable_name",  raw$predictor_variable_name)
            .update_input_safe("predictor_unit",           raw$predictor_unit)
            .update_input_safe("interaction_effect",       raw$interaction_effect)
            .update_input_safe("study_design",             raw$study_design)

            # --- Phase 2: Design-specific fields ---
            # After study_design is set, the design_fields renderUI must
            # fire + flush + render in the browser before field inputs exist.
            # This requires a server→client→server→client round-trip.
            shinyjs::delay(900, {
              design <- raw$study_design %||% ""
              .restore_design_fields(raw, "")

              # --- Phase 3: Interaction pathway fields ---
              if (design == "interaction") {
                .update_input_safe("interaction_pathway",  raw$interaction_pathway)
                shinyjs::delay(700, {
                  pathway <- raw$interaction_pathway %||% "A"
                  if (pathway == "A") {
                    .restore_interaction_a(raw, "")
                  } else {
                    # Pathway B: group A and group B sub-design selectors
                    .update_input_safe("grpA_study_design", raw$group_a$study_design)
                    .update_input_safe("grpB_study_design", raw$group_b$study_design)
                    # --- Phase 4: Pathway B sub-design fields ---
                    shinyjs::delay(700, {
                      if (!is.null(raw$group_a))
                        .restore_design_fields(raw$group_a, "grpA_")
                      if (!is.null(raw$group_b))
                        .restore_design_fields(raw$group_b, "grpB_")
                    })
                  }
                })
              }
            })
          })

        }
        # else: fields already reset above; nothing more to do
      }, error = function(e) {
        message("[mod_effect_size_ui] load error: ", e$message)
        # Fields already reset above; no additional reset needed
      })
    }, ignoreNULL = FALSE)

    # ---- Helper: safely update an input ----
    .update_input_safe <- function(input_id, value) {
      if (is.null(value)) return()
      tryCatch({
        val <- if (is.logical(value)) value else as.character(value)
        if (is.logical(val)) {
          updateCheckboxInput(session, input_id, value = isTRUE(val))
        } else {
          # Try to detect the input type from known IDs
          if (grepl("^(study_design|study_method|response_scale|response_distribution|predictor_distribution|var_statistic_type|interaction_pathway|grpA_study_design|grpB_study_design|beta_type)$", input_id) ||
              grepl("^grp[AB]_(var_statistic_type|beta_type)$", input_id)) {
            updateSelectInput(session, input_id, selected = val)
          } else if (grepl("(mean_|var_value_|n_control|n_treatment|t_stat|F_stat|chi_square|p_value|df|r_reported|se_r|covariance|sd_X|sd_Y|beta|se_beta|interaction_term|se_interaction|n_predictors|^n$)", input_id)) {
            updateNumericInput(session, input_id, value = as.numeric(val))
          } else {
            updateTextInput(session, input_id, value = val)
          }
        }
      }, error = function(e) NULL)
    }

    # ---- Helper: restore design fields from raw JSON ----
    .restore_design_fields <- function(raw, prefix) {
      design <- raw$study_design %||% ""
      if (design == "time_trend") design <- "regression"

      if (design == "control_treatment") {
        .update_input_safe(paste0(prefix, "control_description"),    raw$control_description)
        .update_input_safe(paste0(prefix, "treatment_description"),  raw$treatment_description)
        .update_input_safe(paste0(prefix, "mean_control"),           raw$mean_control)
        .update_input_safe(paste0(prefix, "mean_treatment"),         raw$mean_treatment)
        .update_input_safe(paste0(prefix, "var_statistic_type"),     raw$var_statistic_type)
        .update_input_safe(paste0(prefix, "var_value_control"),      raw$var_value_control)
        .update_input_safe(paste0(prefix, "var_value_treatment"),    raw$var_value_treatment)
        .update_input_safe(paste0(prefix, "n_control"),              raw$n_control)
        .update_input_safe(paste0(prefix, "n_treatment"),            raw$n_treatment)
        .update_input_safe(paste0(prefix, "t_stat"),                 raw$t_stat)
        .update_input_safe(paste0(prefix, "F_stat"),                 raw$F_stat)
        .update_input_safe(paste0(prefix, "chi_square_stat"),        raw$chi_square_stat)
        .update_input_safe(paste0(prefix, "p_value"),                raw$p_value)
        .update_input_safe(paste0(prefix, "df"),                     raw$df)
        .update_input_safe(paste0(prefix, "use_small_sd_approx"),    raw$use_small_sd_approx)
      } else if (design == "correlation") {
        .update_input_safe(paste0(prefix, "r_reported"),    raw$r_reported)
        .update_input_safe(paste0(prefix, "se_r"),          raw$se_r)
        .update_input_safe(paste0(prefix, "n"),             raw$n)
        .update_input_safe(paste0(prefix, "covariance_XY"), raw$covariance_XY)
        .update_input_safe(paste0(prefix, "sd_X"),          raw$sd_X)
        .update_input_safe(paste0(prefix, "sd_Y"),          raw$sd_Y)
        .update_input_safe(paste0(prefix, "t_stat"),        raw$t_stat)
        .update_input_safe(paste0(prefix, "df"),            raw$df)
      } else if (design == "regression") {
        .update_input_safe(paste0(prefix, "beta"),                raw$beta)
        .update_input_safe(paste0(prefix, "beta_type"),           raw$beta_type)
        .update_input_safe(paste0(prefix, "se_beta"),             raw$se_beta)
        .update_input_safe(paste0(prefix, "n"),                   raw$n)
        .update_input_safe(paste0(prefix, "t_stat"),              raw$t_stat)
        .update_input_safe(paste0(prefix, "p_value"),             raw$p_value)
        .update_input_safe(paste0(prefix, "df"),                  raw$df)
        .update_input_safe(paste0(prefix, "sd_X"),                raw$sd_X)
        .update_input_safe(paste0(prefix, "sd_Y"),                raw$sd_Y)
        .update_input_safe(paste0(prefix, "multiple_predictors"), raw$multiple_predictors)
        .update_input_safe(paste0(prefix, "n_predictors"),        raw$n_predictors)
      }
    }

    .restore_interaction_a <- function(raw, prefix) {
      .update_input_safe(paste0(prefix, "interaction_term"),  raw$interaction_term)
      .update_input_safe(paste0(prefix, "se_interaction"),    raw$se_interaction)
      .update_input_safe(paste0(prefix, "t_stat"),            raw$t_stat)
      .update_input_safe(paste0(prefix, "df"),                raw$df)
    }

    # ---- Helper: reset all fields ----
    .reset_all_fields <- function() {
      # Reset interaction first so study_design dropdown re-appears
      updateCheckboxInput(session, "interaction_effect", value = FALSE)
      for (fld in c("study_method", "response_scale", "response_distribution",
                     "predictor_distribution")) {
        updateSelectInput(session, fld, selected = "")
      }
      # study_design needs a short delay since it may be re-rendered after
      # interaction_effect is unchecked
      shinyjs::delay(100, {
        updateSelectInput(session, "study_design", selected = "")
      })
      for (fld in c("response_variable_name", "response_unit",
                     "predictor_variable_name", "predictor_unit",
                     "control_description", "treatment_description")) {
        updateTextInput(session, fld, value = "")
      }
      # Reset ALL numeric / statistics fields across all study designs
      # These live inside conditional renderUI panels that may or may not
      # exist in the DOM yet, so updateNumericInput silently no-ops
      # for inputs that don't exist.
      for (fld in c(
        # Control/Treatment
        "mean_control", "mean_treatment",
        "var_value_control", "var_value_treatment",
        "n_control", "n_treatment",
        # Shared stats
        "t_stat", "F_stat", "chi_square_stat", "p_value", "df",
        # Correlation
        "r_reported", "se_r", "n", "covariance_XY", "sd_X", "sd_Y",
        # Regression
        "beta", "se_beta", "n_predictors",
        # Interaction
        "interaction_term", "se_interaction",
        # Pathway B sub-forms
        "grpA_mean_control", "grpA_mean_treatment",
        "grpA_var_value_control", "grpA_var_value_treatment",
        "grpA_n_control", "grpA_n_treatment",
        "grpA_t_stat", "grpA_F_stat", "grpA_df",
        "grpA_r_reported", "grpA_se_r", "grpA_n",
        "grpA_beta", "grpA_se_beta",
        "grpB_mean_control", "grpB_mean_treatment",
        "grpB_var_value_control", "grpB_var_value_treatment",
        "grpB_n_control", "grpB_n_treatment",
        "grpB_t_stat", "grpB_F_stat", "grpB_df",
        "grpB_r_reported", "grpB_se_r", "grpB_n",
        "grpB_beta", "grpB_se_beta"
      )) {
        updateNumericInput(session, fld, value = NA_real_)
      }
      # Reset select inputs inside design panels
      for (fld in c("var_statistic_type", "beta_type",
                     "interaction_pathway",
                     "grpA_study_design", "grpB_study_design",
                     "grpA_var_statistic_type", "grpA_beta_type",
                     "grpB_var_statistic_type", "grpB_beta_type")) {
        updateSelectInput(session, fld, selected = "")
      }
      # Reset checkboxes inside design panels
      for (fld in c("use_small_sd_approx", "multiple_predictors",
                     "grpA_use_small_sd_approx", "grpB_use_small_sd_approx")) {
        updateCheckboxInput(session, fld, value = FALSE)
      }
      es_result(NULL)
    }

    # ---- Auto-check interaction_effect when design = "interaction" ----
    observeEvent(input$study_design, {
      if (!is.null(input$study_design) && input$study_design == "interaction") {
        updateCheckboxInput(session, "interaction_effect", value = TRUE)
      }
    })

    # ---- When interaction_effect is unchecked, reset study_design if it was 'interaction' ----
    observeEvent(input$interaction_effect, {
      if (!isTRUE(input$interaction_effect)) {
        if (!is.null(input$study_design) && input$study_design == "interaction") {
          updateSelectInput(session, "study_design", selected = "")
        }
      }
    }, ignoreInit = TRUE)

    # ---- Study design dropdown (hidden when interaction_effect is checked) ----
    output$study_design_panel <- renderUI({
      is_interaction <- isTRUE(input$interaction_effect)

      if (is_interaction) {
        # Hide the regular study design dropdown; interaction pathway handles it
        NULL
      } else {
        selectInput(ns("study_design"), "Study design",
                    choices = .study_design_choices,
                    selected = input$study_design %||% "")
      }
    })

    # ---- Design-specific conditional panels ----
    output$design_fields <- renderUI({
      design <- input$study_design %||% ""
      is_interaction <- isTRUE(input$interaction_effect)

      # When interaction_effect is checked, show only the interaction pathway UI
      if (is_interaction) {
        return(.render_interaction_ui(ns))
      }

      if (nchar(design) == 0) {
        return(p(class = "text-muted fst-italic small",
            "Select a study design to show the relevant statistics fields."))
      }

      switch(design,
        "control_treatment" = .render_ct_fields(ns),
        "correlation"       = .render_corr_fields(ns),
        "regression"        = .render_regression_fields(ns),
        "time_trend"        = {
          tagList(
            div(class = "alert alert-info py-2 small mb-2",
              icon("info-circle"),
              " Time trend uses the regression fields. ",
              tags$strong("predictor_distribution"), " will be set to 'Time'."
            ),
            .render_regression_fields(ns)
          )
        },
        "interaction" = .render_interaction_ui(ns),
        p(class = "text-muted small", "Unknown study design.")
      )
    })

    # ---- Interaction design UI with Pathway selector ----
    .render_interaction_ui <- function(ns) {
      tagList(
        selectInput(ns("interaction_pathway"), "Interaction pathway",
          choices = c(
            "Pathway A: Explicit interaction term" = "A",
            "Pathway B: Separate group effects (difference-in-differences)" = "B"
          )
        ),
        uiOutput(ns("interaction_panel"))
      )
    }

    output$interaction_panel <- renderUI({
      pathway <- input$interaction_pathway %||% "A"
      if (pathway == "A") {
        .render_interaction_a_fields(ns)
      } else {
        .render_pathway_b_ui(ns)
      }
    })

    # ---- Pathway B: two sub-forms (Group A, Group B) ----
    .render_pathway_b_ui <- function(ns) {
      tagList(
        div(class = "alert alert-secondary py-2 small mb-3",
          icon("info-circle"),
          " Enter separate effect size statistics for each group. ",
          "The app will compute the difference-in-differences (z_A \u2212 z_B)."
        ),
        # Use navset_card_tab for Group A / Group B
        navset_card_tab(
          id = ns("pathway_b_tabs"),
          nav_panel("Group A",
            div(class = "pt-2",
              selectInput(ns("grpA_study_design"), "Study design (Group A)",
                          choices = c(
                            "-- select --"            = "",
                            "Control / Treatment"     = "control_treatment",
                            "Correlation"             = "correlation",
                            "Regression"              = "regression"
                          )),
              uiOutput(ns("grpA_fields"))
            )
          ),
          nav_panel("Group B",
            div(class = "pt-2",
              selectInput(ns("grpB_study_design"), "Study design (Group B)",
                          choices = c(
                            "-- select --"            = "",
                            "Control / Treatment"     = "control_treatment",
                            "Correlation"             = "correlation",
                            "Regression"              = "regression"
                          )),
              uiOutput(ns("grpB_fields"))
            )
          )
        )
      )
    }

    output$grpA_fields <- renderUI({
      design <- input$grpA_study_design %||% ""
      if (nchar(design) == 0) return(NULL)
      switch(design,
        "control_treatment" = .render_ct_fields(ns, prefix = "grpA_"),
        "correlation"       = .render_corr_fields(ns, prefix = "grpA_"),
        "regression"        = .render_regression_fields(ns, prefix = "grpA_"),
        NULL
      )
    })

    output$grpB_fields <- renderUI({
      design <- input$grpB_study_design %||% ""
      if (nchar(design) == 0) return(NULL)
      switch(design,
        "control_treatment" = .render_ct_fields(ns, prefix = "grpB_"),
        "correlation"       = .render_corr_fields(ns, prefix = "grpB_"),
        "regression"        = .render_regression_fields(ns, prefix = "grpB_"),
        NULL
      )
    })

    # Ensure Group B sub-form renders even when its tab is inactive,
    # so that field inputs exist when restoring saved data.
    outputOptions(output, "grpB_fields", suspendWhenHidden = FALSE)

    # ---- Small SD toggle (for control/treatment) ----
    # Shows only when means are present but no variability/test stats
    output$small_sd_panel <- renderUI({
      m1  <- input$mean_control
      m2  <- input$mean_treatment
      vst <- input$var_statistic_type %||% ""
      vc  <- input$var_value_control
      vt  <- input$var_value_treatment
      ts  <- input$t_stat
      fs  <- input$F_stat
      cs  <- input$chi_square_stat

      has_means <- !is.null(m1) && !is.na(m1) && !is.null(m2) && !is.na(m2)
      has_var   <- (nchar(vst) > 0 && !is.null(vc) && !is.na(vc) &&
                    !is.null(vt) && !is.na(vt))
      has_test  <- (!is.null(ts) && !is.na(ts)) ||
                   (!is.null(fs) && !is.na(fs)) ||
                   (!is.null(cs) && !is.na(cs))

      if (has_means && !has_var && !has_test) {
        div(class = "alert alert-warning py-2 mt-2",
          checkboxInput(ns("use_small_sd_approx"),
            tags$span(
              strong("Use small SD approximation"),
              tags$br(),
              tags$small(class = "text-muted",
                "Not recommended; for use only when no other statistics are available. ",
                "SD will be approximated as 0.01 \u00d7 mean.")
            ),
            value = isTRUE(input$use_small_sd_approx)
          )
        )
      }
    })

    # Small SD panels for Pathway B groups
    output$grpA_small_sd_panel <- renderUI({
      .render_small_sd_for_group("grpA_")
    })
    output$grpB_small_sd_panel <- renderUI({
      .render_small_sd_for_group("grpB_")
    })

    .render_small_sd_for_group <- function(prefix) {
      m1  <- input[[paste0(prefix, "mean_control")]]
      m2  <- input[[paste0(prefix, "mean_treatment")]]
      vst <- input[[paste0(prefix, "var_statistic_type")]] %||% ""
      vc  <- input[[paste0(prefix, "var_value_control")]]
      vt  <- input[[paste0(prefix, "var_value_treatment")]]
      ts  <- input[[paste0(prefix, "t_stat")]]
      fs  <- input[[paste0(prefix, "F_stat")]]
      cs  <- input[[paste0(prefix, "chi_square_stat")]]

      has_means <- !is.null(m1) && !is.na(m1) && !is.null(m2) && !is.na(m2)
      has_var   <- (nchar(vst) > 0 && !is.null(vc) && !is.na(vc) &&
                    !is.null(vt) && !is.na(vt))
      has_test  <- (!is.null(ts) && !is.na(ts)) ||
                   (!is.null(fs) && !is.na(fs)) ||
                   (!is.null(cs) && !is.na(cs))

      if (has_means && !has_var && !has_test) {
        div(class = "alert alert-warning py-2 mt-2",
          checkboxInput(ns(paste0(prefix, "use_small_sd_approx")),
            tags$span(
              strong("Use small SD approximation"),
              tags$br(),
              tags$small(class = "text-muted",
                "Not recommended; SD = 0.01 \u00d7 mean.")
            ),
            value = isTRUE(input[[paste0(prefix, "use_small_sd_approx")]])
          )
        )
      }
    }

    # ---- Effect size result display ----
    output$es_result_display <- renderUI({
      res <- es_result()
      if (is.null(res)) return(NULL)

      status  <- res$effect_status %||% "insufficient_data"
      warns   <- res$effect_warnings
      if (is.null(warns)) warns <- character(0)

      if (status == "insufficient_data") {
        div(class = "card border-warning mt-3",
          div(class = "card-body py-2",
            div(class = "d-flex align-items-center",
              icon("exclamation-triangle", class = "text-warning me-2 fa-lg"),
              div(
                h6(class = "mb-1", "Effect size could not be computed"),
                p(class = "mb-0 small text-muted",
                  "Missing required statistics. Raw data has been saved.")
              )
            )
          )
        )
      } else {
        status_badge <- switch(status,
          "calculated"          = span(class = "badge bg-success", "Calculated"),
          "calculated_relative" = span(class = "badge bg-info",    "Calculated (relative)"),
          "small_sd_used"       = span(class = "badge bg-warning text-dark", "Small SD used"),
          "iqr_sd_used"         = span(class = "badge bg-warning text-dark", "IQR \u2192 SD used"),
          span(class = "badge bg-secondary", status)
        )

        # Show effect type (zero-order vs partial)
        etype <- res$effect_type %||% "zero_order"
        etype_badge <- if (etype == "partial") {
          span(class = "badge bg-warning text-dark ms-1", "Partial r")
        } else {
          NULL
        }

        r_label <- if (etype == "partial") "Partial r" else "Pearson r"
        r_fmt    <- if (!is.null(res$r))     sprintf("%.4f", res$r)     else "NA"
        z_fmt    <- if (!is.null(res$z))     sprintf("%.4f", res$z)     else "NA"
        vz_fmt   <- if (!is.null(res$var_z)) sprintf("%.4f", res$var_z) else "NA"

        div(class = "card border-success mt-3",
          div(class = "card-header py-2 bg-success bg-opacity-10",
            div(class = "d-flex align-items-center gap-2",
              icon("check-circle", class = "text-success"),
              strong("Computed Effect Size"),
              status_badge,
              etype_badge
            )
          ),
          div(class = "card-body py-2",
            div(class = "row g-2",
              div(class = "col-md-4",
                tags$dl(class = "mb-0",
                  tags$dt(class = "small text-muted", r_label),
                  tags$dd(class = "fs-5 fw-bold mb-0", r_fmt)
                )
              ),
              div(class = "col-md-4",
                tags$dl(class = "mb-0",
                  tags$dt(class = "small text-muted", "Fisher Z"),
                  tags$dd(class = "fs-5 fw-bold mb-0", z_fmt)
                )
              ),
              div(class = "col-md-4",
                tags$dl(class = "mb-0",
                  tags$dt(class = "small text-muted", "var(Z)"),
                  tags$dd(class = "fs-5 fw-bold mb-0", vz_fmt)
                )
              )
            ),
            if (length(warns) > 0) {
              div(class = "mt-2",
                tags$small(class = "text-warning",
                  icon("exclamation-triangle"),
                  " Warnings: ",
                  paste(warns, collapse = "; ")
                )
              )
            }
          )
        )
      }
    })

    # ---- Collect all effect size inputs into a list for compute_effect_size ----
    collect_es_inputs <- function() {
      design <- input$study_design %||% ""
      is_interaction <- isTRUE(input$interaction_effect) || design == "interaction"

      if (nchar(design) == 0 && !is_interaction) return(NULL)

      # General fields
      result <- list(
        study_method             = input$study_method %||% "",
        response_scale           = input$response_scale %||% "",
        response_distribution    = input$response_distribution %||% "",
        response_variable_name   = input$response_variable_name %||% "",
        response_unit            = input$response_unit %||% "",
        predictor_distribution   = input$predictor_distribution %||% "",
        predictor_variable_name  = input$predictor_variable_name %||% "",
        predictor_unit           = input$predictor_unit %||% "",
        interaction_effect       = is_interaction,
        study_design             = if (is_interaction) "interaction" else design
      )

      # Time trend: use regression + set predictor_distribution = Time
      if (design == "time_trend") {
        result$predictor_distribution <- "Time"
      }

      # When interaction_effect is checked, collect interaction fields
      # (these override any regular design fields for computation)
      if (is_interaction) {
        pathway <- input$interaction_pathway %||% "A"
        result$interaction_pathway <- pathway

        if (pathway == "A") {
          result$interaction_term  <- .safe_num(input$interaction_term)
          result$se_interaction    <- .safe_num(input$se_interaction)
          result$t_stat            <- .safe_num(input$t_stat)
          result$df                <- .safe_num(input$df)
          result$n                 <- .safe_num(input$n)
        } else {
          # Pathway B: collect two sub-forms
          grpA_design <- input$grpA_study_design %||% ""
          grpB_design <- input$grpB_study_design %||% ""

          group_a <- list(study_design = grpA_design)
          if (grpA_design == "control_treatment") {
            group_a <- c(group_a, .collect_ct_fields("grpA_"))
          } else if (grpA_design == "correlation") {
            group_a <- c(group_a, .collect_corr_fields("grpA_"))
          } else if (grpA_design == "regression") {
            group_a <- c(group_a, .collect_regression_fields("grpA_"))
          }

          group_b <- list(study_design = grpB_design)
          if (grpB_design == "control_treatment") {
            group_b <- c(group_b, .collect_ct_fields("grpB_"))
          } else if (grpB_design == "correlation") {
            group_b <- c(group_b, .collect_corr_fields("grpB_"))
          } else if (grpB_design == "regression") {
            group_b <- c(group_b, .collect_regression_fields("grpB_"))
          }

          result$group_a <- group_a
          result$group_b <- group_b
        }
      } else {
        # Design-specific fields (no interaction)
        if (design == "control_treatment") {
          result <- c(result, .collect_ct_fields(""))
        } else if (design == "correlation") {
          result <- c(result, .collect_corr_fields(""))
        } else if (design == "regression" || design == "time_trend") {
          result <- c(result, .collect_regression_fields(""))
        }
      }

      result
    }

    # ---- Field collectors per design ----
    .safe_num <- function(val) {
      if (is.null(val)) return(NULL)
      if (is.character(val) && nchar(trimws(val)) == 0) return(NULL)
      v <- suppressWarnings(as.numeric(val))
      if (is.na(v)) return(NULL)
      v
    }

    # Check all visible numeric input fields for non-numeric text.
    # Returns a character vector of warning messages (empty if all OK).
    .validate_numeric_inputs <- function() {
      bad <- character(0)
      .check <- function(input_id, label) {
        v <- input[[input_id]]
        if (!is.null(v) && is.character(v) && nchar(trimws(v)) > 0) {
          if (is.na(suppressWarnings(as.numeric(v)))) {
            bad <<- c(bad, sprintf("'%s' is not a valid number for %s", v, label))
          }
        }
      }
      design <- input$study_design %||% ""
      is_interaction <- isTRUE(input$interaction_effect) || design == "interaction"
      if (is_interaction) {
        pathway <- input$interaction_pathway %||% "A"
        if (pathway == "A") {
          .check("interaction_term", "Interaction term")
          .check("se_interaction",   "SE (interaction)")
          .check("t_stat",           "t-statistic")
          .check("df",               "df")
          .check("n",                "n")
        }
        # Pathway B sub-forms use prefixed IDs; check those too
        if (pathway == "B") {
          for (pfx in c("grpA_", "grpB_")) {
            for (fld in c("t_stat", "df", "n", "mean_control", "mean_treatment",
                          "var_value_control", "var_value_treatment",
                          "n_control", "n_treatment", "F_stat",
                          "chi_square_stat", "p_value",
                          "r_reported", "se_r", "beta", "se_beta",
                          "sd_X", "sd_Y", "n_predictors")) {
              .check(paste0(pfx, fld), paste0(pfx, fld))
            }
          }
        }
      } else if (design == "control_treatment") {
        for (fld in c("mean_control", "mean_treatment",
                      "var_value_control", "var_value_treatment",
                      "n_control", "n_treatment", "t_stat", "F_stat",
                      "chi_square_stat", "p_value", "df")) {
          .check(fld, fld)
        }
      } else if (design == "correlation") {
        for (fld in c("r_reported", "se_r", "n", "covariance_XY",
                      "sd_X", "sd_Y", "t_stat", "df")) {
          .check(fld, fld)
        }
      } else if (design %in% c("regression", "time_trend")) {
        for (fld in c("beta", "se_beta", "n", "t_stat", "p_value",
                      "df", "sd_X", "sd_Y", "n_predictors")) {
          .check(fld, fld)
        }
      }
      bad
    }

    .collect_ct_fields <- function(prefix) {
      list(
        control_description    = input[[paste0(prefix, "control_description")]] %||% "",
        treatment_description  = input[[paste0(prefix, "treatment_description")]] %||% "",
        mean_control           = .safe_num(input[[paste0(prefix, "mean_control")]]),
        mean_treatment         = .safe_num(input[[paste0(prefix, "mean_treatment")]]),
        var_statistic_type     = input[[paste0(prefix, "var_statistic_type")]] %||% "",
        var_value_control      = .safe_num(input[[paste0(prefix, "var_value_control")]]),
        var_value_treatment    = .safe_num(input[[paste0(prefix, "var_value_treatment")]]),
        n_control              = .safe_num(input[[paste0(prefix, "n_control")]]),
        n_treatment            = .safe_num(input[[paste0(prefix, "n_treatment")]]),
        t_stat                 = .safe_num(input[[paste0(prefix, "t_stat")]]),
        F_stat                 = .safe_num(input[[paste0(prefix, "F_stat")]]),
        chi_square_stat        = .safe_num(input[[paste0(prefix, "chi_square_stat")]]),
        p_value                = .safe_num(input[[paste0(prefix, "p_value")]]),
        df                     = .safe_num(input[[paste0(prefix, "df")]]),
        use_small_sd_approx    = isTRUE(input[[paste0(prefix, "use_small_sd_approx")]])
      )
    }

    .collect_corr_fields <- function(prefix) {
      list(
        r_reported    = .safe_num(input[[paste0(prefix, "r_reported")]]),
        se_r          = .safe_num(input[[paste0(prefix, "se_r")]]),
        n             = .safe_num(input[[paste0(prefix, "n")]]),
        covariance_XY = .safe_num(input[[paste0(prefix, "covariance_XY")]]),
        sd_X          = .safe_num(input[[paste0(prefix, "sd_X")]]),
        sd_Y          = .safe_num(input[[paste0(prefix, "sd_Y")]]),
        t_stat        = .safe_num(input[[paste0(prefix, "t_stat")]]),
        df            = .safe_num(input[[paste0(prefix, "df")]])
      )
    }

    .collect_regression_fields <- function(prefix) {
      list(
        beta                = .safe_num(input[[paste0(prefix, "beta")]]),
        beta_type           = input[[paste0(prefix, "beta_type")]] %||% "",
        se_beta             = .safe_num(input[[paste0(prefix, "se_beta")]]),
        n                   = .safe_num(input[[paste0(prefix, "n")]]),
        t_stat              = .safe_num(input[[paste0(prefix, "t_stat")]]),
        p_value             = .safe_num(input[[paste0(prefix, "p_value")]]),
        df                  = .safe_num(input[[paste0(prefix, "df")]]),
        sd_X                = .safe_num(input[[paste0(prefix, "sd_X")]]),
        sd_Y                = .safe_num(input[[paste0(prefix, "sd_Y")]]),
        multiple_predictors = isTRUE(input[[paste0(prefix, "multiple_predictors")]]),
        n_predictors        = .safe_num(input[[paste0(prefix, "n_predictors")]])
      )
    }

    # ---- Calculate button: compute only (no DB write) ----
    observeEvent(input$btn_calculate, {
      # Validate numeric fields before collecting inputs
      bad_fields <- .validate_numeric_inputs()
      if (length(bad_fields) > 0) {
        showNotification(
          paste("Please fix non-numeric values:",
                paste(bad_fields, collapse = "; ")),
          type = "error", duration = 8)
        return()
      }

      es_inputs <- collect_es_inputs()
      if (is.null(es_inputs)) {
        showNotification("Please select a study design first.",
                         type = "warning")
        return()
      }

      computed <- tryCatch(
        compute_effect_size(es_inputs),
        error = function(e) {
          message("[effect_size calculate] error: ", e$message)
          list(r = NULL, z = NULL, var_z = NULL,
               effect_status = "insufficient_data",
               effect_warnings = c(paste("Computation error:", e$message)))
        }
      )

      es_result(computed)
      showNotification("Effect size calculated (not yet saved).",
                       type = "message", duration = 3)
    }, ignoreInit = TRUE)

    # NOTE: the actual save-to-DB logic is now in mod_review.R .do_save()
    # (called synchronously before .go_next()) to avoid a race condition
    # where the async observer would fire after the article_id had already
    # changed to the next article.

    # ---- Self-repopulate when UI is re-rendered ----
    # When the parent renderUI re-renders (e.g. Add Instance), all DOM
    # inputs are destroyed and recreated.  The hidden ui_render_token
    # gets a new random value each time the UI is (re-)created.  We watch
    # it here: ignoreInit = TRUE skips the first render (handled by the
    # article-load observer), so this fires only on RE-renders.
    observeEvent(input$ui_render_token, {
      raw <- stored_raw()
      if (is.null(raw) || length(raw) == 0) return()
      # Also restore the computed result badge
      # Same phased restore as the initial load, but without DB roundtrip
      shinyjs::delay(600, {
        .update_input_safe("study_method",             raw$study_method)
        .update_input_safe("response_scale",           raw$response_scale)
        .update_input_safe("response_distribution",    raw$response_distribution)
        .update_input_safe("response_variable_name",   raw$response_variable_name)
        .update_input_safe("response_unit",            raw$response_unit)
        .update_input_safe("predictor_distribution",   raw$predictor_distribution)
        .update_input_safe("predictor_variable_name",  raw$predictor_variable_name)
        .update_input_safe("predictor_unit",           raw$predictor_unit)
        .update_input_safe("interaction_effect",       raw$interaction_effect)
        .update_input_safe("study_design",             raw$study_design)
        shinyjs::delay(900, {
          design <- raw$study_design %||% ""
          .restore_design_fields(raw, "")
          if (design == "interaction") {
            .update_input_safe("interaction_pathway",  raw$interaction_pathway)
            shinyjs::delay(700, {
              pathway <- raw$interaction_pathway %||% "A"
              if (pathway == "A") {
                .restore_interaction_a(raw, "")
              } else {
                .update_input_safe("grpA_study_design", raw$group_a$study_design)
                .update_input_safe("grpB_study_design", raw$group_b$study_design)
                shinyjs::delay(700, {
                  if (!is.null(raw$group_a))
                    .restore_design_fields(raw$group_a, "grpA_")
                  if (!is.null(raw$group_b))
                    .restore_design_fields(raw$group_b, "grpB_")
                })
              }
            })
          }
        })
      })
    }, ignoreInit = TRUE)

    # ---- Return reactive: collected inputs (for the parent module) ----
    return(list(
      collect_inputs = collect_es_inputs,
      result         = es_result
    ))
  })
}
