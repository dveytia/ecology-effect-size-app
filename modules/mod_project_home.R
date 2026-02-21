# ============================================================
# modules/mod_project_home.R — Project home tabs container
# ============================================================
# Implemented in Phase 3+. Stub only.

mod_project_home_ui <- function(id) {
  ns <- NS(id)
  navset_tab(
    id = ns("project_tabs"),
    nav_panel("Review",         uiOutput(ns("review_tab"))),
    nav_panel("Labels",         uiOutput(ns("labels_tab"))),
    nav_panel("Upload",         uiOutput(ns("upload_tab"))),
    nav_panel("Upload History", uiOutput(ns("upload_mgmt_tab"))),
    nav_panel("Export",         uiOutput(ns("export_tab"))),
    nav_panel("Audit Log",      uiOutput(ns("auditlog_tab")))
  )
}

mod_project_home_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 3+ implementation
  })
}
