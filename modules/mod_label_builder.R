# ============================================================
# modules/mod_label_builder.R — Label builder tab
# ============================================================
# Phase 4: Full implementation.
# Supports all variable types, group containers, up/down
# reordering, edit, delete (with reviewed-article warning),
# and a JSON schema preview panel.
# ============================================================

# ─── UI ──────────────────────────────────────────────────────
mod_label_builder_ui <- function(id) {
  ns <- NS(id)
  tagList(
    div(class = "container-fluid py-3",
      uiOutput(ns("owner_banner")),
      uiOutput(ns("toolbar_ui")),
      div(class = "row g-3",
        div(class = "col-xl-7 col-lg-12",
          uiOutput(ns("label_list_ui"))
        ),
        div(class = "col-xl-5 col-lg-12",
          uiOutput(ns("json_preview_ui"))
        )
      )
    )
  )
}

# ─── Server ──────────────────────────────────────────────────
mod_label_builder_server <- function(id, project_id, session_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Refresh trigger ───────────────────────────────────────
    labels_refresh <- reactiveVal(0)

    # ── Load labels from Supabase ─────────────────────────────
    labels_df <- reactive({
      labels_refresh()
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        rows <- sb_get(
          "labels",
          filters = list(project_id = pid),
          select  = paste(
            "label_id,project_id,label_type,parent_label_id,category,",
            "name,display_name,instructions,variable_type,",
            "allowed_values,mandatory,order_index",
            sep = ""
          ),
          token = session_rv$token
        )
        if (!is.data.frame(rows) || nrow(rows) == 0) return(data.frame())
        rows[order(rows$order_index), , drop = FALSE]
      }, error = function(e) {
        showNotification(paste("Error loading labels:", e$message), type = "error")
        data.frame()
      })
    })

    # ── Is current user the project owner? ───────────────────
    is_owner <- reactive({
      pid <- project_id()
      req(pid, session_rv$token)
      tryCatch({
        rows <- sb_get("projects",
                       filters = list(project_id = pid),
                       select  = "owner_id",
                       token   = session_rv$token)
        is.data.frame(rows) && nrow(rows) > 0 &&
          !is.null(rows$owner_id[1]) &&
          rows$owner_id[1] == session_rv$user_id
      }, error = function(e) FALSE)
    })

    # ── Owner banner (for reviewers) ─────────────────────────
    output$owner_banner <- renderUI({
      if (!isTRUE(is_owner())) {
        div(class = "alert alert-info mb-3",
          icon("info-circle"), " Only the project owner can manage labels. ",
          "Labels defined here will appear in the Review tab for all members."
        )
      }
    })

    # ── Toolbar (Add Label / Add Label Group / Export / Import) ─
    output$toolbar_ui <- renderUI({
      req(isTRUE(is_owner()))
      div(class = "d-flex gap-2 mb-3 flex-wrap",
        actionButton(ns("btn_add_label"),
                     tagList(icon("plus"), " Add Label"),
                     class = "btn btn-primary btn-sm"),
        actionButton(ns("btn_add_group"),
                     tagList(icon("layer-group"), " Add Label Group"),
                     class = "btn btn-outline-primary btn-sm"),
        downloadButton(ns("btn_export_schema"),
                       tagList(icon("download"), " Export Schema"),
                       class = "btn btn-outline-secondary btn-sm ms-auto"),
        fileInput(ns("import_schema_file"), label = NULL,
                  accept = ".json",
                  buttonLabel = tagList(icon("upload"), " Import Schema"),
                  placeholder = "No file",
                  width = "220px")
      )
    })

    # ── Label list ───────────────────────────────────────────
    output$label_list_ui <- renderUI({
      df    <- labels_df()
      owner <- isTRUE(is_owner())

      if (!is.data.frame(df) || nrow(df) == 0) {
        return(
          div(class = "text-center text-muted py-5 border rounded bg-light",
            icon("tags", class = "fa-3x mb-3"),
            h5("No labels yet"),
            if (owner)
              p("Use the buttons above to add your first label or label group.")
            else
              p("The project owner has not added any labels yet.")
          )
        )
      }

      # Split top-level vs children
      has_parent <- !is.na(df$parent_label_id) & nchar(df$parent_label_id) > 0
      top_df  <- df[!has_parent, , drop = FALSE]
      kids_df <- df[ has_parent, , drop = FALSE]

      tagList(
        lapply(seq_len(nrow(top_df)), function(i) {
          row <- top_df[i, ]

          if (row$label_type == "group") {
            gc <- kids_df[!is.na(kids_df$parent_label_id) &
                            kids_df$parent_label_id == row$label_id, , drop = FALSE]
            gc <- gc[order(gc$order_index), , drop = FALSE]

            div(class = "card mb-2 border-primary",
              div(class = "card-header bg-primary bg-opacity-10 d-flex align-items-center gap-1",
                span(class = "me-auto fw-bold",
                  icon("layer-group", class = "me-1 text-primary"),
                  row$display_name,
                  span(class = "badge bg-primary ms-1 fw-normal", "GROUP"),
                  if (!is.na(row$category) && nchar(row$category) > 0)
                    span(class = "badge bg-secondary ms-1 fw-normal small",
                         row$category)
                ),
                .lbl_reorder_btns(ns, row$label_id, i, nrow(top_df)),
                .lbl_action_btns(ns, row$label_id, owner)
              ),
              div(class = "card-body py-2",
                if (nrow(gc) > 0)
                  tagList(lapply(seq_len(nrow(gc)), function(j) {
                    .lbl_row_card(ns, gc[j, ], j, nrow(gc),
                                  is_child = TRUE, owner = owner)
                  })),
                if (owner)
                  div(class = "mt-1",
                    tags$button(
                      class   = "btn btn-outline-primary btn-sm",
                      onclick = sprintf(
                        'Shiny.setInputValue("%s", "%s", {priority:"event"})',
                        ns("add_child_to_group"), row$label_id),
                      tagList(icon("plus"), " Add Child Label")
                    )
                  )
              )
            )
          } else {
            .lbl_row_card(ns, row, i, nrow(top_df),
                          is_child = FALSE, owner = owner)
          }
        })
      )
    })

    # ── JSON Preview ─────────────────────────────────────────
    output$json_preview_ui <- renderUI({
      df        <- labels_df()
      json_text <- if (!is.data.frame(df) || nrow(df) == 0) {
        "{}"
      } else {
        .label_schema_json(df)
      }
      div(class = "card",
        div(class = "card-header d-flex align-items-center",
          span(icon("code"), " JSON Schema Preview"),
          span(class = "text-muted small ms-auto",
               "Reflects current saved labels")
        ),
        div(class = "card-body p-0",
          tags$pre(
            class = "m-0 p-3 bg-light rounded-bottom",
            style = paste0(
              "max-height:460px;overflow-y:auto;",
              "font-size:0.72rem;white-space:pre-wrap;",
              "word-break:break-word;"
            ),
            json_text
          )
        )
      )
    })

    # ══════════════════════════════════════════════════════════
    # EXPORT / IMPORT SCHEMA
    # ══════════════════════════════════════════════════════════

    output$btn_export_schema <- downloadHandler(
      filename = function() {
        paste0("label_schema_", format(Sys.Date(), "%Y%m%d"), ".json")
      },
      content = function(file) {
        df <- labels_df()
        json <- build_label_schema_export(df)
        writeLines(json, file)
      }
    )

    observeEvent(input$import_schema_file, {
      req(input$import_schema_file)
      fpath <- input$import_schema_file$datapath
      tryCatch({
        json_text <- paste(readLines(fpath, warn = FALSE), collapse = "\n")
        pid <- project_id()
        import_label_schema(json_text, pid, session_rv$token)
        labels_refresh(labels_refresh() + 1)
        showNotification("Label schema imported successfully.", type = "message")
      }, error = function(e) {
        showNotification(paste("Import failed:", e$message), type = "error")
      })
    })

    # ══════════════════════════════════════════════════════════
    # ADD / EDIT LABEL MODAL
    # ══════════════════════════════════════════════════════════

    editing_label_id  <- reactiveVal(NULL)
    adding_to_group   <- reactiveVal(NULL)   # group UUID or NULL

    # ---- Open modal for new label ---------------------------
    observeEvent(input$btn_add_label, {
      editing_label_id(NULL)
      adding_to_group(NULL)
      .show_label_modal(ns       = ns,
                        mode     = "add",
                        input    = input,
                        groups   = .get_groups(labels_df()))
    })

    # ---- Open modal for new child label ---------------------
    observeEvent(input$add_child_to_group, {
      gid <- input$add_child_to_group
      req(gid)
      editing_label_id(NULL)
      adding_to_group(gid)
      .show_label_modal(ns       = ns,
                        mode     = "add_child",
                        input    = input,
                        groups   = .get_groups(labels_df()),
                        group_id = gid)
    })

    # ---- Open modal to edit existing label ------------------
    observeEvent(input$edit_label_id, {
      lid <- input$edit_label_id
      req(lid)
      editing_label_id(lid)
      adding_to_group(NULL)
      df  <- labels_df()
      row <- df[df$label_id == lid, , drop = FALSE]
      if (nrow(row) == 0) return()
      .show_label_modal(ns        = ns,
                        mode      = "edit",
                        input     = input,
                        groups    = .get_groups(df),
                        label_row = as.list(row[1, ]))
    })

    # ---- Save label (insert or update) ----------------------
    observeEvent(input$confirm_save_label, {
      pid          <- project_id()
      dname        <- trimws(input$lbl_display_name %||% "")
      mname        <- trimws(input$lbl_name         %||% "")
      category     <- trimws(input$lbl_category     %||% "")
      vtype        <- input$lbl_variable_type       %||% "text"
      mandatory    <- isTRUE(input$lbl_mandatory)
      label_def    <- trimws(input$lbl_instructions %||% "")
      allowed_raw  <- trimws(input$lbl_allowed_values %||% "")

      if (nchar(dname) == 0 || nchar(mname) == 0) {
        showNotification("Display name and machine name are required.",
                         type = "warning")
        return()
      }
      if (!grepl("^[a-z0-9_]+$", mname)) {
        showNotification(
          "Machine name may only contain lowercase letters, digits, and underscores.",
          type = "warning")
        return()
      }

      allowed_values <- if (vtype %in% c("select one", "select multiple") &&
                            nchar(allowed_raw) > 0) {
        trimws(unlist(strsplit(allowed_raw, "\n")))
      } else {
        character(0)
      }

      # Build structured instructions with value definitions
      instructions <- label_def
      if (vtype %in% c("select one", "select multiple") &&
          length(allowed_values) > 0) {
        value_defs <- list()
        for (av in allowed_values) {
          vdef <- trimws(input[[paste0("lbl_valdef_", gsub("[^a-zA-Z0-9]", "_", av))]] %||% "")
          if (nchar(vdef) > 0) value_defs[[av]] <- vdef
        }
        if (length(value_defs) > 0 || nchar(label_def) > 0) {
          instr_obj <- list(label_def = label_def, value_defs = value_defs)
          instructions <- jsonlite::toJSON(instr_obj, auto_unbox = TRUE)
        }
      }

      if (nchar(dname) == 0 || nchar(mname) == 0) {
        showNotification("Display name and machine name are required.",
                         type = "warning")
        return()
      }
      if (!grepl("^[a-z0-9_]+$", mname)) {
        showNotification(
          "Machine name may only contain lowercase letters, digits, and underscores.",
          type = "warning")
        return()
      }

      allowed_values <- if (vtype %in% c("select one", "select multiple") &&
                            nchar(allowed_raw) > 0) {
        trimws(unlist(strsplit(allowed_raw, "\n")))
      } else {
        character(0)
      }

      # Determine parent group
      gid <- adding_to_group()
      parent_id <- if (!is.null(gid) && nchar(gid) > 0) {
        gid
      } else if (!is.null(input$lbl_parent_group) &&
                 nchar(input$lbl_parent_group) > 0) {
        input$lbl_parent_group
      } else {
        NULL
      }

      df         <- labels_df()
      next_order <- if (nrow(df) == 0) 1L else
                    max(df$order_index, na.rm = TRUE) + 1L

      body <- list(
        project_id    = pid,
        label_type    = "single",
        name          = mname,
        display_name  = dname,
        variable_type = vtype,
        mandatory     = mandatory
      )
      if (nchar(category)     > 0) body$category     <- category
      if (nchar(instructions) > 0) body$instructions <- instructions
      if (!is.null(parent_id))     body$parent_label_id <- parent_id
      if (length(allowed_values) > 0) body$allowed_values <- allowed_values

      eid <- editing_label_id()

      tryCatch({
        if (!is.null(eid)) {
          sb_patch("labels", "label_id", eid, body, token = session_rv$token)
          removeModal()
          showNotification("Label updated.", type = "message")
        } else {
          body$order_index <- next_order
          sb_post("labels", body, token = session_rv$token)
          removeModal()
          showNotification("Label added.", type = "message")
        }
        editing_label_id(NULL)
        adding_to_group(NULL)
        labels_refresh(labels_refresh() + 1)
      }, error = function(e) {
        showNotification(paste("Error saving label:", e$message), type = "error")
      })
    })

    # ══════════════════════════════════════════════════════════
    # ADD LABEL GROUP MODAL
    # ══════════════════════════════════════════════════════════

    observeEvent(input$btn_add_group, {
      showModal(modalDialog(
        title     = "Add Label Group",
        size      = "m",
        easyClose = TRUE,
        footer    = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_add_group"), "Add Group",
                       class = "btn btn-primary")
        ),
        textInput(ns("grp_display_name"), "Group Display Name *",
                  placeholder = "e.g. Study Site"),
        .auto_name_js(ns, "grp_display_name", "grp_name"),
        textInput(ns("grp_name"), "Machine Name *",
                  placeholder = "e.g. study_site"),
        p(class = "text-muted small mt-n2 mb-2",
          "Auto-derived from display name. Used as the JSON key. No spaces."),
        textInput(ns("grp_category"), "Category",
                  placeholder = "e.g. Location data"),
        textAreaInput(ns("grp_instructions"), "Instructions / Tooltip",
                      rows = 2,
                      placeholder = "Guidance text shown to reviewer")
      ))
    })

    observeEvent(input$confirm_add_group, {
      pid          <- project_id()
      dname        <- trimws(input$grp_display_name %||% "")
      mname        <- trimws(input$grp_name         %||% "")
      category     <- trimws(input$grp_category     %||% "")
      instructions <- trimws(input$grp_instructions %||% "")

      if (nchar(dname) == 0 || nchar(mname) == 0) {
        showNotification("Display name and machine name are required.",
                         type = "warning")
        return()
      }
      if (!grepl("^[a-z0-9_]+$", mname)) {
        showNotification(
          "Machine name may only contain lowercase letters, digits, and underscores.",
          type = "warning")
        return()
      }

      df         <- labels_df()
      next_order <- if (nrow(df) == 0) 1L else
                    max(df$order_index, na.rm = TRUE) + 1L

      body <- list(
        project_id    = pid,
        label_type    = "group",
        name          = mname,
        display_name  = dname,
        variable_type = "text",   # required by DB CHECK; irrelevant for groups
        mandatory     = FALSE,
        order_index   = next_order
      )
      if (nchar(category)     > 0) body$category     <- category
      if (nchar(instructions) > 0) body$instructions <- instructions

      tryCatch({
        sb_post("labels", body, token = session_rv$token)
        removeModal()
        showNotification("Label group added.", type = "message")
        labels_refresh(labels_refresh() + 1)
      }, error = function(e) {
        showNotification(paste("Error adding group:", e$message), type = "error")
      })
    })

    # ══════════════════════════════════════════════════════════
    # DELETE LABEL
    # ══════════════════════════════════════════════════════════

    deleting_label_id <- reactiveVal(NULL)

    observeEvent(input$delete_label_id, {
      lid <- input$delete_label_id
      req(lid)
      deleting_label_id(lid)

      df    <- labels_df()
      row   <- df[df$label_id == lid, , drop = FALSE]
      dname <- if (nrow(row) > 0) row$display_name[1] else lid

      # Warn if project has any reviewed articles
      pid      <- project_id()
      has_data <- tryCatch({
        arts <- sb_get("articles",
                       filters = list(project_id    = pid,
                                      review_status = "eq.reviewed"),
                       select  = "article_id",
                       token   = session_rv$token)
        is.data.frame(arts) && nrow(arts) > 0
      }, error = function(e) FALSE)

      showModal(modalDialog(
        title     = "Delete Label?",
        size      = "s",
        easyClose = TRUE,
        footer    = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_delete_label"), "Delete",
                       class = "btn btn-danger")
        ),
        p("Delete label ", tags$strong(dname), "?"),
        if (has_data)
          div(class = "alert alert-warning mt-2 small",
            icon("exclamation-triangle"), " This project has reviewed articles.",
            " Deleting this label will NOT remove existing coded data, but the",
            " label will no longer appear in new reviews.")
        else
          p(class = "text-muted small", "This action cannot be undone.")
      ))
    })

    observeEvent(input$confirm_delete_label, {
      lid <- deleting_label_id()
      req(lid)

      df  <- labels_df()
      row <- df[df$label_id == lid, , drop = FALSE]

      tryCatch({
        # Delete children first (cascade should handle it, but be explicit)
        if (nrow(row) > 0 && row$label_type[1] == "group") {
          child_ids <- df$label_id[
            !is.na(df$parent_label_id) & df$parent_label_id == lid
          ]
          for (cid in child_ids) {
            sb_delete("labels", "label_id", cid, token = session_rv$token)
          }
        }
        sb_delete("labels", "label_id", lid, token = session_rv$token)
        removeModal()
        deleting_label_id(NULL)
        showNotification("Label deleted.", type = "message")
        labels_refresh(labels_refresh() + 1)
      }, error = function(e) {
        showNotification(paste("Error deleting label:", e$message), type = "error")
      })
    })

    # ══════════════════════════════════════════════════════════
    # REORDER (up / down arrows)
    # ══════════════════════════════════════════════════════════

    .do_reorder <- function(move_id, direction) {
      df <- labels_df()
      if (nrow(df) == 0) return()

      row_i <- which(df$label_id == move_id)
      if (length(row_i) == 0) return()

      parent_val <- df$parent_label_id[row_i]
      is_top     <- is.na(parent_val) | nchar(parent_val) == 0

      # Work within the same sibling scope
      scope <- if (is_top) {
        df[is.na(df$parent_label_id) | nchar(df$parent_label_id) == 0, , drop = FALSE]
      } else {
        df[!is.na(df$parent_label_id) & df$parent_label_id == parent_val, , drop = FALSE]
      }
      scope <- scope[order(scope$order_index), , drop = FALSE]
      pos   <- which(scope$label_id == move_id)
      if (length(pos) == 0) return()

      swap_pos <- if (direction == "up"   && pos > 1)          pos - 1L else
                  if (direction == "down" && pos < nrow(scope)) pos + 1L else return()

      id_a <- scope$label_id[pos];      oi_a <- scope$order_index[pos]
      id_b <- scope$label_id[swap_pos]; oi_b <- scope$order_index[swap_pos]

      tryCatch({
        sb_patch("labels", "label_id", id_a,
                 list(order_index = oi_b), token = session_rv$token)
        sb_patch("labels", "label_id", id_b,
                 list(order_index = oi_a), token = session_rv$token)
        labels_refresh(labels_refresh() + 1)
      }, error = function(e) {
        showNotification(paste("Reorder error:", e$message), type = "error")
      })
    }

    observeEvent(input$move_up_id,   { .do_reorder(input$move_up_id,   "up")   })
    observeEvent(input$move_down_id, { .do_reorder(input$move_down_id, "down") })

  })
}

# ══════════════════════════════════════════════════════════════
# MODULE-LEVEL HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════

# ---- Extract group labels from a label data frame -----------
.get_groups <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) return(data.frame())
  df[df$label_type == "group", , drop = FALSE]
}

# ---- Reorder arrow buttons ----------------------------------
.lbl_reorder_btns <- function(ns, label_id, pos, total) {
  tagList(
    tags$button(
      class   = if (pos > 1)
                  "btn btn-sm btn-outline-secondary me-1"
                else
                  "btn btn-sm btn-outline-secondary me-1 disabled",
      title   = "Move up",
      onclick = if (pos > 1) sprintf(
        'Shiny.setInputValue("%s","%s",{priority:"event"})',
        ns("move_up_id"), label_id) else NULL,
      icon("arrow-up")
    ),
    tags$button(
      class   = if (pos < total)
                  "btn btn-sm btn-outline-secondary me-1"
                else
                  "btn btn-sm btn-outline-secondary me-1 disabled",
      title   = "Move down",
      onclick = if (pos < total) sprintf(
        'Shiny.setInputValue("%s","%s",{priority:"event"})',
        ns("move_down_id"), label_id) else NULL,
      icon("arrow-down")
    )
  )
}

# ---- Edit / Delete buttons ----------------------------------
.lbl_action_btns <- function(ns, label_id, owner) {
  if (!owner) return(NULL)
  tagList(
    tags$button(
      class   = "btn btn-sm btn-outline-secondary me-1",
      title   = "Edit label",
      onclick = sprintf(
        'Shiny.setInputValue("%s","%s",{priority:"event"})',
        ns("edit_label_id"), label_id),
      icon("pencil")
    ),
    tags$button(
      class   = "btn btn-sm btn-outline-danger",
      title   = "Delete label",
      onclick = sprintf(
        'Shiny.setInputValue("%s","%s",{priority:"event"})',
        ns("delete_label_id"), label_id),
      icon("trash")
    )
  )
}

# ---- Single label row card ----------------------------------
.lbl_row_card <- function(ns, row, pos, total, is_child, owner) {
  vt_class <- switch(
    row$variable_type,
    "text"                   = "bg-secondary",
    "integer"                = "bg-info text-dark",
    "numeric"                = "bg-info text-dark",
    "boolean"                = "bg-warning text-dark",
    "select one"             = "bg-success",
    "select multiple"        = "bg-success",
    "YYYY-MM-DD"             = "bg-secondary",
    "bounding_box"           = "bg-dark",
    "openstreetmap_location" = "bg-dark",
    "effect_size"            = "bg-danger",
    "bg-secondary"
  )

  div(
    class = paste0(
      "d-flex align-items-center flex-wrap border rounded px-3 py-2 mb-1 bg-white",
      if (is_child) " ms-3" else ""
    ),
    div(class = "me-auto d-flex align-items-center flex-wrap gap-2",
      span(class = "fw-semibold", row$display_name),
      span(class = paste("badge", vt_class), row$variable_type),
      if (!is.na(row$category) && nchar(row$category) > 0)
        span(class = "badge bg-light text-dark border small",
             row$category),
      if (isTRUE(row$mandatory))
        span(class = "badge bg-warning text-dark",
             icon("asterisk"), " required"),
      if (!is.na(row$name) && nchar(row$name) > 0)
        tags$code(class = "text-muted small", row$name)
    ),
    .lbl_reorder_btns(ns, row$label_id, pos, total),
    .lbl_action_btns(ns, row$label_id, owner)
  )
}

# ---- Show Add / Edit label modal ----------------------------
.show_label_modal <- function(ns, mode, input, groups,
                               label_row = NULL, group_id = NULL) {
  is_edit <- mode == "edit"

  group_choices <- c(
    "(None — top level)" = "",
    setNames(groups$label_id, groups$display_name)
  )

  selected_group <- if (!is.null(group_id)) {
    group_id
  } else if (is_edit && !is.na(label_row$parent_label_id) &&
             nchar(label_row$parent_label_id) > 0) {
    label_row$parent_label_id
  } else {
    ""
  }

  # Reconstruct allowed_values string for editing
  av_str <- ""
  av_vec <- character(0)
  if (is_edit) {
    av <- label_row$allowed_values
    if (!is.null(av) && length(av) > 0 && !all(is.na(av))) {
      av_vec <- unlist(av)
      av_str <- paste(av_vec, collapse = "\n")
    }
  }

  # Parse structured instructions (label_def + value_defs)
  instr_text <- ""
  value_defs <- list()
  if (is_edit && !is.na(label_row$instructions) &&
      nchar(label_row$instructions) > 0) {
    parsed <- tryCatch(
      jsonlite::fromJSON(label_row$instructions, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.list(parsed) && !is.null(parsed$label_def)) {
      instr_text <- parsed$label_def %||% ""
      value_defs <- parsed$value_defs %||% list()
    } else {
      # Plain text instructions (backward compat)
      instr_text <- label_row$instructions
    }
  }

  # Build value definition inputs for existing allowed values
  val_def_ui <- NULL
  if (is_edit && label_row$variable_type %in% c("select one", "select multiple") &&
      length(av_vec) > 0) {
    val_def_ui <- div(id = ns("value_defs_container"),
      class = "mt-3 p-2 border rounded bg-light",
      h6(class = "fw-semibold mb-2", icon("book"), " Value Definitions"),
      p(class = "text-muted small mb-2",
        "Optional: define each allowed value for reviewer guidance."),
      tagList(lapply(av_vec, function(v) {
        safe_id <- gsub("[^a-zA-Z0-9]", "_", v)
        existing_def <- value_defs[[v]] %||% ""
        textInput(ns(paste0("lbl_valdef_", safe_id)),
                  label = v,
                  value = existing_def,
                  placeholder = paste0("Definition for '", v, "'"))
      }))
    )
  }

  showModal(modalDialog(
    title     = switch(mode,
                  edit      = "Edit Label",
                  add_child = "Add Child Label",
                  "Add Label"),
    size      = "l",
    easyClose = TRUE,
    footer    = tagList(
      modalButton("Cancel"),
      actionButton(ns("confirm_save_label"),
                   if (is_edit) "Save Changes" else "Add Label",
                   class = "btn btn-primary")
    ),

    div(class = "row g-3",
      # ── Left column ──────────────────────────────────────
      div(class = "col-md-6",
        textInput(ns("lbl_display_name"), "Display Name *",
                  value       = if (is_edit) label_row$display_name else "",
                  placeholder = "e.g. Country of study"),
        .auto_name_js(ns, "lbl_display_name", "lbl_name"),
        textInput(ns("lbl_name"), "Machine Name *",
                  value       = if (is_edit) label_row$name else "",
                  placeholder = "e.g. country_of_study"),
        p(class = "text-muted small mt-n2 mb-2",
          "Auto-derived. Used as the JSON key. Lowercase letters, digits,",
          " underscores only."),
        textInput(ns("lbl_category"), "Category",
                  value       = if (is_edit && !is.na(label_row$category))
                                  label_row$category else "",
                  placeholder = "e.g. Study details"),
        if (mode != "add_child") {
          selectInput(ns("lbl_parent_group"),
                      "Add to Group (optional)",
                      choices  = group_choices,
                      selected = selected_group)
        }
      ),

      # ── Right column ─────────────────────────────────────
      div(class = "col-md-6",
        selectInput(ns("lbl_variable_type"), "Variable Type *",
                    choices  = c(
                      "text", "integer", "numeric", "boolean",
                      "select one", "select multiple",
                      "YYYY-MM-DD", "bounding_box",
                      "openstreetmap_location", "effect_size"
                    ),
                    selected = if (is_edit) label_row$variable_type else "text"),
        textAreaInput(ns("lbl_allowed_values"),
                      "Allowed Values (one per line)",
                      value = av_str,
                      rows  = 4,
                      placeholder = "e.g.\nForest\nGrassland\nWetland"),
        p(class = "text-muted small mt-n2 mb-2",
          "Only for 'select one' and 'select multiple' types."),
        checkboxInput(ns("lbl_mandatory"), "Mandatory",
                      value = if (is_edit && !is.na(label_row$mandatory))
                                isTRUE(label_row$mandatory) else FALSE),
        textAreaInput(ns("lbl_instructions"), "Label Definition / Tooltip",
                      value = instr_text,
                      rows  = 3,
                      placeholder = "Guidance text shown to reviewer on hover"),
        val_def_ui
      )
    )
  ))
}

# ---- JavaScript: auto-derive machine name from display name -
.auto_name_js <- function(ns, src_id, tgt_id) {
  tags$script(sprintf(
    '(function() {
       var srcId = "#%s";
       var tgtId = "#%s";
       $(document).on("input", srcId, function() {
         var v = $(this).val()
           .toLowerCase()
           .replace(/[^a-z0-9]+/g, "_")
           .replace(/^_+|_+$/, "");
         var $t = $(tgtId);
         if ($t.attr("data-user-edited") !== "true") { $t.val(v).trigger("change"); }
       });
       $(document).on("input", tgtId, function() {
         $(this).attr("data-user-edited", "true");
       });
     })();',
    ns(src_id), ns(tgt_id)
  ))
}

# ---- Build JSON schema preview string -----------------------
.label_schema_json <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) return("{}")

  has_parent <- !is.na(df$parent_label_id) & nchar(df$parent_label_id) > 0
  top_df  <- df[!has_parent, , drop = FALSE]
  kids_df <- df[ has_parent, , drop = FALSE]
  top_df  <- top_df[order(top_df$order_index), , drop = FALSE]

  .parse_instr <- function(instr) {
    if (is.na(instr) || nchar(instr) == 0) return(list(label_def = "", value_defs = list()))
    parsed <- tryCatch(jsonlite::fromJSON(instr, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(parsed) && !is.null(parsed$label_def)) return(parsed)
    list(label_def = instr, value_defs = list())
  }

  .build_entry <- function(row) {
    entry <- list(type = row$variable_type, display = row$display_name)
    if (isTRUE(row$mandatory)) entry$mandatory <- TRUE
    instr <- .parse_instr(row$instructions)
    if (nchar(instr$label_def) > 0) entry$definition <- instr$label_def
    av <- row$allowed_values
    if (is.list(av)) av <- unlist(av)
    if (!is.null(av) && length(av) > 0 && !all(is.na(av))) {
      vals <- lapply(av, function(v) {
        obj <- list(value = v)
        vd <- instr$value_defs[[v]]
        if (!is.null(vd) && nchar(vd) > 0) obj$definition <- vd
        obj
      })
      entry$values <- vals
    }
    entry
  }

schema <- list()

  for (i in seq_len(nrow(top_df))) {
    row  <- top_df[i, ]
    key  <- row$name
    if (is.na(key) || nchar(key) == 0) next

    if (row$label_type == "group") {
      gc <- kids_df[!is.na(kids_df$parent_label_id) &
                      kids_df$parent_label_id == row$label_id, , drop = FALSE]
      gc <- gc[order(gc$order_index), , drop = FALSE]

      child_schema <- list()
      for (j in seq_len(nrow(gc))) {
        ckey <- gc$name[j]
        if (is.na(ckey) || nchar(ckey) == 0) next
        child_schema[[ckey]] <- .build_entry(gc[j, ])
      }

      grp_entry <- list(
        type    = "group",
        display = row$display_name,
        note    = "Stored as JSON array; each article may have multiple instances"
      )
      grp_instr <- .parse_instr(row$instructions)
      if (nchar(grp_instr$label_def) > 0) grp_entry$definition <- grp_instr$label_def
      grp_entry$items <- child_schema
      schema[[key]] <- grp_entry
    } else {
      schema[[key]] <- .build_entry(row)
    }
  }

  jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE)
}

