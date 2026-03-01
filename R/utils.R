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
