# ============================================================
# modules/mod_effect_size_ui.R — Effect size sub-form
# ============================================================
# Implemented in Phase 9. Stub only.

mod_effect_size_ui_ui <- function(id) {
  ns <- NS(id)
  div(
    h5("Effect Size"),
    p(class = "text-muted", "Phase 9: Conditional fields per study design.")
  )
}

mod_effect_size_ui_server <- function(id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 9 implementation
    # Returns: reactive list of effect size inputs for compute_effect_size()
  })
}
