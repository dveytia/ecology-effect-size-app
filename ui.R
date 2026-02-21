# ============================================================
# ui.R — Top-level UI definition
# ============================================================
# Assembles all page modules into a single-page bslib app.
# Authentication state determines which page is shown.

ui <- page_fluid(
  theme = bs_theme(
    version  = 5,
    bootswatch = "flatly",
    primary  = "#2C7A4B",   # ecology-themed green
    font_scale = 0.95
  ),

  useShinyjs(),

  # Include custom assets
  tags$head(
    tags$link(rel = "stylesheet", href = "custom.css"),
    tags$script(src = "tooltips.js")
  ),

  # ---- Page router ------------------------------------------
  # uiOutput toggles between the login page and the app shell
  # based on session state (managed in server.R).
  uiOutput("page_router")
)
