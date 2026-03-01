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
        batch_id   <- r$upload_batch_id
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
          flag_badge,
          tags$button(
            class   = "btn btn-sm btn-outline-danger ms-3",
            title   = "Delete this upload batch and its articles",
            onclick = sprintf(
              'Shiny.setInputValue("%s", "%s", {priority:"event"});',
              ns("delete_batch"), batch_id),
            icon("trash")
          )
        )
      }))
    })

    # ---- Delete upload batch ----------------------------
    deleting_batch_id  <- reactiveVal(NULL)
    deleting_n_reviewed  <- reactiveVal(0)   # articles that will be KEPT
    deleting_n_deletable <- reactiveVal(0)   # articles that will be REMOVED

    observeEvent(input$delete_batch, {
      bid   <- input$delete_batch
      req(bid)
      token <- session_rv$token; req(token)

      tryCatch({
        arts <- sb_get("articles",
                       filters = list(upload_batch_id = bid),
                       select  = "article_id,review_status",
                       token   = token)

        n_total      <- if (is.data.frame(arts)) nrow(arts) else 0
        # Only fully-reviewed articles are protected; unreviewed + skipped are deletable
        n_reviewed   <- if (n_total > 0) sum(arts$review_status == "reviewed")         else 0
        n_deletable  <- if (n_total > 0) sum(arts$review_status %in% c("unreviewed", "skipped")) else 0

        deleting_batch_id(bid)
        deleting_n_reviewed(n_reviewed)
        deleting_n_deletable(n_deletable)

        fname_label <- {
          df  <- batches()
          row <- df[df$upload_batch_id == bid, , drop = FALSE]
          if (nrow(row) > 0) row$filename[1] %||% "(unnamed)" else "(unnamed)"
        }

        body_content <- if (n_total == 0) {
          p("This batch has no inserted articles. The batch record will be removed.")
        } else {
          tagList(
            # Warning when reviewed articles will be left behind
            if (n_reviewed > 0)
              div(class = "alert alert-warning",
                  icon("exclamation-triangle"),
                  sprintf(
                    " %d reviewed article%s cannot be deleted and will be retained.",
                    n_reviewed, if (n_reviewed == 1) "" else "s"))
            else NULL,

            # Count summary
            tags$table(class = "table table-sm mb-3",
              tags$tbody(
                tags$tr(
                  tags$td(icon("trash"), " Will be deleted"),
                  tags$td(tags$strong(
                    sprintf("%d article%s (unreviewed + skipped)",
                            n_deletable, if (n_deletable == 1) "" else "s")))
                ),
                tags$tr(
                  tags$td(icon("lock"), " Will be kept"),
                  tags$td(tags$strong(
                    sprintf("%d reviewed article%s",
                            n_reviewed, if (n_reviewed == 1) "" else "s")))
                )
              )
            ),

            if (n_reviewed > 0)
              p(class = "text-muted small",
                icon("info-circle"),
                sprintf(
                  " The batch record for \u2018%s\u2019 will also be retained ",
                  fname_label),
                "because it still has reviewed articles attached to it.")
            else
              p(class = "text-muted small",
                icon("info-circle"),
                " Pending duplicate flags for this batch will also be discarded.")
          )
        }

        showModal(modalDialog(
          title  = sprintf("Delete from batch \u2018%s\u2019?", fname_label),
          size   = "m",
          footer = tagList(
            modalButton("Cancel"),
            if (n_deletable > 0 || n_total == 0)
              actionButton(ns("confirm_delete_batch"),
                           if (n_reviewed > 0) "Delete unreviewed & skipped" else "Delete",
                           class = "btn btn-danger")
            else
              tags$span(class = "text-muted small align-self-center",
                        "Nothing to delete.")
          ),
          body_content
        ))
      }, error = function(e) {
        showNotification(paste("Error checking batch:", e$message), type = "error")
      })
    })

    observeEvent(input$confirm_delete_batch, {
      bid          <- deleting_batch_id()
      n_reviewed   <- deleting_n_reviewed()
      req(bid)
      pid   <- project_id()
      token <- session_rv$token
      req(pid, token)

      tryCatch({
        # 1. Delete unreviewed AND skipped articles in this batch.
        #    Two separate calls avoid httr2 URL-encoding the in.() syntax
        #    in a way that some PostgREST versions misparse.
        sb_delete_where("articles",
                        filters = list(upload_batch_id = bid,
                                       review_status   = "eq.unreviewed"),
                        token   = token)
        sb_delete_where("articles",
                        filters = list(upload_batch_id = bid,
                                       review_status   = "eq.skipped"),
                        token   = token)

        # 2. Delete pending duplicate flags for this batch
        sb_delete_where("duplicate_flags",
                        filters = list(upload_batch_id = bid),
                        token   = token)

        # 3. Only delete the uploads row if no reviewed articles remain
        #    (FK constraint prevents deletion while reviewed articles still reference it)
        if (n_reviewed == 0) {
          sb_delete("uploads", "upload_batch_id", bid, token = token)
        }

        removeModal()
        deleting_batch_id(NULL)
        deleting_n_reviewed(0)
        deleting_n_deletable(0)

        msg <- if (n_reviewed > 0)
          sprintf("Unreviewed and skipped articles deleted. %d reviewed article%s retained.",
                  n_reviewed, if (n_reviewed == 1) "" else "s")
        else
          "Upload batch deleted."
        showNotification(msg, type = "message", duration = 8)
        refresh_rv(refresh_rv() + 1)
      }, error = function(e) {
        showNotification(paste("Delete failed:", e$message), type = "error")
      })
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
        art_payload <- list(
          project_id      = pid,
          title           = as.character(art_data$title    %||% ""),
          abstract        = as.character(art_data$abstract %||% ""),
          author          = as.character(art_data$author   %||% ""),
          year            = if (!is.null(art_data$year) && !is.na(art_data$year))
                              as.integer(art_data$year) else NULL,
          doi_clean       = as.character(art_data$doi_clean %||% ""),
          upload_batch_id = batch_id,
          review_status   = "unreviewed"
        )
        if (!is.null(art_data$article_num) && !is.na(art_data$article_num))
          art_payload$article_num <- as.integer(art_data$article_num)
        sb_post("articles", art_payload, token = token)

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
