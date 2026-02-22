# ============================================================
# modules/mod_article_upload.R — Article upload tab (Phase 5)
# ============================================================
# Allows project members to upload a CSV of articles.
# Pipeline:
#   1. User selects a UTF-8 CSV file.
#   2. App parses and validates required columns.
#   3. Existing articles for this project are fetched and
#      check_duplicates() is run over the incoming rows.
#   4. A preview summary is shown: clean rows vs. flagged rows.
#   5. "Upload" inserts clean articles + creates an upload batch
#      record. Flagged rows are written to duplicate_flags for
#      resolution in the Upload History tab.
# ============================================================

mod_article_upload_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "container py-4",
      div(class = "row",
        div(class = "col-lg-7",
          # ---- Instructions card ---------------------------
          div(class = "card mb-4",
            div(class = "card-header fw-semibold",
                icon("info-circle"), " CSV Format Requirements"),
            div(class = "card-body",
              p("Upload a comma-separated (CSV) or tab-delimited (TSV/TXT) file in UTF-8 encoding."),
              p(class = "text-muted small",
                icon("lightbulb"),
                " Tab-delimited files are recommended when article titles or abstracts contain commas."),
              tags$table(class = "table table-sm",
                tags$thead(
                  tags$tr(tags$th("Column"), tags$th("Required"), tags$th("Notes"))
                ),
                tags$tbody(
                  tags$tr(tags$td(tags$code("title")),    tags$td("Yes"), tags$td("Article title text")),
                  tags$tr(tags$td(tags$code("abstract")), tags$td("Yes"), tags$td("Full abstract text")),
                  tags$tr(tags$td(tags$code("author")),   tags$td("Yes"), tags$td("Author string (any format)")),
                  tags$tr(tags$td(tags$code("year")),     tags$td("Yes"), tags$td("Publication year (integer)")),
                  tags$tr(tags$td(tags$code("doi")),      tags$td("Yes"), tags$td("DOI (with or without https://doi.org/ prefix)"))
                )
              ),
              p(class = "text-muted small mb-0",
                icon("exclamation-triangle"),
                " Non-UTF-8 files will be rejected with a re-save prompt. Delimiter is auto-detected.")
            )
          ),

          # ---- File input ----------------------------------
          div(class = "card mb-4",
            div(class = "card-header fw-semibold",
                icon("upload"), " Select CSV File"),
            div(class = "card-body",
              fileInput(ns("csv_file"),
                        label    = NULL,
                        accept   = c(".csv", ".tsv", ".txt",
                                     "text/csv", "text/tab-separated-values", "text/plain"),
                        multiple = FALSE,
                        buttonLabel = "Browse\u2026",
                        placeholder = "No file selected"),
              uiOutput(ns("parse_status"))
            )
          ),

          # ---- Preview summary (shown after parsing) -------
          uiOutput(ns("upload_preview")),

          # ---- Upload button (shown when ready) ------------
          uiOutput(ns("upload_btn_area"))
        ),

        # ---- Article preview table (right column) ----------
        div(class = "col-lg-5",
          uiOutput(ns("preview_table_card"))
        )
      )
    )
  )
}


mod_article_upload_server <- function(id, project_id, session_rv,
                                      upload_refresh = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # upload_done must be declared FIRST so existing_articles can depend on it
    upload_done <- reactiveVal(0)

    # ---- Parse result reactive ---------------------------
    parse_result <- reactive({
      req(input$csv_file)
      req(project_id(), session_rv$token)
      path <- input$csv_file$datapath
      fname_orig <- input$csv_file$name
      tryCatch({
        df   <- read_upload_file(path, filename = fname_orig)
        miss <- validate_upload_columns(df)
        if (length(miss) > 0) {
          stop(paste("Missing required column(s):", paste(miss, collapse = ", ")))
        }
        list(ok = TRUE, df = df, error = NULL)
      }, error = function(e) {
        list(ok = FALSE, df = NULL, error = e$message)
      })
    })

    # ---- Existing articles for this project --------------
    # Depends on upload_done so it re-fetches after every successful upload,
    # and on input$csv_file so each new file selection sees the latest DB state.
    existing_articles <- reactive({
      upload_done()          # invalidate after a completed upload
      input$csv_file         # invalidate when user picks a new file
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        sb_get("articles",
               filters = list(project_id = pid),
               select  = "article_id,title,year,doi_clean",
               token   = session_rv$token)
      }, error = function(e) data.frame())
    })

    # ---- Duplicate check ----------------------------------
    dup_result <- reactive({
      pr <- parse_result()
      req(pr$ok)
      existing <- existing_articles()
      check_duplicates(pr$df, existing)
    })

    # ---- Parse status message ----------------------------
    output$parse_status <- renderUI({
      req(input$csv_file)
      pr <- parse_result()
      if (!pr$ok) {
        div(class = "alert alert-danger mt-2 mb-0",
            icon("times-circle"), " ", pr$error)
      } else {
        n <- nrow(pr$df)
        div(class = "alert alert-success mt-2 mb-0",
            icon("check-circle"),
            sprintf(" Parsed %d row%s successfully.", n, if (n == 1) "" else "s"))
      }
    })

    # ---- Upload preview summary --------------------------
    output$upload_preview <- renderUI({
      pr <- parse_result()
      if (!pr$ok) return(NULL)

      dups    <- dup_result()
      total   <- nrow(pr$df)
      n_dup   <- nrow(dups)
      n_clean <- total - n_dup

      dup_summary <- if (n_dup > 0) {
        counts <- table(dups$match_type)
        items <- lapply(names(counts), function(mt) {
          label <- switch(mt,
            exact_doi   = "Exact DOI duplicate",
            title_year  = "Title + year duplicate",
            partial_doi = "Partial DOI match (same year, same DOI prefix)",
            fuzzy       = "Fuzzy title match (similar title in same year)",
            mt
          )
          tags$li(sprintf("%s: %d", label, counts[[mt]]))
        })
        tagList(
          tags$strong("Flagged rows by type:"),
          tags$ul(items)
        )
      } else {
        NULL
      }

      div(class = "card mb-4",
        div(class = "card-header fw-semibold",
            icon("clipboard-check"), " Upload Preview"),
        div(class = "card-body",
          div(class = "row text-center mb-3",
            div(class = "col",
              div(class = "fs-3 fw-bold", total),
              div(class = "text-muted small", "Total rows")
            ),
            div(class = "col",
              div(class = "fs-3 fw-bold text-success", n_clean),
              div(class = "text-muted small", "Clean")
            ),
            div(class = "col",
              div(class = "fs-3 fw-bold text-warning", n_dup),
              div(class = "text-muted small", "Flagged")
            )
          ),
          if (n_dup > 0) {
            div(class = "alert alert-warning mb-0",
              icon("exclamation-triangle"),
              " Flagged rows will be held in ",
              tags$strong("Upload History"), " for review.",
              tags$hr(), dup_summary
            )
          } else {
            div(class = "alert alert-success mb-0",
              icon("check-circle"),
              " All rows are unique and will be inserted immediately.")
          }
        )
      )
    })

    # ---- Upload button -----------------------------------
    output$upload_btn_area <- renderUI({
      pr <- parse_result()
      if (!pr$ok) return(NULL)
      n_dup   <- nrow(dup_result())
      n_clean <- nrow(pr$df) - n_dup
      btn_lbl <- if (n_clean > 0)
        sprintf("Upload %d clean article%s", n_clean, if (n_clean == 1) "" else "s")
      else
        "Submit (all flagged — send to review)"
      tagList(
        if (n_dup > 0)
          p(class = "text-muted small",
            icon("info-circle"),
            sprintf(" %d flagged row%s sent to Upload History.",
                    n_dup, if (n_dup == 1) "" else "s")),
        actionButton(ns("btn_upload"), btn_lbl,
                     class = "btn btn-primary btn-lg w-100",
                     icon  = icon("cloud-upload-alt"))
      )
    })

    # ---- Inline preview table (first 10 rows) ------------
    output$preview_table_card <- renderUI({
      pr <- parse_result()
      if (!pr$ok) return(NULL)
      dups    <- dup_result()
      df      <- pr$df
      df$status <- ifelse(
        seq_len(nrow(df)) %in% dups$row_index, "\u26a0 Flagged", "\u2713 Clean"
      )
      df_show <- head(df[, c("title", "author", "year", "status")], 10)
      names(df_show) <- c("Title", "Author", "Year", "Status")
      df_show$Title <- str_trunc(df_show$Title, 45)
      div(class = "card",
        div(class = "card-header fw-semibold",
            icon("table"), " First 10 rows"),
        div(class = "card-body p-0 table-responsive",
          renderTable(df_show, sanitize.text.function = identity)
        )
      )
    })

    # ---- Upload handler ----------------------------------
    # (upload_done is declared above existing_articles — do not re-declare here)
    observeEvent(input$btn_upload, {
      pr  <- parse_result()
      req(pr$ok)
      pid   <- project_id()
      token <- session_rv$token
      req(pid, token)

      dups    <- dup_result()
      df      <- pr$df
      fname   <- input$csv_file$name
      n_total <- nrow(df)
      n_dup   <- nrow(dups)
      n_clean <- n_total - n_dup

      tryCatch({
        # 1. Create upload batch record
        batch    <- sb_post("uploads",
          list(project_id    = pid,
               filename      = fname,
               rows_uploaded = n_clean,
               rows_flagged  = n_dup),
          token = token)
        batch_id <- batch$upload_batch_id

        # 2. Insert clean articles
        clean_idx <- setdiff(seq_len(n_total), dups$row_index)
        for (i in clean_idx) {
          row <- df[i, ]
          sb_post("articles",
            list(project_id      = pid,
                 title           = as.character(row$title    %||% ""),
                 abstract        = as.character(row$abstract %||% ""),
                 author          = as.character(row$author   %||% ""),
                 year            = if (!is.na(row$year)) as.integer(row$year) else NULL,
                 doi_clean       = clean_doi_dup(as.character(row$doi %||% "")),
                 upload_batch_id = batch_id,
                 review_status   = "unreviewed"),
            token = token)
        }

        # 3. Insert flagged rows into duplicate_flags
        for (j in seq_len(nrow(dups))) {
          fr  <- dups[j, ]
          or  <- df[fr$row_index, ]
          art <- jsonlite::toJSON(list(
            title     = as.character(or$title    %||% ""),
            abstract  = as.character(or$abstract %||% ""),
            author    = as.character(or$author   %||% ""),
            year      = if (!is.na(or$year)) as.integer(or$year) else NULL,
            doi_clean = clean_doi_dup(as.character(or$doi %||% ""))
          ), auto_unbox = TRUE)
          sb_post("duplicate_flags",
            list(upload_batch_id    = batch_id,
                 project_id         = pid,
                 article_data       = art,
                 matched_article_id = fr$matched_article_id,
                 match_type         = fr$match_type,
                 similarity_score   = if (!is.na(fr$similarity_score)) fr$similarity_score else NULL,
                 status             = "pending"),
            token = token)
        }

        showNotification(
          sprintf("Upload complete: %d article%s inserted, %d flagged for review.",
                  n_clean, if (n_clean == 1) "" else "s", n_dup),
          type = "message", duration = 8)

        shinyjs::reset("csv_file")
        upload_done(upload_done() + 1)
        if (!is.null(upload_refresh)) upload_refresh(upload_refresh() + 1)

      }, error = function(e) {
        showNotification(paste("Upload failed:", e$message),
                         type = "error", duration = 10)
      })
    })

    list(upload_done = upload_done)
  })
}
