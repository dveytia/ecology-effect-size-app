# ============================================================
# server.R — Top-level server
# ============================================================
# Routes reactive events to the appropriate module server.
# All persistent state lives in Supabase; session state lives
# in the `session_rv` reactiveValues object below.

server <- function(input, output, session) {

  # ---- Shared session state ---------------------------------
  # Populated by mod_auth on successful login.
  session_rv <- reactiveValues(
    token      = NULL,   # JWT access token
    user_id    = NULL,   # UUID from Supabase auth.users
    username   = NULL,
    expires_at = NULL    # POSIXct; refreshed automatically
  )

  # ---- Page router ------------------------------------------
  # Renders the login page or the main app shell depending on
  # whether the user has an active JWT session.
  output$page_router <- renderUI({
    if (is.null(session_rv$token)) {
      mod_auth_ui("auth")
    } else {
      tagList(
        # Top navbar with project title and logout
        navbarPage(
          title = "Ecology Effect Size Coder",
          id    = "main_nav",
          collapsible = TRUE,
          mod_dashboard_ui("dashboard")
        )
      )
    }
  })

  # ---- Module servers ---------------------------------------
  mod_auth_server("auth", session_rv = session_rv)

  # Dashboard is only active once logged in
  observeEvent(session_rv$token, {
    req(session_rv$token)
    mod_dashboard_server("dashboard", session_rv = session_rv)
  }, once = TRUE)
}
