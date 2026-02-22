# ============================================================
# global.R — Package loading and helper sourcing
# ============================================================
# Shiny always sources global.R FIRST, before ui.R and server.R,
# ensuring all packages and helpers are available when the UI
# and server are evaluated.

# ---- Load packages ------------------------------------------
library(shiny)
library(bslib)
library(shinyjs)
library(httr2)
library(readr)
library(stringdist)
library(jsonlite)

# ---- Source helpers -----------------------------------------
source("R/utils.R")
source("R/supabase.R")
source("R/auth.R")
source("R/effectsize.R")
source("R/duplicates.R")
source("R/export.R")
source("R/gdrive.R")

# ---- Source modules -----------------------------------------
source("modules/mod_auth.R")
source("modules/mod_dashboard.R")
source("modules/mod_project_home.R")
source("modules/mod_label_builder.R")
source("modules/mod_article_upload.R")
source("modules/mod_upload_management.R")
source("modules/mod_review.R")
source("modules/mod_effect_size_ui.R")
source("modules/mod_export.R")
source("modules/mod_audit_log.R")

# ---- Google Drive auth (loads cached OAuth token) -----------
# Token is cached in .httr-oauth after running gdrive_init_oauth() once.
# If no token is available, Drive features are silently disabled.
gdrive_init()

# ---- Global options -----------------------------------------
options(shiny.maxRequestSize = 50 * 1024^2)   # 50 MB upload limit
