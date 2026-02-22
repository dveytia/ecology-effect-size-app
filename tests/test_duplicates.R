# ============================================================
# tests/test_duplicates.R — Unit tests for duplicate detection
# ============================================================
# Run with: testthat::test_file("tests/test_duplicates.R")

library(testthat)
source("R/utils.R")
source("R/duplicates.R")

# ---- Shared fixture -----------------------------------------
make_existing <- function() {
  data.frame(
    article_id = c("id-001", "id-002", "id-003"),
    title      = c(
      "Effects of climate change on forest birds",
      "Soil nutrient cycling in tropical ecosystems",
      "Population dynamics of alpine ungulates"
    ),
    year       = c(2018L, 2019L, 2020L),
    doi_clean  = c("10.1234/abc", "10.5678/def", "10.9999/xyz"),
    stringsAsFactors = FALSE
  )
}

# ---- DOI cleaning -------------------------------------------
test_that("clean_doi strips https://doi.org/ prefix", {
  expect_equal(clean_doi_dup("https://doi.org/10.1234/abc"), "10.1234/abc")
})

test_that("clean_doi strips http://doi.org/ prefix", {
  expect_equal(clean_doi_dup("http://doi.org/10.1234/abc"), "10.1234/abc")
})

test_that("clean_doi strips doi: prefix", {
  expect_equal(clean_doi_dup("doi:10.1234/abc"), "10.1234/abc")
})

test_that("clean_doi lowercases", {
  expect_equal(clean_doi_dup("10.1234/ABC"), "10.1234/abc")
})

test_that("clean_doi trims whitespace", {
  expect_equal(clean_doi_dup("  10.1234/abc  "), "10.1234/abc")
})

test_that("clean_doi handles NA", {
  result <- clean_doi_dup(NA)
  expect_true(is.na(result) || nchar(result) == 0)
})

# ---- Title cleaning -----------------------------------------
test_that("clean_title removes punctuation and lowercases", {
  result <- clean_title("Effects of Climate-Change: A Review!")
  expect_false(grepl("[[:punct:]]", result))
  expect_equal(result, tolower(result))
})

test_that("clean_title collapses extra whitespace", {
  result <- clean_title("A  double   spaced  title")
  expect_false(grepl("  ", result))
})

# ---- No duplicates ------------------------------------------
test_that("no flags returned when new articles are unique", {
  incoming <- data.frame(
    title = "Completely novel study on deep sea vents",
    abstract = "Abstract text.", author = "Smith J",
    year = 2021L, doi = "10.0000/new",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 0)
})

test_that("empty result when existing_df is empty", {
  incoming <- data.frame(
    title = "Some title", abstract = "x", author = "A",
    year = 2021L, doi = "10.0/new",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, data.frame())
  expect_equal(nrow(result), 0)
})

# ---- Exact DOI match ----------------------------------------
test_that("exact DOI duplicate is flagged as exact_doi", {
  incoming <- data.frame(
    title = "Some different title", abstract = "Abstract",
    author = "Jones A", year = 2021L,
    doi = "https://doi.org/10.1234/abc",   # same as id-001 after cleaning
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 1)
  expect_equal(result$match_type[1],         "exact_doi")
  expect_equal(result$matched_article_id[1], "id-001")
  expect_equal(result$similarity_score[1],   1.0)
})

# ---- Title + year match -------------------------------------
test_that("title + year duplicate is flagged as title_year", {
  incoming <- data.frame(
    title = "Soil Nutrient Cycling in Tropical Ecosystems!!",  # same after normalisation
    abstract = "Abstract", author = "Jones A",
    year = 2019L, doi = "10.0000/different",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 1)
  expect_equal(result$match_type[1],         "title_year")
  expect_equal(result$matched_article_id[1], "id-002")
})

test_that("same title but different year is NOT flagged as title_year", {
  incoming <- data.frame(
    title = "Soil Nutrient Cycling in Tropical Ecosystems",
    abstract = "x", author = "A",
    year = 2010L,           # different year
    doi = "10.0000/new2",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 0)
})

# ---- Partial DOI match --------------------------------------
test_that("partial DOI match is flagged as partial_doi", {
  existing <- data.frame(
    article_id = "id-ext",
    title      = "Unrelated title here",
    year       = 2018L,
    doi_clean  = "10.1234/longdoi99",    # 18 chars
    stringsAsFactors = FALSE
  )
  incoming <- data.frame(
    title = "A completely different title for this paper",
    abstract = "x", author = "B", year = 2018L,
    doi = "10.1234/longdoiXX",    # same first 15 chars, same year
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, existing)
  expect_equal(nrow(result), 1)
  expect_equal(result$match_type[1], "partial_doi")
})

# ---- Fuzzy title match --------------------------------------
test_that("fuzzy title match (JW < 0.05) is flagged", {
  incoming <- data.frame(
    title = "Effects of climate change on forest bird",   # missing 's'
    abstract = "x", author = "C",
    year = 2018L, doi = "10.0000/fuzzy",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 1)
  expect_equal(result$match_type[1],         "fuzzy")
  expect_equal(result$matched_article_id[1], "id-001")
  expect_true(result$similarity_score[1] > 0.9)
})

test_that("title with low similarity is NOT flagged as fuzzy", {
  incoming <- data.frame(
    title = "Completely different subject matter entirely",
    abstract = "x", author = "D",
    year = 2018L, doi = "10.0000/notfuzzy",
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 0)
})

# ---- Priority: exact DOI wins over fuzzy --------------------
test_that("exact DOI match takes priority over fuzzy title", {
  existing <- data.frame(
    article_id = c("id-A", "id-B"),
    title      = c(
      "Effects of climate change on forest birds",
      "Unrelated paper about fish ecology"
    ),
    year      = c(2018L, 2018L),
    doi_clean = c("10.1234/abc", "10.9876/xyz"),
    stringsAsFactors = FALSE
  )
  incoming <- data.frame(
    title = "Effects of climate change on forest birds",
    abstract = "x", author = "E", year = 2018L,
    doi = "10.1234/abc",   # exact DOI match
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, existing)
  expect_equal(nrow(result), 1)
  expect_equal(result$match_type[1], "exact_doi")
})

# ---- Multiple incoming rows ---------------------------------
test_that("two clean + two flagged returns two rows", {
  incoming <- data.frame(
    title = c(
      "Brand new unique study A",
      "Brand new unique study B",
      "Effects of climate change on forest birds",   # fuzzy match id-001
      "Soil nutrient cycling in tropical ecosystems" # title_year match id-002
    ),
    abstract = rep("x", 4), author = rep("F", 4),
    year = c(2021L, 2022L, 2018L, 2019L),
    doi  = c("10.0/a", "10.0/b", "10.0/c", "10.0/d"),
    stringsAsFactors = FALSE
  )
  result <- check_duplicates(incoming, make_existing())
  expect_equal(nrow(result), 2)
  expect_true(3 %in% result$row_index)
  expect_true(4 %in% result$row_index)
})

# ---- validate_upload_columns --------------------------------
test_that("validate_upload_columns returns empty for valid df", {
  df <- data.frame(title = "t", abstract = "a", author = "au",
                   year = 2020L, doi = "d", stringsAsFactors = FALSE)
  expect_length(validate_upload_columns(df), 0)
})

test_that("validate_upload_columns flags missing column", {
  df <- data.frame(title = "t", abstract = "a", author = "au",
                   year = 2020L, stringsAsFactors = FALSE)   # missing 'doi'
  miss <- validate_upload_columns(df)
  expect_true("doi" %in% miss)
})
