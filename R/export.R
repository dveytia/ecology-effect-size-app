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
#' @param jd  Character JSON string or already-parsed list
#' @return    Named list (empty list on failure)
.parse_json_data <- function(jd) {
  if (is.null(jd) || (length(jd) == 1 && is.na(jd))) return(list())
  if (is.list(jd)) return(jd)
  if (is.character(jd) && nchar(jd) > 0) {
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
#' @param raw_json  Character JSON string or already-parsed list
#' @return          Named list with "raw_" prefixed keys
.flatten_raw_effect <- function(raw_json) {
  if (is.null(raw_json) || (length(raw_json) == 1 && is.na(raw_json))) return(list())
  parsed <- if (is.character(raw_json)) {
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
    # Skip nested group_a/group_b sub-objects — flatten them separately
    if (nm %in% c("group_a", "group_b") && is.list(val) && !is.null(names(val))) {
      for (sub_nm in names(val)) {
        out[[paste0("raw_", nm, "_", sub_nm)]] <- .flatten_value(val[[sub_nm]])
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

  # Separate top-level (single) labels and group labels
  top_labels  <- label_schema[label_schema$label_type == "single" &
                               (is.na(label_schema$parent_label_id) |
                                label_schema$parent_label_id == ""), ]
  group_parents <- label_schema[label_schema$label_type == "group" &
                                 (is.na(label_schema$parent_label_id) |
                                  label_schema$parent_label_id == ""), ]

  # Build result row by row
  all_rows <- list()
  row_idx  <- 0L

  for (i in seq_len(nrow(metadata_df))) {
    aid <- metadata_df$article_id[i]
    jd  <- .parse_json_data(metadata_df$json_data[i])

    # Extract top-level (single) label values
    base_row <- list(article_id = aid)
    for (j in seq_len(nrow(top_labels))) {
      lbl_name <- top_labels$name[j]
      var_type <- top_labels$variable_type[j]
      val      <- jd[[lbl_name]]
      # Skip effect_size type labels — they are in the effect_sizes table
      if (!is.na(var_type) && var_type == "effect_size") next
      base_row[[lbl_name]] <- .flatten_value(val)
    }

    # If there are group parents, expand instances
    if (nrow(group_parents) > 0) {
      has_any_instances <- FALSE

      for (g in seq_len(nrow(group_parents))) {
        grp_name <- group_parents$name[g]
        grp_id   <- group_parents$label_id[g]
        child_labels <- label_schema[!is.na(label_schema$parent_label_id) &
                                      label_schema$parent_label_id == grp_id, ]
        instances <- jd[[grp_name]]

        if (is.list(instances) && length(instances) > 0) {
          for (inst_num in seq_along(instances)) {
            inst <- instances[[inst_num]]
            inst_row <- base_row
            inst_row[["group_name"]]     <- grp_name
            inst_row[["group_instance"]] <- inst_num

            for (cl in seq_len(nrow(child_labels))) {
              cl_name  <- child_labels$name[cl]
              cl_type  <- child_labels$variable_type[cl]
              if (!is.na(cl_type) && cl_type == "effect_size") next
              inst_row[[cl_name]] <- .flatten_value(inst[[cl_name]])
            }

            row_idx <- row_idx + 1L
            all_rows[[row_idx]] <- inst_row
            has_any_instances <- TRUE
          }
        }
      }

      # If no group instances exist, still emit the base row
      if (!has_any_instances) {
        base_row[["group_name"]]     <- NA_character_
        base_row[["group_instance"]] <- NA_integer_
        row_idx <- row_idx + 1L
        all_rows[[row_idx]] <- base_row
      }
    } else {
      # No groups — just the base row
      row_idx <- row_idx + 1L
      all_rows[[row_idx]] <- base_row
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
      select  = "effect_id,article_id,group_instance_id,raw_effect_json,r,z,var_z,effect_status,effect_type,effect_warnings,computed_at",
      token   = token),
    error = function(e) data.frame()
  )

  # Apply effect_status filter if specified
  if (!is.null(filters$effect_status) && length(filters$effect_status) > 0 &&
      is.data.frame(effects) && nrow(effects) > 0) {
    effects <- effects[effects$effect_status %in% filters$effect_status, , drop = FALSE]
  }

  # 6. Flatten raw_effect_json into prefixed columns
  if (is.data.frame(effects) && nrow(effects) > 0) {
    raw_cols_list <- lapply(seq_len(nrow(effects)), function(i) {
      .flatten_raw_effect(effects$raw_effect_json[i])
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

  # 7. Merge: articles ← labels ← effects
  # First merge articles with label data
  merged <- merge(articles, label_df, by = "article_id", all.x = TRUE)

  # Then merge with effects (may create additional rows if multiple effects per article)
  if (nrow(effect_export) > 0) {
    merged <- merge(merged, effect_export, by = "article_id", all.x = TRUE)
  }

  # Sort by article_num (or article_id)
  if ("article_num" %in% names(merged) &&
      any(!is.na(merged$article_num))) {
    merged <- merged[order(merged$article_num), , drop = FALSE]
  }

  # Reset row names
  rownames(merged) <- NULL
  merged
}

#' Assemble the meta-analysis-ready export
#'
#' Filtered to articles where effect_status indicates a computed effect.
#' Columns: article_id, yi (= Fisher Z), vi (= var_z), effect_status,
#' plus label columns as moderator variables.
#'
#' @param project_id UUID of the project
#' @param filters    Filter criteria
#' @param token      User JWT
#' @return           Data frame compatible with metafor::rma(yi=yi, vi=vi, data=df)
build_meta_export <- function(project_id, filters = list(), token = NULL) {
  # Force effect_status filter to only computed effects
  meta_statuses <- c("calculated", "small_sd_used", "iqr_sd_used", "calculated_relative")

  # If user specified additional filters on effect_status, intersect
  if (!is.null(filters$effect_status) && length(filters$effect_status) > 0) {
    meta_statuses <- intersect(meta_statuses, filters$effect_status)
    if (length(meta_statuses) == 0) return(data.frame())
  }
  filters$effect_status <- meta_statuses

  # Build full export with the restricted effect_status filter
  full <- build_full_export(project_id, filters, token)
  if (!is.data.frame(full) || nrow(full) == 0) return(data.frame())

  # Keep only rows that have z and var_z
  if (!"z" %in% names(full) || !"var_z" %in% names(full)) return(data.frame())
  full <- full[!is.na(full$z) & !is.na(full$var_z), , drop = FALSE]
  if (nrow(full) == 0) return(data.frame())

  # Rename z → yi, var_z → vi for metafor compatibility
  names(full)[names(full) == "z"]     <- "yi"
  names(full)[names(full) == "var_z"] <- "vi"

  # Drop raw_ columns and other non-essential columns for the meta export
  drop_prefix <- grep("^raw_", names(full))
  drop_cols   <- c("effect_id", "group_instance_id", "effect_warnings",
                    "abstract", "computed_at", "effect_type",
                    "upload_batch_id")
  drop_idx    <- which(names(full) %in% drop_cols)
  all_drops   <- unique(c(drop_prefix, drop_idx))
  if (length(all_drops) > 0) {
    full <- full[, -all_drops, drop = FALSE]
  }

  # Keep r alongside yi/vi for reference
  rownames(full) <- NULL
  full
}
