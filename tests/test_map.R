# ============================================================
# tests/test_map.R — Grid-binned location map of coded corpus
# ============================================================
# Phase 10 deliverable.
#
# Purpose: Plot a global map showing density of coded OSM locations,
#   binned to a standard 1° × 1° grid.
#
# Algorithm:
#   For each openstreetmap_location entry, each 1° grid cell the
#   point falls into gets a value of (n instances / n cells).
#   Since a point location covers exactly 1 cell, the value is
#   simply the count of location instances per cell.
#
#   If a location has a bounding_box instead, the box may cover
#   multiple cells — each cell gets (count / n_cells_covered).
#
# Usage:
#   source("tests/test_map.R")
#
# This file can also be used as a testthat test to verify the
# binning logic works without errors.
# ============================================================

library(testthat)

#' Bin a set of locations into a 1° × 1° grid
#'
#' @param locations Data frame with columns: lat, lon, and optionally
#'        lon_min, lon_max, lat_min, lat_max (for bounding boxes)
#' @return Data frame with columns: lon_center, lat_center, value
#'         representing the density per grid cell
bin_locations_to_grid <- function(locations) {
  if (!is.data.frame(locations) || nrow(locations) == 0) {
    return(data.frame(lon_center = numeric(0),
                      lat_center = numeric(0),
                      value      = numeric(0)))
  }

  # Results accumulator: list of (lon_floor, lat_floor, contribution)
  contributions <- list()
  idx <- 0

  for (i in seq_len(nrow(locations))) {
    row <- locations[i, ]

    # Check if this is a bounding box location
    has_bbox <- all(c("lon_min", "lon_max", "lat_min", "lat_max") %in% names(row)) &&
                !is.na(row$lon_min) && !is.na(row$lon_max) &&
                !is.na(row$lat_min) && !is.na(row$lat_max)

    if (has_bbox) {
      # Bounding box: find all 1° cells it covers
      lon_cells <- seq(floor(row$lon_min), floor(row$lon_max), by = 1)
      lat_cells <- seq(floor(row$lat_min), floor(row$lat_max), by = 1)
      n_cells   <- length(lon_cells) * length(lat_cells)
      if (n_cells == 0) n_cells <- 1
      contribution <- 1 / n_cells

      for (lc in lon_cells) {
        for (lt in lat_cells) {
          idx <- idx + 1
          contributions[[idx]] <- data.frame(
            lon_floor = lc, lat_floor = lt, value = contribution)
        }
      }
    } else if (!is.na(row$lat) && !is.na(row$lon)) {
      # Point location: falls in exactly 1 cell
      idx <- idx + 1
      contributions[[idx]] <- data.frame(
        lon_floor = floor(row$lon),
        lat_floor = floor(row$lat),
        value     = 1)
    }
  }

  if (length(contributions) == 0) {
    return(data.frame(lon_center = numeric(0),
                      lat_center = numeric(0),
                      value      = numeric(0)))
  }

  # Combine all contributions
  all_c <- do.call(rbind, contributions)

  # Aggregate by cell
  grid <- aggregate(value ~ lon_floor + lat_floor, data = all_c, FUN = sum)

  # Convert floor to center of cell (add 0.5)
  data.frame(
    lon_center = grid$lon_floor + 0.5,
    lat_center = grid$lat_floor + 0.5,
    value      = grid$value
  )
}

#' Extract openstreetmap_location entries from export data
#'
#' Scans for columns that look like OSM location data (contain lat/lon objects)
#' or extracts from the json_data if available.
#'
#' @param metadata_df Data frame with article_id and json_data columns
#' @param label_schema Data frame of labels
#' @return Data frame with columns: lat, lon (and optionally bbox columns)
extract_locations_from_metadata <- function(metadata_df, label_schema) {
  if (!is.data.frame(metadata_df) || nrow(metadata_df) == 0 ||
      !is.data.frame(label_schema) || nrow(label_schema) == 0) {
    return(data.frame(lat = numeric(0), lon = numeric(0)))
  }

  # Find all labels of type openstreetmap_location or bounding_box
  osm_labels <- label_schema[label_schema$variable_type %in%
                               c("openstreetmap_location", "bounding_box"), ]

  # Also find child labels of groups that are OSM/bbox type
  group_parents <- label_schema[label_schema$label_type == "group" &
                                  (is.na(label_schema$parent_label_id) |
                                   label_schema$parent_label_id == ""), ]

  locations <- list()
  loc_idx   <- 0

  for (i in seq_len(nrow(metadata_df))) {
    jd <- if (is.character(metadata_df$json_data[i])) {
      tryCatch(jsonlite::fromJSON(metadata_df$json_data[i],
                                   simplifyVector = FALSE),
               error = function(e) list())
    } else if (is.list(metadata_df$json_data[i])) {
      metadata_df$json_data[i]
    } else list()

    # Check top-level OSM labels
    for (j in seq_len(nrow(osm_labels))) {
      lbl <- osm_labels[j, ]
      # Skip if it's a child label (handled via groups)
      if (!is.na(lbl$parent_label_id) && nchar(lbl$parent_label_id) > 0) next

      val <- jd[[lbl$name]]
      if (is.list(val) && !is.null(val$lat) && !is.null(val$lon)) {
        loc_idx <- loc_idx + 1
        locations[[loc_idx]] <- data.frame(
          lat = as.numeric(val$lat),
          lon = as.numeric(val$lon),
          lon_min = NA_real_, lon_max = NA_real_,
          lat_min = NA_real_, lat_max = NA_real_)
      } else if (is.list(val) && lbl$variable_type == "bounding_box" &&
                 !is.null(val$lon_min)) {
        loc_idx <- loc_idx + 1
        locations[[loc_idx]] <- data.frame(
          lat = (as.numeric(val$lat_min) + as.numeric(val$lat_max)) / 2,
          lon = (as.numeric(val$lon_min) + as.numeric(val$lon_max)) / 2,
          lon_min = as.numeric(val$lon_min),
          lon_max = as.numeric(val$lon_max),
          lat_min = as.numeric(val$lat_min),
          lat_max = as.numeric(val$lat_max))
      }
    }

    # Check group instances for child OSM/bbox labels
    for (g in seq_len(nrow(group_parents))) {
      grp_name <- group_parents$name[g]
      grp_id   <- group_parents$label_id[g]
      instances <- jd[[grp_name]]
      if (!is.list(instances)) next

      child_osm <- label_schema[!is.na(label_schema$parent_label_id) &
                                  label_schema$parent_label_id == grp_id &
                                  label_schema$variable_type %in%
                                    c("openstreetmap_location", "bounding_box"), ]

      for (inst in instances) {
        for (cl in seq_len(nrow(child_osm))) {
          cl_name <- child_osm$name[cl]
          cl_type <- child_osm$variable_type[cl]
          val <- inst[[cl_name]]

          if (is.list(val) && !is.null(val$lat) && !is.null(val$lon)) {
            loc_idx <- loc_idx + 1
            locations[[loc_idx]] <- data.frame(
              lat = as.numeric(val$lat),
              lon = as.numeric(val$lon),
              lon_min = NA_real_, lon_max = NA_real_,
              lat_min = NA_real_, lat_max = NA_real_)
          } else if (is.list(val) && cl_type == "bounding_box" &&
                     !is.null(val$lon_min)) {
            loc_idx <- loc_idx + 1
            locations[[loc_idx]] <- data.frame(
              lat = (as.numeric(val$lat_min) + as.numeric(val$lat_max)) / 2,
              lon = (as.numeric(val$lon_min) + as.numeric(val$lon_max)) / 2,
              lon_min = as.numeric(val$lon_min),
              lon_max = as.numeric(val$lon_max),
              lat_min = as.numeric(val$lat_min),
              lat_max = as.numeric(val$lat_max))
          }
        }
      }
    }
  }

  if (length(locations) == 0) {
    return(data.frame(lat = numeric(0), lon = numeric(0)))
  }

  do.call(rbind, locations)
}

#' Plot a gridded map of location density
#'
#' @param grid_df Data frame from bin_locations_to_grid (lon_center, lat_center, value)
#' @param title   Plot title
#' @return NULL (opens a plot device)
plot_location_grid <- function(grid_df, title = "Location Density Map (1° grid)") {
  if (!is.data.frame(grid_df) || nrow(grid_df) == 0) {
    message("No locations to plot.")
    return(invisible(NULL))
  }

  # Use base R graphics for maximum portability
  # World coastline approximation using maps package if available
  has_maps <- requireNamespace("maps", quietly = TRUE)

  # Set up the plot
  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par))

  par(mar = c(4, 4, 3, 5))

  # Color scale
  max_val <- max(grid_df$value, na.rm = TRUE)
  n_colors <- 20
  color_pal <- colorRampPalette(c("#f7fbff", "#deebf7", "#9ecae1",
                                   "#3182bd", "#08519c"))(n_colors)
  color_idx <- pmin(ceiling(grid_df$value / max_val * n_colors), n_colors)

  # Plot base (empty world extent)
  plot(NA, xlim = c(-180, 180), ylim = c(-90, 90),
       xlab = "Longitude", ylab = "Latitude", main = title,
       asp = 1)

  # Draw grid cells as rectangles
  rect(
    xleft   = grid_df$lon_center - 0.5,
    ybottom = grid_df$lat_center - 0.5,
    xright  = grid_df$lon_center + 0.5,
    ytop    = grid_df$lat_center + 0.5,
    col     = color_pal[color_idx],
    border  = NA
  )

  # Add world map outline if available
  if (has_maps) {
    maps::map("world", add = TRUE, col = "grey40", lwd = 0.5)
  }

  # Legend
  legend_vals <- round(seq(0, max_val, length.out = 5), 2)
  legend_cols <- color_pal[round(seq(1, n_colors, length.out = 5))]
  legend("bottomleft", legend = legend_vals, fill = legend_cols,
         title = "Density", cex = 0.7, bg = "white")

  invisible(NULL)
}


# ====================================================================
# testthat unit tests for the binning logic
# ====================================================================

test_that("bin_locations_to_grid handles point locations", {
  locs <- data.frame(
    lat = c(48.85, 48.85, -33.86),   # Paris twice, Sydney once
    lon = c(2.35,  2.35, 151.21)
  )
  grid <- bin_locations_to_grid(locs)
  expect_true(is.data.frame(grid))
  expect_true(nrow(grid) >= 2)

  # Paris cell should have value 2
  paris_cell <- grid[grid$lat_center == floor(48.85) + 0.5 &
                      grid$lon_center == floor(2.35) + 0.5, ]
  expect_equal(nrow(paris_cell), 1)
  expect_equal(paris_cell$value, 2)
})

test_that("bin_locations_to_grid handles bounding box", {
  # A bounding box covering 2 longitude cells × 2 latitude cells = 4 cells
  locs <- data.frame(
    lat = 0, lon = 0,
    lon_min = 0.5, lon_max = 1.5,
    lat_min = 0.5, lat_max = 1.5
  )
  grid <- bin_locations_to_grid(locs)
  # Should cover 2 × 2 = 4 cells, each with value 1/4 = 0.25
  expect_equal(nrow(grid), 4)
  expect_true(all(abs(grid$value - 0.25) < 1e-10))
})

test_that("bin_locations_to_grid handles empty input", {
  grid <- bin_locations_to_grid(data.frame())
  expect_equal(nrow(grid), 0)
})

test_that("bin_locations_to_grid accumulates multiple locations in same cell", {
  locs <- data.frame(
    lat = c(10.1, 10.5, 10.9),
    lon = c(20.1, 20.5, 20.9)
  )
  grid <- bin_locations_to_grid(locs)
  expect_equal(nrow(grid), 1)
  expect_equal(grid$value, 3)
})

# ====================================================================
# Demo: Generate a test map with synthetic data
# ====================================================================
if (interactive()) {
  message("Generating test map with synthetic data...")

  # Synthetic locations: Paris(2), London(1), Sydney(3), NYC(1), Tokyo(2)
  test_locs <- data.frame(
    lat = c(48.85, 48.86, 51.51, -33.87, -33.85, -33.88, 40.71, 35.68, 35.69),
    lon = c(2.35, 2.36, -0.13, 151.21, 151.20, 151.19, -74.01, 139.69, 139.70)
  )
  grid <- bin_locations_to_grid(test_locs)
  plot_location_grid(grid, title = "Test Map: Synthetic Locations")
  message("Map plotted. Close the plot window to exit.")
}
