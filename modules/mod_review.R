# ============================================================
# modules/mod_review.R — Main review interface
# ============================================================
# Phase 7: Full implementation.
# - Article list sidebar with search and status badges
# - Article header: title, author, year, DOI, abstract, PDF button
# - Dynamic label form rendered from project label schema
# - Label groups with add/remove instance support
# - Save, Next, Skip action buttons
# - Concurrency conflict detection via audit_log
# - Upserts to article_metadata_json; updates articles.review_status
# - Audit log writes for every save and skip action
# ============================================================

# ---- UI -------------------------------------------------------
mod_review_ui <- function(id) {
  ns <- NS(id)
  div(class = "container-fluid py-3",

    # ---- Top bar: search + progress -------------------------
    div(class = "row mb-3 align-items-center g-2",
      div(class = "col-md-6",
        div(class = "input-group",
          tags$span(class = "input-group-text", icon("search")),
          textInput(ns("search"), label = NULL,
                    placeholder = "Search by ID, title or author…")
        )
      ),
      div(class = "col-md-6 text-md-end",
        uiOutput(ns("progress_badge"))
      )
    ),

    # ---- Main layout: article list + review panel -----------
    div(class = "row g-3",

      # ---- Left: scrollable article list -------------------
      div(class = "col-lg-3",
        div(class = "card h-100",
          div(class = "card-header py-2 d-flex align-items-center",
            strong(icon("list"), " Articles"),
            uiOutput(ns("list_count_badge"), inline = TRUE)
          ),
          div(class = "card-body p-0",
            style = "max-height: 75vh; overflow-y: auto;",
            uiOutput(ns("article_list_ui"))
          )
        )
      ),

      # ---- Right: review panel -----------------------------
      div(class = "col-lg-9",
        uiOutput(ns("review_panel"))
      )
    )
  )
}

# ---- Server ---------------------------------------------------
mod_review_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # --------------------------------------------------------
    # State
    # --------------------------------------------------------
    articles_refresh   <- reactiveVal(0)
    labels_refresh     <- reactiveVal(0)
    current_article_id <- reactiveVal(NULL)
    loaded_at          <- reactiveVal(NULL)   # POSIXct: when article was opened
    # group_instances: named list  group_name -> list of instance keys (strings)
    group_instances    <- reactiveVal(list())
    # Effect size save trigger (incremented on Save to signal the ES module)
    es_save_trigger    <- reactiveVal(0)   # kept for API compat, no longer used
    # Monotonic counter per group for generating unique instance keys.
    # Needed for Add Instance: if user removes instance 2 of 3 then adds
    # a new one, the counter ensures a fresh key (4) rather than reusing 3.
    es_instance_counter <- list()

    # ---- Simple unique key generator (for non-ES label inputs only) ----
    .new_key <- function() paste0(sample(c(letters[1:6], 0:9), 8, replace = TRUE),
                                   collapse = "")

    # --------------------------------------------------------
    # Data loading
    # --------------------------------------------------------

    # All articles for this project
    all_articles <- reactive({
      articles_refresh()
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        rows <- sb_get("articles",
          filters = list(project_id = pid),
          select  = paste("article_id,title,author,year,doi_clean,",
                          "abstract,review_status,pdf_drive_link,article_num"),
          token   = session_rv$token)
        if (!is.data.frame(rows) || nrow(rows) == 0) return(data.frame())
        # Ensure review_status has no NAs for downstream comparisons
        rows$review_status[is.na(rows$review_status)] <- "unreviewed"
        rows
      }, error = function(e) {
        showNotification(paste("Could not load articles:", e$message), type = "error")
        data.frame()
      })
    })

    # Filtered by search text
    filtered_articles <- reactive({
      df <- all_articles()
      if (!is.data.frame(df) || nrow(df) == 0) return(df)
      q  <- trimws(tolower(input$search %||% ""))
      if (nchar(q) == 0) return(df)
      # Use ifelse for vectorised NA-safe coercion (not %||% which is scalar-only)
      t_col  <- tolower(ifelse(is.na(df$title),      "", as.character(df$title)))
      a_col  <- tolower(ifelse(is.na(df$author),     "", as.character(df$author)))
      id_col <- tolower(ifelse(is.na(df$article_num), "", as.character(df$article_num)))
      mask   <- grepl(q, t_col, fixed = TRUE) |
                grepl(q, a_col, fixed = TRUE) |
                grepl(q, id_col, fixed = TRUE)
      df[mask, , drop = FALSE]
    })

    # Label schema for this project (re-fetches on labels_refresh)
    project_labels <- reactive({
      labels_refresh()   # dependency so labels re-fetch when triggered
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        rows <- sb_get("labels",
          filters = list(project_id = pid),
          select  = "label_id,label_type,parent_label_id,category,name,display_name,instructions,variable_type,allowed_values,mandatory,order_index",
          token   = session_rv$token)
        if (!is.data.frame(rows) || nrow(rows) == 0) return(data.frame())
        ord <- ifelse(is.na(rows$order_index), 0L, as.integer(rows$order_index))
        rows[order(ord), , drop = FALSE]
      }, error = function(e) { message("[project_labels] ", e$message); data.frame() })
    })

    # Load existing metadata JSON for an article
    .load_meta <- function(article_id) {
      tryCatch({
        rows <- sb_get("article_metadata_json",
          filters = list(article_id = article_id),
          select  = "json_data",
          token   = session_rv$token)
        if (is.data.frame(rows)) {
         if (nrow(rows) > 0) {
          jd <- rows$json_data[1]
          if (is.character(jd)) {
           if (nchar(jd) > 0) jsonlite::fromJSON(jd, simplifyVector = FALSE)
           else list()
          } else if (is.list(jd)) jd
          else list()
         } else list()
        } else list()
      }, error = function(e) list())
    }

    # --------------------------------------------------------
    # Article selection
    # --------------------------------------------------------
    .select_article <- function(aid) {
      current_article_id(aid)
      loaded_at(Sys.time())

      # Do NOT clear es_started_keys or es_module_entries — module servers
      # are permanent in Shiny and are REUSED across article switches.
      # Their observeEvent(article_id_reactive()) fires automatically
      # when the article changes, loading the correct data.

      # Re-fetch labels so newly added labels are visible
      labels_refresh(labels_refresh() + 1L)

      # Build group_instances from existing metadata
      # Keys are DETERMINISTIC: paste0(gname, "_", j) matching group_instance_id
      meta  <- .load_meta(aid)
      lbls  <- project_labels()
      insts <- list()

      if (is.data.frame(lbls)) { if (nrow(lbls) > 0) {
        pid_col  <- vapply(seq_len(nrow(lbls)), function(r)
          as.character(lbls$parent_label_id[r] %||% "")[1], "")
        pid_col[is.na(pid_col)] <- ""
        grp_rows <- lbls[lbls$label_type == "group" & pid_col == "", ,
                         drop = FALSE]
        for (i in seq_len(nrow(grp_rows))) {
          gname    <- grp_rows$name[i]
          existing <- meta[[gname]]
          n_exist  <- if (is.list(existing)) {
            if (length(existing) > 0) length(existing) else 1L
          } else 1L
          insts[[gname]] <- lapply(seq_len(n_exist), function(j)
            paste0(gname, "_", j))
          # Update monotonic counter to at least n_exist
          es_instance_counter[[gname]] <<- max(
            es_instance_counter[[gname]] %||% 0L, n_exist)
        }
      }}
      group_instances(insts)
    }

    # ---- Effect size module server call ----
    # For top-level effect_size labels (not inside a group), a single module:
    es_module <- mod_effect_size_ui_server(
      "effect_size_form",
      session_rv         = session_rv,
      article_id_reactive = current_article_id,
      project_id_reactive = project_id,
      group_instance_id  = NULL
    )

    # For grouped effect_size labels, modules are started dynamically.
    # Track started keys so we don't start duplicate module servers.
    es_started_keys  <- character(0)         # plain vector (module scope)
    es_module_entries <- list()              # key → list(module, group_name, gi_id)

    # Helper: identify which group names contain an effect_size label
    .find_es_groups <- function(lbls) {
      if (!is.data.frame(lbls) || nrow(lbls) == 0) return(character(0))
      vtype <- as.character(lbls$variable_type)
      pid   <- as.character(lbls$parent_label_id)
      pid[is.na(pid)] <- ""
      lid   <- as.character(lbls$label_id)
      lnm   <- as.character(lbls$name)
      es_idx <- which(vtype == "effect_size" & pid != "")
      if (length(es_idx) == 0) return(character(0))
      parent_ids <- unique(pid[es_idx])
      lnm[which(lid %in% parent_ids)]
    }

    # Start module servers for new group instances that have an effect_size label.
    # Module IDs are DETERMINISTIC (e.g. "es_study_site_1") so they are
    # created exactly once and reused across article switches — eliminating
    # zombie module servers entirely.
    observeEvent(group_instances(), {
      insts <- group_instances()
      aid   <- current_article_id()
      if (is.null(aid)) return()
      lbls <- project_labels()
      es_groups <- .find_es_groups(lbls)
      if (length(es_groups) == 0) return()

      for (gname in es_groups) {
        keys <- insts[[gname]]
        if (is.null(keys)) next
        for (j in seq_along(keys)) {
          key    <- keys[[j]]          # e.g. "study_site_1"
          mod_id <- paste0("es_", key)  # e.g. "es_study_site_1"
          if (!(mod_id %in% es_started_keys)) {
            mod <- mod_effect_size_ui_server(
              mod_id,
              session_rv          = session_rv,
              article_id_reactive = current_article_id,
              project_id_reactive = project_id,
              group_instance_id   = key   # key IS the gi_id
            )
            es_started_keys  <<- c(es_started_keys, mod_id)
            es_module_entries[[mod_id]] <<- list(
              module     = mod,
              group_name = gname,
              key        = key,
              gi_id      = key
            )
          }
        }
      }
    }, ignoreInit = TRUE)

    # Reset when project changes
    observeEvent(project_id(), {
      current_article_id(NULL)
      group_instances(list())
    }, ignoreNULL = TRUE)

    # Auto-select first unreviewed article when articles first load
    observeEvent(all_articles(), {
      if (!is.null(current_article_id())) return()
      df <- all_articles()
      if (!is.data.frame(df) || nrow(df) == 0) return()
      unrev <- df[df$review_status == "unreviewed", , drop = FALSE]
      first <- if (nrow(unrev) > 0) unrev$article_id[1] else df$article_id[1]
      .select_article(first)
    }, ignoreNULL = FALSE)

    # Click handler from list sidebar
    observeEvent(input$select_article, {
      req(input$select_article)
      .select_article(input$select_article)
    })

    # Refresh button — also refreshes labels so newly added labels appear
    observeEvent(input$btn_refresh, {
      articles_refresh(articles_refresh() + 1L)
      labels_refresh(labels_refresh() + 1L)
    })

    # --------------------------------------------------------
    # Progress badge
    # --------------------------------------------------------
    output$progress_badge <- renderUI({
      df <- all_articles()
      if (!is.data.frame(df) || nrow(df) == 0) return(NULL)
      n_done  <- sum(df$review_status %in% c("reviewed", "skipped"), na.rm = TRUE)
      n_total <- nrow(df)
      span(class = "badge bg-secondary fs-6",
           sprintf("Progress: %d / %d", n_done, n_total))
    })

    output$list_count_badge <- renderUI({
      n <- if (is.data.frame(filtered_articles())) nrow(filtered_articles()) else 0L
      span(class = "badge bg-light text-dark ms-2 small", n)
    })

    # --------------------------------------------------------
    # Article list sidebar
    # --------------------------------------------------------
    output$article_list_ui <- renderUI({
      df  <- filtered_articles()
      cid <- current_article_id()

      if (!is.data.frame(df) || nrow(df) == 0)
        return(p(class = "text-muted fst-italic p-3", "No articles found."))

      lapply(seq_len(nrow(df)), function(i) {
        aid    <- df$article_id[i]
        status <- df$review_status[i] %||% "unreviewed"
        active <- if (!is.null(cid)) identical(cid, aid) else FALSE

        status_icon <- switch(status,
          "reviewed" = icon("check-circle", class = "text-success me-1"),
          "skipped"  = icon("forward",      class = "text-warning me-1"),
          icon("circle", class = "text-muted me-1")
        )

        num_lbl <- if (!is.na(df$article_num[i])) df$article_num[i] else i
        ttl     <- if (!is.na(df$title[i])) {
                     if (nchar(df$title[i]) > 0) df$title[i] else sprintf("Article %s", num_lbl)
                   } else sprintf("Article %s", num_lbl)
        short   <- if (nchar(ttl) > 52) paste0(substr(ttl, 1, 52), "…") else ttl
        auth    <- if (!is.na(df$author[i])) {
                     if (nchar(df$author[i]) > 0) df$author[i] else "Unknown author"
                   } else "Unknown author"
        yr      <- if (!is.na(df$year[i])) df$year[i] else ""
        sub_txt <- paste0("ID: ", num_lbl, " · ", auth, " · ", yr)

        div(
          class   = paste("px-2 py-2 border-bottom review-list-item",
                          if (active) "bg-primary text-white" else ""),
          style   = "cursor: pointer;",
          onclick = sprintf('Shiny.setInputValue("%s", "%s", {priority:"event"});',
                            ns("select_article"), aid),
          div(class = "d-flex align-items-start",
            div(class = "mt-1 me-1 flex-shrink-0", status_icon),
            div(
              tags$div(class = paste("fw-semibold",
                                      if (active) "" else ""),
                       style = "font-size:0.85em; line-height:1.2;",
                       short),
              tags$div(class = paste("small",
                                      if (active) "text-white-50" else "text-muted"),
                       sub_txt)
            )
          )
        )
      })
    })

    # --------------------------------------------------------
    # Current article row — cached snapshot so review_panel
    # does NOT depend on all_articles() and won't re-render
    # when articles_refresh() fires after Save.
    # --------------------------------------------------------
    current_article_row <- reactiveVal(NULL)

    observeEvent(current_article_id(), {
      aid <- current_article_id()
      if (is.null(aid)) { current_article_row(NULL); return() }
      df <- all_articles()
      if (!is.data.frame(df) || nrow(df) == 0) { current_article_row(NULL); return() }
      row <- df[df$article_id == aid, , drop = FALSE]
      if (nrow(row) == 0) { current_article_row(NULL); return() }
      current_article_row(row)
    }, ignoreNULL = FALSE)

    # --------------------------------------------------------
    # Review panel (right column)
    # --------------------------------------------------------
    output$review_panel <- renderUI({
      aid <- current_article_id()
      if (is.null(aid)) {
        return(div(class = "card p-5 text-center text-muted",
          icon("book-open", class = "fa-3x mb-3"),
          h5("Select an article from the list to begin reviewing")
        ))
      }

      row <- current_article_row()
      if (is.null(row) || nrow(row) == 0) return(NULL)

      # PDF button
      pdf_link <- row$pdf_drive_link[1]
      has_pdf <- !is.null(pdf_link)
      if (has_pdf) has_pdf <- !is.na(pdf_link)
      if (has_pdf) has_pdf <- nchar(pdf_link) > 0
      pdf_btn <- if (has_pdf) {
        tags$a(href = pdf_link, target = "_blank",
               class = "btn btn-sm btn-outline-primary",
               icon("file-pdf"), " View PDF")
      } else {
        tags$button(
          class    = "btn btn-sm btn-outline-secondary",
          disabled = NA,
          title    = "No PDF linked. Check that a file named [article_num].pdf exists in the project Drive folder and run Sync.",
          icon("file-pdf"), " No PDF"
        )
      }

      # DOI link
      doi <- row$doi_clean[1]
      has_doi <- !is.null(doi)
      if (has_doi) has_doi <- !is.na(doi)
      if (has_doi) has_doi <- nchar(doi) > 0
      doi_ui <- if (has_doi)
        tags$a(href = paste0("https://doi.org/", doi), target = "_blank",
               class = "small", doi)
      else
        span(class = "text-muted small fst-italic", "No DOI")

      # Abstract
      abs_txt <- row$abstract[1]
      has_abs <- !is.null(abs_txt)
      if (has_abs) has_abs <- !is.na(abs_txt)
      if (has_abs) has_abs <- nchar(abs_txt) > 0

      tagList(
        # Article header card
        div(class = "card mb-3",
          div(class = "card-body",
            div(class = "d-flex justify-content-between align-items-start",
              div(class = "me-3",
                h5(class = "card-title mb-1",
                   row$title[1] %||% "Untitled"),
                p(class = "mb-0 small text-muted",
                  tags$strong(paste0("ID: ", if (!is.na(row$article_num[1])) row$article_num[1] else "")),
                  span(class = "mx-1", "·"),
                  row$author[1] %||% "Unknown author",
                  span(class = "mx-1", "·"),
                  row$year[1] %||% "",
                  span(class = "mx-1", "·"),
                  doi_ui
                )
              ),
              pdf_btn
            ),
            # Collapsible abstract
            if (has_abs) {
              div(class = "mt-2",
                tags$details(
                  tags$summary(class = "text-muted small fw-semibold",
                               style = "cursor:pointer;",
                               icon("align-left"), " Abstract"),
                  p(class = "small mt-1 mb-0", abs_txt)
                )
              )
            }
          )
        ),

        # Label form card
        div(class = "card mb-3",
          div(class = "card-header py-2",
            strong(icon("tags"), " Label Form")
          ),
          div(class = "card-body",
            uiOutput(ns("label_form"))
          )
        ),

        # Action buttons
        div(class = "d-flex gap-2 flex-wrap",
          actionButton(ns("btn_save"),
                       tagList(icon("save"), " Save"),
                       class = "btn btn-success"),
          actionButton(ns("btn_next"),
                       tagList(icon("step-forward"), " Next"),
                       class = "btn btn-primary"),
          actionButton(ns("btn_skip"),
                       tagList(icon("forward"), " Skip"),
                       class = "btn btn-outline-warning"),
          actionButton(ns("btn_refresh"),
                       tagList(icon("sync"), " Refresh list"),
                       class = "btn btn-outline-secondary btn-sm")
        )
      )
    })

    # --------------------------------------------------------
    # Label form (re-renders when article or instances change)
    # --------------------------------------------------------
    output$label_form <- renderUI({
      aid  <- current_article_id()
      req(aid)
      group_instances()   # explicit dependency so form re-renders on add/remove

     tryCatch({
      lbls <- project_labels()
      if (!is.data.frame(lbls)) return(p(class = "text-muted fst-italic",
                 "No labels defined. Add labels in the Labels tab."))
      if (nrow(lbls) == 0)
        return(p(class = "text-muted fst-italic",
                 "No labels defined. Add labels in the Labels tab."))

      meta     <- .load_meta(aid)
      # Safely identify top-level labels (no parent)
      pid_col  <- vapply(seq_len(nrow(lbls)), function(r)
        as.character(lbls$parent_label_id[r] %||% "")[1], "")
      pid_col[is.na(pid_col)] <- ""
      top_lbls <- lbls[pid_col == "", , drop = FALSE]

      # Ensure newly-added groups have at least one instance key
      insts    <- group_instances()
      changed  <- FALSE
      for (gi in seq_len(nrow(top_lbls))) {
        gl <- top_lbls[gi, ]
        if (identical(as.character(gl$label_type)[1], "group")) {
          gn <- as.character(gl$name)[1]
          gn_insts <- insts[[gn]]
          if (is.null(gn_insts)) {
            existing <- meta[[gn]]
            n_exist  <- if (is.list(existing)) {
                          if (length(existing) > 0) length(existing) else 1L
                        } else 1L
            insts[[gn]] <- lapply(seq_len(n_exist), function(j)
              paste0(gn, "_", j))
            es_instance_counter[[gn]] <<- max(
              es_instance_counter[[gn]] %||% 0L, n_exist)
            changed <- TRUE
          } else if (length(gn_insts) == 0) {
            # Allow zero instances — user explicitly removed all
          }
        }
      }
      if (changed) {
        group_instances(insts)
        # Return early — the reactive update will re-trigger this renderUI
        return(NULL)
      }

      tagList(lapply(seq_len(nrow(top_lbls)), function(i) {
        lbl <- as.list(top_lbls[i, ])
        if (identical(lbl$label_type, "group")) {
          .render_group(lbl, lbls, meta)
        } else {
          .render_field(lbl, val = meta[[lbl$name]], inst_key = NULL)
        }
      }))
     }, error = function(e) {
      div(class = "alert alert-danger",
        h6("Label form error"),
        p(conditionMessage(e)),
        tags$pre(class = "small", paste(capture.output(traceback()), collapse = "\n"))
      )
     })
    })

    # ---- Helpers: safe scalar check -------------------------
    # Replaces all && / || chains with a safe scalar function
    # that will never error on length > 1 in R >= 4.2
    .safe_scalar <- function(val) {
      # Return scalar val[1] if val is non-NULL, length 1, non-NA scalar
      # For lists/complex objects, returns NULL
      if (is.null(val)) return(NULL)
      if (is.list(val)) return(NULL)
      if (length(val) != 1L) return(NULL)
      v <- val[1L]
      if (is.na(v)) return(NULL)
      v
    }

    # ---- Helpers: UI renderers ----------------------------

    # Render a single input field for one label
    .render_field <- function(lbl, val = NULL, inst_key = NULL) {
     tryCatch({
      base_nm  <- if (!is.null(inst_key))
        paste0("lbl_", lbl$name, "__", inst_key)
      else
        paste0("lbl_", lbl$name)
      input_id <- ns(base_nm)

      # Defensive scalar extraction — guards against length > 1 from DB
      vtype    <- as.character(lbl$variable_type %||% "text")[1]
      disp     <- as.character(lbl$display_name  %||% lbl$name)[1]
      tip      <- as.character(lbl$instructions  %||% "")[1]
      if (is.na(vtype)) vtype <- "text"
      if (is.na(disp))  disp  <- as.character(lbl$name)[1]
      if (is.na(tip))   tip   <- ""
      is_mandatory <- isTRUE(as.logical(lbl$mandatory[1]))
      mstar    <- if (is_mandatory)
        span(class = "text-danger ms-1", "*") else NULL
      lbl_ui   <- tagList(disp, mstar)

      # Flatten val to scalar for types that expect it
      # Uses .safe_scalar() to avoid any && / || on potentially non-scalar values
      val1 <- .safe_scalar(val)

      widget <- switch(vtype,

        "text" =
          textInput(input_id, lbl_ui,
                    value = if (!is.null(val1)) as.character(val1) else ""),

        "integer" =
          numericInput(input_id, lbl_ui,
                       value = if (!is.null(val1)) as.integer(val1) else NA_integer_,
                       step = 1),

        "numeric" =
          numericInput(input_id, lbl_ui,
                       value = if (!is.null(val1)) as.numeric(val1) else NA_real_),

        "boolean" =
          checkboxInput(input_id, lbl_ui, value = isTRUE(val1)),

        "select one" = {
          avs     <- unlist(lbl$allowed_values)
          avs     <- if (!is.null(avs)) { if (length(avs) > 0) avs else character(0) } else character(0)
          choices <- c("-- select --" = "", setNames(avs, avs))
          sel     <- if (!is.null(val1)) as.character(val1) else ""
          selectInput(input_id, lbl_ui, choices = choices, selected = sel)
        },

        "select multiple" = {
          avs     <- unlist(lbl$allowed_values)
          avs     <- if (!is.null(avs)) { if (length(avs) > 0) avs else character(0) } else character(0)
          sel     <- unlist(val)
          sel     <- if (!is.null(sel)) sel else character(0)
          checkboxGroupInput(input_id, lbl_ui, choices = avs, selected = sel)
        },

        "YYYY-MM-DD" = {
          dv <- tryCatch(as.Date(val1), error = function(e) NULL)
          dateInput(input_id, lbl_ui, value = dv)
        },

        "bounding_box" = {
          vb <- if (is.list(val)) val else list()
          tagList(
            p(class = "fw-semibold mb-1 small", lbl_ui),
            div(class = "row g-2",
              div(class = "col-6",
                numericInput(ns(paste0(base_nm, "_lon_min")), "Lon min",
                             value = vb$lon_min %||% NA_real_)),
              div(class = "col-6",
                numericInput(ns(paste0(base_nm, "_lon_max")), "Lon max",
                             value = vb$lon_max %||% NA_real_)),
              div(class = "col-6",
                numericInput(ns(paste0(base_nm, "_lat_min")), "Lat min",
                             value = vb$lat_min %||% NA_real_)),
              div(class = "col-6",
                numericInput(ns(paste0(base_nm, "_lat_max")), "Lat max",
                             value = vb$lat_max %||% NA_real_))
            )
          )
        },

        "openstreetmap_location" = {
          # Parse existing selected locations
          osm_opts <- list()
          osm_sel  <- character(0)

          if (is.list(val)) {
            # val can be a single location {name,lat,lon,osm_id,geojson} or a list of them
            locs <- if (!is.null(val$name)) list(val) else val
            for (loc in locs) {
              if (is.list(loc) && !is.null(loc$name)) {
                obj <- list(
                  name   = loc$name %||% "",
                  lat    = as.numeric(loc$lat %||% NA),
                  lon    = as.numeric(loc$lon %||% NA),
                  osm_id = as.character(loc$osm_id %||% "")
                )
                if (!is.null(loc$geojson)) obj$geojson <- loc$geojson
                geom_type <- if (!is.null(loc$geojson) && !is.null(loc$geojson$type))
                  loc$geojson$type else "none"
                enc <- as.character(jsonlite::toJSON(obj, auto_unbox = TRUE))
                osm_opts <- c(osm_opts, list(list(value = enc, label = loc$name, geom_type = geom_type)))
                osm_sel  <- c(osm_sel, enc)
              }
            }
          }

          tagList(
            selectizeInput(input_id, lbl_ui,
              choices  = NULL,
              multiple = TRUE,
              options  = list(
                create       = FALSE,
                persist      = FALSE,
                valueField   = "value",
                labelField   = "label",
                searchField  = "label",
                options      = osm_opts,
                items        = as.list(osm_sel),
                loadThrottle = 300,
                load = I("function(query, callback) {
                  if (query.length < 3) return callback();
                  fetch('https://nominatim.openstreetmap.org/search?format=json&polygon_geojson=1&limit=10&q=' +
                        encodeURIComponent(query),
                        {headers: {'Accept': 'application/json'}})
                    .then(function(r) { return r.json(); })
                    .then(function(data) {
                      callback(data.map(function(d) {
                        var obj = {
                            name:   d.display_name,
                            lat:    parseFloat(d.lat),
                            lon:    parseFloat(d.lon),
                            osm_id: String(d.osm_id)
                        };
                        if (d.geojson) { obj.geojson = d.geojson; }
                        var geom_type = (d.geojson && d.geojson.type) ? d.geojson.type : 'none';
                        return {
                          value: JSON.stringify(obj),
                          label: d.display_name,
                          geom_type: geom_type
                        };
                      }));
                    })
                    .catch(function() { callback(); });
                }"),
                render = I("{
                  option: function(item, escape) {
                    var gt = item.geom_type || 'none';
                    var color = '#dc3545';
                    var title = 'No geometry data';
                    if (gt === 'Polygon' || gt === 'MultiPolygon') {
                      color = '#198754'; title = 'Polygon / MultiPolygon';
                    } else if (gt !== 'none') {
                      color = '#ffc107'; title = 'Point location';
                    }
                    return '<div style=\"border-left:4px solid ' + color +
                           '; padding-left:6px; padding-top:2px; padding-bottom:2px;\" title=\"' +
                           title + '\">' + escape(item.label) + '</div>';
                  },
                  item: function(item, escape) {
                    var lbl = item.label;
                    var gt = item.geom_type || 'none';
                    var color = '#dc3545';
                    if (gt === 'Polygon' || gt === 'MultiPolygon') {
                      color = '#198754';
                    } else if (gt !== 'none') {
                      color = '#ffc107';
                    }
                    try {
                      var d = JSON.parse(item.value);
                      lbl = d.name || item.label;
                      if (d.lat && d.lon) {
                        lbl += ' (' + Number(d.lat).toFixed(2) + ', ' + Number(d.lon).toFixed(2) + ')';
                      }
                    } catch(e) {}
                    return '<div style=\"border-left:4px solid ' + color +
                           '; padding-left:4px;\">' + escape(lbl) + '</div>';
                  }
                }")
              )
            ),
            tags$div(class = "d-flex flex-wrap gap-3 mt-1",
              tags$small(class = "text-muted",
                "Type at least 3 characters to search OpenStreetMap"),
              tags$small(
                tags$span(style = "display:inline-block;width:10px;height:10px;background:#198754;border-radius:2px;margin-right:3px;"),
                "Polygon / MultiPolygon",
                tags$span(style = "display:inline-block;width:10px;height:10px;background:#ffc107;border-radius:2px;margin-left:8px;margin-right:3px;"),
                "Point",
                tags$span(style = "display:inline-block;width:10px;height:10px;background:#dc3545;border-radius:2px;margin-left:8px;margin-right:3px;"),
                "No geometry"
              )
            )
          )
        },

        "effect_size" = {
          # Render an effect size sub-form for this group instance (or
          # a single top-level form when inst_key is NULL)
          es_id <- if (!is.null(inst_key)) paste0("es_", inst_key)
                   else "effect_size_form"
          mod_effect_size_ui_ui(ns(es_id))
        },

        # Fallback
        textInput(input_id, lbl_ui,
                  value = if (!is.null(val1)) as.character(val1) else "")
      )

      div(class = "mb-3",
        if (nchar(tip) > 0L) div(widget, title = tip) else widget
      )
     }, error = function(e) {
      div(class = "alert alert-warning py-1 small mb-3",
        paste0("Field error (", lbl$name, "): ", conditionMessage(e)))
     })
    }

    # Render a group label container with dynamic instance cards
    .render_group <- function(grp_lbl, all_lbls, meta) {
     tryCatch({
      gname      <- as.character(grp_lbl$name)[1]
      disp_name  <- as.character(grp_lbl$display_name %||% gname)[1]
      # Safely find child labels
      cpid <- vapply(seq_len(nrow(all_lbls)), function(r)
        as.character(all_lbls$parent_label_id[r] %||% "")[1], "")
      cpid[is.na(cpid)] <- ""
      child_lbls <- all_lbls[cpid == as.character(grp_lbl$label_id)[1], ,
                              drop = FALSE]
      existing   <- meta[[gname]]
      if (!is.list(existing)) existing <- list()

      inst_keys  <- group_instances()[[gname]]
      if (is.null(inst_keys)) inst_keys <- list()
      n          <- length(inst_keys)

      div(class = "mb-4",
        div(class = "d-flex align-items-center mb-2 gap-2",
          h6(class = "mb-0 fw-bold", icon("layer-group"), " ", disp_name),
          tags$button(
            class   = "btn btn-sm btn-outline-primary",
            onclick = sprintf(
              'Shiny.setInputValue("%s", "%s", {priority:"event"});',
              ns("add_instance"), gname),
            icon("plus"), " Add Instance"
          )
        ),
        if (n == 0)
          p(class = "text-muted fst-italic small",
            "No instances yet. Click 'Add Instance' to begin.")
        else
          tagList(lapply(seq_len(n), function(j) {
            key       <- inst_keys[[j]]
            inst_meta <- if (j <= length(existing)) existing[[j]] else list()

            div(class = "card mb-2 border-secondary",
              div(class = "card-header py-1 d-flex justify-content-between align-items-center bg-light",
                span(class = "fw-semibold small",
                     sprintf("Instance %d", j)),
                tags$button(
                  class   = "btn btn-sm btn-outline-danger",
                  onclick = sprintf(
                    'Shiny.setInputValue("%s", {g:"%s",j:%d}, {priority:"event"});',
                    ns("remove_instance"), gname, j),
                  icon("trash"), " Remove"
                )
              ),
              div(class = "card-body py-2",
                if (nrow(child_lbls) == 0)
                  p(class = "text-muted small",
                    "No child labels defined for this group.")
                else
                  tagList(lapply(seq_len(nrow(child_lbls)), function(k) {
                    child <- as.list(child_lbls[k, ])
                    .render_field(child,
                                  val      = inst_meta[[child$name]],
                                  inst_key = key)
                  }))
              )
            )
          }))
      )
     }, error = function(e) {
      div(class = "alert alert-danger py-1 small mb-4",
        paste0("Group error (", grp_lbl$name, "): ", conditionMessage(e)))
     })
    }

    # --------------------------------------------------------
    # Group instance management observers
    # --------------------------------------------------------
    observeEvent(input$add_instance, {
      gname <- as.character(input$add_instance)[1]
      req(nchar(gname) > 0)
      insts <- group_instances()
      if (is.null(insts[[gname]])) insts[[gname]] <- list()
      # Monotonic counter ensures unique deterministic keys even after removal
      n <- (es_instance_counter[[gname]] %||% length(insts[[gname]])) + 1L
      es_instance_counter[[gname]] <<- n
      new_key <- paste0(gname, "_", n)
      insts[[gname]] <- c(insts[[gname]], list(new_key))
      group_instances(insts)
    })

    observeEvent(input$remove_instance, {
      info <- input$remove_instance
      req(info$g, info$j)
      insts <- group_instances()
      keys  <- insts[[info$g]]
      if (!is.null(keys)) {
        if (length(keys) >= info$j)
          insts[[info$g]] <- keys[-info$j]
      }
      group_instances(insts)
    })

    # --------------------------------------------------------
    # Collect label values from current inputs
    # --------------------------------------------------------
    .collect_values <- function() {
      lbls <- project_labels()
      if (!is.data.frame(lbls) || nrow(lbls) == 0) return(list())

      insts    <- group_instances()
      result   <- list()
      # Safely identify top-level labels
      pid_col  <- vapply(seq_len(nrow(lbls)), function(r)
        as.character(lbls$parent_label_id[r] %||% "")[1], "")
      pid_col[is.na(pid_col)] <- ""
      top_lbls <- lbls[pid_col == "", , drop = FALSE]

      for (i in seq_len(nrow(top_lbls))) {
        lbl   <- as.list(top_lbls[i, ])
        vtype <- as.character(lbl$variable_type %||% "text")[1]
        nm    <- as.character(lbl$name)[1]

        if (identical(lbl$label_type, "group")) {
          # Collect one value-list per instance
          cpid <- vapply(seq_len(nrow(lbls)), function(r)
            as.character(lbls$parent_label_id[r] %||% "")[1], "")
          cpid[is.na(cpid)] <- ""
          child_lbls  <- lbls[cpid == as.character(lbl$label_id)[1], , drop = FALSE]
          group_keys  <- insts[[nm]]
          if (is.null(group_keys)) group_keys <- list()
          inst_values <- lapply(group_keys, function(key) {
            iv <- list()
            for (k in seq_len(nrow(child_lbls))) {
              cl    <- as.list(child_lbls[k, ])
              raw   <- input[[paste0("lbl_", cl$name, "__", key)]]
              if (!is.null(raw))
                iv[[cl$name]] <- .coerce_value(cl$variable_type %||% "text", raw)
            }
            iv
          })
          result[[nm]] <- inst_values

        } else if (identical(vtype, "bounding_box")) {
          base <- paste0("lbl_", nm)
          result[[nm]] <- list(
            lon_min = input[[paste0(base, "_lon_min")]],
            lon_max = input[[paste0(base, "_lon_max")]],
            lat_min = input[[paste0(base, "_lat_min")]],
            lat_max = input[[paste0(base, "_lat_max")]]
          )

        } else if (identical(vtype, "openstreetmap_location")) {
          raw <- input[[paste0("lbl_", nm)]]
          if (!is.null(raw)) { if (length(raw) > 0) {
            result[[nm]] <- lapply(raw, function(v) {
              tryCatch(
                jsonlite::fromJSON(v, simplifyVector = FALSE),
                error = function(e) list(name = as.character(v))
              )
            })
          }}

        } else if (!identical(vtype, "effect_size")) {
          raw <- input[[paste0("lbl_", nm)]]
          if (!is.null(raw))
            result[[nm]] <- .coerce_value(vtype, raw)
        }
      }
      result
    }

    .coerce_value <- function(vtype, val) {
      switch(vtype,
        "integer"         = as.integer(val),
        "numeric"         = as.numeric(val),
        "boolean"         = isTRUE(val),
        "select multiple" = as.list(val),
        "openstreetmap_location" = {
          # val is a character vector of JSON strings from selectizeInput
          lapply(val, function(v) {
            tryCatch(
              jsonlite::fromJSON(v, simplifyVector = FALSE),
              error = function(e) list(name = as.character(v))
            )
          })
        },
        val
      )
    }

    # --------------------------------------------------------
    # Audit log helper
    # --------------------------------------------------------
    .write_audit <- function(article_id, action,
                              old_json = NULL, new_json = NULL) {
      tryCatch({
        body <- list(
          project_id = project_id(),
          user_id    = session_rv$user_id,
          article_id = article_id,
          action     = action,
          timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
        )
        if (!is.null(old_json))
          body$old_json <- jsonlite::toJSON(old_json, auto_unbox = TRUE)
        if (!is.null(new_json))
          body$new_json <- jsonlite::toJSON(new_json, auto_unbox = TRUE)
        sb_post("audit_log", body, token = session_rv$token)
      }, error = function(e) {
        # Non-fatal — log to console only
        message("[audit_log] write failed: ", e$message)
      })
    }

    # --------------------------------------------------------
    # Concurrency conflict check
    # --------------------------------------------------------
    .has_conflict <- function(article_id) {
      la <- loaded_at()
      if (is.null(la)) return(FALSE)
      tryCatch({
        rows <- sb_get("audit_log",
          filters = list(
            article_id = article_id,
            action     = "save",
            user_id    = paste0("neq.", session_rv$user_id),
            timestamp  = paste0("gt.", format(la, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
          ),
          select = "log_id",
          token  = session_rv$token)
        if (is.data.frame(rows)) nrow(rows) > 0 else FALSE
      }, error = function(e) FALSE)
    }

    # --------------------------------------------------------
    # Core save logic (shared by Save and Next)
    # --------------------------------------------------------
    .do_save <- function() {
      aid <- current_article_id()
      req(aid, session_rv$token)

      vals <- .collect_values()

      # Snapshot old metadata for audit log
      old_meta <- tryCatch({
        rows <- sb_get("article_metadata_json",
          filters = list(article_id = aid),
          select  = "json_data",
          token   = session_rv$token)
        if (is.data.frame(rows)) { if (nrow(rows) > 0) rows$json_data[1] else NULL } else NULL
      }, error = function(e) NULL)

      # Upsert metadata
      sb_upsert("article_metadata_json",
        list(article_id = aid,
             json_data  = jsonlite::toJSON(vals, auto_unbox = TRUE)),
        on_conflict = "article_id",
        token       = session_rv$token)

      # Update article review status
      tryCatch(
        sb_patch("articles", "article_id", aid,
          list(review_status = "reviewed",
               reviewed_by   = session_rv$user_id,
               reviewed_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                                      tz = "UTC")),
          token = session_rv$token),
        error = function(e)
          showNotification(paste("Status update failed:", e$message),
                            type = "warning")
      )

      # Compute and save effect sizes synchronously.
      # Determine whether effect_size labels live inside a group (multi-instance)
      # or are top-level (single instance).
      es_groups <- .find_es_groups(project_labels())

      # Helper: build es_body with explicit NA for nullable numeric fields
      # so jsonlite sends JSON null instead of dropping the field entirely.
      # Without this, PATCH operations silently retain stale r/z/var_z values.
      .build_es_body <- function(aid, gi_id, es_inputs, computed) {
        # Use NULL (not NA_real_) for missing numeric values.
        # httr2::req_body_json passes null="null" to jsonlite, so NULL list
        # elements become JSON null → SQL NULL.  NA_real_ would serialize
        # as the string "NA", causing a PostgreSQL 22P02 error.
        .null_if_missing <- function(x) {
          if (!is.null(x) && length(x) == 1 && !is.na(x)) x else NULL
        }
        list(
          article_id        = aid,
          group_instance_id = gi_id,
          raw_effect_json   = es_inputs,
          r                 = .null_if_missing(computed$r),
          z                 = .null_if_missing(computed$z),
          var_z             = .null_if_missing(computed$var_z),
          effect_status     = computed$effect_status %||% "insufficient_data",
          effect_type       = computed$effect_type %||% "zero_order",
          effect_warnings   = if (length(computed$effect_warnings) > 0)
                                as.list(computed$effect_warnings)
                              else list(),
          computed_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
                                     tz = "UTC")
        )
      }

      if (length(es_groups) > 0) {
        # ---- Multi-instance mode: one ES per group instance ----
        insts <- group_instances()

        # Fetch existing effect_size rows so we can PATCH them in place
        # instead of relying on DELETE + INSERT (which fails silently
        # if the DELETE RLS policy is missing — sql/09).
        existing_es_rows <- tryCatch({
          sb_get("effect_sizes",
                 filters = list(article_id = aid),
                 select  = "effect_id,group_instance_id",
                 token   = session_rv$token)
        }, error = function(e) data.frame())

        # Build a lookup: gi_id -> effect_id (keep latest per gi_id)
        existing_eid <- list()
        if (is.data.frame(existing_es_rows) && nrow(existing_es_rows) > 0) {
          for (r_idx in seq_len(nrow(existing_es_rows))) {
            gi <- existing_es_rows$group_instance_id[r_idx]
            if (!is.na(gi)) existing_eid[[gi]] <- existing_es_rows$effect_id[r_idx]
          }
        }

        # Track which gi_ids we've written so we can clean up orphans
        saved_gi_ids <- character(0)

        for (gname in es_groups) {
          keys <- insts[[gname]]
          if (is.null(keys) || length(keys) == 0) next
          for (j in seq_along(keys)) {
            key    <- keys[[j]]
            mod_id <- paste0("es_", key)
            entry  <- es_module_entries[[mod_id]]
            if (is.null(entry)) {
              message(sprintf("[do_save] Module entry not found for %s (instance %d)", mod_id, j))
              next
            }

            es_inputs <- tryCatch(entry$module$collect_inputs(),
                                  error = function(e) {
                                    message("[do_save] collect_inputs error: ", e$message)
                                    NULL
                                  })
            if (is.null(es_inputs)) {
              message(sprintf("[do_save] No ES inputs for %s instance %d (study_design not set?)", gname, j))
              showNotification(
                sprintf("Effect size for %s instance %d was not saved (no study design selected).",
                        gname, j),
                type = "warning", duration = 8)
              next
            }

            # Always use sequential gi_id matching what .select_article() reconstructs
            gi_id <- paste0(gname, "_", j)
            saved_gi_ids <- c(saved_gi_ids, gi_id)

            computed <- tryCatch(
              compute_effect_size(es_inputs),
              error = function(e) {
                message("[effect_size compute] error: ", e$message)
                list(r = NULL, z = NULL, var_z = NULL,
                     effect_status = "insufficient_data",
                     effect_warnings = c(paste("Computation error:", e$message)))
              }
            )

            tryCatch({
              es_body <- .build_es_body(aid, gi_id, es_inputs, computed)

              # PATCH if a row with this gi_id already exists, else INSERT
              eid <- existing_eid[[gi_id]]
              if (!is.null(eid)) {
                sb_patch("effect_sizes", "effect_id", eid, es_body,
                         token = session_rv$token)
                message(sprintf("[do_save] ES patched for %s %s (inst %d): r=%s, z=%s, status=%s",
                                aid, gname, j, computed$r, computed$z,
                                computed$effect_status))
              } else {
                sb_post("effect_sizes", es_body, token = session_rv$token)
                message(sprintf("[do_save] ES inserted for %s %s (inst %d): r=%s, z=%s, status=%s",
                                aid, gname, j, computed$r, computed$z,
                                computed$effect_status))
              }
            }, error = function(e) {
              showNotification(paste("Effect size save failed:", e$message),
                               type = "warning")
              message("[effect_size save] error: ", e$message)
            })

            entry$module$result(computed)
          }
        }

        # Clean up orphaned rows (gi_ids that no longer have instances).
        # Uses DELETE which requires the RLS policy from sql/09.
        orphan_gi_ids <- setdiff(names(existing_eid), saved_gi_ids)
        for (orphan_gi in orphan_gi_ids) {
          tryCatch({
            sb_delete("effect_sizes", "effect_id", existing_eid[[orphan_gi]],
                      token = session_rv$token)
            message(sprintf("[do_save] Deleted orphan ES row: gi=%s, eid=%s",
                            orphan_gi, existing_eid[[orphan_gi]]))
          }, error = function(e) {
            message("[do_save] Orphan delete failed (non-fatal): ", e$message)
          })
        }

      } else {
        # ---- Single-instance mode: top-level ES or no ES ----
        es_inputs <- tryCatch(es_module$collect_inputs(), error = function(e) NULL)
        if (!is.null(es_inputs)) {
          computed <- tryCatch(
            compute_effect_size(es_inputs),
            error = function(e) {
              message("[effect_size compute] error: ", e$message)
              list(r = NULL, z = NULL, var_z = NULL,
                   effect_status = "insufficient_data",
                   effect_warnings = c(paste("Computation error:", e$message)))
            }
          )
          tryCatch({
            existing_es <- sb_get("effect_sizes",
              filters = list(article_id = aid),
              select  = "effect_id",
              token   = session_rv$token)

            es_body <- .build_es_body(aid, NULL, es_inputs, computed)

            if (is.data.frame(existing_es) && nrow(existing_es) > 0) {
              sb_patch("effect_sizes", "effect_id",
                       existing_es$effect_id[1], es_body,
                       token = session_rv$token)
            } else {
              sb_post("effect_sizes", es_body, token = session_rv$token)
            }
            message(sprintf("[do_save] Effect size saved for %s: r=%s, z=%s, var_z=%s, status=%s",
                            aid, computed$r, computed$z, computed$var_z,
                            computed$effect_status))
          }, error = function(e) {
            showNotification(paste("Effect size save failed:", e$message),
                             type = "warning")
            message("[effect_size save] error: ", e$message)
          })
          es_module$result(computed)
        } else {
          es_module$result(NULL)
          message("[do_save] No effect size inputs collected (study_design not set)")
          showNotification(
            "Effect size was not saved (no study design selected).",
            type = "warning", duration = 6)
        }
      }

      # Audit log
      .write_audit(aid, "save", old_json = old_meta, new_json = vals)

      # Concurrency warning
      if (.has_conflict(aid)) {
        showNotification(
          paste("Another reviewer saved changes to this article since you loaded it.",
                "Your save has been recorded. Review the audit log to check for conflicts."),
          type = "warning", duration = 12
        )
      } else {
        showNotification("Saved successfully.", type = "message", duration = 3)
      }

      articles_refresh(articles_refresh() + 1L)
      invisible(TRUE)
    }

    # ---- Navigate to next unreviewed article ---------------
    .go_next <- function() {
      df  <- all_articles()
      aid <- current_article_id()
      if (!is.data.frame(df) || nrow(df) == 0) return()
      unrev <- df[df$review_status == "unreviewed" &
                    df$article_id != aid, , drop = FALSE]
      if (nrow(unrev) > 0)
        .select_article(unrev$article_id[1])
      else
        showNotification("All articles have been reviewed or skipped.",
                         type = "message")
    }

    # --------------------------------------------------------
    # Action button observers
    # --------------------------------------------------------
    observeEvent(input$btn_save, {
      tryCatch(.do_save(), error = function(e)
        showNotification(paste("Save failed:", e$message), type = "error"))
    })

    observeEvent(input$btn_next, {
      ok <- tryCatch({ .do_save(); TRUE },
                     error = function(e) {
                       showNotification(paste("Save failed:", e$message),
                                        type = "error")
                       FALSE
                     })
      if (ok) .go_next()
    })

    observeEvent(input$btn_skip, {
      aid <- current_article_id()
      req(aid, session_rv$token)
      tryCatch({
        sb_patch("articles", "article_id", aid,
          list(review_status = "skipped"),
          token = session_rv$token)
        .write_audit(aid, "skip")
        showNotification("Article skipped.", type = "message", duration = 3)
        articles_refresh(articles_refresh() + 1L)
        .go_next()
      }, error = function(e)
        showNotification(paste("Skip failed:", e$message), type = "error"))
    })

  })
}
