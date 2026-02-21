# ============================================================
# R/gdrive.R — Google Drive folder sync
# ============================================================
# Implemented fully in Phase 6.
# Requires GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .Renviron.

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

#' List PDF files in a Drive folder
#'
#' @param folder_id  Google Drive folder ID
#' @return           Data frame with columns: file_id, filename
gdrive_list_pdfs <- function(folder_id) {
  # STUB — Phase 6 implementation
  # Will call Drive API v3:
  #   GET https://www.googleapis.com/drive/v3/files
  #   ?q='folder_id' in parents and mimeType='application/pdf' and trashed=false
  #   &fields=files(id,name)
  data.frame(file_id = character(0), filename = character(0),
             stringsAsFactors = FALSE)
}

#' Parse the article integer ID from a PDF filename
#'
#' Expected format: "[integer].pdf", e.g. "123.pdf"
#'
#' @param filename  Filename string
#' @return          Integer article ID, or NA_integer_ if not matching
parse_article_id_from_filename <- function(filename) {
  base <- tools::file_path_sans_ext(filename)
  id   <- suppressWarnings(as.integer(base))
  if (!is.na(id) && id > 0) id else NA_integer_
}

#' Sync a Drive folder: match PDFs to articles and upsert pdf_drive_link
#'
#' @param project_id  UUID of the project
#' @param folder_id   Google Drive folder ID
#' @param token       User JWT for Supabase API calls
#' @return            List: files_found, files_matched, files_skipped, skipped_names
sync_drive_folder <- function(project_id, folder_id, token = NULL) {
  # STUB — Phase 6 implementation
  list(
    files_found   = 0L,
    files_matched = 0L,
    files_skipped = 0L,
    skipped_names = character(0)
  )
}
