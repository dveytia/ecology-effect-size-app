# ============================================================
# R/export.R — Export functions
# ============================================================
# Implemented fully in Phase 10.

#' Flatten JSONB label data into a wide-format data frame
#'
#' @param metadata_df  Data frame from article_metadata_json (columns: article_id, json_data)
#' @param label_schema Data frame of labels for this project
#' @return             Wide data frame with one column per label
unnest_labels <- function(metadata_df, label_schema) {
  # STUB — Phase 10 implementation
  metadata_df
}

#' Assemble the full export for a project
#'
#' @param project_id UUID of the project
#' @param filters    List of filter criteria (reviewer, status, date range, effect_status)
#' @param token      User JWT
#' @return           Data frame ready for CSV download
build_full_export <- function(project_id, filters = list(), token = NULL) {
  # STUB — Phase 10 implementation
  data.frame()
}

#' Assemble the meta-analysis-ready export
#'
#' Columns: article_id, yi (= Fisher Z), vi (= var_z), effect_status, plus label moderators.
#'
#' @param project_id UUID of the project
#' @param filters    Filter criteria
#' @param token      User JWT
#' @return           Data frame compatible with metafor::rma(yi=yi, vi=vi, data=df)
build_meta_export <- function(project_id, filters = list(), token = NULL) {
  # STUB — Phase 10 implementation
  data.frame()
}
