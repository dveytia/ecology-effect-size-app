# ============================================================
# modules/mod_upload_management.R — Upload history tab
# ============================================================
# Implemented in Phase 5. Stub only.

mod_upload_management_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Upload History"),
    p(class = "text-muted", "Phase 5: Review upload batches and resolve duplicate flags.")
  )
}

mod_upload_management_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 5 implementation
  })
}
