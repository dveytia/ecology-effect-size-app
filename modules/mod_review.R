# ============================================================
# modules/mod_review.R — Main review interface
# ============================================================
# Implemented in Phase 7. Stub only.

mod_review_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Review Interface"),
    p(class = "text-muted", "Phase 7: Code articles with dynamic labels, effect sizes, and PDF viewer.")
  )
}

mod_review_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 7 implementation
  })
}
