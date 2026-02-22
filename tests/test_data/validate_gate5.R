library(stringdist)
library(readr)
source("R/utils.R")
source("R/duplicates.R")

# Test TSV auto-detection
partA <- read_upload_file("tests/test_data/gate5_part_A.txt", "gate5_part_A.txt")
cat("Part A rows:", nrow(partA), "\n")
cat("Part A cols:", paste(names(partA), collapse = ", "), "\n\n")

# Simulate existing_df as if Part A was already in the DB
existing <- data.frame(
  article_id = paste0("art-", seq_len(nrow(partA))),
  title      = partA[["title"]],
  year       = as.integer(partA[["year"]]),
  doi_clean  = sapply(partA[["doi"]], clean_doi_dup),
  stringsAsFactors = FALSE
)

partB <- read_upload_file("tests/test_data/gate5_part_B.txt", "gate5_part_B.txt")
cat("Part B rows:", nrow(partB), "\n\n")

flags <- check_duplicates(partB, existing)
cat("Flagged rows:\n")
print(flags[, c("row_index", "match_type", "similarity_score")])
cat("\nExpected 4 flags, got:", nrow(flags), "\n")
stopifnot(nrow(flags) == 4)
stopifnot(flags$match_type[1] == "exact_doi")
stopifnot(flags$match_type[2] == "exact_doi")
stopifnot(flags$match_type[3] == "title_year")
stopifnot(flags$match_type[4] == "fuzzy")
cat("\nAll assertions passed!\n")
