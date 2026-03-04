# ============================================================
# R/utils.R — Shared utility functions
# ============================================================
# Small, stateless helpers used across the app.

#' Clean a DOI string
#' Strips common prefixes, lowercases, and trims whitespace.
#'
#' @param doi Character string
#' @return    Cleaned DOI, or NA_character_ if input is blank
clean_doi <- function(doi) {
  if (is.na(doi) || nchar(trimws(doi)) == 0) return(NA_character_)
  doi <- trimws(tolower(doi))
  doi <- sub("^https?://", "", doi)
  doi <- sub("^doi\\.org/", "", doi)
  doi <- sub("^doi:", "", doi)
  doi
}

#' Format a POSIXct timestamp for display
#'
#' @param ts  POSIXct or character timestamp
#' @return    Human-readable string, e.g. "21 Feb 2026 14:32"
format_timestamp <- function(ts) {
  if (is.null(ts) || is.na(ts)) return("—")
  format(as.POSIXct(ts, tz = "UTC"), "%d %b %Y %H:%M", tz = "UTC")
}

#' Truncate a string to n characters, adding ellipsis if needed
#'
#' @param x  Character string
#' @param n  Maximum characters
#' @return   Truncated string
str_trunc <- function(x, n = 80) {
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 3), "..."), x)
}

#' Convert a Unix timestamp (seconds) to POSIXct
#'
#' @param ts  Numeric Unix timestamp
#' @return    POSIXct in UTC
unix_to_posixct <- function(ts) {
  as.POSIXct(as.numeric(ts), origin = "1970-01-01", tz = "UTC")
}

#' Render a clickable question-mark icon that shows a Bootstrap tooltip
#'
#' Place next to a field label so users can click the icon for guidance.
#' Tooltips are initialised by www/tooltips.js and triggered on click.
#'
#' @param text  Tooltip text to display when the icon is clicked
#' @return      An inline HTML span tag
tooltip_icon <- function(text) {
  tags$span(
    class               = "tooltip-icon ms-1",
    `data-bs-toggle`    = "tooltip",
    `data-bs-title`     = text,
    `data-bs-trigger`   = "click",
    `data-bs-placement` = "top",
    icon("circle-question")
  )
}

# ---- Toast notification helpers (shinytoastr) ---------------
# These wrap shinytoastr functions with sensible defaults.
# Use toast_error() in tryCatch error handlers for a polished
# non-blocking notification.  Falls back to showNotification()
# if shinytoastr is not loaded.

#' Show an error toast notification
#'
#' @param msg    Message text
#' @param title  Optional toast title (default "Error")
toast_error <- function(msg, title = "Error") {
  if (requireNamespace("shinytoastr", quietly = TRUE)) {
    shinytoastr::toastr_error(msg, title = title,
                              closeButton = TRUE,
                              timeOut = 8000,
                              position = "top-right")
  } else {
    showNotification(msg, type = "error")
  }
}

#' Show a success toast notification
#'
#' @param msg    Message text
#' @param title  Optional toast title (default "Success")
toast_success <- function(msg, title = "Success") {
  if (requireNamespace("shinytoastr", quietly = TRUE)) {
    shinytoastr::toastr_success(msg, title = title,
                                 closeButton = TRUE,
                                 timeOut = 4000,
                                 position = "top-right")
  } else {
    showNotification(msg, type = "message")
  }
}

#' Show a warning toast notification
#'
#' @param msg    Message text
#' @param title  Optional toast title (default "Warning")
toast_warning <- function(msg, title = "Warning") {
  if (requireNamespace("shinytoastr", quietly = TRUE)) {
    shinytoastr::toastr_warning(msg, title = title,
                                 closeButton = TRUE,
                                 timeOut = 6000,
                                 position = "top-right")
  } else {
    showNotification(msg, type = "warning")
  }
}

#' Clone labels from one project to another
#'
#' Copies all labels (single + groups + children) from a source project
#' to a target project. The parent_label_id references are remapped to
#' the newly-created group label UUIDs in the target project.
#' Articles, collaborators, and review data are NOT copied.
#'
#' @param source_project_id UUID of the source project
#' @param target_project_id UUID of the new (target) project
#' @param token             User JWT for Supabase API calls
#' @return Invisible NULL; labels are inserted as a side effect
clone_labels_to_project <- function(source_project_id, target_project_id, token) {
  # 1. Fetch all labels from the source project
  src_labels <- sb_get(
    "labels",
    filters = list(project_id = source_project_id),
    select  = paste0(
      "label_id,project_id,label_type,parent_label_id,category,",
      "name,display_name,instructions,variable_type,",
      "allowed_values,mandatory,order_index"
    ),
    token = token
  )

  if (!is.data.frame(src_labels) || nrow(src_labels) == 0) {
    return(invisible(NULL))
  }

  # Sort by order_index so insertion order is deterministic
  src_labels <- src_labels[order(src_labels$order_index), , drop = FALSE]

  # 2. Map old label_id -> new label_id (filled as we insert)
  id_map <- list()  # old_id -> new_id

  # 3. Insert top-level labels first (parent_label_id IS NULL or empty)
  is_top <- is.na(src_labels$parent_label_id) |
            src_labels$parent_label_id == ""
  top_labels   <- src_labels[is_top, , drop = FALSE]
  child_labels <- src_labels[!is_top, , drop = FALSE]

  for (i in seq_len(nrow(top_labels))) {
    row <- top_labels[i, ]
    body <- list(
      project_id    = target_project_id,
      label_type    = row$label_type,
      category      = if (is.na(row$category)) NULL else row$category,
      name          = row$name,
      display_name  = row$display_name,
      instructions  = if (is.na(row$instructions)) NULL else row$instructions,
      variable_type = row$variable_type,
      mandatory     = as.logical(row$mandatory),
      order_index   = as.integer(row$order_index)
    )
    # allowed_values is TEXT[] — pass as vector if present
    if (!is.null(row$allowed_values) && length(row$allowed_values) > 0) {
      av <- row$allowed_values
      # Handle case where allowed_values is stored as a list column
      if (is.list(av)) av <- unlist(av)
      if (!all(is.na(av))) body$allowed_values <- av
    }
    new_row <- sb_post("labels", body, token = token)
    id_map[[row$label_id]] <- new_row$label_id
  }

  # 4. Insert child labels (with remapped parent_label_id)
  if (nrow(child_labels) > 0) {
    for (i in seq_len(nrow(child_labels))) {
      row <- child_labels[i, ]
      new_parent_id <- id_map[[row$parent_label_id]]
      if (is.null(new_parent_id)) {
        warning(sprintf(
          "clone_labels: skipping child '%s' — parent '%s' not found in id_map",
          row$name, row$parent_label_id))
        next
      }
      body <- list(
        project_id      = target_project_id,
        label_type      = row$label_type,
        parent_label_id = new_parent_id,
        category        = if (is.na(row$category)) NULL else row$category,
        name            = row$name,
        display_name    = row$display_name,
        instructions    = if (is.na(row$instructions)) NULL else row$instructions,
        variable_type   = row$variable_type,
        mandatory       = as.logical(row$mandatory),
        order_index     = as.integer(row$order_index)
      )
      if (!is.null(row$allowed_values) && length(row$allowed_values) > 0) {
        av <- row$allowed_values
        if (is.list(av)) av <- unlist(av)
        if (!all(is.na(av))) body$allowed_values <- av
      }
      new_row <- sb_post("labels", body, token = token)
      id_map[[row$label_id]] <- new_row$label_id
    }
  }

  invisible(NULL)
}

# ---- Parse structured instructions -------------------------
#' Parse label instructions (may be plain text or JSON with value_defs)
#'
#' @param instr  Character string (plain text or JSON)
#' @return       Named list with label_def (string) and value_defs (named list)
parse_label_instructions <- function(instr) {
  if (is.null(instr) || is.na(instr) || nchar(trimws(instr)) == 0)
    return(list(label_def = "", value_defs = list()))
  parsed <- tryCatch(
    jsonlite::fromJSON(instr, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.list(parsed) && !is.null(parsed$label_def))
    return(parsed)
  list(label_def = instr, value_defs = list())
}

# ---- Build label schema JSON for export --------------------
#' Export label schema to JSON with definitions
#'
#' @param labels_df  Data frame of labels from the labels table
#' @return           Character string of pretty-printed JSON
build_label_schema_export <- function(labels_df) {
  if (!is.data.frame(labels_df) || nrow(labels_df) == 0) return("{}")

  has_parent <- !is.na(labels_df$parent_label_id) &
                nchar(as.character(labels_df$parent_label_id)) > 0
  top_df  <- labels_df[!has_parent, , drop = FALSE]
  kids_df <- labels_df[ has_parent, , drop = FALSE]
  top_df  <- top_df[order(top_df$order_index), , drop = FALSE]

  .build_entry <- function(row) {
    entry <- list(type = as.character(row$variable_type),
                  display = as.character(row$display_name))
    if (isTRUE(row$mandatory)) entry$mandatory <- TRUE
    instr <- parse_label_instructions(row$instructions)
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
    if (!is.na(row$category) && nchar(as.character(row$category)) > 0)
      entry$category <- as.character(row$category)
    entry
  }

  schema <- list()
  for (i in seq_len(nrow(top_df))) {
    row <- top_df[i, ]
    key <- as.character(row$name)
    if (is.na(key) || nchar(key) == 0) next

    if (row$label_type == "group") {
      gc <- kids_df[!is.na(kids_df$parent_label_id) &
                      kids_df$parent_label_id == row$label_id, , drop = FALSE]
      gc <- gc[order(gc$order_index), , drop = FALSE]
      child_schema <- list()
      for (j in seq_len(nrow(gc))) {
        ckey <- as.character(gc$name[j])
        if (is.na(ckey) || nchar(ckey) == 0) next
        child_schema[[ckey]] <- .build_entry(gc[j, ])
      }
      grp_entry <- list(type = "group", display = as.character(row$display_name))
      grp_instr <- parse_label_instructions(row$instructions)
      if (nchar(grp_instr$label_def) > 0) grp_entry$definition <- grp_instr$label_def
      if (!is.na(row$category) && nchar(as.character(row$category)) > 0)
        grp_entry$category <- as.character(row$category)
      grp_entry$items <- child_schema
      schema[[key]] <- grp_entry
    } else {
      schema[[key]] <- .build_entry(row)
    }
  }

  jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE)
}

# ---- Import label schema from JSON -------------------------
#' Import a label schema JSON and create labels in the DB
#'
#' @param json_text   Character string of JSON
#' @param project_id  UUID of the target project
#' @param token       User JWT for Supabase API calls
#' @return Invisible NULL; labels are inserted as a side effect
import_label_schema <- function(json_text, project_id, token) {
  schema <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
  if (!is.list(schema) || length(schema) == 0)
    stop("Invalid schema: expected a JSON object with label keys.")

  # Get current max order_index
  existing <- tryCatch(
    sb_get("labels", filters = list(project_id = project_id),
           select = "order_index", token = token),
    error = function(e) data.frame()
  )
  next_order <- if (is.data.frame(existing) && nrow(existing) > 0)
    max(existing$order_index, na.rm = TRUE) + 1L else 1L

  # Build structured instructions from definition + value definitions
  .build_instructions <- function(entry) {
    label_def <- entry$definition %||% ""
    value_defs <- list()
    if (!is.null(entry$values) && is.list(entry$values)) {
      for (v in entry$values) {
        if (!is.null(v$definition) && nchar(v$definition) > 0)
          value_defs[[v$value]] <- v$definition
      }
    }
    if (nchar(label_def) == 0 && length(value_defs) == 0) return("")
    as.character(jsonlite::toJSON(
      list(label_def = label_def, value_defs = value_defs),
      auto_unbox = TRUE
    ))
  }

  for (key in names(schema)) {
    entry <- schema[[key]]
    ltype <- entry$type %||% "text"

    if (identical(ltype, "group")) {
      # Create group
      body <- list(
        project_id    = project_id,
        label_type    = "group",
        name          = key,
        display_name  = entry$display %||% key,
        variable_type = "text",
        mandatory     = FALSE,
        order_index   = next_order
      )
      if (!is.null(entry$category)) body$category <- entry$category
      instr <- .build_instructions(entry)
      if (nchar(instr) > 0) body$instructions <- instr
      grp <- sb_post("labels", body, token = token)
      next_order <- next_order + 1L

      # Create children
      items <- entry$items %||% list()
      child_order <- 1L
      for (child_key in names(items)) {
        child <- items[[child_key]]
        child_body <- list(
          project_id      = project_id,
          label_type      = "single",
          parent_label_id = grp$label_id,
          name            = child_key,
          display_name    = child$display %||% child_key,
          variable_type   = child$type %||% "text",
          mandatory       = isTRUE(child$mandatory),
          order_index     = child_order
        )
        if (!is.null(child$category)) child_body$category <- child$category
        # Extract allowed values from values array
        if (!is.null(child$values) && is.list(child$values)) {
          child_body$allowed_values <- vapply(child$values, function(v)
            v$value %||% as.character(v), character(1))
        }
        c_instr <- .build_instructions(child)
        if (nchar(c_instr) > 0) child_body$instructions <- c_instr
        sb_post("labels", child_body, token = token)
        child_order <- child_order + 1L
      }
    } else {
      # Single label
      body <- list(
        project_id    = project_id,
        label_type    = "single",
        name          = key,
        display_name  = entry$display %||% key,
        variable_type = ltype,
        mandatory     = isTRUE(entry$mandatory),
        order_index   = next_order
      )
      if (!is.null(entry$category)) body$category <- entry$category
      if (!is.null(entry$values) && is.list(entry$values)) {
        body$allowed_values <- vapply(entry$values, function(v)
          v$value %||% as.character(v), character(1))
      }
      instr <- .build_instructions(entry)
      if (nchar(instr) > 0) body$instructions <- instr
      sb_post("labels", body, token = token)
      next_order <- next_order + 1L
    }
  }

  invisible(NULL)
}
