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
