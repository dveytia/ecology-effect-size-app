# Ecological Effect Size Coding Platform

A multi-user R Shiny web application for systematic reviewers to extract, code, and standardise effect sizes from ecological primary literature.

**Version:** 0.1.0 (Phase 1 scaffold)  
**Tech stack:** R Shiny · Supabase (PostgreSQL + Auth) · Google Drive API · bslib

---

## What This App Does

- Structured metadata capture from ecological studies using a configurable per-project label system
- Flexible effect size entry across five study designs: control/treatment, correlation, regression, interaction, time trend
- Automated conversion to standardised Pearson *r* and Fisher *Z*
- Safe multi-user concurrent access via Supabase row-level security
- PDF viewing via Google Drive folder integration
- Meta-analysis-ready CSV export compatible with the `metafor` R package

---

## Prerequisites

Before you start, install the following on your computer:

| Tool | Version | Where to get it |
|------|---------|-----------------|
| R | ≥ 4.3 | https://cloud.r-project.org |
| RStudio | Latest | https://posit.co/download/rstudio-desktop |
| Git | Latest | https://git-scm.com/downloads |

---

## Phase 1 Setup: Step-by-Step

> **You are here.** This section is for someone who has never built an app before.  
> Follow every step in order. Don't skip ahead.

---

### Step 1 — Create a Supabase account and project

Supabase is a free cloud database. Think of it as the filing cabinet where all your app data lives.

1. Open your browser and go to **https://supabase.com**
2. Click **Start your project** and create a free account (you can sign up with GitHub or email)
3. Once logged in, click **New project**
4. Fill in:
   - **Organisation:** your name or team name
   - **Project name:** `ecology-app-dev` (use "dev" — keep a production project separate later)
   - **Database password:** choose a strong password and **save it somewhere safe**
   - **Region:** choose the one geographically closest to you
5. Click **Create new project** and wait ~2 minutes for it to finish setting up

---

### Step 2 — Get your Supabase API credentials

1. In Supabase, click the cog icon **⚙ Project Settings** (bottom-left sidebar)
2. Click **API** in the left sidebar
3. You will see:
   - **Project URL** — looks like `https://abcdefghij.supabase.co`
   - **anon public** key — a long string starting with `eyJ...` (safe for client code)
   - **service_role** key — another long string (keep this secret; use only in trusted server code)
4. Leave this page open — you'll need these values in Step 4

---

### Step 3 — Clone this repository

Open **RStudio**. In the top menu, click:  
**File → New Project → Version Control → Git**

- **Repository URL:** `https://github.com/dveytia/ecology-effect-size-app`
- **Project directory name:** `ecology-effect-size-app`
- **Create project as subdirectory of:** choose a folder on your computer (e.g. `Documents`)
- Click **Create Project**

RStudio will download all the code and open the project automatically.

---

### Step 4 — Create your `.Renviron` credentials file

Your API keys must be stored in a file called `.Renviron`. This file is **never uploaded to GitHub** (it is listed in `.gitignore`).

1. In the RStudio **Files** panel (bottom-right), find `.Renviron.example` and click it to open
2. In the RStudio menu: **File → Save As...** and save it as `.Renviron`  
   *(the filename starts with a dot and has no `.example` at the end)*
3. Replace the placeholder values with your real Supabase values from Step 2:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your-anon-public-key
SUPABASE_SERVICE_KEY=your-service-role-key
```

4. Save the file
5. **Restart R** to load the new environment variables:  
   RStudio menu → **Session → Restart R**

---

### Step 5 — Install R packages

In the RStudio **Console** (the panel at the bottom), paste the following and press Enter:

```r
install.packages(c(
  "shiny", "bslib", "shinyjs", "httr2",
  "jsonlite", "stringr", "stringdist",
  "readr", "data.table", "writexl", "tools",
  "testthat"
))
```

Wait for all packages to finish installing (may take 5–10 minutes on a first install).

---

### Step 6 — Run the SQL setup scripts in Supabase

This creates all the database tables your app needs.

1. Go back to your Supabase project in the browser
2. In the left sidebar, click **SQL Editor**
3. Click **+ New query**
4. Open the file `sql/01_create_tables.sql` in RStudio (click it in the Files panel)
5. Select all the text (Ctrl+A on Windows / Cmd+A on Mac), then copy (Ctrl+C / Cmd+C)
6. Click inside the Supabase SQL Editor text box and paste (Ctrl+V / Cmd+V)
7. Click the **Run** button (green triangle, or press Ctrl+Enter)
8. You should see a green success message at the bottom

9. Repeat steps 3–8 for `sql/03_triggers.sql`
10. Repeat steps 3–8 for `sql/04_indexes.sql`

> ⚠️ **Do NOT run `sql/02_rls_policies.sql` yet** — this is for Phase 3 after authentication is working.

---

### Step 7 — Verify the tables were created

1. In the Supabase left sidebar, click **Table Editor**
2. You should see all of these tables listed:  
   `users` · `projects` · `project_members` · `labels` · `articles` · `uploads` · `article_metadata_json` · `effect_sizes` · `audit_log`
3. If any tables are missing, return to SQL Editor and re-run `sql/01_create_tables.sql`

---

### Step 8 — Run the app (UI preview)

In the RStudio Console, type:

```r
shiny::runApp()
```

A browser window should open showing the **Ecology Effect Size Coder** app with a Login page.

> **At Phase 1, the login does not yet connect to Supabase Auth.** You will see the UI skeleton only.  
> Full authentication is implemented in Phase 2.

---

### Step 9 — Run the Validation Gate 1 smoke test

This confirms that R can communicate with your Supabase database.

In the RStudio Console, paste and run:

```r
# Load the Supabase helper functions
source("R/utils.R")
source("R/supabase.R")

# Reload credentials (in case you have not restarted R yet)
readRenviron(".Renviron")

# Test 1: read from the projects table (empty data frame expected — no data yet)
result <- sb_get("projects", token = Sys.getenv("SUPABASE_SERVICE_KEY"))
cat("Connection OK. Rows returned:", nrow(result), "\n")

# Test 2: insert a test row, read it back, update it, then delete it
test_row <- sb_post("projects",
  list(
    owner_id    = "00000000-0000-0000-0000-000000000000",
    title       = "Smoke Test Project",
    description = "Created by validation gate"
  ),
  token = Sys.getenv("SUPABASE_SERVICE_KEY")
)
cat("Created project_id:", test_row$project_id, "\n")

read_back <- sb_get("projects",
  filters = list(project_id = test_row$project_id),
  token   = Sys.getenv("SUPABASE_SERVICE_KEY")
)
cat("Read back title:", read_back$title, "\n")

updated <- sb_patch("projects", "project_id", test_row$project_id,
  list(description = "Updated by smoke test"),
  token = Sys.getenv("SUPABASE_SERVICE_KEY")
)
cat("Updated description:", updated$description, "\n")

sb_delete("projects", "project_id", test_row$project_id,
  token = Sys.getenv("SUPABASE_SERVICE_KEY"))
cat("Deleted OK — Validation Gate 1 PASSED\n")
```

**Expected output:**
```
Connection OK. Rows returned: 0
Created project_id: <some-uuid>
Read back title: Smoke Test Project
Updated description: Updated by smoke test
Deleted OK — Validation Gate 1 PASSED
```

**Troubleshooting:**
- `SUPABASE_URL is not set` → Save `.Renviron` and run `Session → Restart R`
- `401 Unauthorized` → Check that your service_role key is correct (no extra spaces)
- `Table not found` → Re-run `sql/01_create_tables.sql` in Supabase

---

### Step 10 — Commit and prepare for Phase 2

Once the smoke test passes, commit your work:

Open the RStudio **Terminal** panel (Tools → Terminal → New Terminal) and run:

```bash
git add .
git commit -m "Phase 1 complete: scaffold and Supabase connection validated"
git push origin phase-1-scaffold
```

Then go to GitHub and open a Pull Request to merge `phase-1-scaffold` into `main`.  
After merging, start Phase 2 on a new branch: `git checkout -b phase-2-auth`

---

## Project Structure

```
ecology-effect-size-app/
├── app.R                        # App entry point
├── ui.R                         # Top-level UI
├── server.R                     # Top-level server
├── R/
│   ├── supabase.R               # ✅ COMPLETE (Phase 1) — Supabase REST API wrapper
│   ├── utils.R                  # ✅ COMPLETE (Phase 1) — Shared utility functions
│   ├── auth.R                   # 🔲 Phase 2 — Session management
│   ├── duplicates.R             # 🔲 Phase 5 — Duplicate detection
│   ├── gdrive.R                 # 🔲 Phase 6 — Google Drive integration
│   ├── effectsize.R             # 🔲 Phase 8 — Effect size computation engine
│   └── export.R                 # 🔲 Phase 10 — CSV export functions
├── modules/
│   ├── mod_auth.R               # 🔲 Phase 2 — Login / register
│   ├── mod_dashboard.R          # 🔲 Phase 3 — Project dashboard
│   ├── mod_project_home.R       # 🔲 Phase 3 — Project home tabs
│   ├── mod_label_builder.R      # 🔲 Phase 4 — Label schema builder
│   ├── mod_article_upload.R     # 🔲 Phase 5 — CSV article upload
│   ├── mod_upload_management.R  # 🔲 Phase 5 — Upload history
│   ├── mod_review.R             # 🔲 Phase 7 — Main review interface
│   ├── mod_effect_size_ui.R     # 🔲 Phase 9 — Effect size sub-form UI
│   ├── mod_export.R             # 🔲 Phase 10 — Export tab
│   └── mod_audit_log.R          # 🔲 Phase 11 — Audit log viewer
├── sql/
│   ├── 01_create_tables.sql     # ✅ Run in Supabase (Phase 1, Step 6)
│   ├── 02_rls_policies.sql      # Run in Supabase (Phase 3)
│   ├── 03_triggers.sql          # ✅ Run in Supabase (Phase 1, Step 6)
│   └── 04_indexes.sql           # ✅ Run in Supabase (Phase 1, Step 6)
├── tests/
│   ├── test_effectsize.R        # Phase 8
│   ├── test_duplicates.R        # Phase 5
│   └── test_export.R            # Phase 10
├── www/
│   ├── custom.css               # ✅ Custom styles
│   └── tooltips.js              # ✅ Bootstrap tooltip initialisation
├── .Renviron.example            # ✅ Template — copy to .Renviron and fill in your keys
├── .gitignore                   # ✅ Excludes .Renviron, .httr-oauth, *.csv, *.zip
├── DESCRIPTION                  # R package metadata (for renv)
├── DEVELOPMENT.md               # Phase-by-phase developer checklist
└── EcologyApp_Design_Spec_v3.2.md  # Full technical specification
```

---

## Development Workflow

See [DEVELOPMENT.md](DEVELOPMENT.md) for the complete phase-by-phase implementation guide with validation gate checklists.

---

## License

MIT — see [LICENSE](LICENSE)
