# ============================================================
# modules/mod_audit_log.R — Audit log viewer tab
# ============================================================
# Phase 12: Full implementation.
# - Filterable table of all save/skip/delete actions
# - Shows timestamp, user, article, action, before/after JSON
# - Expandable diff view for each entry
# - Filters by action type, user, and date range
# - Visible to all project members (owners and reviewers)
# ============================================================

mod_audit_log_ui <- function(id) {
  ns <- NS(id)
  div(class = "container-fluid py-3",

    # ---- Header & refresh -----------------------------------
    div(class = "d-flex justify-content-between align-items-center mb-3",
      h5(class = "mb-0", icon("clipboard-list"), " Audit Log"),
      actionButton(ns("btn_refresh"), tagList(icon("sync"), " Refresh"),
                   class = "btn btn-sm btn-outline-secondary")
    ),

    # ---- Filters row ----------------------------------------
    div(class = "row g-2 mb-3",
      div(class = "col-md-3",
        selectInput(ns("filter_action"), "Action",
                    choices  = c("All" = "", "save", "skip", "delete",
                                 "effect_computed"),
                    selected = "")
      ),
      div(class = "col-md-3",
        selectInput(ns("filter_user"), "User",
                    choices  = c("All users" = ""),
                    selected = "")
      ),
      div(class = "col-md-3",
        dateInput(ns("filter_date_from"), "From date",
                  value = Sys.Date() - 30)
      ),
      div(class = "col-md-3",
        dateInput(ns("filter_date_to"), "To date",
                  value = Sys.Date() + 1)
      )
    ),

    # ---- Summary badge --------------------------------------
    uiOutput(ns("summary_badge")),

    # ---- Log table ------------------------------------------
    div(class = "card",
      div(class = "card-body p-0",
        div(style = "max-height: 65vh; overflow-y: auto;",
          shinycssloaders::withSpinner(
            uiOutput(ns("log_table")),
            type = 6, color = "#2C7A4B", size = 0.5
          )
        )
      )
    )
  )
}

mod_audit_log_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- State -----------------------------------------------
    refresh_trigger <- reactiveVal(0)

    observeEvent(input$btn_refresh, {
      refresh_trigger(refresh_trigger() + 1L)
    })

    # ---- Load audit log data ---------------------------------
    log_data <- reactive({
      refresh_trigger()
      pid <- project_id()
      req(pid, session_rv$token)

      tryCatch({
        rows <- sb_get("audit_log",
          filters = list(project_id = pid),
          select  = "log_id,project_id,user_id,article_id,action,old_json,new_json,timestamp",
          token   = session_rv$token)
        if (!is.data.frame(rows) || nrow(rows) == 0) return(data.frame())
        # Sort by timestamp descending (most recent first)
        rows$timestamp_posix <- as.POSIXct(rows$timestamp,
                                            format = "%Y-%m-%dT%H:%M:%S",
                                            tz = "UTC")
        rows <- rows[order(rows$timestamp_posix, decreasing = TRUE), ,
                     drop = FALSE]
        rows
      }, error = function(e) {
        showNotification(paste("Could not load audit log:", e$message),
                         type = "error")
        data.frame()
      })
    })

    # ---- Load users for display names ------------------------
    user_lookup <- reactive({
      df <- log_data()
      if (!is.data.frame(df) || nrow(df) == 0) return(list())
      uids <- unique(df$user_id)
      svc  <- Sys.getenv("SUPABASE_SERVICE_KEY")
      if (nchar(svc) == 0) return(list())
      tryCatch({
        uid_str  <- paste0("(", paste(uids, collapse = ","), ")")
        user_rows <- sb_get("users",
                            filters = list(user_id = paste0("in.", uid_str)),
                            select  = "user_id,email,username",
                            token   = svc)
        if (!is.data.frame(user_rows) || nrow(user_rows) == 0) return(list())
        lk <- list()
        for (i in seq_len(nrow(user_rows))) {
          uid   <- user_rows$user_id[i]
          label <- user_rows$username[i]
          if (is.na(label) || is.null(label) || nchar(label) == 0)
            label <- user_rows$email[i]
          lk[[uid]] <- label
        }
        lk
      }, error = function(e) list())
    })

    # ---- Load article titles for display ---------------------
    article_lookup <- reactive({
      df <- log_data()
      if (!is.data.frame(df) || nrow(df) == 0) return(list())
      aids <- unique(df$article_id[!is.na(df$article_id)])
      if (length(aids) == 0) return(list())
      tryCatch({
        aid_str <- paste0("(", paste(aids, collapse = ","), ")")
        art_rows <- sb_get("articles",
                           filters = list(article_id = paste0("in.", aid_str)),
                           select  = "article_id,title,article_num",
                           token   = session_rv$token)
        if (!is.data.frame(art_rows) || nrow(art_rows) == 0) return(list())
        lk <- list()
        for (i in seq_len(nrow(art_rows))) {
          aid   <- art_rows$article_id[i]
          num   <- art_rows$article_num[i]
          title <- art_rows$title[i]
          label <- if (!is.na(num) && !is.null(num))
                     paste0("#", num, ": ", str_trunc(title, 40))
                   else str_trunc(title, 50)
          lk[[aid]] <- label
        }
        lk
      }, error = function(e) list())
    })

    # ---- Update user filter options when data loads ----------
    observe({
      lk <- user_lookup()
      if (length(lk) == 0) return()
      choices <- c("All users" = "")
      for (uid in names(lk)) {
        choices <- c(choices, setNames(uid, lk[[uid]]))
      }
      updateSelectInput(session, "filter_user", choices = choices)
    })

    # ---- Filtered data ---------------------------------------
    filtered_log <- reactive({
      df <- log_data()
      if (!is.data.frame(df) || nrow(df) == 0) return(data.frame())

      # Filter by action
      act <- input$filter_action %||% ""
      if (nchar(act) > 0) {
        df <- df[df$action == act, , drop = FALSE]
      }

      # Filter by user
      uid_filter <- input$filter_user %||% ""
      if (nchar(uid_filter) > 0) {
        df <- df[df$user_id == uid_filter, , drop = FALSE]
      }

      # Filter by date range
      from_date <- input$filter_date_from
      to_date   <- input$filter_date_to
      if (!is.null(from_date)) {
        from_posix <- as.POSIXct(from_date, tz = "UTC")
        df <- df[!is.na(df$timestamp_posix) &
                   df$timestamp_posix >= from_posix, , drop = FALSE]
      }
      if (!is.null(to_date)) {
        to_posix <- as.POSIXct(to_date + 1, tz = "UTC")
        df <- df[!is.na(df$timestamp_posix) &
                   df$timestamp_posix < to_posix, , drop = FALSE]
      }

      df
    })

    # ---- Summary badge ---------------------------------------
    output$summary_badge <- renderUI({
      df <- filtered_log()
      total <- if (is.data.frame(df)) nrow(df) else 0
      all_total <- if (is.data.frame(log_data())) nrow(log_data()) else 0
      div(class = "mb-2",
        span(class = "badge bg-secondary me-2",
             sprintf("%d entr%s shown", total,
                     if (total == 1) "y" else "ies")),
        if (total < all_total)
          span(class = "text-muted small",
               sprintf("(%d total)", all_total))
      )
    })

    # ---- Render log table ------------------------------------
    output$log_table <- renderUI({
      df <- filtered_log()
      if (!is.data.frame(df) || nrow(df) == 0) {
        return(div(class = "text-center text-muted py-5",
          icon("clipboard-list", class = "fa-2x mb-2"),
          p("No audit log entries found.")
        ))
      }

      ul <- user_lookup()
      al <- article_lookup()

      tags$table(class = "table table-sm table-hover mb-0",
        tags$thead(
          tags$tr(
            tags$th(style = "width: 155px;", "Timestamp"),
            tags$th(style = "width: 150px;", "User"),
            tags$th("Article"),
            tags$th(style = "width: 100px;", "Action"),
            tags$th(style = "width: 80px; text-align: center;", "Diff")
          )
        ),
        tags$tbody(
          lapply(seq_len(nrow(df)), function(i) {
            row <- df[i, ]
            # Timestamp
            ts_display <- format_timestamp(row$timestamp)

            # User
            user_display <- ul[[row$user_id]] %||% substr(row$user_id, 1, 8)

            # Article
            art_display <- if (!is.na(row$article_id))
                             al[[row$article_id]] %||% substr(row$article_id, 1, 8)
                           else "\u2014"

            # Action badge
            action_class <- switch(row$action,
              "save"   = "audit-action-save",
              "skip"   = "audit-action-skip",
              "delete" = "audit-action-delete",
              "text-info"
            )
            action_icon <- switch(row$action,
              "save"             = icon("floppy-disk"),
              "skip"             = icon("forward"),
              "delete"           = icon("trash"),
              "effect_computed"  = icon("calculator"),
              icon("circle")
            )

            # Has diff?
            has_old <- !is.null(row$old_json) && !is.na(row$old_json) &&
                       nchar(as.character(row$old_json)) > 2
            has_new <- !is.null(row$new_json) && !is.na(row$new_json) &&
                       nchar(as.character(row$new_json)) > 2

            tags$tr(
              tags$td(tags$small(ts_display)),
              tags$td(tags$small(user_display)),
              tags$td(tags$small(art_display)),
              tags$td(span(class = action_class, action_icon, " ", row$action)),
              tags$td(style = "text-align: center;",
                if (has_old || has_new) {
                  tags$button(
                    class   = "btn btn-sm btn-outline-primary py-0 px-1",
                    title   = "View before/after snapshot",
                    onclick = sprintf(
                      'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                      ns("view_diff"), row$log_id),
                    icon("code-compare")
                  )
                } else {
                  span(class = "text-muted", "\u2014")
                }
              )
            )
          })
        )
      )
    })

    # ---- Diff modal -----------------------------------------
    observeEvent(input$view_diff, {
      log_id <- input$view_diff
      req(log_id)

      df <- log_data()
      row <- df[df$log_id == log_id, , drop = FALSE]
      if (nrow(row) == 0) return()
      row <- row[1, ]

      ul <- user_lookup()
      al <- article_lookup()

      user_label <- ul[[row$user_id]] %||% row$user_id
      art_label  <- if (!is.na(row$article_id))
                      al[[row$article_id]] %||% row$article_id
                    else "\u2014"

      # Format JSON snapshots for display
      .format_json <- function(jstr) {
        if (is.null(jstr) || is.na(jstr) || nchar(as.character(jstr)) < 3)
          return(tags$em(class = "text-muted", "(empty)"))
        tryCatch({
          parsed <- jsonlite::fromJSON(as.character(jstr),
                                        simplifyVector = FALSE)
          pretty <- jsonlite::toJSON(parsed, auto_unbox = TRUE,
                                      pretty = TRUE, null = "null")
          tags$pre(class = "bg-light p-2 rounded small",
                   style = "max-height: 300px; overflow-y: auto; white-space: pre-wrap;",
                   as.character(pretty))
        }, error = function(e) {
          tags$pre(class = "bg-light p-2 rounded small",
                   as.character(jstr))
        })
      }

      showModal(modalDialog(
        title  = tagList(icon("code-compare"), " Audit Log Detail"),
        size   = "l",
        easyClose = TRUE,
        footer = modalButton("Close"),

        div(class = "row mb-3",
          div(class = "col-md-4",
            tags$small(class = "text-muted", "Timestamp"),
            div(tags$strong(format_timestamp(row$timestamp)))
          ),
          div(class = "col-md-4",
            tags$small(class = "text-muted", "User"),
            div(tags$strong(user_label))
          ),
          div(class = "col-md-4",
            tags$small(class = "text-muted", "Action"),
            div(tags$strong(class = switch(row$action,
              "save" = "audit-action-save",
              "skip" = "audit-action-skip",
              "delete" = "audit-action-delete",
              ""), row$action))
          )
        ),

        div(class = "mb-2",
          tags$small(class = "text-muted", "Article"),
          div(art_label)
        ),

        hr(),

        div(class = "row",
          div(class = "col-md-6",
            h6(icon("arrow-left"), " Before (old_json)"),
            .format_json(row$old_json)
          ),
          div(class = "col-md-6",
            h6(icon("arrow-right"), " After (new_json)"),
            .format_json(row$new_json)
          )
        )
      ))
    })

  })
}
