# ============================================================
# modules/mod_dashboard.R — Project dashboard
# ============================================================
# Phase 1: Placeholder showing session info and a project list stub.
# Phase 3: Full project CRUD, member management.

mod_dashboard_ui <- function(id) {
  ns <- NS(id)
  nav_panel(
    title = "Dashboard",
    icon  = icon("home"),
    value = "dashboard",
    br(),
    fluidRow(
      col_md = 12,
      div(class = "d-flex justify-content-between align-items-center mb-3",
        h3("My Projects"),
        actionButton(ns("btn_new_project"), "＋ New Project",
                     class = "btn-primary")
      )
    ),
    fluidRow(
      column(6,
        h5("Projects I Own"),
        uiOutput(ns("owned_projects"))
      ),
      column(6,
        h5("Projects I've Joined"),
        uiOutput(ns("joined_projects"))
      )
    ),
    # Logout link in footer area
    hr(),
    div(class = "text-end",
      actionLink(ns("btn_logout"), "Log out", icon = icon("sign-out-alt"))
    )
  )
}

mod_dashboard_server <- function(id, session_rv) {
  moduleServer(id, function(input, output, session) {

    # ---- Load projects --------------------------------------
    projects <- reactive({
      req(session_rv$token, session_rv$user_id)
      tryCatch(
        sb_get("projects",
               filters = list(owner_id = session_rv$user_id),
               token   = session_rv$token),
        error = function(e) {
          showNotification(paste("Could not load projects:", e$message), type = "error")
          data.frame()
        }
      )
    })

    output$owned_projects <- renderUI({
      df <- projects()
      if (is.null(df) || nrow(df) == 0) {
        return(p(class = "text-muted", "No projects yet. Click '+ New Project' to start."))
      }
      lapply(seq_len(nrow(df)), function(i) {
        card(class = "mb-2",
          card_body(
            div(class = "d-flex justify-content-between",
              div(
                strong(df$title[i]),
                br(),
                small(class = "text-muted", df$description[i])
              ),
              actionButton(
                paste0("open_", df$project_id[i]),
                "Open", class = "btn-sm btn-outline-primary"
              )
            )
          )
        )
      })
    })

    output$joined_projects <- renderUI({
      # STUB — Phase 3 will query project_members for joined projects
      p(class = "text-muted", "Projects you have been invited to will appear here.")
    })

    # ---- New Project modal ----------------------------------
    observeEvent(input$btn_new_project, {
      # STUB — Phase 3 implements the Create Project modal
      showModal(modalDialog(
        title  = "New Project",
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_new_project", "Create", class = "btn-primary")
        ),
        textInput("new_proj_title", "Project Title"),
        textAreaInput("new_proj_desc", "Description (optional)", rows = 3)
      ))
    })

    # ---- Logout ---------------------------------------------
    observeEvent(input$btn_logout, {
      session_rv$token      <- NULL
      session_rv$user_id    <- NULL
      session_rv$username   <- NULL
      session_rv$expires_at <- NULL
    })
  })
}
