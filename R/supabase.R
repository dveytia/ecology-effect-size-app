# ============================================================
# R/supabase.R — Supabase REST API wrapper
# ============================================================
# All database access goes through these functions.
# Credentials are read from .Renviron:
#   SUPABASE_URL        e.g. https://xyz.supabase.co
#   SUPABASE_KEY        anon (public) key
#   SUPABASE_SERVICE_KEY  service role key (admin ops only)
#
# Every function returns parsed JSON on success, or stops with
# an informative error message on HTTP failure.
# ============================================================

# ---- Internal helpers ---------------------------------------

.sb_url <- function() {
  url <- Sys.getenv("SUPABASE_URL")
  if (nchar(url) == 0) stop("SUPABASE_URL is not set in .Renviron")
  url
}

.sb_anon_key <- function() {
  key <- Sys.getenv("SUPABASE_KEY")
  if (nchar(key) == 0) stop("SUPABASE_KEY is not set in .Renviron")
  key
}

# Build base request to the PostgREST REST API endpoint.
# If `token` is provided (user JWT), it is used for RLS.
# Otherwise the anon key is used.
.sb_base_req <- function(path, token = NULL) {
  key <- if (!is.null(token)) token else .sb_anon_key()
  httr2::request(paste0(.sb_url(), path)) |>
    httr2::req_headers(
      "apikey"        = .sb_anon_key(),   # always needed
      "Authorization" = paste("Bearer", key),
      "Content-Type"  = "application/json",
      "Prefer"        = "return=representation"
    )
}

# Parse an httr2 response; stop on HTTP error with message.
.sb_parse <- function(resp) {
  httr2::resp_check_status(resp)
  httr2::resp_body_json(resp, simplifyVector = TRUE)
}

# Convert a named list of filters to PostgREST query params.
# Each element: name = column, value = "eq.VALUE" | "gt.VALUE" etc.
# Simple equality shorthand: pass value as a plain scalar.
.sb_filters_to_params <- function(filters) {
  if (length(filters) == 0) return(list())
  lapply(filters, function(v) {
    if (grepl("^(eq|neq|gt|gte|lt|lte|like|ilike|is|in)\\.", v)) v
    else paste0("eq.", v)
  })
}

# ---- CRUD functions -----------------------------------------

#' GET rows from a table
#'
#' @param table   Table name (character)
#' @param filters Named list of column = value pairs for WHERE clause
#' @param select  Comma-separated column names (default "*")
#' @param token   User JWT (NULL = anon key)
#' @return        Data frame (possibly 0 rows)
sb_get <- function(table, filters = list(), select = "*", token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/", table), token) |>
    httr2::req_url_query(select = select,
                         !!!.sb_filters_to_params(filters))
  resp <- httr2::req_perform(req)
  result <- .sb_parse(resp)
  # Ensure data frame even when result is empty list
  if (is.list(result) && length(result) == 0) {
    return(data.frame())
  }
  result
}

#' INSERT a single row into a table
#'
#' @param table  Table name
#' @param body   Named list of column = value pairs
#' @param token  User JWT
#' @return       Inserted row as a list
sb_post <- function(table, body, token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/", table), token) |>
    httr2::req_body_json(body) |>
    httr2::req_method("POST")
  resp <- httr2::req_perform(req)
  result <- .sb_parse(resp)
  if (is.data.frame(result) && nrow(result) == 1) as.list(result[1, ])
  else result
}

#' UPDATE a row identified by a primary-key column
#'
#' @param table    Table name
#' @param id_col   Name of the PK column (e.g. "project_id")
#' @param id_val   Value of the PK
#' @param body     Named list of columns to update
#' @param token    User JWT
#' @return         Updated row as a list
sb_patch <- function(table, id_col, id_val, body, token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/", table), token) |>
    httr2::req_url_query(!!id_col := paste0("eq.", id_val)) |>
    httr2::req_body_json(body) |>
    httr2::req_method("PATCH")
  resp <- httr2::req_perform(req)
  result <- .sb_parse(resp)
  if (is.data.frame(result) && nrow(result) == 1) as.list(result[1, ])
  else result
}

#' DELETE a row identified by a primary-key column
#'
#' @param table   Table name
#' @param id_col  Name of the PK column
#' @param id_val  Value of the PK
#' @param token   User JWT
#' @return        Deleted row(s) as a data frame
sb_delete <- function(table, id_col, id_val, token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/", table), token) |>
    httr2::req_url_query(!!id_col := paste0("eq.", id_val)) |>
    httr2::req_method("DELETE")
  resp <- httr2::req_perform(req)
  .sb_parse(resp)
}

#' DELETE rows matching multiple filter conditions
#'
#' Use this for tables with composite primary keys (e.g. project_members).
#'
#' @param table    Table name
#' @param filters  Named list of column = value pairs (all combined with AND)
#' @param token    User JWT
#' @return         Deleted row(s) as a data frame
sb_delete_where <- function(table, filters = list(), token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/", table), token) |>
    httr2::req_url_query(!!!.sb_filters_to_params(filters)) |>
    httr2::req_method("DELETE")
  resp <- httr2::req_perform(req)
  .sb_parse(resp)
}

#' UPSERT (INSERT OR UPDATE) one or more rows
#'
#' Uses the PostgREST "resolution=merge-duplicates" preference.
#'
#' @param table     Table name
#' @param body      Named list (single row) or data frame (multiple rows)
#' @param on_conflict  Comma-separated column(s) that trigger conflict detection
#' @param token     User JWT
#' @return          Upserted row(s)
sb_upsert <- function(table, body, on_conflict = NULL, token = NULL) {
  prefer <- "return=representation,resolution=merge-duplicates"
  req <- httr2::request(paste0(.sb_url(), "/rest/v1/", table)) |>
    httr2::req_headers(
      "apikey"        = .sb_anon_key(),
      "Authorization" = paste("Bearer", if (!is.null(token)) token else .sb_anon_key()),
      "Content-Type"  = "application/json",
      "Prefer"        = prefer
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_method("POST")
  if (!is.null(on_conflict)) {
    req <- httr2::req_url_query(req, on_conflict = on_conflict)
  }
  resp <- httr2::req_perform(req)
  .sb_parse(resp)
}

#' Call a Postgres RPC function
#'
#' @param fn_name  Function name
#' @param params   Named list of parameters
#' @param token    User JWT
#' @return         Function return value
sb_rpc <- function(fn_name, params = list(), token = NULL) {
  req <- .sb_base_req(paste0("/rest/v1/rpc/", fn_name), token) |>
    httr2::req_body_json(params) |>
    httr2::req_method("POST")
  resp <- httr2::req_perform(req)
  .sb_parse(resp)
}

# ---- Authentication functions --------------------------------

#' Sign in with email + password
#'
#' @param email     User email
#' @param password  User password
#' @return          List with access_token, refresh_token, expires_at, user
sb_auth_login <- function(email, password) {
  req <- httr2::request(paste0(.sb_url(), "/auth/v1/token")) |>
    httr2::req_url_query(grant_type = "password") |>
    httr2::req_headers(
      "apikey"       = .sb_anon_key(),
      "Content-Type" = "application/json"
    ) |>
    httr2::req_body_json(list(email = email, password = password)) |>
    httr2::req_method("POST") |>
    # Return the response even on 4xx so we can show friendly errors
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp)
  if (httr2::resp_status(resp) != 200) {
    stop(body$error_description %||% body$msg %||% "Login failed")
  }
  body
}

#' Register a new user
#'
#' @param email     New user email
#' @param password  New user password
#' @return          List with access_token, user, etc.
sb_auth_register <- function(email, password) {
  req <- httr2::request(paste0(.sb_url(), "/auth/v1/signup")) |>
    httr2::req_headers(
      "apikey"       = .sb_anon_key(),
      "Content-Type" = "application/json"
    ) |>
    httr2::req_body_json(list(email = email, password = password)) |>
    httr2::req_method("POST") |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp)
  if (httr2::resp_status(resp) %in% c(400, 422)) {
    stop(body$error_description %||% body$msg %||% "Registration failed")
  }
  body
}

#' Refresh an access token using a refresh token
#'
#' @param refresh_token  The refresh_token from a previous login
#' @return               Updated list with access_token, expires_at, etc.
sb_auth_refresh <- function(refresh_token) {
  req <- httr2::request(paste0(.sb_url(), "/auth/v1/token")) |>
    httr2::req_url_query(grant_type = "refresh_token") |>
    httr2::req_headers(
      "apikey"       = .sb_anon_key(),
      "Content-Type" = "application/json"
    ) |>
    httr2::req_body_json(list(refresh_token = refresh_token)) |>
    httr2::req_method("POST") |>
    httr2::req_error(is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  body <- httr2::resp_body_json(resp)
  if (httr2::resp_status(resp) != 200) {
    stop(body$error_description %||% body$msg %||% "Token refresh failed")
  }
  body
}

# Null-coalescing operator (base R does not have one)
`%||%` <- function(a, b) if (!is.null(a) && !is.na(a) && nchar(as.character(a)) > 0) a else b
