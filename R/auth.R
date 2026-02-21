# ============================================================
# R/auth.R — Session management and route guard
# ============================================================
# Phase 2: Full implementation of session refresh and route guard.

#' Check whether the session token is still valid
#'
#' @param session_rv reactiveValues with token and expires_at
#' @return TRUE if valid, FALSE otherwise
check_session <- function(session_rv) {
  if (is.null(session_rv$token)) return(FALSE)
  if (is.null(session_rv$expires_at)) return(TRUE)   # no expiry info — assume valid
  Sys.time() < session_rv$expires_at
}

#' Refresh the JWT if it expires within the next 60 seconds
#'
#' Calls sb_auth_refresh() with the stored refresh_token and updates
#' session_rv$token, session_rv$expires_at, and session_rv$refresh_token
#' in-place.  If the refresh fails (e.g. refresh token expired), the session
#' is cleared so the page router returns the user to the login screen.
#'
#' @param session_rv reactiveValues; must contain token, expires_at, refresh_token
#' @return invisible NULL (side-effects only)
refresh_if_needed <- function(session_rv) {
  # Nothing to do if there's no active session
  if (is.null(session_rv$token)) return(invisible(NULL))

  # If we have no expiry information, assume still valid
  if (is.null(session_rv$expires_at)) return(invisible(NULL))

  seconds_left <- as.numeric(
    difftime(session_rv$expires_at, Sys.time(), units = "secs")
  )

  # Token is still fresh — nothing to do
  if (seconds_left > 60) return(invisible(NULL))

  # Cannot refresh without a refresh_token — force re-login
  if (is.null(session_rv$refresh_token) ||
      nchar(session_rv$refresh_token) == 0) {
    message("[auth] Token expiring but no refresh_token available — clearing session.")
    session_rv$token         <- NULL
    session_rv$user_id       <- NULL
    session_rv$username      <- NULL
    session_rv$expires_at    <- NULL
    session_rv$refresh_token <- NULL
    return(invisible(NULL))
  }

  # Attempt the refresh
  tryCatch({
    result <- sb_auth_refresh(session_rv$refresh_token)
    session_rv$token         <- result$access_token
    session_rv$expires_at    <- unix_to_posixct(result$expires_at)
    # Supabase rotates refresh tokens on each use
    if (!is.null(result$refresh_token))
      session_rv$refresh_token <- result$refresh_token
    message("[auth] JWT refreshed successfully.")
  }, error = function(e) {
    warning("[auth] Token refresh failed: ", e$message, " — clearing session.")
    session_rv$token         <- NULL
    session_rv$user_id       <- NULL
    session_rv$username      <- NULL
    session_rv$expires_at    <- NULL
    session_rv$refresh_token <- NULL
  })

  invisible(NULL)
}

#' Clear the session if the token is no longer valid
#'
#' Should be called after refresh_if_needed().  Clears all session
#' fields so the page router redirects the user to the login screen.
#'
#' @param session_rv reactiveValues
#' @return invisible NULL (side-effects only)
route_guard <- function(session_rv) {
  if (!check_session(session_rv)) {
    session_rv$token         <- NULL
    session_rv$user_id       <- NULL
    session_rv$username      <- NULL
    session_rv$expires_at    <- NULL
    session_rv$refresh_token <- NULL
  }
  invisible(NULL)
}
