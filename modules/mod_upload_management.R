# ============================================================
# modules/mod_upload_management.R — Upload history + duplicate
# flag resolution (Phase 5)
# ============================================================
# Shows:
#   • Upload batch history (date, filename, clean rows, flagged)
#   • Pending duplicate flags for this project
#     – Accept: insert the flagged article, mark flag 'accepted'
#     – Reject: discard the flagged article, mark flag 'rejected'
# ============================================================

mod_upload_management_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "container py-4",

      # ---- Pending duplicate flags -----------------------
      div(class = "mb-5",
        div(class = "d-flex align-items-center mb-3",
          h5(class = "mb-0 me-auto",
             icon("flag"), " Pending Duplicate Flags"),
          actionButton(ns("btn_refresh"), "Refresh",
                       class = "btn btn-sm btn-outline-secondary",
                       icon  = icon("sync"))
        ),
        uiOutput(ns("pending_flags_ui"))
      ),

      tags$hr(),

      # ---- Upload batch history --------------------------
      div(
        h5(class = "mb-3", icon("history"), " Upload Batch History"),
        uiOutput(ns("batch_history_ui"))
      )
    )
  )
}


mod_upload_management_server <- function(id, project_id, session_rv,
                                         upload_refresh = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Refresh trigger ---------------------------------
    refresh_rv <- reactiveVal(0)

    observeEvent(input$btn_refresh,    { refresh_rv(refresh_rv() + 1) })
    if (!is.null(upload_refresh))
      observeEvent(upload_refresh(),   { refresh_rv(refresh_rv() + 1) })

    # ---- Load upload batches ----------------------------
    batches <- reactive({
      refresh_rv()
      pid <- project_id(); req(pid, session_rv$token)
      tryCatch(
        sb_get("uploads",
               filters = list(project_id = pid),
               select  = "upload_batch_id,filename,upload_date,rows_uploaded,rows_flagged",
               token   = session_rv$token),
        error = function(e) data.frame()
      )
    })

    # ---- Load pending duplicate flags -------------------
    pending_flags <- reactive({
      refresh_rv()
      pid <- project_id(); req(pid, session_rv$token)
      tryCatch(
        sb_get("duplicate_flags",
               filters = list(project_id = pid,
                               status     = "eq.pending"),
               select  = paste("flag_id,article_data,matched_article_id,",
                               "match_type,similarity_score,upload_batch_id"),
               token   = session_rv$token),
        error = function(e) data.frame()
      )
    })

    # ---- Render batch history ----------------------------
    output$batch_history_ui <- renderUI({
      df <- batches()
      if (!is.data.frame(df) || nrow(df) == 0) {
        return(p(class = "text-muted fst-italic",
                 "No uploads yet for this project."))
      }
      # Sort newest first
      if ("upload_date" %in% names(df)) {
        df <- df[order(df$upload_date, decreasing = TRUE), , drop = FALSE]
      }
      tagList(lapply(seq_len(nrow(df)), function(i) {
        r          <- df[i, ]
        date_str   <- format_timestamp(r$upload_date)
        fname      <- r$filename %||% "(unnamed)"
        n_up       <- r$rows_uploaded %||% 0
        n_fl       <- r$rows_flagged  %||% 0
        flag_badge <- if (!is.na(n_fl) && n_fl > 0)
          span(class = "badge bg-warning text-dark ms-2",
               icon("flag"), sprintf(" %d flagged", n_fl))
        else
          span(class = "badge bg-success ms-2",
               icon("check"), " No flags")
        div(class = "d-flex align-items-center border rounded px-3 py-2 mb-2 bg-white",
          div(class = "me-auto",
            icon("file-csv", class = "me-2 text-muted"),
            tags$strong(fname),
            span(class = "text-muted small ms-2", date_str)
          ),
          span(class = "text-muted small me-3",
               sprintf("%d inserted", n_up)),
          flag_badge
        )
      }))
    })

    # ---- Render pending flags ----------------------------
    output$pending_flags_ui <- renderUI({
      df <- pending_flags()
      if (!is.data.frame(df) || nrow(df) == 0) {
        return(
          div(class = "alert alert-success",
              icon("check-circle"),
              " No pending duplicate flags. All uploads have been resolved.")
        )
      }
      tagList(
        div(class = "alert alert-warning",
            icon("exclamation-triangle"),
            sprintf(" %d pending flag%s require%s your decision.",
                    nrow(df), if (nrow(df) == 1) "" else "s",
                    if (nrow(df) == 1) "s" else "")),
        lapply(seq_len(nrow(df)), function(i) {
          r        <- df[i, ]
          flag_id  <- r$flag_id
          art_data <- tryCatch(
            jsonlite::fromJSON(r$article_data),
            error = function(e) list()
          )
          title    <- art_data$title   %||% "(no title)"
          author   <- art_data$author  %||% ""
          year     <- art_data$year    %||% ""
          doi      <- art_data$doi_clean %||% ""

          match_label <- switch(r$match_type,
            exact_doi   = "Exact DOI match",
            title_year  = "Title + year match",
            partial_doi = "Partial DOI match",
            fuzzy       = sprintf("Fuzzy title match (similarity %.1f%%)",
                                  (r$similarity_score %||% 0) * 100),
            r$match_type
          )

          div(class = "card mb-3 border-warning",
            div(class = "card-body",
              div(class = "d-flex justify-content-between align-items-start",
                div(
                  tags$strong(str_trunc(title, 80)),
                  tags$br(),
                  span(class = "text-muted small",
                       paste(c(author, year, if (nchar(doi) > 0) doi),
                             collapse = " \u00b7 "))
                ),
                div(class = "d-flex gap-2 ms-2",
                  tags$button(
                    class   = "btn btn-sm btn-success",
                    title   = "Accept: insert this article",
                    onclick = sprintf(
                      'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                      ns("accept_flag"), flag_id),
                    icon("check"), " Accept"
                  ),
                  tags$button(
                    class   = "btn btn-sm btn-outline-danger",
                    title   = "Reject: discard this article",
                    onclick = sprintf(
                      'Shiny.setInputValue("%s", "%s", {priority:"event"});',
                      ns("reject_flag"), flag_id),
                    icon("times"), " Reject"
                  )
                )
              ),
              div(class = "mt-2",
                span(class = "badge bg-warning text-dark",
                     icon("exclamation-triangle"), " ", match_label)
              )
            )
          )
        })
      )
    })

    # ---- Accept a flag -----------------------------------
    observeEvent(input$accept_flag, {
      flag_id <- input$accept_flag
      req(flag_id)
      pid   <- project_id()
      token <- session_rv$token
      req(pid, token)

      df  <- pending_flags()
      row <- df[df$flag_id == flag_id, , drop = FALSE]
      if (nrow(row) == 0) return()

      art_data <- tryCatch(
        jsonlite::fromJSON(row$article_data[1]),
        error = function(e) NULL
      )
      if (is.null(art_data)) {
        showNotification("Could not parse article data.", type = "error")
        return()
      }

      # Get the upload batch id for this flag
      batch_id <- row$upload_batch_id[1]

      tryCatch({
        # Insert the article
        sb_post("articles",
          list(project_id      = pid,
               title           = as.character(art_data$title    %||% ""),
               abstract        = as.character(art_data$abstract %||% ""),
               author          = as.character(art_data$author   %||% ""),
               year            = if (!is.null(art_data$year) && !is.na(art_data$year))
                                   as.integer(art_data$year) else NULL,
               doi_clean       = as.character(art_data$doi_clean %||% ""),
               upload_batch_id = batch_id,
               review_status   = "unreviewed"),
          token = token)

        # Update flag to 'accepted'
        sb_patch("duplicate_flags", "flag_id", flag_id,
          list(status      = "accepted",
               resolved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
               resolved_by = session_rv$user_id),
          token = token)

        showNotification("Article accepted and inserted.", type = "message")
        refresh_rv(refresh_rv() + 1)
      }, error = function(e) {
        showNotification(paste("Accept failed:", e$message), type = "error")
      })
    })

    # ---- Reject a flag -----------------------------------
    observeEvent(input$reject_flag, {
      flag_id <- input$reject_flag
      req(flag_id)
      token <- session_rv$token; req(token)

      tryCatch({
        sb_patch("duplicate_flags", "flag_id", flag_id,
          list(status      = "rejected",
               resolved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
               resolved_by = session_rv$user_id),
          token = token)
        showNotification("Flagged article rejected.", type = "message")
        refresh_rv(refresh_rv() + 1)
      }, error = function(e) {
        showNotification(paste("Reject failed:", e$message), type = "error")
      })
    })

  })
}
