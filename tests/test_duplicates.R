# ============================================================
# tests/test_duplicates.R — Unit tests for duplicate detection
# ============================================================
# Run with: testthat::test_file("tests/test_duplicates.R")
# Full tests implemented in Phase 5.

library(testthat)
source("R/utils.R")
source("R/duplicates.R")

# ---- DOI cleaning -------------------------------------------
test_that("clean_doi strips https://doi.org/ prefix", {
  expect_equal(clean_doi_dup("https://doi.org/10.1234/abc"), "10.1234/abc")
})

test_that("clean_doi lowercases", {
  expect_equal(clean_doi_dup("10.1234/ABC"), "10.1234/abc")
})

test_that("clean_doi handles NA", {
  # Returns NA or empty — just shouldn't error
  expect_true(is.na(clean_doi_dup(NA)) || nchar(clean_doi_dup(NA)) == 0)
})

# ---- Title cleaning -----------------------------------------
test_that("clean_title removes punctuation and lowercases", {
  result <- clean_title("Effects of Climate-Change: A Review!")
  expect_false(grepl("[[:punct:]]", result))
  expect_equal(result, tolower(result))
})

# ---- Phase 5: full duplicate detection tests ----------------
# (uncomment and expand in Phase 5)
# test_that("exact DOI match is flagged", { ... })
# test_that("fuzzy title match is flagged with score", { ... })
