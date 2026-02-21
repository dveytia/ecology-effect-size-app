# ============================================================
# modules/mod_export.R — Export tab
# ============================================================
# Implemented in Phase 10. Stub only.

mod_export_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Export"),
    p(class = "text-muted", "Phase 10: Download full CSV or meta-analysis-ready CSV.")
  )
}

mod_export_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 10 implementation
  })
}
