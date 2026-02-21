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
#'   2. Title + year match
#'   3. Partial DOI match (year + first 15 chars of DOI)
#'   4. Fuzzy title match (Jaro-Winkler distance < 0.05)
#'
#' @param new_df       Data frame of incoming articles (title, author, year, doi)
#' @param existing_df  Data frame of articles already in the database
#' @return             Data frame of flagged rows with columns:
#'                       row_index, match_type, matched_article_id, similarity_score
check_duplicates <- function(new_df, existing_df) {
  # STUB — full implementation in Phase 5
  data.frame(
    row_index          = integer(0),
    match_type         = character(0),
    matched_article_id = character(0),
    similarity_score   = numeric(0),
    stringsAsFactors   = FALSE
  )
}
