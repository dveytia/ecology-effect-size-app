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
      span(class = "text-muted small", "Owner only: download project data as CSV")
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
            # Date range
            column(3,
              dateInput(ns("date_from"), "Reviewed From", value = NA),
              dateInput(ns("date_to"),   "Reviewed To",   value = NA)
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
                             class = "btn btn-success")
            )
          )
        )
      ),

      # ---- Preview table ----
      div(class = "card",
        div(class = "card-header", icon("table"), " Preview (first 20 rows)"),
        div(class = "card-body", style = "overflow-x: auto;",
          tableOutput(ns("preview_table"))
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
      list(
        reviewer      = input$reviewer,
        review_status = input$review_status,
        date_from     = input$date_from,
        date_to       = input$date_to,
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

    # ---- Full CSV download ----
    output$dl_full <- downloadHandler(
      filename = function() {
        paste0("full_export_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        pid <- project_id()
        req(pid, session_rv$token)
        df <- tryCatch(
          build_full_export(pid, .current_filters(), session_rv$token),
          error = function(e) {
            showNotification(paste("Export error:", e$message), type = "error")
            data.frame()
          }
        )
        data.table::fwrite(df, file, bom = TRUE)
      },
      contentType = "text/csv"
    )

    # ---- Meta-ready CSV download ----
    output$dl_meta <- downloadHandler(
      filename = function() {
        paste0("meta_export_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        pid <- project_id()
        req(pid, session_rv$token)
        df <- tryCatch(
          build_meta_export(pid, .current_filters(), session_rv$token),
          error = function(e) {
            showNotification(paste("Export error:", e$message), type = "error")
            data.frame()
          }
        )
        if (nrow(df) == 0) {
          showNotification("No rows with computed effect sizes match the current filters.",
                           type = "warning")
        }
        data.table::fwrite(df, file, bom = TRUE)
      },
      contentType = "text/csv"
    )

  })
}
