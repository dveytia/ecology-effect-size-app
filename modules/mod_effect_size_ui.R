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
        selectInput(ns("study_design"), "Study design",
                    choices = .study_design_choices),

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
                      tags$span("Variability type",
                        title = "What type of variability is reported?"),
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
                       tags$span("t-statistic",
                         title = 'Look for t = or a value in parentheses, e.g. t(24) = 2.3'),
                       value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("df"),
                       tags$span("Degrees of freedom (df)",
                         title = 'Look for \"df =\", or the number in parentheses after t, e.g. t(24): df = 24. For F(1, 45): df = 45 (use the second number).'),
                       value = NA_real_)
        )
      )
    ),
    # Fallback 2: F-stat (shares df from above)
    div(class = "es-pathway-c",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("F_stat"),
                       tags$span("F-statistic",
                         title = "Look for F = in ANOVA tables"),
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
                       tags$span("r (reported)",
                         title = "Pearson r or Spearman rho as reported. Range: -1 to 1"),
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
                       tags$span("t-statistic",
                         title = 'Look for t = or a value in parentheses'),
                       value = NA_real_)
        ),
        div(class = "col-md-6",
          numericInput(p("df"),
                       tags$span("Degrees of freedom",
                         title = "For correlation tests, df is usually n \u2212 2."),
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
      "Primary: t-stat + df \u2192 r"                   = "es-pathway-a",
      "Fallback: \u03b2 \u00d7 (SD_X / SD_Y) \u2192 r" = "es-pathway-b"
    )),
    # Primary: t-stat path
    div(class = "es-pathway-a",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("t_stat"),
                       tags$span("t-statistic",
                         title = "t-statistic for the coefficient"),
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("df"),
                       tags$span("Residual df",
                         title = 'Look for df in regression output. For F(1, 45), use 45 (the second number).'),
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("n"), "Sample size (n)", value = NA_integer_, step = 1)
        )
      )
    ),
    # Fallback: beta + SDs
    div(class = "es-pathway-b",
      div(class = "row g-2",
        div(class = "col-md-4",
          numericInput(p("beta"), "Regression coefficient (\u03b2)",
                       value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("sd_X"), "SD of predictor", value = NA_real_)
        ),
        div(class = "col-md-4",
          numericInput(p("sd_Y"), "SD of response", value = NA_real_)
        )
      )
    ),
    # Additional fields (not pathway-specific)
    div(class = "row g-2",
      div(class = "col-md-4",
        numericInput(p("se_beta"), "SE of \u03b2", value = NA_real_)
      ),
      div(class = "col-md-4",
        numericInput(p("p_value"), "p-value", value = NA_real_)
      )
    ),
    checkboxInput(p("multiple_predictors"),
                  tags$span("Multiple predictors",
                    title = "Check if the model contains more than one predictor"),
                  value = FALSE)
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
                       tags$span("t-statistic",
                         title = "t-statistic for the interaction term"),
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
                                       on_save_trigger) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Stored result (from last save/load) ----
    es_result <- reactiveVal(NULL)

    # ---- Load existing effect size data when article changes ----
    observeEvent(article_id_reactive(), {
      aid <- article_id_reactive()
      es_result(NULL)   # clear previous result
      if (is.null(aid)) return()
      tryCatch({
        rows <- sb_get("effect_sizes",
          filters = list(article_id = aid),
          token   = session_rv$token)
        if (is.data.frame(rows) && nrow(rows) > 0) {
          row <- rows[1, ]   # first effect size for this article
          raw <- tryCatch({
            if (is.character(row$raw_effect_json))
              jsonlite::fromJSON(row$raw_effect_json, simplifyVector = FALSE)
            else if (is.list(row$raw_effect_json))
              row$raw_effect_json
            else
              list()
          }, error = function(e) list())

          # Populate general fields
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

          # Populate design-specific fields after a short delay
          # so the conditional panel has time to render
          shinyjs::delay(300, {
            design <- raw$study_design %||% ""
            .restore_design_fields(raw, "")

            # Interaction fields
            if (design == "interaction") {
              .update_input_safe("interaction_pathway",  raw$interaction_pathway)
              shinyjs::delay(200, {
                pathway <- raw$interaction_pathway %||% "A"
                if (pathway == "A") {
                  .restore_interaction_a(raw, "")
                } else {
                  # Pathway B: group A and group B
                  .update_input_safe("grpA_study_design", raw$group_a$study_design)
                  .update_input_safe("grpB_study_design", raw$group_b$study_design)
                  shinyjs::delay(200, {
                    if (!is.null(raw$group_a))
                      .restore_design_fields(raw$group_a, "grpA_")
                    if (!is.null(raw$group_b))
                      .restore_design_fields(raw$group_b, "grpB_")
                  })
                }
              })
            }
          })

          # Show stored result
          es_result(list(
            r               = row$r,
            z               = row$z,
            var_z           = row$var_z,
            effect_status   = row$effect_status,
            effect_warnings = if (is.character(row$effect_warnings))
                                row$effect_warnings
                              else if (is.list(row$effect_warnings))
                                unlist(row$effect_warnings)
                              else character(0)
          ))
        } else {
          # No existing effect size — reset all fields
          .reset_all_fields()
        }
      }, error = function(e) {
        message("[mod_effect_size_ui] load error: ", e$message)
        .reset_all_fields()
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
          if (grepl("^(study_design|study_method|response_scale|response_distribution|predictor_distribution|var_statistic_type|interaction_pathway|grpA_study_design|grpB_study_design)$", input_id) ||
              grepl("^grp[AB]_var_statistic_type$", input_id)) {
            updateSelectInput(session, input_id, selected = val)
          } else if (grepl("(mean_|var_value_|n_control|n_treatment|t_stat|F_stat|chi_square|p_value|df|r_reported|se_r|covariance|sd_X|sd_Y|beta|se_beta|interaction_term|se_interaction|^n$)", input_id)) {
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
        .update_input_safe(paste0(prefix, "se_beta"),             raw$se_beta)
        .update_input_safe(paste0(prefix, "n"),                   raw$n)
        .update_input_safe(paste0(prefix, "t_stat"),              raw$t_stat)
        .update_input_safe(paste0(prefix, "p_value"),             raw$p_value)
        .update_input_safe(paste0(prefix, "df"),                  raw$df)
        .update_input_safe(paste0(prefix, "sd_X"),                raw$sd_X)
        .update_input_safe(paste0(prefix, "sd_Y"),                raw$sd_Y)
        .update_input_safe(paste0(prefix, "multiple_predictors"), raw$multiple_predictors)
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
      for (fld in c("study_method", "response_scale", "response_distribution",
                     "predictor_distribution", "study_design")) {
        updateSelectInput(session, fld, selected = "")
      }
      for (fld in c("response_variable_name", "response_unit",
                     "predictor_variable_name", "predictor_unit")) {
        updateTextInput(session, fld, value = "")
      }
      updateCheckboxInput(session, "interaction_effect", value = FALSE)
      es_result(NULL)
    }

    # ---- Design-specific conditional panels ----
    output$design_fields <- renderUI({
      design <- input$study_design %||% ""
      is_interaction <- isTRUE(input$interaction_effect)

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
        "interaction"       = .render_interaction_ui(ns),
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

        r_fmt    <- if (!is.null(res$r))     sprintf("%.4f", res$r)     else "NA"
        z_fmt    <- if (!is.null(res$z))     sprintf("%.4f", res$z)     else "NA"
        vz_fmt   <- if (!is.null(res$var_z)) sprintf("%.4f", res$var_z) else "NA"

        div(class = "card border-success mt-3",
          div(class = "card-header py-2 bg-success bg-opacity-10",
            div(class = "d-flex align-items-center gap-2",
              icon("check-circle", class = "text-success"),
              strong("Computed Effect Size"),
              status_badge
            )
          ),
          div(class = "card-body py-2",
            div(class = "row g-2",
              div(class = "col-md-4",
                tags$dl(class = "mb-0",
                  tags$dt(class = "small text-muted", "Pearson r"),
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
      if (nchar(design) == 0) return(NULL)

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
        interaction_effect       = isTRUE(input$interaction_effect),
        study_design             = design
      )

      # Time trend: use regression + set predictor_distribution = Time
      if (design == "time_trend") {
        result$predictor_distribution <- "Time"
      }

      # Design-specific fields
      if (design == "control_treatment") {
        result <- c(result, .collect_ct_fields(""))

      } else if (design == "correlation") {
        result <- c(result, .collect_corr_fields(""))

      } else if (design == "regression" || design == "time_trend") {
        result <- c(result, .collect_regression_fields(""))

      } else if (design == "interaction") {
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
      }

      result
    }

    # ---- Field collectors per design ----
    .safe_num <- function(val) {
      if (is.null(val)) return(NULL)
      v <- suppressWarnings(as.numeric(val))
      if (is.na(v)) return(NULL)
      v
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
        se_beta             = .safe_num(input[[paste0(prefix, "se_beta")]]),
        n                   = .safe_num(input[[paste0(prefix, "n")]]),
        t_stat              = .safe_num(input[[paste0(prefix, "t_stat")]]),
        p_value             = .safe_num(input[[paste0(prefix, "p_value")]]),
        df                  = .safe_num(input[[paste0(prefix, "df")]]),
        sd_X                = .safe_num(input[[paste0(prefix, "sd_X")]]),
        sd_Y                = .safe_num(input[[paste0(prefix, "sd_Y")]]),
        multiple_predictors = isTRUE(input[[paste0(prefix, "multiple_predictors")]])
      )
    }

    # ---- Calculate button: compute only (no DB write) ----
    observeEvent(input$btn_calculate, {
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

    # ---- On save trigger: compute effect size and upsert ----
    observeEvent(on_save_trigger(), {
      aid <- article_id_reactive()
      if (is.null(aid)) return()

      es_inputs <- collect_es_inputs()
      if (is.null(es_inputs)) {
        es_result(NULL)
        return()
      }

      # Run computation
      computed <- tryCatch(
        compute_effect_size(es_inputs),
        error = function(e) {
          message("[effect_size compute] error: ", e$message)
          list(r = NULL, z = NULL, var_z = NULL,
               effect_status = "insufficient_data",
               effect_warnings = c(paste("Computation error:", e$message)))
        }
      )

      # Build the raw JSON to store
      raw_json <- jsonlite::toJSON(es_inputs, auto_unbox = TRUE, null = "null")

      # Upsert to effect_sizes table
      tryCatch({
        # Check if an existing row exists for this article
        existing <- sb_get("effect_sizes",
          filters = list(article_id = aid),
          select  = "effect_id",
          token   = session_rv$token)

        body <- list(
          article_id       = aid,
          raw_effect_json  = raw_json,
          r                = computed$r,
          z                = computed$z,
          var_z            = computed$var_z,
          effect_status    = computed$effect_status %||% "insufficient_data",
          effect_warnings  = if (length(computed$effect_warnings) > 0)
                               as.list(computed$effect_warnings)
                             else list(),
          computed_at      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
        )

        if (is.data.frame(existing) && nrow(existing) > 0) {
          # Update existing
          sb_patch("effect_sizes", "effect_id",
                   existing$effect_id[1], body,
                   token = session_rv$token)
        } else {
          # Insert new
          sb_post("effect_sizes", body, token = session_rv$token)
        }
      }, error = function(e) {
        showNotification(paste("Effect size save failed:", e$message),
                         type = "warning")
        message("[effect_size save] error: ", e$message)
      })

      # Update result display
      es_result(computed)

    }, ignoreInit = TRUE)

    # ---- Return reactive: collected inputs (for the parent module) ----
    return(list(
      collect_inputs = collect_es_inputs,
      result         = es_result
    ))
  })
}
