# ============================================================
# R/gdrive.R — Google Drive folder sync
# ============================================================
# Phase 6: Full implementation using Drive API v3 + API key.
#
# Prerequisites:
#   - The Drive folder must be shared as "Anyone with the link can view"
#   - A Google API key stored in .Renviron as: GOOGLE_API_KEY=AIza...
#
# How to create an API key (one-time, ~2 minutes):
#   1. Go to console.cloud.google.com
#   2. Select your project, make sure Google Drive API is enabled
#   3. APIs & Services -> Credentials -> + CREATE CREDENTIALS -> API key
#   4. Copy the key shown, paste it into .Renviron as GOOGLE_API_KEY=AIza...
#   5. Restart R (Session -> Restart R in RStudio)
#
# No OAuth, no browser login, no .httr-oauth file required.
# ============================================================

#' Stub kept for backward compatibility — not needed with API key approach.
#' @return Invisibly FALSE
gdrive_init_oauth <- function() {
  message("[gdrive] OAuth is not used. Set GOOGLE_API_KEY in .Renviron instead.")
  invisible(FALSE)
}

#' Check Drive config at app startup (no-op for API key approach).
#' @return Invisibly TRUE if GOOGLE_API_KEY is set, FALSE otherwise.
gdrive_init <- function() {
  if (gdrive_is_authed()) {
    message("[gdrive] GOOGLE_API_KEY found — Drive sync enabled.")
    invisible(TRUE)
  } else {
    message("[gdrive] GOOGLE_API_KEY not set — Drive features disabled.",
            "\n  Add GOOGLE_API_KEY=AIza... to .Renviron and restart R.")
    invisible(FALSE)
  }
}

#' Check whether a Google API key is configured
#'
#' @return TRUE if GOOGLE_API_KEY is set in the environment.
gdrive_is_authed <- function() {
  nchar(Sys.getenv("GOOGLE_API_KEY")) > 0
}

#' Extract the folder ID from a Google Drive folder URL
#'
#' Handles URLs of the form:
#'   https://drive.google.com/drive/folders/FOLDER_ID
#'   https://drive.google.com/drive/folders/FOLDER_ID?usp=sharing
#'
#' @param url  The full Drive folder URL (character)
#' @return     Folder ID string, or NA_character_ if not found
extract_drive_folder_id <- function(url) {
  if (is.null(url) || is.na(url) || nchar(trimws(url)) == 0) return(NA_character_)
  stringr::str_extract(url, "(?<=/folders/)[^/?]+")
}

#' Parse the article integer ID from a PDF filename
#'
#' Expected format: "[article_num].pdf", e.g. "42.pdf"
#' The integer must be > 0.
#'
#' @param filename  Filename string (with or without .pdf extension)
#' @return          Integer article_num, or NA_integer_ if not matching
parse_article_id_from_filename <- function(filename) {
  base <- tools::file_path_sans_ext(filename)
  id   <- suppressWarnings(as.integer(trimws(base)))
  if (!is.na(id) && id > 0) id else NA_integer_
}

#' List PDF files in a Drive folder via Drive API v3 (API key)
#'
#' Uses httr2 with a Google API key. The folder must be shared as
#' "Anyone with the link can view". Handles pagination automatically.
#'
#' @param folder_id  Google Drive folder ID (character)
#' @return           Data frame with columns \code{file_id} and \code{filename}.
#'                   Returns zero-row data frame on empty folder.
#' @throws           Stops with an informative message on API error.
gdrive_list_pdfs <- function(folder_id) {
  api_key <- Sys.getenv("GOOGLE_API_KEY")
  if (nchar(api_key) == 0)
    stop("GOOGLE_API_KEY is not set in .Renviron. ",
         "See the header of R/gdrive.R for setup instructions.",
         call. = FALSE)

  q <- sprintf("'%s' in parents and mimeType='application/pdf' and trashed=false",
               folder_id)

  all_files  <- list()
  page_token <- NULL

  repeat {
    qp <- list(
      key       = api_key,
      q         = q,
      fields    = "nextPageToken,files(id,name)",
      pageSize  = "1000",
      supportsAllDrives         = "true",
      includeItemsFromAllDrives = "true"
    )
    if (!is.null(page_token)) qp$pageToken <- page_token

    resp <- httr2::request("https://www.googleapis.com/drive/v3/files") |>
      httr2::req_url_query(!!!qp) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_is_error(resp)) {
      body   <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
      detail <- body$error$message %||% httr2::resp_status_desc(resp)
      status <- httr2::resp_status(resp)
      hint <- if (status == 403L)
        " (Folder not shared as 'Anyone with the link can view', or API key restricted.)"
      else if (status == 404L) " (Folder not found — check the URL.)"
      else ""
      stop(sprintf("Drive API error %s: %s%s", status, detail, hint), call. = FALSE)
    }

    result     <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    new_files  <- result$files
    if (!is.null(new_files)) all_files <- c(all_files, new_files)
    page_token <- result$nextPageToken

    if (is.null(page_token)) break
  }

  if (length(all_files) == 0) {
    return(data.frame(file_id  = character(0),
                      filename = character(0),
                      stringsAsFactors = FALSE))
  }

  data.frame(
    file_id  = vapply(all_files, function(f) f$id   %||% NA_character_, character(1)),
    filename = vapply(all_files, function(f) f$name %||% NA_character_, character(1)),
    stringsAsFactors = FALSE
  )
}

#' Sync a Drive folder: match PDFs to articles and upsert pdf_drive_link
#'
#' PDFs must be named \code{[article_num].pdf} where \code{article_num} is the
#' integer sequence number assigned to each article (column \code{article_num}
#' in the \code{articles} table).
#'
#' Steps:
#'   1. List all PDFs in the Drive folder.
#'   2. For each PDF, parse the integer article_num from the filename.
#'   3. Match against articles belonging to \code{project_id}.
#'   4. Upsert \code{articles.pdf_drive_link} with the Drive preview URL.
#'   5. Update \code{projects.drive_last_synced}.
#'
#' @param project_id  UUID of the project (character)
#' @param folder_id   Google Drive folder ID (character)
#' @param token       User JWT for Supabase API calls (character or NULL)
#' @return            Named list:
#'   \describe{
#'     \item{files_found}{Total PDFs found in folder}
#'     \item{files_matched}{PDFs matched and linked to an article}
#'     \item{files_skipped}{PDFs not matched (bad filename or no article)}
#'     \item{skipped_names}{Character vector of skipped filenames}
#'   }
sync_drive_folder <- function(project_id, folder_id, token = NULL) {

  # --- 1. List PDFs from Drive -------------------------------------------
  pdfs <- tryCatch(
    gdrive_list_pdfs(folder_id),
    error = function(e) stop(e$message, call. = FALSE)
  )

  files_found   <- nrow(pdfs)
  files_matched <- 0L
  skipped_names <- character(0)

  if (files_found > 0) {

    # --- 2. Fetch project articles (article_id + article_num) -----------
    articles <- tryCatch(
      sb_get("articles",
             filters = list(project_id = project_id),
             select  = "article_id,article_num",
             token   = token),
      error = function(e) {
        stop("Could not fetch articles from Supabase: ", e$message, call. = FALSE)
      }
    )

    has_articles <- is.data.frame(articles) && nrow(articles) > 0 &&
                    "article_num" %in% names(articles)

    # --- 3 & 4. Match each PDF to an article and upsert link ------------
    for (i in seq_len(nrow(pdfs))) {
      fname   <- pdfs$filename[i]
      file_id <- pdfs$file_id[i]

      art_num <- parse_article_id_from_filename(fname)

      if (is.na(art_num) || !has_articles ||
          !art_num %in% articles$article_num) {
        skipped_names <- c(skipped_names, fname)
        next
      }

      # Construct the Drive preview link
      preview_url <- paste0("https://drive.google.com/file/d/", file_id, "/preview")

      # Find the UUID article_id for this article_num
      aid <- articles$article_id[articles$article_num == art_num][1]

      tryCatch(
        sb_patch("articles", "article_id", aid,
                 list(pdf_drive_link = preview_url),
                 token = token),
        error = function(e) {
          warning(sprintf("Failed to update pdf_drive_link for article %s: %s",
                          aid, e$message))
          skipped_names <<- c(skipped_names, fname)
          return(NULL)
        }
      )

      files_matched <- files_matched + 1L
    }
  }

  # --- 5. Update drive_last_synced on the project ----------------------
  tryCatch(
    sb_patch("projects", "project_id", project_id,
             list(drive_last_synced = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")),
             token = token),
    error = function(e) warning("Could not update drive_last_synced: ", e$message)
  )

  list(
    files_found   = files_found,
    files_matched = files_matched,
    files_skipped = as.integer(length(skipped_names)),
    skipped_names = skipped_names
  )
}
