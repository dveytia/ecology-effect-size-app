# ============================================================
# R/auth.R — Session management and route guard
# ============================================================
# Implemented fully in Phase 2.
# Phase 1 stubs provided here so app.R can source without error.

#' Check whether the session token is still valid
#' @param session_rv reactiveValues with token and expires_at
#' @return TRUE if valid, FALSE otherwise
check_session <- function(session_rv) {
  if (is.null(session_rv$token)) return(FALSE)
  if (is.null(session_rv$expires_at)) return(TRUE)   # no expiry info — assume valid
  Sys.time() < session_rv$expires_at
}

#' Refresh the JWT if it expires within the next 60 seconds
#' @param session_rv reactiveValues; updated in-place on refresh
refresh_if_needed <- function(session_rv) {
  # STUB — full implementation in Phase 2
  # Will call sb_auth_refresh() and update session_rv$token and expires_at
  invisible(NULL)
}

#' Redirect to login page if session is not valid
#' @param session_rv reactiveValues
#' @param output shiny output object (used to trigger UI re-render)
route_guard <- function(session_rv, output) {
  # STUB — full implementation in Phase 2
  # Will call shiny::updateNavbarPage or similar to force login page
  invisible(NULL)
}
