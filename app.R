# ============================================================
# Ecological Effect Size Coding Platform
# app.R — Main entry point
# ============================================================
# This file sources all R helpers and modules, then launches
# the Shiny application. Do not put business logic here.

# ---- Load packages ------------------------------------------
library(shiny)
library(bslib)
library(shinyjs)
library(httr2)

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

# ---- Global options -----------------------------------------
options(shiny.maxRequestSize = 50 * 1024^2)   # 50 MB upload limit

# ---- Launch -------------------------------------------------
shinyApp(ui = ui, server = server)
