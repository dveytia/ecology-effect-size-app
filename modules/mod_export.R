# ============================================================
# modules/mod_export.R — Export tab
# ============================================================
# Phase 10: Full implementation.
#
# Provides filter options and two download buttons:
#   1. Full Export (all columns, all articles matching filters)
#   2. Meta-Ready Export (yi/vi columns for metafor)

mod_export_ui <- function(id) {
  ns <- NS(id)
  div(class = "container py-4",
    # ---- Header ----
    div(class = "d-flex justify-content-between align-items-center mb-3",
      h5(class = "mb-0", icon("file-export"), " Export Data"),
      span(class = "text-muted small", "Owner only: download project data as Excel")
    ),

    # ---- Access control message (shown to non-owners) ----
    uiOutput(ns("access_msg")),

    # ---- Filter panel ----
    conditionalPanel(
      condition = sprintf("output['%s'] === 'true'", ns("is_owner")),
      div(class = "card mb-4",
        div(class = "card-header", icon("filter"), " Filters"),
        div(class = "card-body",
          fluidRow(
            # Reviewer multi-select
            column(3,
              uiOutput(ns("reviewer_select_ui"))
            ),
            # Review status
            column(3,
              checkboxGroupInput(ns("review_status"), "Review Status",
                choices  = c("reviewed", "skipped", "unreviewed"),
                selected = c("reviewed"),
                inline   = FALSE)
            ),
            # Date range (opt-in)
            column(3,
              checkboxInput(ns("use_date_filter"), "Filter by review date",
                            value = FALSE),
              conditionalPanel(
                condition = sprintf("input['%s'] === true", ns("use_date_filter")),
                dateInput(ns("date_from"), "From",
                          value = Sys.Date() - 365),
                dateInput(ns("date_to"),   "To",
                          value = Sys.Date())
              )
            ),
            # Effect status
            column(3,
              uiOutput(ns("effect_status_select_ui"))
            )
          ),
          hr(),
          fluidRow(
            column(6,
              actionButton(ns("btn_preview"), tagList(icon("eye"), " Preview"),
                           class = "btn btn-outline-primary me-2"),
              span(class = "text-muted small ms-2",
                   textOutput(ns("preview_count"), inline = TRUE))
            ),
            column(6, class = "text-end",
              downloadButton(ns("dl_full"), tagList(icon("download"), " Full Export"),
                             class = "btn btn-primary me-2"),
              downloadButton(ns("dl_meta"), tagList(icon("chart-line"), " Meta-Ready Export"),
                             class = "btn btn-success me-2"),
              downloadButton(ns("dl_json"), tagList(icon("code"), " JSON Export"),
                             class = "btn btn-outline-secondary")
            )
          )
        )
      ),

      # ---- Preview table ----
      div(class = "card",
        div(class = "card-header", icon("table"), " Preview (first 20 rows)"),
        div(class = "card-body", style = "overflow-x: auto;",
          shinycssloaders::withSpinner(
            tableOutput(ns("preview_table")),
            type = 6, color = "#2C7A4B", size = 0.5
          )
        )
      )
    )
  )
}

mod_export_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ---- Check ownership ----
    is_owner_val <- reactive({
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        proj <- sb_get("projects",
          filters = list(project_id = pid),
          select  = "owner_id",
          token   = session_rv$token)
        if (is.data.frame(proj) && nrow(proj) > 0) {
          isTRUE(proj$owner_id[1] == session_rv$user_id)
        } else FALSE
      }, error = function(e) FALSE)
    })

    output$is_owner <- reactive({ if (is_owner_val()) "true" else "false" })
    outputOptions(output, "is_owner", suspendWhenHidden = FALSE)

    output$access_msg <- renderUI({
      if (!is_owner_val()) {
        div(class = "alert alert-info mt-3",
          icon("info-circle"),
          " Only the project owner can export data. Contact the project owner for exports."
        )
      }
    })

    # ---- Reviewer multi-select ----
    output$reviewer_select_ui <- renderUI({
      pid <- project_id()
      req(pid, session_rv$token)
      reviewers <- get_reviewers(pid, session_rv$token)
      choices <- if (is.data.frame(reviewers) && nrow(reviewers) > 0) {
        setNames(reviewers$user_id, reviewers$email)
      } else {
        c()
      }
      checkboxGroupInput(ns("reviewer"), "Reviewer",
        choices  = choices,
        selected = NULL)
    })

    # ---- Effect status multi-select ----
    output$effect_status_select_ui <- renderUI({
      pid <- project_id()
      req(pid, session_rv$token)
      statuses <- get_effect_statuses(pid, session_rv$token)
      if (length(statuses) == 0) {
        statuses <- c("calculated", "insufficient_data", "small_sd_used",
                       "iqr_sd_used", "calculated_relative")
      }
      checkboxGroupInput(ns("effect_status"), "Effect Status",
        choices  = statuses,
        selected = NULL)
    })

    # ---- Collect current filters ----
    .current_filters <- function() {
      # Only pass date filters when the opt-in checkbox is ticked
      use_dates <- isTRUE(input$use_date_filter)
      list(
        reviewer      = input$reviewer,
        review_status = input$review_status,
        date_from     = if (use_dates) input$date_from else NULL,
        date_to       = if (use_dates) input$date_to   else NULL,
        effect_status = input$effect_status
      )
    }

    # ---- Preview ----
    preview_data <- reactiveVal(data.frame())

    observeEvent(input$btn_preview, {
      req(is_owner_val(), session_rv$token)
      pid <- project_id()
      req(pid)

      withProgress(message = "Building export preview...", value = 0.5, {
        df <- tryCatch(
          build_full_export(pid, .current_filters(), session_rv$token),
          error = function(e) {
            showNotification(paste("Export error:", e$message), type = "error")
            data.frame()
          }
        )
        preview_data(df)
      })
    })

    output$preview_count <- renderText({
      df <- preview_data()
      if (is.data.frame(df) && nrow(df) > 0) {
        sprintf("%d rows × %d columns", nrow(df), ncol(df))
      } else {
        "No data"
      }
    })

    output$preview_table <- renderTable({
      df <- preview_data()
      if (!is.data.frame(df) || nrow(df) == 0) return(NULL)
      # Show first 20 rows, truncate wide text columns
      preview <- head(df, 20)
      # Truncate long columns for display
      for (col in names(preview)) {
        if (is.character(preview[[col]])) {
          preview[[col]] <- ifelse(
            nchar(preview[[col]]) > 60 & !is.na(preview[[col]]),
            paste0(substr(preview[[col]], 1, 57), "..."),
            preview[[col]]
          )
        }
      }
      preview
    }, striped = TRUE, hover = TRUE, bordered = TRUE, spacing = "s", na = "")

    # ---- Full Excel download ----
    output$dl_full <- downloadHandler(
      filename = function() {
        paste0("full_export_", format(Sys.Date(), "%Y%m%d"), ".xlsx")
      },
      content = function(file) {
        pid <- project_id()
        tok <- session_rv$token
        if (is.null(pid) || is.null(tok)) {
          writexl::write_xlsx(data.frame(error = "Session expired. Please log in again."), file)
          return(invisible(NULL))
        }
        df <- tryCatch(
          build_full_export(pid, .current_filters(), tok),
          error = function(e) {
            message("[dl_full] export error: ", e$message)
            showNotification(paste("Export error:", e$message), type = "error")
            data.frame(error = paste("Export failed:", e$message))
          }
        )
        # Write to a temp .xlsx first, then copy to the Shiny-provided path.
        # This avoids corruption from Shiny Server's temp-file handling
        # which can mangle binary content when the temp file has no extension.
        tmp <- tempfile(fileext = ".xlsx")
        on.exit(unlink(tmp), add = TRUE)
        writexl::write_xlsx(df, tmp)
        file.copy(tmp, file, overwrite = TRUE)
      },
      contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    # ---- Meta-ready Excel download ----
    output$dl_meta <- downloadHandler(
      filename = function() {
        paste0("meta_export_", format(Sys.Date(), "%Y%m%d"), ".xlsx")
      },
      content = function(file) {
        pid <- project_id()
        tok <- session_rv$token
        if (is.null(pid) || is.null(tok)) {
          writexl::write_xlsx(data.frame(error = "Session expired. Please log in again."), file)
          return(invisible(NULL))
        }
        df <- tryCatch(
          build_meta_export(pid, .current_filters(), tok),
          error = function(e) {
            message("[dl_meta] export error: ", e$message)
            showNotification(paste("Export error:", e$message), type = "error")
            data.frame()
          }
        )
        if (nrow(df) == 0) {
          diag_msg <- attr(df, "meta_export_msg") %||%
            paste0("No rows with a computed effect size match the current filters.")
          showNotification(diag_msg, type = "warning", duration = 15)
        } else if (!is.null(attr(df, "meta_export_msg"))) {
          showNotification(attr(df, "meta_export_msg"),
                           type = "warning", duration = 12)
        }
        tmp <- tempfile(fileext = ".xlsx")
        on.exit(unlink(tmp), add = TRUE)
        writexl::write_xlsx(df, tmp)
        file.copy(tmp, file, overwrite = TRUE)
      },
      contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    # ---- JSON download ----
    output$dl_json <- downloadHandler(
      filename = function() {
        paste0("export_", format(Sys.Date(), "%Y%m%d"), ".json")
      },
      content = function(file) {
        pid <- project_id()
        tok <- session_rv$token
        if (is.null(pid) || is.null(tok)) {
          writeLines("[]", file)
          return(invisible(NULL))
        }
        json_str <- tryCatch(
          build_json_export(pid, .current_filters(), session_rv$token),
          error = function(e) {
            showNotification(paste("Export error:", e$message), type = "error")
            "[]"
          }
        )
        writeLines(json_str, file, useBytes = TRUE)
      },
      contentType = "application/json"
    )

  })
}
