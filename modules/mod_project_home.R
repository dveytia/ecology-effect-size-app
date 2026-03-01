# ============================================================
# modules/mod_project_home.R — Project home tabs container
# ============================================================
# Phase 3: Header with back-to-dashboard navigation + all tab
# stubs.  Members tab is fully implemented here (view members,
# remove a reviewer).  Remaining tabs are stubs filled in by
# later phases.
# ============================================================

mod_project_home_ui <- function(id) {
  ns <- NS(id)
  tagList(
    useShinyjs(),
    # ---- Project header bar --------------------------------
    div(class = "d-flex align-items-center px-3 py-2 border-bottom bg-light",
      actionButton(ns("btn_back"),
                   label = tagList(icon("arrow-left"), " Dashboard"),
                   class = "btn btn-sm btn-outline-secondary me-3"),
      h5(class = "mb-0 me-auto", uiOutput(ns("project_title_header"))),
      uiOutput(ns("project_owner_badge"))
    ),
    # ---- Tabs ----------------------------------------------
    navset_tab(
      id = ns("project_tabs"),
      nav_panel(title = tagList(icon("book-open"),   " Review"),
                value = "review",
                uiOutput(ns("review_tab"))),
      nav_panel(title = tagList(icon("tags"),         " Labels"),
                value = "labels",
                uiOutput(ns("labels_tab"))),
      nav_panel(title = tagList(icon("upload"),       " Upload"),
                value = "upload",
                uiOutput(ns("upload_tab"))),
      nav_panel(title = tagList(icon("history"),      " Upload History"),
                value = "upload_mgmt",
                uiOutput(ns("upload_mgmt_tab"))),
      nav_panel(title = tagList(icon("file-export"),  " Export"),
                value = "export",
                uiOutput(ns("export_tab"))),
      nav_panel(title = tagList(icon("clipboard-list"), " Audit Log"),
                value = "auditlog",
                uiOutput(ns("auditlog_tab"))),
      nav_panel(title = tagList(icon("users"),        " Members"),
                value = "members",
                uiOutput(ns("members_tab")))
    )
  )
}

# ---- Server -------------------------------------------------
mod_project_home_server <- function(id, project_id, session_rv, app_state) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Project title in header ----------------------------
    output$project_title_header <- renderUI({
      req(project_id())
      app_state$current_project_title %||% "Project"
    })

    # ---- Owner badge (shown when current user is owner) -----
    output$project_owner_badge <- renderUI({
      req(project_id())
      proj <- current_project()
      if (!is.null(proj) && !is.null(proj$owner_id) &&
          proj$owner_id == session_rv$user_id) {
        span(class = "badge bg-secondary", icon("crown"), " Owner")
      }
    })

    # ---- Load current project row ---------------------------
    current_project <- reactive({
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        rows <- sb_get("projects",
                       filters = list(project_id = pid),
                       token   = session_rv$token)
        if (is.data.frame(rows) && nrow(rows) > 0) as.list(rows[1, ]) else NULL
      }, error = function(e) NULL)
    })

    # ---- Members tab refresh trigger ------------------------
    members_refresh <- reactiveVal(0)

    # ---- Load project members -------------------------------
    project_members_df <- reactive({
      members_refresh()
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        # Get all members for this project
        mems <- sb_get("project_members",
                       filters = list(project_id = pid),
                       select  = "project_id,user_id,role",
                       token   = session_rv$token)
        if (!is.data.frame(mems) || nrow(mems) == 0) return(data.frame())

        # Fetch user details using service key (need emails/names)
        svc <- Sys.getenv("SUPABASE_SERVICE_KEY")
        if (nchar(svc) > 0) {
          uid_str <- paste0("(", paste(mems$user_id, collapse = ","), ")")
          users_df <- sb_get("users",
                             filters = list(user_id = paste0("in.", uid_str)),
                             select  = "user_id,email,username",
                             token   = svc)
          if (is.data.frame(users_df) && nrow(users_df) > 0) {
            mems <- merge(mems, users_df, by = "user_id", all.x = TRUE)
          }
        }
        mems
      }, error = function(e) {
        showNotification(paste("Could not load members:", e$message), type = "error")
        data.frame()
      })
    })

    # ---- Tab: stub helper -----------------------------------
    .stub_tab <- function(phase_num, tab_name, icon_name) {
      div(class = "container-fluid py-5 text-center text-muted",
        icon(icon_name, class = "fa-3x mb-3"),
        h4(tab_name),
        p(sprintf("This tab will be implemented in Phase %d.", phase_num))
      )
    }

    # ---- Shared upload refresh signal -----------------
    upload_refresh <- reactiveVal(0)

    # ---- Review tab (Phase 7) --------------------------------
    output$review_tab <- renderUI({
      req(project_id())
      mod_review_ui(ns("review"))
    })

    mod_review_server("review",
                      project_id     = project_id,
                      session_rv     = session_rv,
                      upload_refresh = upload_refresh)

    output$labels_tab <- renderUI({
      req(project_id())
      mod_label_builder_ui(ns("label_builder"))
    })

    mod_label_builder_server("label_builder",
                             project_id = project_id,
                             session_rv = session_rv)

    output$upload_tab <- renderUI({
      req(project_id())
      mod_article_upload_ui(ns("article_upload"))
    })

    mod_article_upload_server("article_upload",
                              project_id     = project_id,
                              session_rv     = session_rv,
                              upload_refresh = upload_refresh)

    output$upload_mgmt_tab <- renderUI({
      req(project_id())
      mod_upload_management_ui(ns("upload_mgmt"))
    })

    mod_upload_management_server("upload_mgmt",
                                 project_id     = project_id,
                                 session_rv     = session_rv,
                                 upload_refresh = upload_refresh)

    output$export_tab <- renderUI({
      req(project_id())
      mod_export_ui(ns("export"))
    })

    mod_export_server("export",
                      project_id = project_id,
                      session_rv = session_rv)

    output$auditlog_tab <- renderUI({
      req(project_id())
      mod_audit_log_ui(ns("audit_log"))
    })

    mod_audit_log_server("audit_log",
                         project_id = project_id,
                         session_rv = session_rv)

    # ---- Members tab ----------------------------------------
    output$members_tab <- renderUI({
      req(project_id())
      proj <- current_project()
      is_owner <- !is.null(proj) && !is.null(proj$owner_id) &&
                  proj$owner_id == session_rv$user_id

      div(class = "container py-4",
        div(class = "d-flex justify-content-between align-items-center mb-3",
          h5(class = "mb-0", icon("users"), " Project Members"),
          if (is_owner)
            actionButton(ns("btn_add_member"),
                         tagList(icon("user-plus"), " Invite Member"),
                         class = "btn btn-success btn-sm")
        ),
        uiOutput(ns("members_list"))
      )
    })

    output$members_list <- renderUI({
      req(project_id())
      df   <- project_members_df()
      proj <- current_project()
      is_owner <- !is.null(proj) && !is.null(proj$owner_id) &&
                  proj$owner_id == session_rv$user_id

      if (!is.data.frame(df) || nrow(df) == 0) {
        return(p(class = "text-muted fst-italic",
                 "No members found. Invite a collaborator using the button above."))
      }

      # Sort: owner first, then reviewers
      role_order <- match(df$role, c("owner", "reviewer"))
      df <- df[order(role_order), , drop = FALSE]

      tagList(
        lapply(seq_len(nrow(df)), function(i) {
          uid         <- df$user_id[i]
          role        <- df$role[i]
          email_label <- if ("email" %in% names(df) && !is.na(df$email[i]))
                           df$email[i] else uid
          badge_class <- if (role == "owner") "bg-dark" else "bg-primary"
          is_self     <- uid == session_rv$user_id

          div(class = "d-flex align-items-center border rounded px-3 py-2 mb-2 bg-white",
            div(class = "me-auto",
              icon("user-circle", class = "me-2 text-muted"),
              tags$strong(email_label),
              if (is_self) span(class = "text-muted small ms-2", "(you)")
            ),
            span(class = paste("badge me-3", badge_class),
                 if (role == "owner") tagList(icon("crown"), " Owner")
                 else tagList(icon("pencil"), " Reviewer")),
            # Owner can remove reviewers (but not themselves)
            if (is_owner && role != "owner") {
              tags$button(
                class   = "btn btn-sm btn-outline-danger",
                title   = "Remove this member",
                onclick = sprintf(
                  'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                  ns("remove_member"), uid),
                icon("user-times")
              )
            }
          )
        })
      )
    })

    # ---- Invite member (from Members tab) -------------------
    observeEvent(input$btn_add_member, {
      showModal(modalDialog(
        title  = "Invite Member",
        size   = "m",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_add_member"), "Send Invitation",
                       class = "btn btn-success")
        ),
        p("Enter the registered email address of the person you want to invite."),
        p(class = "text-muted small",
          icon("info-circle"),
          " The user must already have an account."),
        textInput(ns("add_member_email"), "Email address",
                  placeholder = "colleague@university.edu"),
        uiOutput(ns("add_member_feedback"))
      ))
    })

    observeEvent(input$confirm_add_member, {
      pid   <- project_id()
      email <- trimws(tolower(input$add_member_email %||% ""))
      if (is.null(pid) || nchar(email) == 0) {
        showNotification("Please enter an email address.", type = "warning")
        return()
      }
      tryCatch({
        svc <- Sys.getenv("SUPABASE_SERVICE_KEY")
        if (nchar(svc) == 0)
          stop("SUPABASE_SERVICE_KEY is not configured.")

        user_rows <- sb_get("users",
                            filters = list(email = email),
                            select  = "user_id,email",
                            token   = svc)

        if (!is.data.frame(user_rows) || nrow(user_rows) == 0) {
          output$add_member_feedback <- renderUI(
            div(class = "alert alert-warning mt-2",
                icon("user-times"),
                sprintf(" No account found for '%s'.", email))
          )
          return()
        }

        target_uid <- user_rows$user_id[1]
        if (target_uid == session_rv$user_id) {
          output$add_member_feedback <- renderUI(
            div(class = "alert alert-warning mt-2",
                "You are already the owner of this project.")
          )
          return()
        }

        existing <- sb_get("project_members",
                           filters = list(project_id = pid,
                                          user_id    = target_uid),
                           token   = session_rv$token)
        if (is.data.frame(existing) && nrow(existing) > 0) {
          output$add_member_feedback <- renderUI(
            div(class = "alert alert-info mt-2",
                sprintf("'%s' is already a member.", email))
          )
          return()
        }

        sb_post("project_members",
          list(project_id = pid,
               user_id    = target_uid,
               role       = "reviewer"),
          token = session_rv$token)

        removeModal()
        members_refresh(members_refresh() + 1)
        showNotification(sprintf("'%s' invited as reviewer.", email),
                         type = "message")
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
      })
    })

    # ---- Remove member (owner action) -----------------------
    removing_uid <- reactiveVal(NULL)

    observeEvent(input$remove_member, {
      uid <- input$remove_member
      req(uid)
      df  <- project_members_df()
      row <- df[df$user_id == uid, , drop = FALSE]
      removing_uid(uid)
      email_label <- if (nrow(row) > 0 && "email" %in% names(df))
                       row$email[1] else uid
      showModal(modalDialog(
        title  = "Remove Member?",
        size   = "s",
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_remove_member"), "Remove",
                       class = "btn btn-danger")
        ),
        p("Remove ", tags$strong(email_label), " from this project?"),
        p(class = "text-muted small",
          "They will lose access immediately. You can invite them back later.")
      ))
    })

    observeEvent(input$confirm_remove_member, {
      pid <- project_id()
      uid <- removing_uid()
      req(pid, uid)
      tryCatch({
        sb_delete_where("project_members",
                        filters = list(project_id = pid,
                                       user_id    = uid),
                        token   = session_rv$token)
        removeModal()
        removing_uid(NULL)
        members_refresh(members_refresh() + 1)
        showNotification("Member removed.", type = "message")
      }, error = function(e) {
        showNotification(paste("Error:", e$message), type = "error")
      })
    })

    # ---- Back to dashboard ----------------------------------
    observeEvent(input$btn_back, {
      app_state$current_project_id    <- NULL
      app_state$current_project_title <- NULL
    })

  })
}

