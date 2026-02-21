# ============================================================
# modules/mod_dashboard.R — Project dashboard
# ============================================================
# Phase 3: Full project CRUD and membership management.
#
# UI action buttons in card rows use Shiny.setInputValue() in their
# onclick attribute to pass the project UUID as the input value.
# A single observeEvent per action type handles all projects,
# avoiding the need to manage per-project dynamic observers.
# ============================================================

mod_dashboard_ui <- function(id) {
  ns <- NS(id)
  tagList(
    useShinyjs(),
    div(class = "container-fluid py-4",
      # ---- Header row ----------------------------------------
      fluidRow(
        column(12,
          div(class = "d-flex justify-content-between align-items-center mb-4",
            h3(class = "mb-0", icon("leaf"), " My Projects"),
            actionButton(ns("btn_new_project"),
                         label = tagList(icon("plus"), " New Project"),
                         class = "btn btn-primary")
          )
        )
      ),
      # ---- Two-column layout ---------------------------------
      fluidRow(
        column(6,
          h5(icon("user"), " Projects I Own"),
          uiOutput(ns("owned_projects"))
        ),
        column(6,
          h5(icon("users"), " Projects I've Joined"),
          uiOutput(ns("joined_projects"))
        )
      ),
      hr(),
      div(class = "text-end",
        actionLink(ns("btn_logout"),
                   label = tagList(icon("sign-out-alt"), " Log out"))
      )
    )
  )
}

# ---- Server -------------------------------------------------
mod_dashboard_server <- function(id, session_rv, app_state) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Refresh counter ------------------------------------
    # Increment after any CRUD or membership operation to force
    # the project lists to reload from Supabase.
    refresh_trigger <- reactiveVal(0)

    # ---- Load owned projects --------------------------------
    owned_projects <- reactive({
      refresh_trigger()
      req(session_rv$token, session_rv$user_id)
      tryCatch(
        sb_get("projects",
               filters = list(owner_id = session_rv$user_id),
               token   = session_rv$token),
        error = function(e) {
          showNotification(paste("Could not load projects:", e$message),
                           type = "error")
          data.frame()
        }
      )
    })

    # ---- Load joined projects (reviewer role only) ----------
    joined_projects <- reactive({
      refresh_trigger()
      req(session_rv$token, session_rv$user_id)
      tryCatch({
        mems <- sb_get("project_members",
                       filters = list(user_id = session_rv$user_id,
                                      role    = "reviewer"),
                       select  = "project_id,role",
                       token   = session_rv$token)
        if (is.null(mems) || !is.data.frame(mems) || nrow(mems) == 0)
          return(data.frame())

        ids_str <- paste0("(", paste(mems$project_id, collapse = ","), ")")
        sb_get("projects",
               filters = list(project_id = paste0("in.", ids_str)),
               token   = session_rv$token)
      }, error = function(e) {
        showNotification(paste("Could not load joined projects:", e$message),
                         type = "error")
        data.frame()
      })
    })

    # ---- Render owned project cards -------------------------
    output$owned_projects <- renderUI({
      df <- owned_projects()
      if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) {
        return(
          div(class = "text-muted fst-italic py-3",
              icon("info-circle"), " No projects yet. Click '+ New Project' to start.")
        )
      }
      lapply(seq_len(nrow(df)), function(i) {
        pid   <- df$project_id[i]
        ptitle <- df$title[i]
        pdesc  <- if (is.na(df$description[i])) "" else df$description[i]
        div(class = "card mb-3 shadow-sm",
          div(class = "card-body",
            div(class = "d-flex justify-content-between align-items-start gap-2",
              div(class = "flex-grow-1",
                tags$strong(ptitle),
                if (nchar(pdesc) > 0)
                  div(class = "text-muted small mt-1", pdesc)
              ),
              div(class = "btn-group btn-group-sm flex-shrink-0",
                # Open — sets input$open_project = pid
                tags$button(
                  class   = "btn btn-outline-primary",
                  title   = "Open project",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("open_project"), pid),
                  icon("folder-open"), " Open"
                ),
                # Edit
                tags$button(
                  class   = "btn btn-outline-secondary",
                  title   = "Edit project details",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("edit_project"), pid),
                  icon("pencil-alt"), " Edit"
                ),
                # Invite member
                tags$button(
                  class   = "btn btn-outline-success",
                  title   = "Invite a member",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("invite_project"), pid),
                  icon("user-plus"), " Invite"
                ),
                # Delete
                tags$button(
                  class   = "btn btn-outline-danger",
                  title   = "Delete project",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("delete_project"), pid),
                  icon("trash-alt"), " Delete"
                )
              )
            )
          )
        )
      })
    })

    # ---- Render joined project cards ------------------------
    output$joined_projects <- renderUI({
      df <- joined_projects()
      if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) {
        return(
          div(class = "text-muted fst-italic py-3",
              icon("info-circle"),
              " Projects you have been invited to will appear here.")
        )
      }
      lapply(seq_len(nrow(df)), function(i) {
        pid    <- df$project_id[i]
        ptitle <- df$title[i]
        pdesc  <- if (is.na(df$description[i])) "" else df$description[i]
        div(class = "card mb-3 shadow-sm border-start border-primary border-3",
          div(class = "card-body",
            div(class = "d-flex justify-content-between align-items-start gap-2",
              div(class = "flex-grow-1",
                tags$strong(ptitle),
                span(class = "badge bg-primary ms-2 small", "Reviewer"),
                if (nchar(pdesc) > 0)
                  div(class = "text-muted small mt-1", pdesc)
              ),
              div(class = "btn-group btn-group-sm flex-shrink-0",
                tags$button(
                  class   = "btn btn-outline-primary",
                  title   = "Open project",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("open_project"), pid),
                  icon("folder-open"), " Open"
                ),
                tags$button(
                  class   = "btn btn-outline-warning",
                  title   = "Leave this project",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                    ns("leave_project"), pid),
                  icon("sign-out-alt"), " Leave"
                )
              )
            )
          )
        )
      })
    })

    # ===========================================================
    # ACTION: Open project
    # ===========================================================
    observeEvent(input$open_project, {
      pid    <- input$open_project
      df_own <- owned_projects()
      df_jnd <- joined_projects()
      # Find project title across both lists
      all_df <- if (is.data.frame(df_own) && nrow(df_own) > 0)
                  rbind(df_own, if (is.data.frame(df_jnd)) df_jnd else data.frame())
                else
                  if (is.data.frame(df_jnd)) df_jnd else data.frame()
      ptitle <- if (nrow(all_df) > 0 && pid %in% all_df$project_id)
                  all_df$title[all_df$project_id == pid][1]
                else "Project"
      app_state$current_project_id    <- pid
      app_state$current_project_title <- ptitle
    })

    # ===========================================================
    # ACTION: Create project — modal
    # ===========================================================
    observeEvent(input$btn_new_project, {
      showModal(modalDialog(
        title  = "New Project",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_new_project"), "Create",
                       class = "btn btn-primary")
        ),
        textInput(ns("new_proj_title"), "Project Title *",
                  placeholder = "e.g. Climate Change Meta-analysis 2025"),
        textAreaInput(ns("new_proj_desc"), "Description (optional)",
                      rows = 3,
                      placeholder = "Brief summary of the project scope")
      ))
    })

    observeEvent(input$confirm_new_project, {
      title <- trimws(input$new_proj_title)
      if (nchar(title) == 0) {
        showNotification("Project title is required.", type = "warning")
        return()
      }
      tryCatch({
        sb_post("projects",
          list(owner_id    = session_rv$user_id,
               title       = title,
               description = trimws(input$new_proj_desc)),
          token = session_rv$token)
        removeModal()
        refresh_trigger(refresh_trigger() + 1)
        showNotification(paste0("'", title, "' created."), type = "message")
      }, error = function(e) {
        showNotification(paste("Error creating project:", e$message), type = "error")
      })
    })

    # ===========================================================
    # ACTION: Edit project — modal
    # ===========================================================
    editing_project <- reactiveVal(NULL)

    observeEvent(input$edit_project, {
      pid <- input$edit_project
      df  <- owned_projects()
      row <- df[df$project_id == pid, , drop = FALSE]
      if (nrow(row) == 0) return()
      editing_project(row)
      showModal(modalDialog(
        title  = "Edit Project",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_edit_project"), "Save Changes",
                       class = "btn btn-primary")
        ),
        textInput(ns("edit_proj_title"), "Project Title *",
                  value = row$title[1]),
        textAreaInput(ns("edit_proj_desc"), "Description",
                      value = if (is.na(row$description[1])) "" else row$description[1],
                      rows  = 3)
      ))
    })

    observeEvent(input$confirm_edit_project, {
      row   <- editing_project()
      title <- trimws(input$edit_proj_title)
      if (is.null(row) || nchar(title) == 0) {
        showNotification("Project title is required.", type = "warning")
        return()
      }
      tryCatch({
        sb_patch("projects", "project_id", row$project_id[1],
          list(title       = title,
               description = trimws(input$edit_proj_desc)),
          token = session_rv$token)
        removeModal()
        editing_project(NULL)
        refresh_trigger(refresh_trigger() + 1)
        showNotification("Project updated.", type = "message")
      }, error = function(e) {
        showNotification(paste("Error updating project:", e$message), type = "error")
      })
    })

    # ===========================================================
    # ACTION: Delete project — confirmation modal
    # ===========================================================
    deleting_project_id <- reactiveVal(NULL)

    observeEvent(input$delete_project, {
      pid <- input$delete_project
      df  <- owned_projects()
      row <- df[df$project_id == pid, , drop = FALSE]
      if (nrow(row) == 0) return()
      deleting_project_id(pid)
      showModal(modalDialog(
        title  = "Delete Project?",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_delete_project"), "Delete Permanently",
                       class = "btn btn-danger")
        ),
        p("You are about to permanently delete:",
          tags$strong(row$title[1])),
        div(class = "alert alert-danger",
          icon("exclamation-triangle"),
          " This action cannot be undone. All articles, labels, effect sizes,",
          " and audit log entries within this project will be permanently deleted."
        )
      ))
    })

    observeEvent(input$confirm_delete_project, {
      pid <- deleting_project_id()
      req(pid)
      tryCatch({
        sb_delete("projects", "project_id", pid, token = session_rv$token)
        removeModal()
        deleting_project_id(NULL)
        refresh_trigger(refresh_trigger() + 1)
        showNotification("Project deleted.", type = "message")
      }, error = function(e) {
        showNotification(paste("Error deleting project:", e$message), type = "error")
      })
    })

    # ===========================================================
    # ACTION: Invite member — modal with email lookup
    # ===========================================================
    invite_project_id <- reactiveVal(NULL)

    observeEvent(input$invite_project, {
      pid <- input$invite_project
      invite_project_id(pid)
      showModal(modalDialog(
        title  = "Invite Member",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_invite"), "Send Invitation",
                       class = "btn btn-success")
        ),
        p("Enter the registered email address of the person you want to invite."),
        p(class = "text-muted small",
          icon("info-circle"),
          " The user must already have an account. Share the app URL with them",
          " first if they have not registered yet."),
        textInput(ns("invite_email"), "Email address",
                  placeholder = "colleague@university.edu"),
        uiOutput(ns("invite_feedback"))
      ))
    })

    observeEvent(input$confirm_invite, {
      pid   <- invite_project_id()
      email <- trimws(tolower(input$invite_email %||% ""))
      if (is.null(pid) || nchar(email) == 0) {
        showNotification("Please enter an email address.", type = "warning")
        return()
      }

      tryCatch({
        # Use service key to search users table (bypasses per-user RLS).
        # The service key is only available server-side in .Renviron;
        # it is never sent to the browser.
        svc <- Sys.getenv("SUPABASE_SERVICE_KEY")
        if (nchar(svc) == 0)
          stop("SUPABASE_SERVICE_KEY is not configured on this server.")

        user_rows <- sb_get("users",
                            filters = list(email = email),
                            select  = "user_id,email",
                            token   = svc)

        if (is.null(user_rows) || !is.data.frame(user_rows) ||
            nrow(user_rows) == 0) {
          output$invite_feedback <- renderUI(
            div(class = "alert alert-warning mt-2",
                icon("user-times"),
                sprintf(" No account found for '%s'.", email),
                "Ask them to register first, then try again.")
          )
          return()
        }

        target_uid <- user_rows$user_id[1]

        if (target_uid == session_rv$user_id) {
          output$invite_feedback <- renderUI(
            div(class = "alert alert-warning mt-2",
                "You cannot invite yourself — you already own this project.")
          )
          return()
        }

        # Check not already a member
        existing <- sb_get("project_members",
                           filters = list(project_id = pid,
                                          user_id    = target_uid),
                           token   = session_rv$token)
        if (!is.null(existing) && is.data.frame(existing) && nrow(existing) > 0) {
          output$invite_feedback <- renderUI(
            div(class = "alert alert-info mt-2",
                icon("info-circle"),
                sprintf(" '%s' is already a member of this project.", email))
          )
          return()
        }

        # Insert reviewer membership
        sb_post("project_members",
          list(project_id = pid,
               user_id    = target_uid,
               role       = "reviewer"),
          token = session_rv$token)

        removeModal()
        showNotification(sprintf("'%s' has been invited as a reviewer.", email),
                         type = "message")
      }, error = function(e) {
        showNotification(paste("Error inviting member:", e$message), type = "error")
      })
    })

    # ===========================================================
    # ACTION: Leave project — confirmation modal (reviewers only)
    # ===========================================================
    leaving_project_id <- reactiveVal(NULL)

    observeEvent(input$leave_project, {
      pid <- input$leave_project
      df  <- joined_projects()
      row <- df[df$project_id == pid, , drop = FALSE]
      if (nrow(row) == 0) return()
      leaving_project_id(pid)
      showModal(modalDialog(
        title  = "Leave Project?",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_leave"), "Leave Project",
                       class = "btn btn-warning")
        ),
        p("You are about to leave:", tags$strong(row$title[1])),
        p(class = "text-muted small",
          "The project owner can invite you back at any time.")
      ))
    })

    observeEvent(input$confirm_leave, {
      pid <- leaving_project_id()
      req(pid)
      tryCatch({
        # Delete composite-key row: project_id AND user_id
        sb_delete_where("project_members",
                        filters = list(project_id = pid,
                                       user_id    = session_rv$user_id),
                        token   = session_rv$token)
        removeModal()
        leaving_project_id(NULL)
        refresh_trigger(refresh_trigger() + 1)
        showNotification("You have left the project.", type = "message")
      }, error = function(e) {
        showNotification(paste("Error leaving project:", e$message), type = "error")
      })
    })

    # ===========================================================
    # ACTION: Logout
    # ===========================================================
    observeEvent(input$btn_logout, {
      session_rv$token         <- NULL
      session_rv$user_id       <- NULL
      session_rv$username      <- NULL
      session_rv$expires_at    <- NULL
      session_rv$refresh_token <- NULL
    })

  })
}
