# ============================================================
# server.R — Top-level server
# ============================================================
# Routes reactive events to the appropriate module server.
# All persistent state lives in Supabase; session state lives
# in the `session_rv` reactiveValues object below.
#
# Three-state page router (Phase 3):
#   1. No token          → login / register page
#   2. Token, no project → dashboard (My Projects)
#   3. Token + project   → project home (tabs view)
# ============================================================

server <- function(input, output, session) {

  # ---- Shared session state ---------------------------------
  # Populated by mod_auth on successful login.
  session_rv <- reactiveValues(
    token         = NULL,   # JWT access token
    user_id       = NULL,   # UUID from Supabase auth.users
    username      = NULL,
    expires_at    = NULL,   # POSIXct; refreshed automatically
    refresh_token = NULL    # Supabase refresh token (Phase 2)
  )

  # ---- App navigation state --------------------------------
  # Tracks which project (if any) is currently open.
  # Set to a project UUID by mod_dashboard when the user clicks
  # "Open"; cleared by mod_project_home when the user clicks
  # "← Dashboard".
  app_state <- reactiveValues(
    current_project_id    = NULL,
    current_project_title = NULL
  )

  # ---- Auto-refresh timer -----------------------------------
  # Fires every 30 seconds.  refresh_if_needed() only actually
  # contacts Supabase when the token is within 60 s of expiry,
  # so this is inexpensive in the normal case.
  .refresh_timer <- reactiveTimer(30000)

  observe({
    .refresh_timer()
    isolate({
      if (!is.null(session_rv$token)) {
        refresh_if_needed(session_rv)
        route_guard(session_rv)
      }
    })
  })

  # ---- Three-state page router ------------------------------
  output$page_router <- renderUI({
    if (is.null(session_rv$token)) {
      # State 1: not authenticated → login page
      mod_auth_ui("auth")
    } else if (!is.null(app_state$current_project_id)) {
      # State 3: inside a project → project home
      mod_project_home_ui("project_home")
    } else {
      # State 2: authenticated, no project open → dashboard
      tagList(
        navbarPage(
          title       = "Ecology Effect Size Coder",
          id          = "main_nav",
          collapsible = TRUE,
          nav_panel(
            title = tagList(icon("home"), " Dashboard"),
            value = "dashboard",
            mod_dashboard_ui("dashboard")
          )
        )
      )
    }
  })

  # ---- Module servers ---------------------------------------
  mod_auth_server("auth", session_rv = session_rv)

  # Dashboard and project home are both initialised once after
  # the first successful login.  They are kept alive for the
  # duration of the session; the page router simply shows or
  # hides their UI based on app_state$current_project_id.
  observeEvent(session_rv$token, {
    req(session_rv$token)

    mod_dashboard_server("dashboard",
                         session_rv = session_rv,
                         app_state  = app_state)

    mod_project_home_server("project_home",
                            project_id = reactive(app_state$current_project_id),
                            session_rv = session_rv,
                            app_state  = app_state)
  }, once = TRUE)
}

