# ============================================================
# tests/test_export.R — Unit tests for export functions
# ============================================================
# Run with: testthat::test_file("tests/test_export.R")
# Phase 10: Full implementation.

library(testthat)
# resolve path relative to tests/ directory when run via test_file()
source(file.path(dirname(getwd()), "R", "utils.R"), chdir = FALSE)
source(file.path(dirname(getwd()), "R", "export.R"), chdir = FALSE)

# ---- Helper: mock label schema --------------------------------
make_label_schema <- function() {
  data.frame(
    label_id        = c("lbl1", "lbl2", "lbl3", "grp1", "child1", "child2"),
    label_type      = c("single", "single", "single", "group", "single", "single"),
    parent_label_id = c(NA, NA, NA, NA, "grp1", "grp1"),
    category        = c("Meta", "Meta", "Meta", "Sites", "Sites", "Sites"),
    name            = c("country", "habitat", "study_year",
                        "study_sites", "site_name", "latitude"),
    display_name    = c("Country", "Habitat", "Study Year",
                        "Study Sites", "Site Name", "Latitude"),
    variable_type   = c("text", "select multiple", "integer",
                        "group", "text", "numeric"),
    order_index     = 1:6,
    stringsAsFactors = FALSE
  )
}

# ---- Helper: mock metadata_df ---------------------------------
make_metadata_df <- function() {
  json1 <- jsonlite::toJSON(list(
    country    = "Australia",
    habitat    = list("Forest", "Grassland"),
    study_year = 2018,
    study_sites = list(
      list(site_name = "Site A", latitude = -33.8),
      list(site_name = "Site B", latitude = -34.1)
    )
  ), auto_unbox = TRUE)

  json2 <- jsonlite::toJSON(list(
    country    = "Brazil",
    habitat    = list("Wetland"),
    study_year = 2020
  ), auto_unbox = TRUE)

  data.frame(
    article_id = c("art1", "art2"),
    json_data  = c(json1, json2),
    stringsAsFactors = FALSE
  )
}

# ==== Tests: .parse_json_data ====

test_that(".parse_json_data handles character JSON", {
  result <- .parse_json_data('{"country":"NZ"}')
  expect_true(is.list(result))
  expect_equal(result$country, "NZ")
})

test_that(".parse_json_data handles already-parsed list", {
  ll <- list(country = "NZ")
  expect_equal(.parse_json_data(ll), ll)
})

test_that(".parse_json_data handles NULL and NA", {
  expect_equal(.parse_json_data(NULL), list())
  expect_equal(.parse_json_data(NA), list())
})

test_that(".parse_json_data handles empty string", {
  expect_equal(.parse_json_data(""), list())
})

# ==== Tests: .flatten_value ====

test_that(".flatten_value handles scalar", {
  expect_equal(.flatten_value("hello"), "hello")
  expect_equal(.flatten_value(42), "42")
})

test_that(".flatten_value handles NULL → NA", {
  expect_true(is.na(.flatten_value(NULL)))
})

test_that(".flatten_value handles unnamed list → semicolon string", {
  expect_equal(.flatten_value(list("A", "B", "C")), "A; B; C")
})

test_that(".flatten_value handles named list → key=value pairs", {
  val <- list(lon_min = 10, lon_max = 20)
  result <- .flatten_value(val)
  expect_true(grepl("lon_min=10", result))
  expect_true(grepl("lon_max=20", result))
})

test_that(".flatten_value handles vector", {
  expect_equal(.flatten_value(c("X", "Y")), "X; Y")
})

# ==== Tests: .flatten_raw_effect ====

test_that(".flatten_raw_effect adds raw_ prefix", {
  json <- '{"study_design":"correlation","r_reported":0.5,"n":30}'
  result <- .flatten_raw_effect(json)
  expect_true("raw_study_design" %in% names(result))
  expect_true("raw_r_reported" %in% names(result))
  expect_true("raw_n" %in% names(result))
  expect_equal(result$raw_r_reported, "0.5")
})

test_that(".flatten_raw_effect handles NULL", {
  expect_equal(length(.flatten_raw_effect(NULL)), 0)
})

test_that(".flatten_raw_effect handles nested group_a/group_b", {
  json <- '{"study_design":"interaction","interaction_pathway":"B","group_a":{"mean_control":10,"mean_treatment":15}}'
  result <- .flatten_raw_effect(json)
  expect_true("raw_group_a_mean_control" %in% names(result))
  expect_true("raw_group_a_mean_treatment" %in% names(result))
})

test_that(".extract_jsonb_cell preserves named fields from nested data.frame columns", {
  nested <- data.frame(
    study_design = c("control_treatment", "regression"),
    F_stat = c(NA, 6.411),
    control_description = c("Control", NA),
    stringsAsFactors = FALSE
  )
  df <- data.frame(article_id = c("a1", "a2"), stringsAsFactors = FALSE)
  df$raw_effect_json <- nested

  cell <- .extract_jsonb_cell(df, "raw_effect_json", 2)
  expect_true(is.list(cell))
  expect_equal(cell$study_design, "regression")
  expect_equal(cell$F_stat, 6.411)
})

test_that(".normalise_json_like keeps named raw effect objects", {
  x <- data.frame(study_design = "regression", F_stat = 6.411,
                  stringsAsFactors = FALSE)
  out <- .normalise_json_like(x)
  expect_true(is.list(out))
  expect_equal(out$study_design, "regression")
  expect_equal(out$F_stat, 6.411)
})

# ==== Tests: unnest_labels ====

test_that("unnest_labels expands group instances into rows", {
  schema <- make_label_schema()
  meta   <- make_metadata_df()
  result <- unnest_labels(meta, schema)

  # art1 has 2 study_site instances → 2 rows
  # art2 has 0 study_site instances → 1 row with NA group
  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 3)

  art1_rows <- result[result$article_id == "art1", ]
  expect_equal(nrow(art1_rows), 2)
  expect_equal(art1_rows$site_name[1], "Site A")
  expect_equal(art1_rows$site_name[2], "Site B")
  expect_equal(art1_rows$country[1], "Australia")
  # Both rows should have the same top-level country
  expect_equal(art1_rows$country[2], "Australia")
})

test_that("unnest_labels handles articles with no group instances", {
  schema <- make_label_schema()
  meta   <- make_metadata_df()
  result <- unnest_labels(meta, schema)

  art2_rows <- result[result$article_id == "art2", ]
  expect_equal(nrow(art2_rows), 1)
  expect_equal(art2_rows$country, "Brazil")
  expect_true(is.na(art2_rows$group_instance))
})

test_that("unnest_labels returns correct columns", {
  schema <- make_label_schema()
  meta   <- make_metadata_df()
  result <- unnest_labels(meta, schema)

  expect_true("article_id" %in% names(result))
  expect_true("country" %in% names(result))
  expect_true("habitat" %in% names(result))
  expect_true("study_year" %in% names(result))
  expect_true("group_instance" %in% names(result))
  expect_true("site_name" %in% names(result))
  expect_true("latitude" %in% names(result))
})

test_that("unnest_labels handles empty metadata_df", {
  schema <- make_label_schema()
  result <- unnest_labels(data.frame(), schema)
  expect_equal(nrow(result), 0)
})

test_that("unnest_labels handles empty label_schema", {
  meta <- make_metadata_df()
  result <- unnest_labels(meta, data.frame())
  expect_true(is.data.frame(result))
  expect_true("article_id" %in% names(result))
})

test_that("unnest_labels flattens select multiple to semicolon string", {
  schema <- make_label_schema()
  meta   <- make_metadata_df()
  result <- unnest_labels(meta, schema)
  art1   <- result[result$article_id == "art1", ]
  # habitat is a list("Forest","Grassland") → "Forest; Grassland"
  expect_equal(art1$habitat[1], "Forest; Grassland")
})

# ==== Tests: schema with no groups ====

test_that("unnest_labels works with single labels only (no groups)", {
  schema <- data.frame(
    label_id        = c("l1", "l2"),
    label_type      = c("single", "single"),
    parent_label_id = c(NA, NA),
    category        = c("A", "A"),
    name            = c("country", "year"),
    display_name    = c("Country", "Year"),
    variable_type   = c("text", "integer"),
    order_index     = 1:2,
    stringsAsFactors = FALSE
  )
  json <- jsonlite::toJSON(list(country = "USA", year = 2021), auto_unbox = TRUE)
  meta <- data.frame(article_id = "a1", json_data = json, stringsAsFactors = FALSE)
  result <- unnest_labels(meta, schema)
  expect_equal(nrow(result), 1)
  expect_equal(result$country, "USA")
  expect_equal(result$year, "2021")
})

# ==== Tests: meta export column naming ====

test_that("meta export renames z → yi and var_z → vi", {
  # We can't call build_meta_export without a real DB, but we can test the

  # rename logic by simulating what it does:
  df <- data.frame(
    article_id    = "a1",
    z             = 0.55,
    var_z         = 0.033,
    r             = 0.5,
    effect_status = "calculated",
    country       = "AU",
    stringsAsFactors = FALSE
  )
  names(df)[names(df) == "z"]     <- "yi"
  names(df)[names(df) == "var_z"] <- "vi"

  expect_true("yi" %in% names(df))
  expect_true("vi" %in% names(df))
  expect_false("z" %in% names(df))
  expect_false("var_z" %in% names(df))
  expect_equal(df$yi, 0.55)
  expect_equal(df$vi, 0.033)
})

# ==== Tests: effect_size variable_type is skipped ====

test_that("unnest_labels skips effect_size variable_type labels", {
  schema <- data.frame(
    label_id        = c("l1", "l2"),
    label_type      = c("single", "single"),
    parent_label_id = c(NA, NA),
    category        = c("A", "A"),
    name            = c("country", "es_field"),
    display_name    = c("Country", "Effect Size"),
    variable_type   = c("text", "effect_size"),
    order_index     = 1:2,
    stringsAsFactors = FALSE
  )
  json <- jsonlite::toJSON(list(country = "NZ"), auto_unbox = TRUE)
  meta <- data.frame(article_id = "a1", json_data = json, stringsAsFactors = FALSE)
  result <- unnest_labels(meta, schema)
  expect_true("country" %in% names(result))
  expect_false("es_field" %in% names(result))
})

# ==== Tests: effect deduplication helper (internal to build_full_export) ====

test_that("stale effect rows are deduplicated by computed_at", {

  # Simulate an effects data frame with stale rows (same article + group_instance_id,
  # different computed_at timestamps)
  effects <- data.frame(
    effect_id         = c("old1", "old2", "latest1", "old3", "latest2"),
    article_id        = c("a1",   "a1",   "a1",      "a1",   "a1"),
    group_instance_id = c("study_site_1", "study_site_1", "study_site_1",
                          "study_site_2", "study_site_2"),
    r                 = c(0.3, 0.4, 0.5, 0.6, 0.7),
    z                 = c(0.31, 0.42, 0.55, 0.69, 0.87),
    var_z             = c(NA, NA, 0.05, NA, 0.04),
    effect_status     = c("calculated", "calculated", "calculated",
                          "calculated", "calculated"),
    computed_at       = c("2026-02-20T10:00:00Z", "2026-02-21T10:00:00Z",
                          "2026-02-22T10:00:00Z", "2026-02-23T10:00:00Z",
                          "2026-02-24T10:00:00Z"),
    stringsAsFactors  = FALSE
  )

  # Run the deduplication logic (extracted from build_full_export)
  effects$computed_at_ts <- as.POSIXct(effects$computed_at, tz = "UTC")
  gi <- effects$group_instance_id
  gi[is.na(gi)] <- "__no_group__"
  effects$.dedup_key <- paste0(effects$article_id, "|||", gi)
  keep <- logical(nrow(effects))
  for (dk in unique(effects$.dedup_key)) {
    idx <- which(effects$.dedup_key == dk)
    if (length(idx) == 1L) {
      keep[idx] <- TRUE
    } else {
      ts <- effects$computed_at_ts[idx]
      best <- idx[which.max(ts)]
      keep[best] <- TRUE
    }
  }
  deduped <- effects[keep, , drop = FALSE]
  deduped$computed_at_ts <- NULL
  deduped$.dedup_key    <- NULL

  # Should keep only 2 rows: the latest per group_instance_id
  expect_equal(nrow(deduped), 2)
  expect_equal(sort(deduped$effect_id), c("latest1", "latest2"))
  expect_equal(deduped$r[deduped$group_instance_id == "study_site_1"], 0.5)
  expect_equal(deduped$r[deduped$group_instance_id == "study_site_2"], 0.7)
})
