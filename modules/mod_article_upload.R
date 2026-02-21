# ============================================================
# modules/mod_article_upload.R — Article upload tab
# ============================================================
# Implemented in Phase 5. Stub only.

mod_article_upload_ui <- function(id) {
  ns <- NS(id)
  div(
    h4("Upload Articles"),
    p(class = "text-muted", "Phase 5: Upload a CSV of articles (title, abstract, author, year, doi).")
  )
}

mod_article_upload_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    # STUB — Phase 5 implementation
  })
}
