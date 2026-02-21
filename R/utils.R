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
