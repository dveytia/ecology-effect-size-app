# ============================================================
# modules/mod_auth.R — Login / Register page
# ============================================================
# Phase 1: Basic UI skeleton (no real authentication yet).
# Phase 2: Full login, register, and session management.

mod_auth_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "d-flex justify-content-center align-items-center",
        style = "min-height: 100vh;",
      card(
        max_width  = "400px",
        card_header(
          h4("Ecology Effect Size Coder", class = "mb-0 text-center")
        ),
        card_body(
          # Tab switcher: Login vs Register
          navset_tab(
            id = ns("auth_tab"),
            nav_panel("Log In",
              br(),
              textInput(ns("login_email"),    "Email",    placeholder = "you@example.com"),
              passwordInput(ns("login_pw"),   "Password", placeholder = "••••••••"),
              br(),
              actionButton(ns("btn_login"),   "Log In",
                           class = "btn-primary w-100"),
              br(), br(),
              uiOutput(ns("login_msg"))
            ),
            nav_panel("Register",
              br(),
              textInput(ns("reg_email"),      "Email",           placeholder = "you@example.com"),
              passwordInput(ns("reg_pw"),     "Password",        placeholder = "min. 8 characters"),
              passwordInput(ns("reg_pw2"),    "Confirm password", placeholder = "••••••••"),
              br(),
              actionButton(ns("btn_register"), "Create Account",
                           class = "btn-success w-100"),
              br(), br(),
              uiOutput(ns("reg_msg"))
            )
          )
        )
      )
    )
  )
}

mod_auth_server <- function(id, session_rv) {
  moduleServer(id, function(input, output, session) {

    # ---- Login ----------------------------------------------
    observeEvent(input$btn_login, {
      req(input$login_email, input$login_pw)
      output$login_msg <- renderUI(NULL)

      tryCatch({
        result <- sb_auth_login(input$login_email, input$login_pw)

        session_rv$token      <- result$access_token
        session_rv$user_id    <- result$user$id
        session_rv$username   <- result$user$email   # username set after Phase 2
        session_rv$expires_at <- unix_to_posixct(result$expires_at)
        # Store refresh token for auto-refresh (Phase 2)
        session_rv$refresh_token <- result$refresh_token

      }, error = function(e) {
        output$login_msg <- renderUI(
          div(class = "alert alert-danger", as.character(e$message))
        )
      })
    })

    # ---- Register -------------------------------------------
    observeEvent(input$btn_register, {
      req(input$reg_email, input$reg_pw, input$reg_pw2)
      output$reg_msg <- renderUI(NULL)

      if (input$reg_pw != input$reg_pw2) {
        output$reg_msg <- renderUI(
          div(class = "alert alert-danger", "Passwords do not match.")
        )
        return()
      }
      if (nchar(input$reg_pw) < 8) {
        output$reg_msg <- renderUI(
          div(class = "alert alert-danger", "Password must be at least 8 characters.")
        )
        return()
      }

      tryCatch({
        result <- sb_auth_register(input$reg_email, input$reg_pw)

        if (!is.null(result$access_token)) {
          # Auto log in after registration if Supabase returns a token
          session_rv$token      <- result$access_token
          session_rv$user_id    <- result$user$id
          session_rv$username   <- result$user$email
          session_rv$expires_at <- unix_to_posixct(result$expires_at)
          session_rv$refresh_token <- result$refresh_token
        } else {
          # Supabase may require email confirmation
          output$reg_msg <- renderUI(
            div(class = "alert alert-success",
                "Account created! Check your email to confirm your address, then log in.")
          )
        }
      }, error = function(e) {
        output$reg_msg <- renderUI(
          div(class = "alert alert-danger", as.character(e$message))
        )
      })
    })
  })
}
