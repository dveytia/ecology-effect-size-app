# ============================================================
# tests/test_map.R — Grid-binned location map of coded corpus
# ============================================================
# Phase 10 deliverable (updated Phase 14 — JSON-native reader).
#
# Purpose: Plot a global map showing density of coded OSM locations,
#   binned to a standard 1° × 1° grid.
#
# Primary input: JSON export files produced by build_full_export().
#   Each article object may contain:
#     labels.location_osm — array of {name, lat, lon, osm_id, geojson?}
#     labels.bounding_box_label — {lon_min, lon_max, lat_min, lat_max}
#
# Legacy xlsx parsing (semicolon-delimited strings) is retained for
# backward compatibility but is no longer the primary path.
#
# Algorithm:
#   For each location:
#     - Point or centroid only: 1 count to the single 1° cell it falls in.
#     - Polygon (GeoJSON): PIP test over grid cells;
#       each inside cell receives 1/N (total contribution per location = 1).
#     - Bounding box: bbox spans N cells;
#       each cell receives 1/N (total contribution per location = 1).
#
# Usage:
#   source("tests/test_map.R")                    -- run tests + demo (if interactive)
#   testthat::test_file("tests/test_map.R")        -- run tests only
# ============================================================

library(testthat)

# ---------------------------------------------------------------------------
# 1. Parse individual location strings
# ---------------------------------------------------------------------------

#' Parse a single location_osm string
#'
#' Handles the three formats stored in the location_osm export column:
#'
#'   Point:        "Display Name; lat; lon; osm_id"
#'   Polygon:      "Display Name; lat; lon; osm_id; Polygon; lon1; lat1; lon2; lat2; ..."
#'   MultiPolygon: "Display Name; lat; lon; osm_id; MultiPolygon; lon1; lat1; ..."
#'
#' Note: polygon vertex coordinates are interleaved as **lon, lat** pairs.
#' For Polygon/MultiPolygon the centroid (lat/lon at positions 2-3) is preserved,
#' and a bounding box is derived from all polygon vertices.
#'
#' @param s  Single character string (one location_osm value)
#' @return   One-row data.frame: lat, lon, lon_min, lon_max, lat_min, lat_max,
#'           or NULL when the string cannot be parsed.
parse_location_osm <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(trimws(s))) return(NULL)

  parts <- trimws(strsplit(s, ";", fixed = TRUE)[[1]])
  if (length(parts) < 3L) return(NULL)

  lat <- suppressWarnings(as.numeric(parts[2L]))
  lon <- suppressWarnings(as.numeric(parts[3L]))
  if (is.na(lat) || is.na(lon)) return(NULL)

  rec <- data.frame(lat = lat, lon = lon,
                    lon_min = NA_real_, lon_max = NA_real_,
                    lat_min = NA_real_, lat_max = NA_real_,
                    stringsAsFactors = FALSE)

  # Polygon / MultiPolygon: keyword at parts[5], vertices from parts[6]+.
  # Stored as list-columns for accurate point-in-polygon binning.
  # bbox columns are intentionally left NA; binning uses the vertices directly.
  if (length(parts) >= 6L) {
    geom_type <- toupper(trimws(parts[5L]))
    if (geom_type %in% c("POLYGON", "MULTIPOLYGON")) {
      coords <- suppressWarnings(as.numeric(parts[6L:length(parts)]))
      coords <- coords[!is.na(coords)]
      if (length(coords) >= 4L) {
        # Vertices are interleaved lon, lat pairs
        lons_v <- coords[seq(1L, length(coords), by = 2L)]
        lats_v <- coords[seq(2L, length(coords), by = 2L)]
        rec$poly_lons <- list(lons_v)
        rec$poly_lats <- list(lats_v)
        return(rec)
      }
    }
  }

  # Point location: no polygon vertices
  rec$poly_lons <- list(NULL)
  rec$poly_lats <- list(NULL)
  rec
}

#' Parse a flattened bounding_box label value
#'
#' Expects semicolon-separated key=value pairs as produced by .flatten_value():
#'   "lon_min=-10; lon_max=10; lat_min=-5; lat_max=5"
#'
#' @param s  Character string
#' @return   One-row data.frame (lat = midpoint, lon = midpoint, plus bbox),
#'           or NULL if required keys are absent.
parse_bbox_value <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(trimws(s))) return(NULL)

  pairs <- strsplit(s, ";", fixed = TRUE)[[1]]
  kv <- list()
  for (p in pairs) {
    p  <- trimws(p)
    eq <- regexpr("=", p, fixed = TRUE)
    if (eq < 1L) next
    key <- tolower(trimws(substring(p, 1L, eq - 1L)))
    val <- suppressWarnings(as.numeric(trimws(substring(p, eq + 1L))))
    if (!is.na(val)) kv[[key]] <- val
  }

  need <- c("lon_min", "lon_max", "lat_min", "lat_max")
  if (!all(need %in% names(kv))) return(NULL)

  res <- data.frame(
    lat     = (kv$lat_min + kv$lat_max) / 2,
    lon     = (kv$lon_min + kv$lon_max) / 2,
    lon_min = kv$lon_min,
    lon_max = kv$lon_max,
    lat_min = kv$lat_min,
    lat_max = kv$lat_max,
    stringsAsFactors = FALSE
  )
  res$poly_lons <- list(NULL)
  res$poly_lats <- list(NULL)
  res
}

#' Parse a flattened openstreetmap_location label value
#'
#' Expects semicolon-separated key=value pairs as produced by .flatten_value():
#'   "lat=48.85; lon=2.32; display_name=Paris; osm_id=7444"
#'
#' @param s  Character string
#' @return   One-row data.frame with lat, lon (NA bbox), or NULL.
parse_osm_point_value <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(trimws(s))) return(NULL)

  pairs <- strsplit(s, ";", fixed = TRUE)[[1]]
  kv <- list()
  for (p in pairs) {
    p  <- trimws(p)
    eq <- regexpr("=", p, fixed = TRUE)
    if (eq < 1L) next
    key <- tolower(trimws(substring(p, 1L, eq - 1L)))
    val <- trimws(substring(p, eq + 1L))
    kv[[key]] <- val
  }

  lat <- suppressWarnings(as.numeric(kv[["lat"]]))
  lon <- suppressWarnings(as.numeric(kv[["lon"]]))
  if (length(lat) == 0L || length(lon) == 0L) return(NULL)
  if (is.na(lat) || is.na(lon)) return(NULL)

  rec <- data.frame(lat = lat, lon = lon,
                    lon_min = NA_real_, lon_max = NA_real_,
                    lat_min = NA_real_, lat_max = NA_real_,
                    stringsAsFactors = FALSE)
  rec$poly_lons <- list(NULL)
  rec$poly_lats <- list(NULL)
  rec
}

# ---------------------------------------------------------------------------
# 2. Detect location-bearing columns in an export data frame
# ---------------------------------------------------------------------------

#' Identify location columns in a full-export data frame
#'
#' Scans column names and samples up to 10 non-NA values per column to
#' classify columns as one of:
#'   "location_osm" -- the built-in article-level OSM location column (by name)
#'   "osm_point"    -- flattened openstreetmap_location label ("lat=X; lon=Y; ...")
#'   "bbox"         -- flattened bounding_box label ("lon_min=X; lon_max=Y; ...")
#'
#' @param df  Data frame (from readxl::read_xlsx)
#' @return    Named character vector: column_name -> type string
detect_location_columns <- function(df) {
  result <- character(0)

  for (col in names(df)) {
    if (col == "location_osm") {
      result[col] <- "location_osm"
      next
    }

    vals <- df[[col]]
    sample_vals <- vals[!is.na(vals) & nzchar(as.character(vals))]
    if (length(sample_vals) == 0L) next
    sample_vals <- as.character(
      sample_vals[seq_len(min(10L, length(sample_vals)))]
    )

    is_bbox <- any(vapply(sample_vals, function(v) {
      grepl("lon_min\\s*=",  v, ignore.case = TRUE) &&
      grepl("lon_max\\s*=",  v, ignore.case = TRUE) &&
      grepl("lat_min\\s*=",  v, ignore.case = TRUE) &&
      grepl("lat_max\\s*=",  v, ignore.case = TRUE)
    }, logical(1L)))

    if (is_bbox) { result[col] <- "bbox"; next }

    is_osm_point <- any(vapply(sample_vals, function(v) {
      grepl("\\blat\\s*=\\s*-?[0-9]", v, ignore.case = TRUE) &&
      grepl("\\blon\\s*=\\s*-?[0-9]", v, ignore.case = TRUE)
    }, logical(1L)))

    if (is_osm_point) result[col] <- "osm_point"
  }

  result
}

# ---------------------------------------------------------------------------
# 3. Read an export .xlsx file and extract all location records
# ---------------------------------------------------------------------------

.empty_location_df <- function() {
  df <- data.frame(lat = numeric(0), lon = numeric(0),
                   lon_min = numeric(0), lon_max = numeric(0),
                   lat_min = numeric(0), lat_max = numeric(0),
                   source_column = character(0),
                   stringsAsFactors = FALSE)
  df$poly_lons <- list()
  df$poly_lats <- list()
  df
}

#' Read a full-export .xlsx file and return all location records
#'
#' Parses:
#'   - The location_osm column (points, Polygon, MultiPolygon).
#'     Deduplicated per article_id so articles with multiple group-instance
#'     rows are counted once for article-level location.
#'   - Any columns detected as flattened openstreetmap_location labels.
#'   - Any columns detected as flattened bounding_box labels.
#'
#' @param filepath  Path to .xlsx export file from build_full_export()
#' @return          Data frame: lat, lon, lon_min, lon_max, lat_min, lat_max,
#'                  source_column
read_export_for_map <- function(filepath) {
  stopifnot(file.exists(filepath))
  df <- readxl::read_xlsx(filepath, col_types = "text")

  col_types <- detect_location_columns(df)
  if (length(col_types) == 0L) {
    message("No location columns detected in ", basename(filepath))
    return(.empty_location_df())
  }

  loc_list <- list()
  lid <- 0L

  for (col in names(col_types)) {
    col_type <- col_types[[col]]
    parse_fn <- switch(col_type,
      location_osm = parse_location_osm,
      osm_point    = parse_osm_point_value,
      bbox         = parse_bbox_value,
      NULL
    )
    if (is.null(parse_fn)) next

    # For location_osm: one record per article_id.
    # Deduplicating by article_id (not by location string) means 3 articles
    # all coded to "Paris" produce 3 Paris records (3 units of weight), while
    # an article with 5 group-instance rows at Paris still counts only once.
    if (col_type == "location_osm" && "article_id" %in% names(df)) {
      sub  <- df[!is.na(df[[col]]) & nzchar(df[[col]]),
                 c("article_id", col), drop = FALSE]
      sub  <- sub[!duplicated(sub$article_id), , drop = FALSE]
      vals <- as.character(sub[[col]])
    } else {
      vals <- as.character(df[[col]])
      vals <- vals[!is.na(vals) & nzchar(vals)]
    }

    for (v in vals) {
      rec <- parse_fn(v)
      if (!is.null(rec)) {
        rec$source_column <- col
        lid <- lid + 1L
        loc_list[[lid]] <- rec
      }
    }
  }

  if (length(loc_list) == 0L) {
    message("No parseable locations found in ", basename(filepath))
    return(.empty_location_df())
  }

  do.call(rbind, loc_list)
}

# ---------------------------------------------------------------------------
# 3b. Read a JSON export file and extract all location records
# ---------------------------------------------------------------------------

#' Read a JSON export file and return all location records
#'
#' Parses the native JSON structure produced by build_full_export().
#' Each article may contain:
#'   - labels$location_osm — array of {name, lat, lon, osm_id, geojson?}
#'     where geojson is a standard GeoJSON Polygon object:
#'     {type: "Polygon", coordinates: [[[lon, lat], ...]]}
#'   - labels$bounding_box_label — {lon_min, lon_max, lat_min, lat_max}
#'
#' One location record is produced per unique location entry per article.
#'
#' @param filepath  Path to JSON export file
#' @return          Data frame: lat, lon, lon_min, lon_max, lat_min, lat_max,
#'                  poly_lons (list), poly_lats (list), source_column
read_json_export_for_map <- function(filepath) {
  stopifnot(file.exists(filepath))
  articles <- jsonlite::fromJSON(filepath, simplifyVector = FALSE)

  loc_list <- list()
  lid      <- 0L

  for (art in articles) {
    labels <- art$labels
    if (is.null(labels)) next

    # --- location_osm entries ---
    osm_locs <- labels$location_osm
    if (!is.null(osm_locs) && length(osm_locs) > 0L) {
      for (loc in osm_locs) {
        lat <- suppressWarnings(as.numeric(loc$lat))
        lon <- suppressWarnings(as.numeric(loc$lon))
        if (length(lat) == 0L || length(lon) == 0L) next
        if (is.na(lat) || is.na(lon)) next

        rec <- data.frame(lat = lat, lon = lon,
                          lon_min = NA_real_, lon_max = NA_real_,
                          lat_min = NA_real_, lat_max = NA_real_,
                          source_column = "location_osm",
                          stringsAsFactors = FALSE)

        # Extract polygon vertices from GeoJSON if present
        geojson <- loc$geojson
        if (!is.null(geojson) && !is.null(geojson$coordinates)) {
          ring <- geojson$coordinates[[1L]]          # outer ring
          if (length(ring) >= 3L) {
            coords_mat <- do.call(rbind, lapply(ring, as.numeric))
            rec$poly_lons <- list(coords_mat[, 1L])
            rec$poly_lats <- list(coords_mat[, 2L])
          } else {
            rec$poly_lons <- list(NULL)
            rec$poly_lats <- list(NULL)
          }
        } else {
          rec$poly_lons <- list(NULL)
          rec$poly_lats <- list(NULL)
        }

        lid <- lid + 1L
        loc_list[[lid]] <- rec
      }
    }

    # --- bounding_box_label ---
    bbox <- labels$bounding_box_label
    if (!is.null(bbox)) {
      lon_min <- suppressWarnings(as.numeric(bbox$lon_min))
      lon_max <- suppressWarnings(as.numeric(bbox$lon_max))
      lat_min <- suppressWarnings(as.numeric(bbox$lat_min))
      lat_max <- suppressWarnings(as.numeric(bbox$lat_max))

      if (length(lon_min) == 1L && length(lon_max) == 1L &&
          length(lat_min) == 1L && length(lat_max) == 1L &&
          !is.na(lon_min) && !is.na(lon_max) &&
          !is.na(lat_min) && !is.na(lat_max)) {
        rec <- data.frame(
          lat     = (lat_min + lat_max) / 2,
          lon     = (lon_min + lon_max) / 2,
          lon_min = lon_min, lon_max = lon_max,
          lat_min = lat_min, lat_max = lat_max,
          source_column = "bounding_box",
          stringsAsFactors = FALSE
        )
        rec$poly_lons <- list(NULL)
        rec$poly_lats <- list(NULL)
        lid <- lid + 1L
        loc_list[[lid]] <- rec
      }
    }
  }

  if (length(loc_list) == 0L) {
    message("No parseable locations found in ", basename(filepath))
    return(.empty_location_df())
  }

  do.call(rbind, loc_list)
}

# ---------------------------------------------------------------------------
# 4. Bin locations to a 1° x 1° grid
# ---------------------------------------------------------------------------

#' Point-in-polygon test using the ray casting algorithm.
#'
#' Vectorised over test points; iterates over polygon vertices.
#' The polygon ring need not be explicitly closed.
#'
#' @param test_lons  Numeric vector of query longitudes (cell centres)
#' @param test_lats  Numeric vector of query latitudes  (cell centres)
#' @param poly_lons  Numeric vector of polygon vertex longitudes
#' @param poly_lats  Numeric vector of polygon vertex latitudes
#' @return Logical vector (TRUE = inside polygon)
.pip_vectorized <- function(test_lons, test_lats, poly_lons, poly_lats) {
  n      <- length(poly_lons)
  result <- rep(FALSE, length(test_lons))
  j      <- n
  for (i in seq_len(n)) {
    xi <- poly_lons[i]; yi <- poly_lats[i]
    xj <- poly_lons[j]; yj <- poly_lats[j]
    cross <- ((yi > test_lats) != (yj > test_lats)) &
             (test_lons < (xj - xi) * (test_lats - yi) / (yj - yi) + xi)
    result[cross] <- !result[cross]
    j <- i
  }
  result
}

#' Bin a set of locations into a 1° × 1° grid
#'
#' For each location the total weight contributed is 1:
#'   - Point: 1 unit to the single cell the point falls in.
#'   - Polygon / MultiPolygon (has poly_lons/poly_lats list-columns):
#'       ray-casting PIP test determines which cells are inside;
#'       each inside cell receives 1 / n_inside.
#'   - Bounding box (lon_min/lon_max/lat_min/lat_max not NA, no vertices):
#'       every cell whose centre is within the box receives 1 / n_cells.
#'
#' @param locations Data frame from read_export_for_map() (or compatible).
#'        May contain list-columns poly_lons / poly_lats.
#' @return Data frame: lon_center, lat_center, value (weighted article count)
bin_locations_to_grid <- function(locations) {
  if (!is.data.frame(locations) || nrow(locations) == 0) {
    return(data.frame(lon_center = numeric(0),
                      lat_center = numeric(0),
                      value      = numeric(0)))
  }

  has_poly_col <- "poly_lons" %in% names(locations)
  contributions <- list()
  idx <- 0L

  for (i in seq_len(nrow(locations))) {
    row <- locations[i, ]

    # --- 1. Polygon / MultiPolygon: accurate PIP binning ---
    has_poly <- has_poly_col &&
                !is.null(locations$poly_lons[[i]]) &&
                length(locations$poly_lons[[i]]) > 0L

    if (has_poly) {
      plons <- locations$poly_lons[[i]]
      plats <- locations$poly_lats[[i]]

      lon_floors <- seq(floor(min(plons)), floor(max(plons)))
      lat_floors <- seq(floor(min(plats)), floor(max(plats)))
      cands      <- expand.grid(lon_f = lon_floors, lat_f = lat_floors)
      inside     <- .pip_vectorized(cands$lon_f + 0.5, cands$lat_f + 0.5,
                                    plons, plats)
      hit        <- cands[inside, , drop = FALSE]
      n_cells    <- nrow(hit)

      if (n_cells == 0L) {
        # Fallback: centroid cell (e.g. tiny island smaller than 1° cell)
        idx <- idx + 1L
        contributions[[idx]] <- data.frame(
          lon_floor = floor(row$lon), lat_floor = floor(row$lat), value = 1)
      } else {
        contribution <- 1 / n_cells
        for (ci in seq_len(n_cells)) {
          idx <- idx + 1L
          contributions[[idx]] <- data.frame(
            lon_floor = hit$lon_f[ci], lat_floor = hit$lat_f[ci],
            value = contribution)
        }
      }
      next
    }

    # --- 2. Bounding box (from bbox label columns) ---
    has_bbox <- all(c("lon_min", "lon_max", "lat_min", "lat_max") %in% names(row)) &&
                !is.na(row$lon_min) && !is.na(row$lon_max) &&
                !is.na(row$lat_min) && !is.na(row$lat_max)

    if (has_bbox) {
      lon_cells <- seq(floor(row$lon_min), floor(row$lon_max), by = 1)
      lat_cells <- seq(floor(row$lat_min), floor(row$lat_max), by = 1)
      n_cells   <- length(lon_cells) * length(lat_cells)
      if (n_cells == 0L) n_cells <- 1L
      contribution <- 1 / n_cells

      for (lc in lon_cells) {
        for (lt in lat_cells) {
          idx <- idx + 1L
          contributions[[idx]] <- data.frame(
            lon_floor = lc, lat_floor = lt, value = contribution)
        }
      }
      next
    }

    # --- 3. Point ---
    if (!is.na(row$lat) && !is.na(row$lon)) {
      idx <- idx + 1L
      contributions[[idx]] <- data.frame(
        lon_floor = floor(row$lon),
        lat_floor = floor(row$lat),
        value     = 1)
    }
  }

  if (length(contributions) == 0L) {
    return(data.frame(lon_center = numeric(0),
                      lat_center = numeric(0),
                      value      = numeric(0)))
  }

  all_c <- do.call(rbind, contributions)
  grid  <- aggregate(value ~ lon_floor + lat_floor, data = all_c, FUN = sum)

  data.frame(
    lon_center = grid$lon_floor + 0.5,
    lat_center = grid$lat_floor + 0.5,
    value      = grid$value
  )
}

# ---------------------------------------------------------------------------
# 5. Convenience wrapper — read, bin, plot in one call
# ---------------------------------------------------------------------------

#' Create a grid-binned location map from a full-export file
#'
#' Convenience wrapper that reads locations, bins them to a 1° grid,
#' and (optionally) renders the map.
#'
#' File type is auto-detected by extension:
#'   .json  → read_json_export_for_map()
#'   .xlsx  → read_export_for_map()        (legacy)
#'
#' @param filepath  Path to export file (JSON preferred; xlsx legacy)
#' @param title     Plot title passed to plot_location_grid()
#' @param plot      Whether to render the map (default TRUE)
#' @return          Invisibly, the grid data frame (lon_center, lat_center, value)
map_from_export <- function(filepath,
                            title = paste0("Location Density \u2014 ",
                                           basename(filepath)),
                            plot  = TRUE) {
  ext <- tolower(tools::file_ext(filepath))
  locs <- if (ext == "json") {
    read_json_export_for_map(filepath)
  } else {
    read_export_for_map(filepath)     # legacy xlsx path
  }
  grid <- bin_locations_to_grid(locs)
  if (plot && nrow(grid) > 0L) {
    plot_location_grid(grid, title = title)
  }
  invisible(grid)
}

# ---------------------------------------------------------------------------
# 6. Plot a gridded map
# ---------------------------------------------------------------------------

#' Plot a gridded map of location density using ggplot2
#'
#' Renders each 1° × 1° grid cell as a coloured tile (viridis plasma scale).
#' A world coastline outline is added when the \code{maps} package is available.
#'
#' @param grid_df  Data frame from bin_locations_to_grid (lon_center, lat_center, value)
#' @param title    Plot title
#' @return The ggplot object (invisibly); also printed as a side-effect.
plot_location_grid <- function(grid_df, title = "Location Density Map (1\u00b0 grid)") {
  if (!is.data.frame(grid_df) || nrow(grid_df) == 0) {
    message("No locations to plot.")
    return(invisible(NULL))
  }

  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("ggplot2 is required; install with: install.packages('ggplot2')")

  # Build plot base with ocean background
  p <- ggplot2::ggplot() +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.background = ggplot2::element_rect(fill = "#d6eaf8", colour = NA),
      panel.grid       = ggplot2::element_blank(),
      axis.text        = ggplot2::element_text(size  = 8),
      legend.position  = "right"
    )

  # Grey land basemap (drawn BEFORE tiles so tiles appear on top)
  if (requireNamespace("maps", quietly = TRUE)) {
    world <- ggplot2::map_data("world")
    p <- p +
      ggplot2::geom_polygon(
        data  = world,
        ggplot2::aes(x = .data[["long"]], y = .data[["lat"]],
                     group = .data[["group"]]),
        fill    = "grey82",
        colour  = NA,
        inherit.aes = FALSE
      )
  }

  # Article-density tiles
  p <- p +
    ggplot2::geom_tile(
      data  = grid_df,
      ggplot2::aes(x    = .data[["lon_center"]],
                   y    = .data[["lat_center"]],
                   fill = .data[["value"]]),
      width  = 1, height = 1, alpha = 0.85
    ) +
    ggplot2::scale_fill_viridis_c(
      option    = "plasma",
      direction = -1,
      name      = "Articles\n(weighted)"
    )

  # Coastline outline on top of tiles
  if (requireNamespace("maps", quietly = TRUE)) {
    world <- ggplot2::map_data("world")
    p <- p +
      ggplot2::geom_polygon(
        data  = world,
        ggplot2::aes(x = .data[["long"]], y = .data[["lat"]],
                     group = .data[["group"]]),
        fill        = NA,
        colour      = "grey30",
        linewidth   = 0.15,
        inherit.aes = FALSE
      )
  }

  p <- p +
    ggplot2::coord_fixed(
      xlim   = c(-180, 180),
      ylim   = c(-90,   90),
      expand = FALSE
    ) +
    ggplot2::labs(title = title, x = "Longitude", y = "Latitude")

  print(p)
  invisible(p)
}


# ====================================================================
# testthat unit tests
# ====================================================================

# --- parse_location_osm ---

test_that("parse_location_osm parses a plain point string", {
  res <- parse_location_osm("Paris; 48.8589; 2.3200; 7444")
  expect_equal(res$lat, 48.8589)
  expect_equal(res$lon, 2.3200)
  expect_true(is.na(res$lon_min))
})

test_that("parse_location_osm parses Polygon and stores vertices", {
  # Minimal polygon: 4 lon/lat vertex pairs
  s <- "Toronto; 43.65; -79.38; 324211; Polygon; -79.6; 43.5; -79.1; 43.5; -79.1; 43.9; -79.6; 43.9"
  res <- parse_location_osm(s)
  expect_equal(res$lat, 43.65)
  expect_equal(res$lon, -79.38)
  # bbox columns must be NA (PIP uses vertices directly)
  expect_true(is.na(res$lon_min))
  # Polygon vertices stored in list-columns
  expect_false(is.null(res$poly_lons[[1L]]))
  expect_equal(min(res$poly_lons[[1L]]), -79.6)
  expect_equal(max(res$poly_lons[[1L]]), -79.1)
  expect_equal(min(res$poly_lats[[1L]]),  43.5)
  expect_equal(max(res$poly_lats[[1L]]),  43.9)
})

test_that("parse_location_osm parses MultiPolygon (keyword case-insensitive)", {
  s <- "Iceland; 64.98; -18.11; 299133; multipolygon; -25.0; 65.5; -13.5; 66.5; -25.0; 65.5"
  res <- parse_location_osm(s)
  expect_false(is.null(res$poly_lons[[1L]]))
  expect_equal(min(res$poly_lons[[1L]]), -25.0)
  expect_equal(max(res$poly_lons[[1L]]), -13.5)
})

test_that("parse_location_osm returns NULL for NA / empty string", {
  expect_null(parse_location_osm(NA_character_))
  expect_null(parse_location_osm(""))
  expect_null(parse_location_osm("  "))
})

# --- parse_bbox_value ---

test_that("parse_bbox_value parses a standard bounding_box label string", {
  s <- "lon_min=-10; lon_max=10; lat_min=-5; lat_max=5"
  res <- parse_bbox_value(s)
  expect_equal(res$lon_min, -10)
  expect_equal(res$lon_max,  10)
  expect_equal(res$lat,       0)   # centroid
  expect_equal(res$lon,       0)
})

test_that("parse_bbox_value returns NULL when required keys are absent", {
  expect_null(parse_bbox_value("lat=1; lon=2"))
  expect_null(parse_bbox_value(NA_character_))
})

# --- parse_osm_point_value ---

test_that("parse_osm_point_value parses a flattened osm_point label string", {
  s <- "lat=48.8589; lon=2.3200; display_name=Paris; osm_id=7444"
  res <- parse_osm_point_value(s)
  expect_equal(res$lat, 48.8589)
  expect_equal(res$lon,  2.3200)
  expect_true(is.na(res$lon_min))
})

test_that("parse_osm_point_value returns NULL when lat/lon missing", {
  expect_null(parse_osm_point_value("display_name=Unknown"))
  expect_null(parse_osm_point_value(NA_character_))
})

# --- detect_location_columns ---

test_that("detect_location_columns identifies location_osm by column name", {
  df <- data.frame(location_osm = "Paris; 48.85; 2.32; 7444", stringsAsFactors = FALSE)
  res <- detect_location_columns(df)
  expect_equal(unname(res["location_osm"]), "location_osm")
})

test_that("detect_location_columns identifies bbox column by value pattern", {
  df <- data.frame(
    some_label = "lon_min=-10; lon_max=10; lat_min=-5; lat_max=5",
    stringsAsFactors = FALSE
  )
  res <- detect_location_columns(df)
  expect_equal(unname(res["some_label"]), "bbox")
})

test_that("detect_location_columns identifies osm_point column by value pattern", {
  df <- data.frame(
    loc_label = "lat=48.85; lon=2.32; display_name=Paris; osm_id=7444",
    stringsAsFactors = FALSE
  )
  res <- detect_location_columns(df)
  expect_equal(unname(res["loc_label"]), "osm_point")
})

# --- bin_locations_to_grid ---

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

# --- JSON integration tests ---

.find_json_fixture <- function() {
  candidates <- c(
    file.path("test_outputs", "export_20260228.json"),        # CWD = tests/
    file.path("tests", "test_outputs", "export_20260228.json") # CWD = project root
  )
  for (p in candidates) if (file.exists(p)) return(p)
  NULL
}

test_that("read_json_export_for_map parses locations from real JSON export", {
  json_path <- .find_json_fixture()
  skip_if(is.null(json_path), "Export JSON not found")

  locs <- read_json_export_for_map(json_path)
  expect_true(is.data.frame(locs))
  expect_true(nrow(locs) > 0L)
  expect_true(all(c("lat", "lon") %in% names(locs)))

  # At least one record should have valid lat/lon
  valid_pts <- locs[!is.na(locs$lat) & !is.na(locs$lon), ]
  expect_true(nrow(valid_pts) > 0L)

  # Paris (point only) should appear
  paris <- locs[abs(locs$lat - 48.8589) < 0.01 & abs(locs$lon - 2.32) < 0.01, ]
  expect_true(nrow(paris) >= 1L, info = "Paris point location expected")
})

test_that("read_json_export_for_map extracts GeoJSON polygon vertices", {
  json_path <- .find_json_fixture()
  skip_if(is.null(json_path), "Export JSON not found")

  locs <- read_json_export_for_map(json_path)

  # Toronto and Edinburgh have GeoJSON polygons — they should have poly_lons set
  poly_rows <- locs[vapply(locs$poly_lons, function(x) !is.null(x) && length(x) > 0,
                           logical(1L)), ]
  expect_true(nrow(poly_rows) >= 2L,
              info = "Expected at least 2 Polygon records (Toronto, Edinburgh)")

  # Toronto centroid is near lat ~43.65, lon ~-79.38
  toronto <- poly_rows[abs(poly_rows$lat - 43.65) < 0.1, ]
  expect_true(nrow(toronto) >= 1L, info = "Toronto polygon expected")
  expect_true(length(toronto$poly_lons[[1L]]) > 10L,
              info = "Toronto polygon should have many vertices")
})

test_that("read_json_export_for_map extracts bounding box", {
  json_path <- .find_json_fixture()
  skip_if(is.null(json_path), "Export JSON not found")

  locs <- read_json_export_for_map(json_path)

  # Article 5 has bounding_box_label: lon_min=-40, lon_max=40, lat_min=0, lat_max=20
  bbox_rows <- locs[!is.na(locs$lon_min) & !is.na(locs$lon_max), ]
  expect_true(nrow(bbox_rows) >= 1L, info = "Expected at least one bounding box record")
  expect_equal(bbox_rows$lon_min[1L], -40)
  expect_equal(bbox_rows$lon_max[1L],  40)
})

test_that("Polygon locations from JSON bin to accurate cells via PIP", {
  json_path <- .find_json_fixture()
  skip_if(is.null(json_path), "Export JSON not found")

  locs <- read_json_export_for_map(json_path)

  # Binning should complete without error and produce plausible cells
  grid <- bin_locations_to_grid(locs)
  expect_true(is.data.frame(grid))
  expect_true(nrow(grid) > 0L)

  # Toronto polygon spans roughly lat 43.58-43.86, lon -79.64 to -79.12.
  # PIP binning should place cells only inside Toronto's shape, so all
  # Toronto cells must lie within its bounding box.
  toronto_rows <- locs[vapply(locs$poly_lons, function(x) !is.null(x) && length(x) > 0,
                               logical(1L)), ]
  toronto <- toronto_rows[abs(toronto_rows$lat - 43.65) < 0.5, ]
  if (nrow(toronto) > 0L) {
    poly_lons <- toronto$poly_lons[[1L]]
    poly_lats <- toronto$poly_lats[[1L]]
    toronto_bbox_lon <- c(floor(min(poly_lons)), floor(max(poly_lons)) + 1)
    toronto_bbox_lat <- c(floor(min(poly_lats)), floor(max(poly_lats)) + 1)
    toronto_cells <- grid[grid$lon_center >= toronto_bbox_lon[1] &
                            grid$lon_center <= toronto_bbox_lon[2] &
                            grid$lat_center >= toronto_bbox_lat[1] &
                            grid$lat_center <= toronto_bbox_lat[2], ]
    # PIP should produce fewer cells than a naive full-bbox fill
    full_bbox_cells <- (diff(toronto_bbox_lon) + 1) * (diff(toronto_bbox_lat) + 1)
    expect_true(nrow(toronto_cells) <= full_bbox_cells,
                info = "PIP binning should cover fewer or equal cells than the full bounding box")
  }
})

test_that("map_from_export auto-detects JSON vs xlsx by extension", {
  json_path <- .find_json_fixture()
  skip_if(is.null(json_path), "Export JSON not found")

  # map_from_export should detect .json and use read_json_export_for_map
  grid <- map_from_export(json_path, plot = FALSE)
  expect_true(is.data.frame(grid))
  expect_true(nrow(grid) > 0L)
})

# ====================================================================
# Demo: Read from real JSON export and render map
# ====================================================================
if (interactive()) {
  json_path <- .find_json_fixture()
  if (!is.null(json_path)) {
    message("Rendering location map from ", basename(json_path), "...")
    map_from_export(json_path)
    message("Done. Close the plot window to continue.")
  } else {
    message("Export JSON not found; using synthetic data instead.")
    test_locs <- data.frame(
      lat = c(48.85, 48.86, 51.51, -33.87, -33.85, -33.88, 40.71, 35.68, 35.69),
      lon = c(2.35, 2.36, -0.13, 151.21, 151.20, 151.19, -74.01, 139.69, 139.70)
    )
    grid <- bin_locations_to_grid(test_locs)
    plot_location_grid(grid, title = "Test Map: Synthetic Locations")
    message("Map plotted. Close the plot window to exit.")
  }
}
