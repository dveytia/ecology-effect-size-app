# ============================================================
# modules/mod_label_builder.R — Label builder tab
# ============================================================
# Implemented in Phase 4. Stub only.

mod_label_builder_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Label Builder"),
    p(class = "text-muted", "Phase 4: Configure the label schema for this project.")
  )
}

mod_label_builder_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 4 implementation
  })
}
