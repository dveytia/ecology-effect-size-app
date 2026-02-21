# ============================================================
# modules/mod_audit_log.R — Audit log viewer tab
# ============================================================
# Implemented in Phase 11. Stub only.

mod_audit_log_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Audit Log"),
    p(class = "text-muted", "Phase 11: View all save/skip/delete actions with before/after snapshots.")
  )
}

mod_audit_log_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 11 implementation
  })
}
