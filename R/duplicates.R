# ============================================================
# R/duplicates.R — Duplicate detection logic
# ============================================================
# Implemented fully in Phase 5.

library(stringdist)

#' Clean a DOI for comparison (strips prefixes, lowercases)
#' @param doi Character vector
#' @return    Cleaned character vector
clean_doi_dup <- function(doi) {
  doi <- trimws(tolower(as.character(doi)))
  doi <- sub("^https?://", "", doi)
  doi <- sub("^doi\\.org/", "", doi)
  doi <- sub("^doi:", "", doi)
  doi
}

#' Normalise a title for comparison (lowercase, remove punctuation)
#' @param title Character vector
#' @return      Normalised character vector
clean_title <- function(title) {
  title <- trimws(tolower(as.character(title)))
  title <- gsub("[[:punct:]]", "", title)
  title <- gsub("\\s+", " ", title)
  title
}

#' Check incoming articles data frame for duplicates against existing
#'
#' Pipeline (stops at first match per row):
#'   1. Exact DOI match
#'   2. Title + year match (if no DOI)
#'   3. Partial DOI match (year + first 15 chars of DOI)
#'   4. Fuzzy title match (Jaro-Winkler distance < 0.05, same year)
#'
#' @param new_df       Data frame of incoming articles.
#'                     Expected columns: title, author, year, doi.
#'                     The 'doi' column is the raw value from the CSV; it will
#'                     be cleaned internally.
#' @param existing_df  Data frame of articles already in the database.
#'                     Expected columns: article_id, title, year, doi_clean.
#' @return             Data frame of flagged rows with columns:
#'                       row_index, match_type, matched_article_id, similarity_score
#'                     Rows NOT in the returned data frame are clean.
check_duplicates <- function(new_df, existing_df) {
  empty <- data.frame(
    row_index          = integer(0),
    match_type         = character(0),
    matched_article_id = character(0),
    similarity_score   = numeric(0),
    stringsAsFactors   = FALSE
  )

  if (is.null(existing_df) || nrow(existing_df) == 0) return(empty)
  if (is.null(new_df)      || nrow(new_df)      == 0) return(empty)

  # Pre-clean existing articles
  existing_df$doi_c   <- clean_doi_dup(existing_df$doi_clean)
  existing_df$title_c <- clean_title(existing_df$title)
  existing_df$year_i  <- suppressWarnings(as.integer(existing_df$year))

  results <- empty

  for (i in seq_len(nrow(new_df))) {
    row     <- new_df[i, ]
    doi_raw <- if ("doi" %in% names(row)) row$doi else NA_character_
    doi_c   <- clean_doi_dup(doi_raw)
    title_c <- clean_title(row$title)
    year_i  <- suppressWarnings(as.integer(row$year))

    matched <- FALSE

    # ---- 1. Exact DOI match ---------------------------------
    if (!is.na(doi_c) && nchar(doi_c) > 0) {
      hits <- which(
        !is.na(existing_df$doi_c) &
        nchar(existing_df$doi_c) > 0 &
        existing_df$doi_c == doi_c
      )
      if (length(hits) > 0) {
        results <- rbind(results, data.frame(
          row_index          = i,
          match_type         = "exact_doi",
          matched_article_id = existing_df$article_id[hits[1]],
          similarity_score   = 1.0,
          stringsAsFactors   = FALSE
        ))
        matched <- TRUE
      }
    }

    # ---- 2. Title + year exact match ------------------------
    if (!matched && nchar(title_c) > 0 && !is.na(year_i)) {
      hits <- which(
        !is.na(existing_df$title_c) &
        existing_df$title_c == title_c &
        !is.na(existing_df$year_i) &
        existing_df$year_i == year_i
      )
      if (length(hits) > 0) {
        results <- rbind(results, data.frame(
          row_index          = i,
          match_type         = "title_year",
          matched_article_id = existing_df$article_id[hits[1]],
          similarity_score   = 1.0,
          stringsAsFactors   = FALSE
        ))
        matched <- TRUE
      }
    }

    # ---- 3. Partial DOI: same year + first 15 chars ---------
    if (!matched && !is.na(doi_c) && nchar(doi_c) >= 15 && !is.na(year_i)) {
      doi_prefix <- substr(doi_c, 1, 15)
      hits <- which(
        !is.na(existing_df$doi_c) &
        nchar(existing_df$doi_c) >= 15 &
        substr(existing_df$doi_c, 1, 15) == doi_prefix &
        !is.na(existing_df$year_i) &
        existing_df$year_i == year_i
      )
      if (length(hits) > 0) {
        results <- rbind(results, data.frame(
          row_index          = i,
          match_type         = "partial_doi",
          matched_article_id = existing_df$article_id[hits[1]],
          similarity_score   = NA_real_,
          stringsAsFactors   = FALSE
        ))
        matched <- TRUE
      }
    }

    # ---- 4. Fuzzy title (Jaro-Winkler < 0.05, same year) ---
    if (!matched && nchar(title_c) > 0 && !is.na(year_i)) {
      same_year <- existing_df[
        !is.na(existing_df$year_i) & existing_df$year_i == year_i, ,
        drop = FALSE
      ]
      if (nrow(same_year) > 0 && any(!is.na(same_year$title_c))) {
        dists <- stringdist::stringdist(title_c, same_year$title_c, method = "jw")
        best  <- which.min(dists)
        if (length(best) > 0 && !is.na(dists[best]) && dists[best] < 0.05) {
          results <- rbind(results, data.frame(
            row_index          = i,
            match_type         = "fuzzy",
            matched_article_id = same_year$article_id[best],
            similarity_score   = round(1 - dists[best], 4),
            stringsAsFactors   = FALSE
          ))
        }
      }
    }
  }

  results
}


#' Validate that a parsed CSV data frame has the required columns
#'
#' @param df  Data frame from read_upload_csv()
#' @return    Character vector of missing column names (empty = OK)
validate_upload_columns <- function(df) {
  required <- c("title", "abstract", "author", "year", "doi")
  missing  <- required[!required %in% tolower(names(df))]
  missing
}


#' Read and normalise an uploaded delimited file (CSV or TSV)
#'
#' Auto-detects the delimiter: files ending in .tsv or .txt, or whose first
#' line contains a tab character, are read as tab-delimited. All others are
#' read as comma-delimited. Encoding is checked and must be UTF-8.
#'
#' @param path      Path to the uploaded file (from input$file$datapath)
#' @param filename  Original filename (used for extension detection; optional)
#' @return          Normalised data frame, or stops with a user-friendly message
read_upload_file <- function(path, filename = NULL) {
  # ---- Encoding check ------------------------------------
  enc_guess <- tryCatch(
    readr::guess_encoding(path),
    error = function(e) data.frame(encoding = "UTF-8", confidence = 1)
  )
  top_enc <- if (nrow(enc_guess) > 0) enc_guess$encoding[1] else "UTF-8"
  # ASCII is a strict subset of UTF-8 — both are safe to read without conversion
  if (!grepl("utf-?8|ascii", top_enc, ignore.case = TRUE)) {
    stop(paste0(
      "Non-UTF-8 encoding detected (", top_enc, "). ",
      "Please re-save your file as UTF-8 before uploading."
    ))
  }

  # ---- Delimiter detection --------------------------------
  # 1. Extension hint (from original filename when available)
  ext_tab <- !is.null(filename) &&
               grepl("\\.tsv$|\\.txt$", filename, ignore.case = TRUE)

  # 2. Sniff first line for a tab character
  first_line <- tryCatch({
    con <- file(path, open = "r", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    readLines(con, n = 1L, warn = FALSE)
  }, error = function(e) "")
  sniff_tab <- grepl("\t", first_line, fixed = TRUE)

  use_tab <- ext_tab || sniff_tab

  # ---- Parse -----------------------------------------------
  df <- tryCatch({
    if (use_tab)
      readr::read_tsv(path, show_col_types = FALSE)
    else
      readr::read_csv(path, show_col_types = FALSE)
  }, error = function(e) {
    fmt <- if (use_tab) "TSV" else "CSV"
    stop(paste0("Could not read ", fmt, " file: ", e$message))
  })

  # ---- Normalise column names ------------------------------
  names(df) <- tolower(names(df))
  df
}

# Backward-compatible alias kept for any external callers / tests
read_upload_csv <- read_upload_file
