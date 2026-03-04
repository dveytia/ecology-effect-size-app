# ============================================================
# R/export.R — Export functions
# ============================================================
# Phase 10: Full implementation.
#
# Core functions:
#   unnest_labels()       — Flattens JSONB label data into wide-format columns
#   build_full_export()   — Full export (articles + labels + effects)
#   build_meta_export()   — metafor-ready export (yi, vi, moderators)
#   get_reviewers()       — List of reviewers who have reviewed articles
#   get_effect_statuses() — Distinct effect_status values in a project
# ============================================================

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Safely parse json_data from a single article's metadata row
#'
#' Handles both character JSON strings and already-parsed lists.
#' Also handles the case where a list-column [i] access returns a
#' length-1 wrapper list rather than the actual value.
#'
#' @param jd  Character JSON string, already-parsed list, or a length-1
#'            list-wrapper (from single-bracket extraction on a list column)
#' @return    Named list (empty list on failure)
.parse_json_data <- function(jd) {
  if (is.null(jd)) return(list())
  # Unwrap a single-element list-wrapper (from df$col[i] on list columns)
  if (is.list(jd) && length(jd) == 1 && !is.null(names(jd)) &&
      all(names(jd) == "")) {
    jd <- jd[[1]]
  } else if (is.list(jd) && length(jd) == 1 && is.null(names(jd))) {
    jd <- jd[[1]]
  }
  if (is.null(jd)) return(list())
  # NA scalar
  if (length(jd) == 1 && !is.list(jd) && is.na(jd)) return(list())
  # Already a named list — use directly
  if (is.list(jd)) return(jd)
  # Character JSON string
  if (is.character(jd) && nchar(trimws(jd)) > 0) {
    tryCatch(
      jsonlite::fromJSON(jd, simplifyVector = FALSE),
      error = function(e) list()
    )
  } else {
    list()
  }
}

#' Flatten a single value for export
#'
#' Converts lists/vectors to semicolon-separated strings;
#' keeps scalars as-is; NULLs become NA.
.flatten_value <- function(val) {
  if (is.null(val)) return(NA_character_)
  if (is.list(val)) {
    # Could be a named list (bounding_box, osm location) or unnamed list (select multiple)
    if (!is.null(names(val)) && length(names(val)) > 0) {
      # Named object → collapse key=value pairs
      return(paste(paste0(names(val), "=", unlist(val)), collapse = "; "))
    } else {
      # Unnamed list → semicolon-separated
      return(paste(unlist(val), collapse = "; "))
    }
  }
  if (length(val) > 1) return(paste(val, collapse = "; "))
  as.character(val)
}

#' Flatten raw_effect_json fields with "raw_" prefix
#'
#' @param raw_json  Character JSON string, already-parsed list, or
#'                  list-column wrapper
#' @return          Named list with "raw_" prefixed keys
.flatten_raw_effect <- function(raw_json) {
  if (is.null(raw_json)) return(list())
  # Unwrap single-element list-wrapper from list-column access
  if (is.list(raw_json) && length(raw_json) == 1 && is.null(names(raw_json))) {
    raw_json <- raw_json[[1]]
  }
  if (is.null(raw_json)) return(list())
  if (!is.list(raw_json) && length(raw_json) == 1 && is.na(raw_json)) return(list())
  parsed <- if (is.character(raw_json) && length(raw_json) == 1) {
    tryCatch(jsonlite::fromJSON(raw_json, simplifyVector = FALSE), error = function(e) list())
  } else if (is.list(raw_json)) {
    raw_json
  } else {
    list()
  }
  if (length(parsed) == 0) return(list())

  out <- list()
  for (nm in names(parsed)) {
    val <- parsed[[nm]]
    # Recursively flatten nested named sub-objects (group_a, group_b, etc.)
    if (is.list(val) && !is.null(names(val)) && length(val) > 0) {
      for (sub_nm in names(val)) {
        sub_val <- val[[sub_nm]]
        # One more level: handle deeply nested sub-sub-objects
        if (is.list(sub_val) && !is.null(names(sub_val)) && length(sub_val) > 0) {
          for (sub_sub_nm in names(sub_val)) {
            out[[paste0("raw_", nm, "_", sub_nm, "_", sub_sub_nm)]] <-
              .flatten_value(sub_val[[sub_sub_nm]])
          }
        } else {
          out[[paste0("raw_", nm, "_", sub_nm)]] <- .flatten_value(sub_val)
        }
      }
    } else {
      out[[paste0("raw_", nm)]] <- .flatten_value(val)
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Get list of reviewers who have reviewed articles in a project
#'
#' @param project_id UUID
#' @param token      User JWT
#' @return Data frame with user_id and email columns
get_reviewers <- function(project_id, token = NULL) {
  tryCatch({
    articles <- sb_get("articles",
      filters = list(project_id = project_id,
                     review_status = "in.(reviewed,skipped)"),
      select  = "reviewed_by",
      token   = token)
    if (!is.data.frame(articles) || nrow(articles) == 0) return(data.frame())
    uids <- unique(articles$reviewed_by)
    uids <- uids[!is.na(uids)]
    if (length(uids) == 0) return(data.frame())

    svc <- Sys.getenv("SUPABASE_SERVICE_KEY")
    if (nchar(svc) > 0) {
      uid_str <- paste0("(", paste(uids, collapse = ","), ")")
      users <- sb_get("users",
        filters = list(user_id = paste0("in.", uid_str)),
        select  = "user_id,email",
        token   = svc)
      if (is.data.frame(users) && nrow(users) > 0) return(users)
    }
    data.frame(user_id = uids, email = uids, stringsAsFactors = FALSE)
  }, error = function(e) data.frame())
}

#' Get distinct effect_status values present in a project
#'
#' @param project_id UUID
#' @param token      User JWT
#' @return Character vector of distinct effect_status values
get_effect_statuses <- function(project_id, token = NULL) {
  tryCatch({
    # Get article IDs for this project
    articles <- sb_get("articles",
      filters = list(project_id = project_id),
      select  = "article_id",
      token   = token)
    if (!is.data.frame(articles) || nrow(articles) == 0) return(character(0))

    # Get effect_sizes for all articles in the project
    aid_str <- paste0("(", paste(articles$article_id, collapse = ","), ")")
    effects <- sb_get("effect_sizes",
      filters = list(article_id = paste0("in.", aid_str)),
      select  = "effect_status",
      token   = token)
    if (!is.data.frame(effects) || nrow(effects) == 0) return(character(0))

    unique(effects$effect_status)
  }, error = function(e) character(0))
}

#' Flatten JSONB label data into a wide-format data frame
#'
#' Iterates the label schema and extracts each label value into a named column.
#' Label group instances expand into multiple rows (one per instance),
#' with a `group_instance` integer column indicating the instance number.
#'
#' @param metadata_df  Data frame with columns: article_id, json_data
#' @param label_schema Data frame of labels for this project (from the labels table)
#' @return Wide data frame with one column per single label,
#'         group labels expanded into rows
unnest_labels <- function(metadata_df, label_schema) {
  if (!is.data.frame(metadata_df) || nrow(metadata_df) == 0) {
    return(data.frame())
  }
  if (!is.data.frame(label_schema) || nrow(label_schema) == 0) {
    # No labels → just return article_ids
    return(data.frame(article_id = metadata_df$article_id,
                      stringsAsFactors = FALSE))
  }

  # Normalise columns that may arrive as list-columns (JSONB NULL → list element)
  # Coerce to plain character vectors so == and is.na() behave predictably.

  safe_char <- function(x) {
    if (is.list(x)) {
      vapply(x, function(v) if (is.null(v) || (length(v) == 1 && is.na(v))) NA_character_ else as.character(v[[1]]), character(1))
    } else {
      as.character(x)
    }
  }
  label_schema$label_type      <- safe_char(label_schema$label_type)
  label_schema$parent_label_id <- safe_char(label_schema$parent_label_id)
  label_schema$variable_type   <- safe_char(label_schema$variable_type)
  label_schema$name            <- safe_char(label_schema$name)
  label_schema$label_id        <- safe_char(label_schema$label_id)

  # Helper: TRUE if parent_label_id is absent (NA or empty string)
  no_parent <- is.na(label_schema$parent_label_id) |
               label_schema$parent_label_id == "" |
               label_schema$parent_label_id == "NA"

  # ---- Recursive expansion helper ----
  # Given a JSON context (top-level jd or a group instance) and the labels

  # at this nesting level, return a list of "row fragments".  Each fragment
  # is a list with: vals (named list of column values), group_name,
  # group_instance, group_instance_id.
  .expand <- function(jd_ctx, labels_here, prefix) {
    singles <- labels_here[labels_here$label_type %in% "single", ]
    groups  <- labels_here[labels_here$label_type %in% "group",  ]

    # Collect single-label values at this level
    single_vals <- list()
    for (j in seq_len(nrow(singles))) {
      nm <- singles$name[j]
      vt <- singles$variable_type[j]
      if (is.na(nm)) next
      if (!is.na(vt) && vt %in% "effect_size") next
      single_vals[[nm]] <- .flatten_value(jd_ctx[[nm]])
    }

    if (nrow(groups) == 0) {
      # Leaf level — no groups, just return the single values
      return(list(list(vals = single_vals,
                       group_name = NA_character_,
                       group_instance = NA_integer_,
                       group_instance_id = NA_character_)))
    }

    all_frags <- list()
    for (g in seq_len(nrow(groups))) {
      gname <- groups$name[g]
      gid   <- groups$label_id[g]
      if (is.na(gname) || is.na(gid)) next

      g_children <- label_schema[!is.na(label_schema$parent_label_id) &
                                  label_schema$parent_label_id == gid, ]
      instances  <- jd_ctx[[gname]]

      if (is.list(instances) && length(instances) > 0) {
        for (inst_num in seq_along(instances)) {
          inst <- instances[[inst_num]]
          key  <- if (nzchar(prefix)) paste0(prefix, "__", gname, "_", inst_num)
                  else paste0(gname, "_", inst_num)

          # Recurse into group instance children
          sub_frags <- .expand(inst, g_children, key)

          for (sf in sub_frags) {
            merged_vals <- c(single_vals, sf$vals)
            # Use deepest nested group info if present, otherwise this group
            if (!is.na(sf$group_instance_id)) {
              all_frags <- c(all_frags, list(list(
                vals              = merged_vals,
                group_name        = sf$group_name,
                group_instance    = sf$group_instance,
                group_instance_id = sf$group_instance_id)))
            } else {
              all_frags <- c(all_frags, list(list(
                vals              = merged_vals,
                group_name        = gname,
                group_instance    = inst_num,
                group_instance_id = key)))
            }
          }
        }
      }
    }

    if (length(all_frags) == 0) {
      # No instances found for any group at this level
      return(list(list(vals = single_vals,
                       group_name = NA_character_,
                       group_instance = NA_integer_,
                       group_instance_id = NA_character_)))
    }

    all_frags
  }

  # Top-level labels
  top_level <- label_schema[no_parent, ]

  # Build result row by row
  all_rows <- list()
  row_idx  <- 0L

  for (i in seq_len(nrow(metadata_df))) {
    aid <- metadata_df$article_id[i]
    # Use [[i]] to extract the actual value from a list-column (JSONB)
    raw_jd <- tryCatch(metadata_df$json_data[[i]], error = function(e) NULL)
    jd  <- .parse_json_data(raw_jd)

    # Expand recursively (handles singles + nested groups at all depths)
    frags <- .expand(jd, top_level, "")

    for (frag in frags) {
      row <- c(list(article_id = aid), frag$vals)
      row[["group_name"]]        <- frag$group_name
      row[["group_instance"]]    <- frag$group_instance
      row[["group_instance_id"]] <- frag$group_instance_id
      row_idx <- row_idx + 1L
      all_rows[[row_idx]] <- row
    }
  }

  if (length(all_rows) == 0) return(data.frame())

  # Convert list of lists to data frame
  # First, get all unique column names
  all_names <- unique(unlist(lapply(all_rows, names)))

  df <- data.frame(
    matrix(nrow = length(all_rows), ncol = length(all_names)),
    stringsAsFactors = FALSE
  )
  names(df) <- all_names

  for (r in seq_along(all_rows)) {
    row <- all_rows[[r]]
    for (nm in names(row)) {
      df[[nm]][r] <- row[[nm]]
    }
  }

  df
}

#' Build filter query params from user filter selections
#'
#' @param project_id UUID
#' @param filters    Named list: reviewer (char vector), review_status (char vector),
#'                   date_from (Date), date_to (Date), effect_status (char vector)
#' @param token      User JWT
#' @return Data frame of filtered articles
.fetch_filtered_articles <- function(project_id, filters = list(), token = NULL) {
  f <- list(project_id = project_id)

  # Review status filter
  if (!is.null(filters$review_status) && length(filters$review_status) > 0) {
    statuses <- paste0("(", paste(filters$review_status, collapse = ","), ")")
    f$review_status <- paste0("in.", statuses)
  }

  # Reviewer filter
  if (!is.null(filters$reviewer) && length(filters$reviewer) > 0) {
    reviewers <- paste0("(", paste(filters$reviewer, collapse = ","), ")")
    f$reviewed_by <- paste0("in.", reviewers)
  }

  articles <- sb_get("articles",
    filters = f,
    select  = paste("article_id,article_num,title,author,year,doi_clean",
                     "review_status,reviewed_by,reviewed_at", sep = ","),
    token   = token)

  if (!is.data.frame(articles) || nrow(articles) == 0) return(data.frame())

  # Date range filter (client-side since PostgREST date filtering is cumbersome)
  if (!is.null(filters$date_from) && !is.na(filters$date_from)) {
    articles$reviewed_at_dt <- as.POSIXct(articles$reviewed_at, tz = "UTC")
    articles <- articles[!is.na(articles$reviewed_at_dt) &
                          articles$reviewed_at_dt >= as.POSIXct(filters$date_from, tz = "UTC"), ]
    articles$reviewed_at_dt <- NULL
  }
  if (!is.null(filters$date_to) && !is.na(filters$date_to)) {
    articles$reviewed_at_dt <- as.POSIXct(articles$reviewed_at, tz = "UTC")
    # Add 1 day to include the full end date
    end_dt <- as.POSIXct(filters$date_to, tz = "UTC") + 86400
    articles <- articles[!is.na(articles$reviewed_at_dt) &
                          articles$reviewed_at_dt <= end_dt, ]
    articles$reviewed_at_dt <- NULL
  }

  articles
}

#' Assemble the full export for a project
#'
#' All articles matching the filter. Output format: data frame ready for CSV.
#' Columns: article metadata, label values (one per label), raw effect fields
#' (prefixed raw_), computed effect (r, z, var_z, effect_status, effect_warnings).
#'
#' @param project_id UUID of the project
#' @param filters    List of filter criteria
#' @param token      User JWT
#' @return           Data frame ready for CSV download
build_full_export <- function(project_id, filters = list(), token = NULL) {
  # 1. Fetch filtered articles
  articles <- .fetch_filtered_articles(project_id, filters, token)
  if (!is.data.frame(articles) || nrow(articles) == 0) return(data.frame())

  article_ids <- articles$article_id
  aid_str <- paste0("(", paste(article_ids, collapse = ","), ")")

  # 2. Fetch label schema
  labels <- tryCatch(
    sb_get("labels",
      filters = list(project_id = project_id),
      select  = "label_id,label_type,parent_label_id,category,name,display_name,variable_type,order_index",
      token   = token),
    error = function(e) data.frame()
  )

  # 3. Fetch article_metadata_json for all matching articles
  metadata <- tryCatch(
    sb_get("article_metadata_json",
      filters = list(article_id = paste0("in.", aid_str)),
      select  = "article_id,json_data",
      token   = token),
    error = function(e) data.frame()
  )

  # 4. Unnest labels
  label_df <- if (is.data.frame(metadata) && nrow(metadata) > 0 &&
                   is.data.frame(labels) && nrow(labels) > 0) {
    unnest_labels(metadata, labels)
  } else if (is.data.frame(metadata) && nrow(metadata) > 0) {
    data.frame(article_id = metadata$article_id, stringsAsFactors = FALSE)
  } else {
    data.frame(article_id = article_ids, stringsAsFactors = FALSE)
  }

  # 5. Fetch effect_sizes
  effects <- tryCatch(
    sb_get("effect_sizes",
      filters = list(article_id = paste0("in.", aid_str)),
      select  = "effect_id,article_id,group_instance_id,raw_effect_json,r,z,var_z,effect_status,effect_warnings,computed_at",
      token   = token),
    error = function(e) {
      message("[build_full_export] effect_sizes fetch error: ", e$message)
      data.frame()
    }
  )
  message(sprintf("[build_full_export] effect_sizes fetched: %d rows for %d articles",
                  if (is.data.frame(effects)) nrow(effects) else 0L,
                  length(article_ids)))
  if (is.data.frame(effects) && nrow(effects) > 0) {
    message(sprintf("[build_full_export] effect_status values: %s",
                    paste(unique(as.character(effects$effect_status)), collapse = ", ")))
    message(sprintf("[build_full_export] z values (first 5): %s",
                    paste(head(effects$z, 5), collapse = ", ")))
    message(sprintf("[build_full_export] var_z values (first 5): %s",
                    paste(head(effects$var_z, 5), collapse = ", ")))
  }

  # Apply effect_status filter if specified
  if (!is.null(filters$effect_status) && length(filters$effect_status) > 0 &&
      is.data.frame(effects) && nrow(effects) > 0) {
    effects <- effects[effects$effect_status %in% filters$effect_status, , drop = FALSE]
  }

  # 5b. Deduplicate stale effect rows: keep only the most recent computed_at
  #     per article_id + group_instance_id.  Earlier saves may have left
  #     orphan rows in the database before the delete-and-reinsert logic was
  #     added.
  if (is.data.frame(effects) && nrow(effects) > 1 &&
      "computed_at" %in% names(effects)) {
    effects$computed_at_ts <- as.POSIXct(effects$computed_at, tz = "UTC")
    # Coerce NA group_instance_id so we can group safely
    gi <- effects$group_instance_id
    gi[is.na(gi)] <- "__no_group__"
    effects$.dedup_key <- paste0(effects$article_id, "|||", gi)
    keep <- logical(nrow(effects))
    for (dk in unique(effects$.dedup_key)) {
      idx <- which(effects$.dedup_key == dk)
      if (length(idx) == 1L) {
        keep[idx] <- TRUE
      } else {
        # Keep the row with the latest computed_at (break ties by last row)
        ts <- effects$computed_at_ts[idx]
        best <- idx[which.max(ts)]
        keep[best] <- TRUE
      }
    }
    n_dropped <- sum(!keep)
    if (n_dropped > 0) {
      message(sprintf("[build_full_export] Deduplicated %d stale effect_size row(s)", n_dropped))
    }
    effects <- effects[keep, , drop = FALSE]
    effects$computed_at_ts <- NULL
    effects$.dedup_key    <- NULL
  }

  # 6. Flatten raw_effect_json into prefixed columns
  if (is.data.frame(effects) && nrow(effects) > 0) {
    raw_cols_list <- lapply(seq_len(nrow(effects)), function(i) {
      # Use [[i]] to extract from a list-column (JSONB stored as object)
      raw_val <- tryCatch(effects$raw_effect_json[[i]], error = function(e) NULL)
      .flatten_raw_effect(raw_val)
    })
    # Collect all raw_ column names
    all_raw_names <- unique(unlist(lapply(raw_cols_list, names)))
    raw_df <- data.frame(matrix(NA_character_, nrow = nrow(effects),
                                 ncol = length(all_raw_names)),
                          stringsAsFactors = FALSE)
    names(raw_df) <- all_raw_names
    for (i in seq_len(nrow(effects))) {
      rc <- raw_cols_list[[i]]
      for (nm in names(rc)) {
        raw_df[[nm]][i] <- rc[[nm]]
      }
    }

    # Flatten effect_warnings from list/array to string
    effects$effect_warnings_str <- sapply(effects$effect_warnings, function(w) {
      if (is.null(w) || (length(w) == 1 && is.na(w))) return(NA_character_)
      if (is.list(w)) w <- unlist(w)
      paste(w, collapse = "; ")
    })

    # Build effect columns
    effect_export <- data.frame(
      article_id        = effects$article_id,
      effect_id         = effects$effect_id,
      group_instance_id = effects$group_instance_id,
      r                 = effects$r,
      z                 = effects$z,
      var_z             = effects$var_z,
      effect_status     = effects$effect_status,
      effect_type       = if ("effect_type" %in% names(effects)) effects$effect_type else NA_character_,
      effect_warnings   = effects$effect_warnings_str,
      stringsAsFactors  = FALSE
    )

    # Bind raw columns
    effect_export <- cbind(effect_export, raw_df)
  } else {
    effect_export <- data.frame()
  }

  # 7. Identify which group(s) contain an effect_size label.
  #    Effect data should only appear on rows from those groups (or on
  #    articles with no groups at all).  This prevents duplicating the
  #    effect size across every label-group row in the export.
  es_group_names <- character(0)
  if (is.data.frame(labels) && nrow(labels) > 0) {
    safe_char2 <- function(x) {
      if (is.list(x)) vapply(x, function(v) if (is.null(v) || (length(v) == 1 && is.na(v))) NA_character_ else as.character(v[[1]]), character(1))
      else as.character(x)
    }
    lbl_vtype <- safe_char2(labels$variable_type)
    lbl_pid   <- safe_char2(labels$parent_label_id)
    lbl_pid[is.na(lbl_pid)] <- ""
    es_child_idx <- which(lbl_vtype == "effect_size" & lbl_pid != "")
    if (length(es_child_idx) > 0) {
      es_parent_ids <- unique(lbl_pid[es_child_idx])
      lbl_lid <- safe_char2(labels$label_id)
      lbl_nm  <- safe_char2(labels$name)
      parent_match <- which(lbl_lid %in% es_parent_ids)
      es_group_names <- lbl_nm[parent_match]
      es_group_names <- es_group_names[!is.na(es_group_names)]
    }
  }

  # 8. Merge: articles ← labels ← effects
  # First merge articles with label data
  merged <- merge(articles, label_df, by = "article_id", all.x = TRUE)

  # Then merge with effects using composite key (article_id + group_instance_id)
  # to avoid cross-joining multiple effect rows across label-group rows.
  # Use a sentinel for NA group_instance_id so R's merge() can match NULLs.
  if (nrow(effect_export) > 0) {
    sentinel <- "__no_group__"
    if ("group_instance_id" %in% names(merged) &&
        "group_instance_id" %in% names(effect_export)) {
      merged$group_instance_id[is.na(merged$group_instance_id)]               <- sentinel
      effect_export$group_instance_id[is.na(effect_export$group_instance_id)] <- sentinel
      merged <- merge(merged, effect_export,
                      by = c("article_id", "group_instance_id"), all.x = TRUE)
      merged$group_instance_id[merged$group_instance_id == sentinel] <- NA_character_
    } else {
      # Fallback for schemas without group_instance_id
      merged <- merge(merged, effect_export, by = "article_id", all.x = TRUE)
    }
  }

  # 9. Remove duplicated effect data from non-effect-size group rows.
  #    If there are multiple label groups but only some contain an
  #    effect_size label, blank out effect columns on rows from groups
  #    that do NOT hold the effect size.  This avoids the cross-join
  #    duplication the user reported.
  if (length(es_group_names) > 0 &&
      "group_name" %in% names(merged) &&
      nrow(effect_export) > 0) {
    effect_cols <- setdiff(names(effect_export), "article_id")
    # Also include any raw_ columns added via cbind
    effect_cols <- intersect(effect_cols, names(merged))
    # Rows from a group that is NOT the effect-size group
    non_es_rows <- !is.na(merged$group_name) &
                   !(merged$group_name %in% es_group_names)
    if (any(non_es_rows)) {
      for (ec in effect_cols) {
        merged[[ec]][non_es_rows] <- NA
      }
    }
  }

  # Sort by article_num (or article_id)
  if ("article_num" %in% names(merged) &&
      any(!is.na(merged$article_num))) {
    merged <- merged[order(merged$article_num), , drop = FALSE]
  }

  # Trim location_osm: strip "; Polygon; ..." geometry suffix so only
  # "Display Name; lat; lon; osm_id" is included in the export.
  if ("location_osm" %in% names(merged)) {
    merged$location_osm <- sub(";\\s*[Pp]olygon;.*$", "", merged$location_osm,
                                perl = TRUE)
    merged$location_osm <- trimws(merged$location_osm)
  }

  # Reset row names
  rownames(merged) <- NULL
  merged
}

#' Assemble the meta-analysis-ready export
#'
#' Includes all articles with a computed effect status. Rows that are
#' missing yi or vi are included but flagged so the export is never
#' blocked.
#' Columns: article_id, yi (= Fisher Z), vi (= var_z), effect_status,
#' meta_flag (quality flag), plus label columns as moderator variables.
#'
#' @param project_id UUID of the project
#' @param filters    Filter criteria
#' @param token      User JWT
#' @return           Data frame compatible with metafor::rma(yi=yi, vi=vi, data=df)
build_meta_export <- function(project_id, filters = list(), token = NULL) {
  # Statuses that represent a successfully-computed effect size
  meta_statuses <- c("calculated", "small_sd_used", "iqr_sd_used", "calculated_relative")

  # If the user narrowed the effect_status filter to specific computed statuses,
  # honour that choice — but only intersect within the computed list.
  # Non-computed values (e.g. "insufficient_data") are silently ignored here.
  if (!is.null(filters$effect_status) && length(filters$effect_status) > 0) {
    user_computed <- intersect(meta_statuses, filters$effect_status)
    if (length(user_computed) > 0) {
      meta_statuses <- user_computed
    }
    # If the user only selected non-computed statuses, keep all meta_statuses.
  }

  # Fetch the full export WITHOUT an effect_status restriction so that the
  # effect columns (z, var_z) are always present in the merged data frame.
  # We apply the status filter ourselves below, which avoids an empty
  # effect_export causing z/var_z columns to be absent entirely.
  filters_for_full <- filters
  filters_for_full$effect_status <- NULL          # fetch all effects
  full <- build_full_export(project_id, filters_for_full, token)

  # Helper: return an empty data frame carrying a diagnostic message attribute
  .empty <- function(msg) {
    message("[meta_export] ", msg)
    df <- data.frame()
    attr(df, "meta_export_msg") <- msg
    df
  }

  if (!is.data.frame(full) || nrow(full) == 0) {
    return(.empty(paste0(
      "No articles matched the current filters (review status = '",
      paste(filters$review_status %||% "reviewed", collapse = ", "),
      "'). Check that articles have been saved via Save/Next.")))
  }

  # If no effect columns present at all, nothing was joined — return empty.
  if (!"z" %in% names(full) || !"var_z" %in% names(full) ||
      !"effect_status" %in% names(full)) {
    return(.empty(paste0(
      "No effect size data was found for the ", nrow(full), " article(s) matching ",
      "the filters. Open each article in the Review tab and click Save/Next to ",
      "compute and store the effect size.")))
  }

  n_total      <- nrow(full)
  n_no_status  <- sum(is.na(full$effect_status))
  n_bad_status <- sum(!is.na(full$effect_status) &
                      !trimws(as.character(full$effect_status)) %in% meta_statuses)
  n_no_z    <- sum(!is.na(full$effect_status) &
                   trimws(as.character(full$effect_status)) %in% meta_statuses &
                   is.na(full$z))
  n_no_varz <- sum(!is.na(full$effect_status) &
                   trimws(as.character(full$effect_status)) %in% meta_statuses &
                   !is.na(full$z) & is.na(full$var_z))

  message(sprintf("[meta_export] total rows: %d, no status: %d, non-computed status: %d, computed but z=NA: %d, computed+z but var_z=NA: %d",
                  n_total, n_no_status, n_bad_status, n_no_z, n_no_varz))

  # Keep only rows with a computed effect status (but do NOT require
  # z and var_z — incomplete rows are flagged instead of dropped).
  full <- full[
    !is.na(full$effect_status) &
    trimws(as.character(full$effect_status)) %in% meta_statuses, , drop = FALSE]

  if (nrow(full) == 0) {
    statuses_found <- sort(unique(na.omit(trimws(as.character(
      build_full_export(project_id, filters_for_full, token)$effect_status)))))
    msg <- if (length(statuses_found) > 0) {
      paste0(n_total, " article(s) found but effect_status values (",
             paste(statuses_found, collapse = ", "),
             ") are not in the required computed set (",
             paste(meta_statuses, collapse = ", "), ").")
    } else {
      paste0(n_total, " article(s) found but none have a stored effect size. Open ",
             "each article in the Review tab and click Save/Next.")
    }
    return(.empty(msg))
  }

  # Rename z → yi, var_z → vi for metafor compatibility
  names(full)[names(full) == "z"]     <- "yi"
  names(full)[names(full) == "var_z"] <- "vi"

  # Add meta_flag column: flag rows that are incomplete for meta-analysis
  full$meta_flag <- NA_character_
  yi_missing  <- is.na(full$yi)
  vi_missing  <- is.na(full$vi)
  both_ok     <- !yi_missing & !vi_missing
  full$meta_flag[both_ok]                 <- "ok"
  full$meta_flag[yi_missing]              <- "yi_missing"
  full$meta_flag[!yi_missing & vi_missing] <- "vi_missing (enter sample size n)"

  n_flagged <- sum(full$meta_flag != "ok", na.rm = TRUE)
  if (n_flagged > 0) {
    msg <- sprintf(
      "%d of %d row(s) are flagged — see the meta_flag column. %s",
      n_flagged, nrow(full),
      if (any(vi_missing & !yi_missing))
        "Rows with vi_missing need sample size (n) entered in the Review tab."
      else "")
    attr(full, "meta_export_msg") <- msg
    message("[meta_export] ", msg)
  }

  # Drop non-essential columns for the meta export
  # (keep raw_ columns as they contain study metadata and entered statistics)
  drop_cols   <- c("effect_id", "group_instance_id", "effect_warnings",
                    "abstract", "computed_at", "effect_type",
                    "upload_batch_id")
  drop_idx    <- which(names(full) %in% drop_cols)
  if (length(drop_idx) > 0) {
    full <- full[, -drop_idx, drop = FALSE]
  }

  # Keep r alongside yi/vi for reference
  rownames(full) <- NULL
  full
}

#' Build raw JSON export
#'
#' Returns a nested list structure suitable for serialising to JSON.
#' Each article is an object with its metadata, labels, and effect sizes.
#'
#' @param project_id UUID of the project
#' @param filters    Filter criteria
#' @param token      User JWT
#' @return           Character string of pretty-printed JSON
build_json_export <- function(project_id, filters = list(), token = NULL) {
  # 1. Fetch filtered articles
  articles <- .fetch_filtered_articles(project_id, filters, token)
  if (!is.data.frame(articles) || nrow(articles) == 0) return("[]")

  article_ids <- articles$article_id
  aid_str <- paste0("(", paste(article_ids, collapse = ","), ")")

  # 2. Fetch label schema to determine which groups contain effect_size labels
  labels <- tryCatch(
    sb_get("labels",
      filters = list(project_id = project_id),
      select  = "label_id,label_type,parent_label_id,name,variable_type",
      token   = token),
    error = function(e) data.frame()
  )

  # Build mapping: group_name → es_label_name
  # e.g., "study_site" → "effect_size_data"
  es_group_map <- list()   # group_name → es_label_name
  has_toplevel_es <- FALSE
  if (is.data.frame(labels) && nrow(labels) > 0) {
    lbl_vtype <- as.character(labels$variable_type)
    lbl_pid   <- as.character(labels$parent_label_id)
    lbl_pid[is.na(lbl_pid)] <- ""
    lbl_lid   <- as.character(labels$label_id)
    lbl_nm    <- as.character(labels$name)
    es_idx    <- which(lbl_vtype == "effect_size")
    for (ei in es_idx) {
      parent <- lbl_pid[ei]
      if (nchar(parent) > 0) {
        # effect_size inside a group → find parent group name
        parent_match <- which(lbl_lid == parent)
        if (length(parent_match) > 0) {
          gname <- lbl_nm[parent_match[1]]
          es_group_map[[gname]] <- lbl_nm[ei]
        }
      } else {
        has_toplevel_es <- TRUE
      }
    }
  }

  # 3. Fetch article_metadata_json
  metadata <- tryCatch(
    sb_get("article_metadata_json",
      filters = list(article_id = paste0("in.", aid_str)),
      select  = "article_id,json_data",
      token   = token),
    error = function(e) data.frame()
  )

  # 4. Fetch effect_sizes
  effects <- tryCatch(
    sb_get("effect_sizes",
      filters = list(article_id = paste0("in.", aid_str)),
      select  = "effect_id,article_id,group_instance_id,raw_effect_json,r,z,var_z,effect_status,effect_warnings,computed_at",
      token   = token),
    error = function(e) data.frame()
  )

  # Apply effect_status filter if specified
  if (!is.null(filters$effect_status) && length(filters$effect_status) > 0 &&
      is.data.frame(effects) && nrow(effects) > 0) {
    effects <- effects[effects$effect_status %in% filters$effect_status, , drop = FALSE]
  }

  # 4b. Deduplicate stale effect rows (same logic as build_full_export)
  if (is.data.frame(effects) && nrow(effects) > 1 &&
      "computed_at" %in% names(effects)) {
    effects$computed_at_ts <- as.POSIXct(effects$computed_at, tz = "UTC")
    gi <- effects$group_instance_id
    gi[is.na(gi)] <- "__no_group__"
    effects$.dedup_key <- paste0(effects$article_id, "|||", gi)
    keep <- logical(nrow(effects))
    for (dk in unique(effects$.dedup_key)) {
      idx <- which(effects$.dedup_key == dk)
      if (length(idx) == 1L) {
        keep[idx] <- TRUE
      } else {
        ts <- effects$computed_at_ts[idx]
        best <- idx[which.max(ts)]
        keep[best] <- TRUE
      }
    }
    n_dropped <- sum(!keep)
    if (n_dropped > 0) {
      message(sprintf("[build_json_export] Deduplicated %d stale effect_size row(s)", n_dropped))
    }
    effects <- effects[keep, , drop = FALSE]
    effects$computed_at_ts <- NULL
    effects$.dedup_key    <- NULL
  }

  # Helper: parse one effect row into a clean list
  .parse_es_row <- function(j) {
    es_row <- as.list(effects[j, ])
    rj <- tryCatch(effects$raw_effect_json[[j]], error = function(e) NULL)
    if (is.list(rj) && length(rj) == 1 && is.null(names(rj))) rj <- rj[[1]]
    if (is.character(rj) && length(rj) == 1) {
      rj <- tryCatch(jsonlite::fromJSON(rj, simplifyVector = FALSE),
                      error = function(e) rj)
    }
    es_row$raw_effect_json <- rj
    ew <- tryCatch(effects$effect_warnings[[j]], error = function(e) NULL)
    if (is.list(ew)) ew <- unlist(ew)
    es_row$effect_warnings <- as.list(ew)
    es_row
  }

  # Build a list per article
  result <- lapply(seq_len(nrow(articles)), function(i) {
    aid <- articles$article_id[i]
    art <- as.list(articles[i, ])

    # Attach label metadata (raw JSON/list)
    if (is.data.frame(metadata) && nrow(metadata) > 0) {
      idx <- which(metadata$article_id == aid)
      if (length(idx) > 0) {
        raw_jd <- tryCatch(metadata$json_data[[idx[1]]], error = function(e) NULL)
        art$labels <- .parse_json_data(raw_jd)
      }
    }

    # Collect effect sizes for this article
    if (is.data.frame(effects) && nrow(effects) > 0) {
      es_idx <- which(effects$article_id == aid)
      if (length(es_idx) > 0) {
        parsed_es <- lapply(es_idx, .parse_es_row)

        # Embed effect sizes with group_instance_id into their
        # parent group instances inside art$labels
        toplevel_es <- list()
        for (es in parsed_es) {
          gi_id <- es$group_instance_id
          if (!is.null(gi_id) && !is.na(gi_id) && nchar(gi_id) > 0) {
            # Parse group_instance_id: "group_name_N"
            # Find matching group by checking all known ES groups
            matched <- FALSE
            for (gname in names(es_group_map)) {
              prefix <- paste0(gname, "_")
              if (startsWith(gi_id, prefix)) {
                inst_num <- suppressWarnings(
                  as.integer(sub(paste0("^", prefix), "", gi_id)))
                if (!is.na(inst_num) && !is.null(art$labels[[gname]]) &&
                    is.list(art$labels[[gname]]) &&
                    inst_num <= length(art$labels[[gname]])) {
                  es_label_name <- es_group_map[[gname]]
                  # Embed: drop group_instance_id from the nested object
                  es_embed <- es
                  es_embed$group_instance_id <- NULL
                  art$labels[[gname]][[inst_num]][[es_label_name]] <- es_embed
                  matched <- TRUE
                }
                break
              }
            }
            if (!matched) {
              # Couldn't match to a group instance — keep as top-level
              toplevel_es <- c(toplevel_es, list(es))
            }
          } else {
            # No group_instance_id — top-level or stale
            if (has_toplevel_es) {
              toplevel_es <- c(toplevel_es, list(es))
            }
            # else: stale row from before multi-instance — omit
          }
        }

        if (length(toplevel_es) > 0) {
          art$effect_sizes <- toplevel_es
        }
      }
    }
    art
  })

  jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, null = "null",
                   na = "null", force = TRUE)
}
