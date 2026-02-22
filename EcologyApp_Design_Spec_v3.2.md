# Ecological Effect Size Coding Platform
## Design Document & Phased Implementation Specification
### Version 3.2 — R Shiny + Supabase + Google Drive Folder PDF Linking

> **Intended for:** Systematic reviewers, meta-analysts, and LLM-assisted developers.  
> **Status:** Stand-alone specification. No external documents required.  
> **Format:** Markdown, optimised for LLM ingestion and human review.

---

## Table of Contents

1. [Purpose & Scope](#1-purpose--scope)
2. [Technology Stack](#2-technology-stack)
3. [System Architecture](#3-system-architecture)
4. [Database Schema](#4-database-schema)
5. [Label System](#5-label-system)
6. [Article Upload Logic](#6-article-upload-logic)
7. [Review Interface](#7-review-interface)
8. [Effect Size Module](#8-effect-size-module)
9. [Export System](#9-export-system)
10. [GitHub Repository Structure](#10-github-repository-structure)
11. [Phased Implementation Specification](#11-phased-implementation-specification)
12. [Risk Register](#12-risk-register)

---

## 1. Purpose & Scope

The Ecological Effect Size Coding Platform is a multi-user R Shiny web application that supports systematic reviewers in extracting, coding, and standardising effect sizes from ecological primary literature. It handles the full pipeline from article upload through to meta-analysis-ready export.

### Core Capabilities

- Structured metadata capture from ecological studies using a configurable, per-project label system
- Flexible effect size entry across five study designs (control/treatment, correlation, regression, interaction, time trend)
- Automated conversion of heterogeneous statistics to standardised Pearson *r* and Fisher *Z*
- Safe multi-user concurrent access via Supabase row-level security
- PDF access via Google Drive folder: project owner links a shared Drive folder; PDFs named `[article_id].pdf` are automatically matched to articles and opened in-browser during review
- Meta-analysis-ready CSV export compatible with the `metafor` R package
- All effect size entries saved regardless of completeness; entries are flagged but never blocked

### Design Principles

- **Never block saving.** If statistics are incomplete, save raw data and set `effect_status = insufficient_data`.
- **Flag, don't exclude.** Small SD approximations and IQR-derived SDs are saved and flagged. All flagged entries are included in exports. Sensitivity analyses are conducted outside the app.
- **Non-statistician friendly.** All statistical fields have tooltips with plain-language guidance and concrete paper examples.
- **Concurrent-safe.** Supabase transactions and an audit log prevent data loss from simultaneous reviewer edits.

---

## 2. Technology Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Frontend | R Shiny | `bslib` for UI; `shinyjs` for conditional logic |
| Authentication | Supabase Auth | Email + password; JWT session tokens |
| Database | Supabase PostgreSQL | Free tier; JSONB for nested label data |
| PDF Access | Google Drive API v3 + `googledrive` R package | Project owner pastes a shared Drive folder URL; app reads folder contents via API and matches filenames to article IDs |
| GIS | `sf` + `osmdata` | Bounding box and OSM location label types |
| Effect Size Engine | R module (`R/effectsize.R`) | Pure R; unit-tested independently with `testthat` |
| Duplicate Detection | `stringdist` | Jaro-Winkler fuzzy matching on titles |
| Export | `data.table` / `writexl` | `metafor`-compatible column naming |
| HTTP Client | `httr2` | All Supabase REST API calls |

---

## 3. System Architecture

The app is a single-page Shiny application with a server-side reactive session model. All state is persisted to Supabase on Save; the browser holds no persistent state.

### Session Flow

1. User authenticates via Supabase Auth → JWT stored in `reactiveValues()` session object
2. Dashboard loads projects owned or joined by that user
3. On project entry, articles and labels are loaded into reactive values
4. Reviewer navigates articles; each Save triggers a Supabase upsert
5. Effect size engine runs server-side on each Save; result stored alongside raw data
6. All Save/Skip/Delete events are written to the audit log

### Session Object Structure

```r
session <- reactiveValues(
  token      = NULL,   # JWT access token
  user_id    = NULL,   # UUID from Supabase auth
  username   = NULL,
  expires_at = NULL    # POSIXct; refresh if within 60s of expiry
)
```

Token refresh uses the Supabase `/auth/v1/token?grant_type=refresh_token` endpoint, called automatically before any API request when `expires_at` is within 60 seconds.

### Supabase R Client (`R/supabase.R`)

All database access goes through these wrapper functions:

```r
sb_get(table, filters = list(), token)     # GET with optional query params
sb_post(table, body, token)                # INSERT; returns new row
sb_patch(table, id, body, token)           # UPDATE by primary key
sb_delete(table, id, token)               # DELETE by primary key
sb_rpc(function_name, params, token)      # Call a Postgres function
```

`SUPABASE_URL` and `SUPABASE_KEY` (anon key) are read from `.Renviron`. A `SUPABASE_SERVICE_KEY` is used only for admin operations (e.g. initial schema setup).

---

## 4. Database Schema

All tables use UUID primary keys generated by Supabase. Row-level security (RLS) policies restrict access so users can only see projects they own or are members of.

### 4.1 Table: `users`

Mirror of `auth.users`. Populated automatically on registration via a Supabase database trigger.

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | UUID (PK) | Matches `auth.users.id` |
| `email` | TEXT | |
| `username` | TEXT | |
| `created_at` | TIMESTAMPTZ | |

---

### 4.2 Table: `projects`

| Column | Type | Notes |
|--------|------|-------|
| `project_id` | UUID (PK) | |
| `owner_id` | UUID (FK → users) | |
| `title` | TEXT | |
| `description` | TEXT | |
| `drive_folder_url` | TEXT (nullable) | Google Drive shared folder URL pasted by project owner; e.g. `https://drive.google.com/drive/folders/FOLDER_ID` |
| `drive_folder_id` | TEXT (nullable) | Extracted `FOLDER_ID` from `drive_folder_url`; stored separately for API calls |
| `drive_last_synced` | TIMESTAMPTZ (nullable) | Timestamp of last successful Drive folder sync |
| `created_at` | TIMESTAMPTZ | |

---

### 4.3 Table: `project_members`

| Column | Type | Notes |
|--------|------|-------|
| `project_id` | UUID (FK → projects) | |
| `user_id` | UUID (FK → users) | |
| `role` | TEXT | `owner` or `reviewer` |

---

### 4.4 Table: `labels`

| Column | Type | Notes |
|--------|------|-------|
| `label_id` | UUID (PK) | |
| `project_id` | UUID (FK → projects) | |
| `label_type` | TEXT | `single` or `group` |
| `parent_label_id` | UUID (nullable) | FK to `labels`; used for child labels within a group |
| `category` | TEXT | Grouping header shown in UI |
| `name` | TEXT | Machine-readable key used in JSON storage |
| `display_name` | TEXT | Human-readable label shown to reviewer |
| `instructions` | TEXT | Tooltip / guidance text |
| `variable_type` | TEXT | See Section 5 |
| `allowed_values` | TEXT[] | For `select one` and `select multiple` types |
| `mandatory` | BOOLEAN | Default FALSE |
| `order_index` | INTEGER | Display order within category |

---

### 4.5 Table: `articles`

| Column | Type | Notes |
|--------|------|-------|
| `article_id` | UUID (PK) | |
| `project_id` | UUID (FK → projects) | |
| `title` | TEXT | |
| `abstract` | TEXT | |
| `author` | TEXT | |
| `year` | INTEGER | |
| `doi_clean` | TEXT | Cleaned DOI (lowercase, no http prefix) |
| `pdf_drive_link` | TEXT (nullable) | Direct Google Drive file link; populated automatically when Drive folder is synced; format: `https://drive.google.com/file/d/FILE_ID/preview` |
| `upload_batch_id` | UUID (FK → uploads) | |
| `reviewed_by` | UUID (FK → users) | |
| `reviewed_at` | TIMESTAMPTZ | |
| `review_status` | TEXT | `unreviewed`, `reviewed`, `skipped` |

---

### 4.6 Table: `article_metadata_json`

| Column | Type | Notes |
|--------|------|-------|
| `article_id` | UUID (FK → articles, unique) | One row per article |
| `json_data` | JSONB | All coded label values; label groups stored as JSON arrays |

Example `json_data` structure:
```json
{
  "country": "Australia",
  "study_year": 2018,
  "habitat": ["Forest", "Grassland"],
  "study_sites": [
    { "site_name": "Site A", "latitude": -33.8, "longitude": 151.2 },
    { "site_name": "Site B", "latitude": -34.1, "longitude": 150.9 }
  ]
}
```

---

### 4.7 Table: `effect_sizes`

| Column | Type | Notes |
|--------|------|-------|
| `effect_id` | UUID (PK) | |
| `article_id` | UUID (FK → articles) | |
| `group_instance_id` | TEXT (nullable) | Identifies which label group instance this effect belongs to |
| `raw_effect_json` | JSONB | All raw statistical fields entered by reviewer |
| `r` | NUMERIC | Computed Pearson *r*; NULL if insufficient data |
| `z` | NUMERIC | Fisher Z = atanh(r); NULL if r is NULL |
| `var_z` | NUMERIC | Variance of Fisher Z; NULL if insufficient |
| `effect_status` | TEXT | See below |
| `effect_warnings` | TEXT[] | Array of warning strings (e.g. "IQR used for SD") |
| `computed_at` | TIMESTAMPTZ | |

#### `effect_status` Values

| Value | Meaning |
|-------|---------|
| `calculated` | Full *r*, *z*, `var_z` computed from provided statistics |
| `insufficient_data` | Raw data saved; *r*, *z*, `var_z` are NULL |
| `small_sd_used` | SD imputed as 0.01 × mean; flagged for sensitivity analysis |
| `calculated_relative` | Difference-in-differences result (Pathway B interactions) |
| `iqr_sd_used` | SD derived from IQR using SD = IQR / 1.35; flagged for sensitivity analysis |

> **Note:** `small_sd_used` and `iqr_sd_used` entries ARE included in all exports. The `effect_status` column allows users to filter or exclude them during external sensitivity analyses.

---

### 4.8 Table: `uploads`

| Column | Type | Notes |
|--------|------|-------|
| `upload_batch_id` | UUID (PK) | |
| `project_id` | UUID (FK → projects) | |
| `filename` | TEXT | |
| `upload_date` | TIMESTAMPTZ | |
| `rows_uploaded` | INTEGER | |
| `rows_flagged` | INTEGER | Duplicates flagged |

---

### 4.9 Table: `audit_log`

Visible to all project members (owners and reviewers).

| Column | Type | Notes |
|--------|------|-------|
| `log_id` | UUID (PK) | |
| `project_id` | UUID (FK → projects) | |
| `user_id` | UUID (FK → users) | |
| `article_id` | UUID (FK → articles) | |
| `action` | TEXT | `save`, `skip`, `delete`, `effect_computed` |
| `old_json` | JSONB | Snapshot of `article_metadata_json` before action |
| `new_json` | JSONB | Snapshot after action |
| `timestamp` | TIMESTAMPTZ | |

---

### 4.10 Row-Level Security (RLS) Policies

Enable RLS on all tables. Apply the following policies:

| Table | Policy |
|-------|--------|
| `projects` | SELECT / UPDATE / DELETE where `owner_id = auth.uid()` OR `project_id IN (SELECT project_id FROM project_members WHERE user_id = auth.uid())` |
| `project_members` | SELECT where `user_id = auth.uid()` OR `project_id IN (projects accessible to auth.uid())` |
| `labels` | Access only if `project_id` is accessible to `auth.uid()` |
| `articles` | Access only if `project_id` is accessible to `auth.uid()` |
| `article_metadata_json` | Linked via `article_id` → `articles` → `project_id` membership check |
| `effect_sizes` | Linked via `article_id` → `articles` → `project_id` membership check |
| `uploads` | Access only if `project_id` is accessible to `auth.uid()` |
| `audit_log` | READ: any project member. WRITE: any project member |

---

## 5. Label System

### 5.1 Variable Types

| Type | UI Widget | Storage Format |
|------|-----------|----------------|
| `text` | Free-text input | String |
| `integer` | Numeric input (whole numbers only) | Integer |
| `numeric` | Numeric input (decimals allowed) | Float |
| `boolean` | Checkbox | Boolean (default `false`) |
| `select one` | Dropdown from `allowed_values` | String |
| `select multiple` | Multi-select checkbox group | String array |
| `YYYY-MM-DD` | Date picker | ISO date string |
| `bounding_box` | Four numeric inputs: `lon_min`, `lon_max`, `lat_min`, `lat_max` | Object `{lon_min, lon_max, lat_min, lat_max}` |
| `openstreetmap_location` | Text search returning OSM result | Object `{name, lat, lon, osm_id}` |
| `effect_size` | Full structured statistical block (see Section 8) | Stored in `effect_sizes` table |

### 5.2 Label Groups

- A label of `label_type = group` acts as a container for child labels
- Each group can have multiple instances per article (e.g. multiple study sites, multiple species)
- Instances are stored as a JSON array in `article_metadata_json`
- Reviewers can dynamically add or remove instances during review using **+ Add Instance** / **Remove Instance** buttons
- Each instance is rendered as a card in the review UI

### 5.3 Label Builder UI (Project Owner Only)

Located in the **Editing Labels** tab of project home.

- **Add Label** button: opens modal with fields for `display_name`, `category`, `variable_type`, `allowed_values` (for select types), `mandatory` toggle, `instructions` text
- **Add Label Group** button: creates a group container; child labels added within it
- Labels displayed in `order_index` order with up/down arrow reordering
- **Edit** and **Delete** icons per label
- Delete is blocked if any article has data stored for that label
- **JSON preview panel** shows the full label schema as it will be stored

---

## 6. Article Upload Logic

### 6.1 CSV Requirements

Required columns: `title`, `abstract`, `author`, `year`, `doi`

Optional column: `id` (integer). If absent, integers are auto-assigned sequentially within the project.

Encoding: UTF-8 required. If non-UTF-8 is detected (via `readr::guess_encoding()`), show a friendly error: *"Please re-save your CSV as UTF-8 before uploading."*

### 6.2 Duplicate Detection Pipeline

Run in order. Stop at the first match found for each incoming row.

1. **Clean DOI:** strip `http://`, `https://`, `doi.org/` prefix; lowercase; trim whitespace
2. **Exact DOI match** → flag as `exact_doi` duplicate
3. **Title + year match** (if no DOI): lowercase title, remove all punctuation, compare with existing → flag as `title_year` duplicate
4. **Partial DOI match:** year + DOI prefix (first 15 chars) → flag as `partial_doi` with warning
5. **Fuzzy title match:** Jaro-Winkler distance < 0.05 on cleaned title within same year → flag as `fuzzy` with similarity score shown to reviewer

Flagged rows are shown in the **Upload Management** tab. Reviewer can:
- Accept a flagged match (insert the article anyway, with a note)
- Reject a flagged match (skip insertion)

**Reviewed articles cannot be deleted.**

---

## 6.3 Google Drive Folder Integration

This section describes how the project owner links a Google Drive folder containing PDFs, and how the app automatically matches those PDFs to articles.

### Overview

The project owner pastes a single shared Google Drive folder URL into the project settings. The app uses the Google Drive API to list the folder contents and match filenames of the form `[article_id].pdf` to records in the `articles` table. No individual share links need to be copied. Reviewers see a **Display PDF** button when a matched file exists.

### Prerequisites

- The Drive folder must be shared as **"Anyone with the link can view"** (or more permissive)
- PDFs must be named exactly `[article_id].pdf` where `article_id` matches the integer ID in the `articles` table (e.g. `123.pdf`)
- The app authenticates with Google Drive using OAuth 2.0 via the `googledrive` R package
- OAuth credentials (Client ID + Client Secret) are stored in `.Renviron` as `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`
- The OAuth token is obtained once by the project owner (or app administrator) and cached server-side

### Project Settings UI

In the **Edit Project** modal (owner only), add a field:

> **Google Drive PDF Folder URL**  
> Paste the URL of a shared Google Drive folder containing PDFs named `[article_id].pdf`.  
> Example: `https://drive.google.com/drive/folders/1A2B3C4D5E6F`

Beneath this field, show:
- Last synced: `[drive_last_synced timestamp]` or *"Never synced"*
- A **Sync Now** button

### Folder ID Extraction

When the owner saves the folder URL, the app extracts the `FOLDER_ID`:

```r
extract_drive_folder_id <- function(url) {
  # Matches: https://drive.google.com/drive/folders/FOLDER_ID
  # or:      https://drive.google.com/drive/folders/FOLDER_ID?usp=sharing
  stringr::str_extract(url, "(?<=/folders/)[^/?]+")
}
```

The extracted ID is stored in `projects.drive_folder_id`.

### Sync Process

Triggered when the owner clicks **Sync Now**, or automatically when a reviewer clicks **Display PDF** for an article with no cached link.

```
sync_drive_folder(project_id, folder_id, token)
```

Steps:

1. Call Google Drive API: list all files in folder where `mimeType = 'application/pdf'`
   ```
   GET https://www.googleapis.com/drive/v3/files
     ?q='FOLDER_ID' in parents and mimeType='application/pdf' and trashed=false
     &fields=files(id,name)
   ```
2. For each file returned:
   - Parse filename: extract `article_id` from `[article_id].pdf` (strip `.pdf` suffix; must be a valid integer matching an article in this project)
   - Construct preview link: `https://drive.google.com/file/d/FILE_ID/preview`
   - Upsert `articles.pdf_drive_link` for the matching `article_id`
3. Update `projects.drive_last_synced` to current timestamp
4. Return a sync summary: files found, files matched, files skipped (filename did not match any article ID)

### Sync Summary Display

After sync, show in project settings:

```
Sync complete.
  Files found in folder:   47
  Matched to articles:     43
  Skipped (no match):       4

Skipped filenames: 'notes.pdf', 'extra.pdf', '999.pdf', '0.pdf'
```

Skipped files are listed so the owner can identify naming errors.

### Display PDF Button Behaviour

In the review interface:

- If `pdf_drive_link` is populated: **Display PDF** button opens the link in an embedded `<iframe>` or a new tab
- If `pdf_drive_link` is NULL: button is greyed out with tooltip *"No PDF linked. Check that a file named [article_id].pdf exists in the project Drive folder and run Sync."*
- If Drive sync has never been run: show a project-level banner: *"No Drive folder linked. Add a folder URL in Project Settings to enable PDF viewing."*

### Re-syncing

The owner should re-run Sync whenever new PDFs are added to the Drive folder. There is no automatic polling. `drive_last_synced` is displayed in the project settings panel so the owner knows when the last sync occurred.

### `.Renviron` additions for Google Drive

```
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
```

OAuth token is cached by `googledrive` in a local `.httr-oauth` file (excluded from git via `.gitignore`).

### `R/gdrive.R` Functions

Add a new file `R/gdrive.R` containing:

| Function | Description |
|----------|-------------|
| `extract_drive_folder_id(url)` | Extracts folder ID from a Drive folder URL |
| `sync_drive_folder(project_id, folder_id)` | Lists PDFs in folder, matches to article IDs, upserts `pdf_drive_link` |
| `gdrive_list_pdfs(folder_id)` | Calls Drive API; returns data frame of `(file_id, filename)` |
| `parse_article_id_from_filename(filename)` | Returns integer article ID or NA if filename is not `[integer].pdf` |

---

## 7. Review Interface

### 7.1 Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Search bar: ID / title / author]   Progress: 12 / 47   │
├─────────────────────────────────────────────────────────┤
│ Article Title                                            │
│ Author(s) · Year · DOI                                  │
│ [Display PDF] (opens pdf_url in new tab)                │
│ ─────────────────────────────────────────────────────   │
│ Abstract text...                                        │
├─────────────────────────────────────────────────────────┤
│ [Label fields — rendered from project label schema]     │
│                                                         │
│ [+ Add Instance] buttons for label groups               │
├─────────────────────────────────────────────────────────┤
│             [Save]    [Next]    [Skip]                  │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Button Behaviour

| Button | Action |
|--------|--------|
| **Save** | Upserts `article_metadata_json`; triggers effect size computation if an `effect_size` label is present; writes to `audit_log`; sets `review_status = reviewed` |
| **Next** | Saves (as above) then loads the next `unreviewed` article |
| **Skip** | Sets `review_status = skipped` without saving metadata; writes to `audit_log` |
| **Display PDF** | Opens `pdf_drive_link` in a new browser tab. If `pdf_drive_link` is NULL, shows tooltip: *"No PDF linked. Check that a file named [article_id].pdf exists in the project Drive folder and run Sync."* |

### 7.3 Concurrency Warning

On Save, check `audit_log` for any `save` action on this `article_id` since the current reviewer loaded the page. If a conflict is detected:

> *"Another reviewer saved changes to this article since you loaded it. Your save has been recorded. Review the audit log to check for conflicts."*

Do not block the save. Log the conflict. Last-write-wins.

### 7.4 Multiple Effect Sizes per Article

Reviewers can code **multiple effect sizes per article**. This is supported via label groups:

- Each instance of a label group that contains an `effect_size` variable generates one row in the `effect_sizes` table
- The `group_instance_id` column links the effect size back to its label group instance
- On export, each effect size generates one row in the output (article metadata is duplicated across rows for the same article)

---

## 8. Effect Size Module

### 8.1 Module Location

`R/effectsize.R` — a standalone R file with no Shiny dependencies. Tested independently with `tests/test_effectsize.R`.

### 8.2 Entry Point

```r
compute_effect_size(input_list) 
# Returns: list(r, z, var_z, effect_status, effect_warnings)
```

`input_list` is a named list containing all fields entered by the reviewer.

### 8.3 General Fields (All Study Designs)

These fields appear at the top of the effect size block for all designs.

| Field | Type | Allowed Values |
|-------|------|----------------|
| `study_method` | Select one | `Observational`, `Experimental (ex-situ)`, `Experimental (in-situ)`, `Statistical model`, `Simulation` |
| `response_scale` | Select one | See complete list below |
| `response_distribution` | Select one | `Continuous`, `Proportion`, `Count`, `Ordinal` |
| `response_variable_name` | Text | Name exactly as written in paper |
| `response_unit` | Text | Units as reported (e.g. kg/ha, individuals/m²) |
| `predictor_distribution` | Select one | `Continuous`, `Categorical`, `Ordinal`, `Time` |
| `predictor_variable_name` | Text | Name exactly as written in paper |
| `predictor_unit` | Text | Units as reported |
| `interaction_effect` | Boolean | Default `false`; check if this effect captures a difference between two groups |

#### Complete `response_scale` Allowed Values

| Value | Category |
|-------|----------|
| `Ind. fitness or reproduction` | Individual |
| `Ind. health or growth` | Individual |
| `Ind. behaviour` | Individual |
| `Pop. size` | Population |
| `Pop. genetic` | Population |
| `Sp. range` | Species |
| `Sp. loss` | Species |
| `As. structure` | Assemblage |
| `As. succession` | Assemblage |
| `As. sound` | Assemblage |
| `Eco. prim. prod.` | Ecosystem |
| `Eco. function` | Ecosystem |
| `Eco. food web` | Ecosystem |
| `Eco. habitat` | Ecosystem |
| `Abio. hydrology` | Abiotic |
| `Abio. nutrient flux` | Abiotic |
| `Abio. soil` | Abiotic |
| `Unclear` | Other |
| `NA` | Other |

### 8.4 Study Design Branching

Reviewer selects one study design. Conditional UI panels display only the fields relevant to that design.

| Study Design Value | Description |
|--------------------|-------------|
| `control_treatment` | Two-group comparison with a control and treatment group |
| `correlation` | Direct correlation between two continuous variables |
| `regression` | Regression coefficient (single or multiple predictor) |
| `interaction` | Explicit interaction term OR relative comparison between two groups |
| `time_trend` | Regression with time as the predictor; uses the same fields as `regression` with `predictor_distribution = Time` |

> **Time trend note:** No dedicated fields for time trends. Use the regression design and set `predictor_distribution = Time`.

---

### 8.5 Study Design: Control / Treatment

#### Fields

| Field | Type | Tooltip |
|-------|------|---------|
| `control_description` | Text | Brief description of the control condition |
| `treatment_description` | Text | Brief description of the treatment condition |
| `mean_control` | Numeric | Mean of the control group |
| `mean_treatment` | Numeric | Mean of the treatment group |
| `var_statistic_type` | Select one | `SD`, `SE`, `95% CI`, `IQR` — what type of variability is reported? |
| `var_value_control` | Numeric | The SD / SE / CI half-width / IQR value for the control group |
| `var_value_treatment` | Numeric | The SD / SE / CI half-width / IQR value for the treatment group |
| `n_control` | Integer | Sample size of control group |
| `n_treatment` | Integer | Sample size of treatment group |
| `t_stat` | Numeric | t-statistic. Tooltip: *"Look for t = or a value in parentheses, e.g. t(24) = 2.3"* |
| `F_stat` | Numeric | F-statistic. Tooltip: *"Look for F = in ANOVA tables"* |
| `chi_square_stat` | Numeric | Chi-squared statistic |
| `p_value` | Numeric | p-value as reported |
| `df` | Numeric | Degrees of freedom. Tooltip: *"Look for 'df =', or the number in parentheses after t, e.g. t(24): df = 24. For F(1, 45): df = 45 (use the second number)."* |

#### Conversion Pipeline

1. If `var_statistic_type = SE`: `SD = SE × sqrt(n)`
2. If `var_statistic_type = 95% CI`: `SD = CI_half_width / 1.96`
3. If `var_statistic_type = IQR`: `SD = IQR / 1.35`; add `"IQR used for SD"` to `effect_warnings`; set `effect_status = iqr_sd_used`
4. Compute pooled SD: `SD_pool = sqrt(((n1-1)*SD1² + (n2-1)*SD2²) / (n1+n2-2))`
5. Compute Hedges' *g*: `g = (mean_treatment - mean_control) / SD_pool`
6. Apply small-sample correction: `J = 1 - (3 / (4*(n1+n2-2) - 1))`; `g_corrected = g × J`
7. Convert to *r*: `r = g / sqrt(g² + (n1+n2)²/(n1×n2))`

**Fallback (if means/SD unavailable but t-stat present):**
`r = t / sqrt(t² + df)`

**Fallback (if F-stat present, single df):**
Convert F to t: `t = sqrt(F)`; then use t formula.

**If insufficient:** `effect_status = insufficient_data`; *r*, *z*, `var_z` = NULL.

#### Small SD Approximation

If means are present but SD, SE, CI, IQR, and all test statistics are absent, a toggle appears:

> **"Use small SD approximation"** *(not recommended; for use only when no other statistics are available)*

If enabled: `SD = 0.01 × mean`; set `effect_status = small_sd_used`; add warning.

---

### 8.6 Study Design: Correlation

#### Fields

| Field | Type | Tooltip |
|-------|------|---------|
| `r_reported` | Numeric | Pearson r or Spearman rho as reported. Range: -1 to 1 |
| `se_r` | Numeric | Standard error of the correlation |
| `covariance_XY` | Numeric | Covariance of X and Y |
| `sd_X` | Numeric | Standard deviation of X |
| `sd_Y` | Numeric | Standard deviation of Y |
| `n` | Integer | Sample size |
| `t_stat` | Numeric | t-statistic for the correlation test |
| `df` | Numeric | Degrees of freedom. Tooltip: *"For correlation tests, df is usually n − 2."* |

#### Conversion Pipeline

1. If `r_reported` present: use directly
2. Else if `covariance_XY`, `sd_X`, `sd_Y` present: `r = covariance_XY / (sd_X × sd_Y)`
3. Else if `t_stat` and `df` present: `r = t / sqrt(t² + df)`
4. Else: `effect_status = insufficient_data`

#### Variance

- If `n` present: `var_z = 1 / (n − 3)`
- Else if `se_r` present: `var_z = (se_r / (1 − r²))²`
- Else: `var_z = NULL`

---

### 8.7 Study Design: Regression

#### Fields

| Field | Type | Tooltip |
|-------|------|---------|
| `beta` | Numeric | Regression coefficient (standardised or unstandardised) |
| `se_beta` | Numeric | Standard error of the regression coefficient |
| `n` | Integer | Total sample size |
| `t_stat` | Numeric | t-statistic for the coefficient |
| `p_value` | Numeric | p-value for the coefficient |
| `df` | Numeric | Residual degrees of freedom. Tooltip: *"Look for df in regression output. For F(1, 45), use 45 (the second number)."* |
| `sd_X` | Numeric | Standard deviation of the predictor variable |
| `sd_Y` | Numeric | Standard deviation of the response variable |
| `multiple_predictors` | Boolean | Check if the model contains more than one predictor |

#### Conversion Pipeline

**If `multiple_predictors = false` (single predictor):**

1. If `t_stat` and `df` present: `r = t / sqrt(t² + df)`
2. Else if `beta`, `sd_X`, `sd_Y` present: `r = beta × (sd_X / sd_Y)`
3. Else: `effect_status = insufficient_data`

**If `multiple_predictors = true`:**

1. Treat as partial *r*
2. If `t_stat` and `df` present: `r = t / sqrt(t² + df)` (partial r via t)
3. Else if `beta`, `sd_X`, `sd_Y` present: `r = beta × (sd_X / sd_Y)` (partial r approximation; add warning)
4. Else: `effect_status = insufficient_data`

---

### 8.8 Study Design: Interaction / Relative Comparison

This design handles two scenarios:
1. **Pathway A:** The paper explicitly reports an interaction term (e.g. in a regression or ANOVA)
2. **Pathway B:** The paper reports separate effect sizes for two groups (e.g. climate effect on invasive species vs. native species); the relative difference is computed as a difference-in-differences

When `interaction_effect = true`, the reviewer selects Pathway A or Pathway B.

---

#### Pathway A: Explicit Interaction Term

**Fields:**

| Field | Type | Tooltip |
|-------|------|---------|
| `interaction_term` | Numeric | The coefficient for the interaction term |
| `se_interaction` | Numeric | Standard error of the interaction term |
| `t_stat` | Numeric | t-statistic for the interaction term |
| `df` | Numeric | Degrees of freedom |

**Conversion:** `r = t / sqrt(t² + df)`

---

#### Pathway B: Separate Group Effect Sizes (Difference-in-Differences)

Two sub-forms are displayed (as tabs: **Group A** and **Group B**). Each sub-form contains a full study design selector and all matching fields for the selected design.

**Computation:**

1. Compute `r_A` from Group A statistics (using the appropriate pipeline above)
2. Compute `r_B` from Group B statistics
3. Convert to Fisher Z: `z_A = atanh(r_A)`, `z_B = atanh(r_B)`
4. Compute difference: `z_diff = z_A − z_B`
5. Compute variance (assuming independent groups): `var_z_diff = var_z_A + var_z_B`
6. Convert back: `r_diff = tanh(z_diff)`

**Storage:**

- `r = r_diff`
- `z = z_diff`
- `var_z = var_z_diff`
- `effect_status = calculated_relative`

If either sub-effect cannot be computed: `effect_status = insufficient_data`.

---

### 8.9 Fisher Z Transform (Applied to All Designs)

After computing *r*:

```r
z     <- atanh(r)                      # Fisher Z transformation
var_z <- 1 / (n - 3)                   # if n is available
var_z <- (se_r / (1 - r^2))^2         # fallback if se_r available
var_z <- NULL                          # if neither n nor se_r available
```

---

### 8.10 Effect Size Result Display

After Save **or** clicking the **"Calculate effect size"** button, show below the form:

```
Computed effect size:
  r     = [value]
  z     = [value]
  var_z = [value]
  Status: [effect_status]
  Warnings: [list if any]
```

The **"Calculate effect size"** button runs `compute_effect_size()` and displays the result immediately **without** writing to the database, allowing reviewers to preview results without scrolling to Save. Save still computes + persists as before.

If `effect_status = insufficient_data`, show:

> *"Effect size could not be computed. Missing: [list of missing fields]. Raw data has been saved."*

---

### 8.11 Pathway Colour Coding

To help reviewers identify which fields belong to which conversion pathway, the UI wraps groups of fields in colour-coded panels:

| Colour | CSS Class | Meaning | Visual |
|--------|-----------|---------|--------|
| **Green** | `es-pathway-a` | Primary conversion pathway | Green left border + light green tint |
| **Blue** | `es-pathway-b` | Fallback / alternative pathway 1 | Blue left border + light blue tint |
| **Amber** | `es-pathway-c` | Fallback / alternative pathway 2 | Amber left border + light amber tint |

A **pathway legend** is displayed at the top of each study design's field set, explaining which colour maps to which conversion route.

#### Pathway mapping per study design

| Study Design | Green (Primary) | Blue (Fallback 1) | Amber (Fallback 2) |
|-------------|-----------------|--------------------|--------------------|  
| Control / Treatment | means + variability + n → Hedges g → r | t-stat + df → r | F-stat + df → t → r |
| Correlation | r (reported) | covariance / (SD_X × SD_Y) | t-stat + df → r |
| Regression | t-stat + df → r | β × (SD_X / SD_Y) → r | — |
| Interaction (Pathway A) | t-stat + df → r | — | — |

Fields that are not pathway-specific (e.g. `control_description`, `treatment_description`, `multiple_predictors`, `se_beta`, `p_value`) appear outside any colour-coded panel.

CSS classes are defined in `www/custom.css`. The colour coding is purely visual; it does not affect computation logic.

---

### 8.12 Unit Tests (`tests/test_effectsize.R`)

All tests use `testthat`. Tolerance: 4 decimal places.

| Test | Input | Expected *r* |
|------|-------|-------------|
| t-statistic path | `t=2.5, df=30` | `0.4152` |
| Means + SD path (Hedges g) | `m1=5, m2=3, sd1=2, sd2=2, n1=20, n2=20` | `≈ 0.4472` |
| Correlation direct | `r=0.35, n=50` | `r=0.3500; var_z=0.0213` |
| Covariance path | `cov=0.6, sd_X=1.2, sd_Y=2.0` | `0.2500` |
| Regression + SDs | `beta=0.4, sd_X=1.5, sd_Y=2.0` | `0.3000` |
| Interaction Pathway B | `r_A=0.5, r_B=0.2, n_A=30, n_B=30` | `z_diff = atanh(0.5) − atanh(0.2); var_z_diff = 1/27 + 1/27` |
| SE to SD conversion | `se=0.5, n=25` | `SD = 2.5` |
| 95% CI to SD | `ci_half_width=1.96, n=30` | `SD = 1.0` |
| IQR to SD | `IQR=2.7, n=30` | `SD ≈ 2.0; effect_status = iqr_sd_used` |
| Small SD flag | `mean=100, no SD, no stats` | `effect_status = small_sd_used` |
| Insufficient data | `p_value=0.03 only` | `effect_status = insufficient_data; r = NULL` |

---

## 9. Export System

### 9.1 Export Tab (Project Owner Only)

Located in the **Export** tab of project home.

**Filter options:**
- Reviewer (multi-select)
- Review status (`reviewed`, `skipped`, `unreviewed`)
- Date range (`reviewed_at`)
- Effect status (multi-select; includes all `effect_status` values)

### 9.2 Full Export

All articles matching the filter. Output format: CSV (UTF-8, comma-separated).

**Columns included:**

| Column Group | Columns |
|-------------|---------|
| Article metadata | `article_id`, `title`, `author`, `year`, `doi_clean`, `review_status`, `reviewed_by`, `reviewed_at` |
| Label values | One column per label `name`; label group instances generate multiple rows with a `group_instance` column |
| Raw effect fields | All fields from `raw_effect_json`, prefixed with `raw_` |
| Computed effect | `r`, `z`, `var_z`, `effect_status`, `effect_warnings` |

**JSONB unnesting:**

Server-side R function `unnest_labels(df, label_schema)`:
- Iterates label schema
- Extracts each label value into a named column
- Label group instances expand into multiple rows (one per instance), with a `group_instance` integer column

### 9.3 Meta-Ready Export

Filtered to articles where `effect_status IN ('calculated', 'small_sd_used', 'iqr_sd_used', 'calculated_relative')`.

Columns:
- `article_id`
- `yi` (= `z`, Fisher Z; column named for `metafor` compatibility)
- `vi` (= `var_z`; column named for `metafor` compatibility)
- `effect_status` (for sensitivity analysis filtering)
- All label columns as moderator variables

This export is directly importable into `metafor::rma(yi=yi, vi=vi, data=df)`.

> **Note:** `small_sd_used` and `iqr_sd_used` entries are included in the meta-ready export. Filter using `effect_status` before running the main meta-analysis if desired.

---

## 10. GitHub Repository Structure

### 10.1 Setup Instructions

```bash
# 1. Create a new GitHub repository
#    - Go to https://github.com/new
#    - Repository name: ecology-effect-size-app (or your preferred name)
#    - Visibility: Private (recommended; contains API keys via .Renviron)
#    - Initialise with README: Yes
#    - Add .gitignore: R (select the R template)
#    - Licence: MIT (or your preference)

# 2. Clone locally
git clone https://github.com/YOUR_USERNAME/ecology-effect-size-app.git
cd ecology-effect-size-app

# 3. Create branch structure
git checkout -b phase-1-scaffold     # one branch per phase
# After each phase passes its validation gate:
# git checkout main && git merge phase-N-name --no-ff
```

### 10.2 `.gitignore` additions

Add these lines to the default R `.gitignore`:

```
.Renviron
.httr-oauth
*.csv
*.zip
renv/library/
```

### 10.3 Repository File Structure

```
ecology-effect-size-app/
│
├── app.R                        # Main Shiny app entry point; calls ui.R and server.R
├── ui.R                         # Top-level UI definition; assembles all page modules
├── server.R                     # Top-level server; routes to module servers
│
├── R/
│   ├── supabase.R               # Supabase REST API wrapper (sb_get, sb_post, sb_patch, sb_delete, sb_rpc)
│   ├── gdrive.R                 # Google Drive folder sync (extract_drive_folder_id, sync_drive_folder, gdrive_list_pdfs)
│   ├── effectsize.R             # Effect size computation engine; no Shiny dependencies
│   ├── duplicates.R             # Duplicate detection logic (check_duplicates function)
│   ├── export.R                 # Export functions (unnest_labels, build_full_export, build_meta_export)
│   ├── utils.R                  # Shared utility functions (DOI cleaning, date formatting, etc.)
│   └── auth.R                   # Session management (token refresh, route guard)
│
├── modules/
│   ├── mod_auth.R               # Login / register page UI and server
│   ├── mod_dashboard.R          # Project dashboard UI and server
│   ├── mod_project_home.R       # Project home tabs container UI and server
│   ├── mod_label_builder.R      # Label builder tab UI and server
│   ├── mod_article_upload.R     # Article upload tab UI and server
│   ├── mod_upload_management.R  # Upload history and duplicate resolution tab
│   ├── mod_review.R             # Main review interface UI and server
│   ├── mod_effect_size_ui.R     # Effect size sub-form UI (conditional panels per design)
│   ├── mod_export.R             # Export tab UI and server
│   └── mod_audit_log.R          # Audit log viewer UI and server
│
├── sql/
│   ├── 01_create_tables.sql     # All CREATE TABLE statements in dependency order
│   ├── 02_rls_policies.sql      # All RLS ENABLE and POLICY statements
│   ├── 03_triggers.sql          # Supabase triggers (e.g. mirror auth.users to public.users)
│   └── 04_indexes.sql           # Performance indexes (project_id, article_id, doi_clean)
│
├── tests/
│   ├── test_effectsize.R        # testthat unit tests for all effect size conversion paths
│   ├── test_duplicates.R        # testthat unit tests for duplicate detection logic
│   └── test_export.R            # testthat unit tests for JSONB unnesting and export formatting
│
├── www/
│   ├── custom.css               # Custom CSS overrides for bslib theme
│   └── tooltips.js              # JavaScript for tooltip initialisation (Bootstrap tooltips)
│
├── .Renviron.example            # Template showing required environment variables (no real values)
├── DESCRIPTION                  # R package-style metadata (used by renv)
├── renv.lock                    # renv lockfile for reproducible package versions
├── README.md                    # Project overview, setup instructions, and development guide
└── DEVELOPMENT.md               # Phase-by-phase developer notes and validation gate checklist
```

### 10.4 File Contents Detail

#### `app.R`
Entry point. Calls `shinyApp(ui = ui, server = server)`. Sources all files in `R/` and `modules/`. Sets global options.

#### `R/supabase.R`
- `sb_get(table, filters, token)`: Constructs GET request to `{SUPABASE_URL}/rest/v1/{table}` with filter query params and Authorization header
- `sb_post(table, body, token)`: POST with JSON body; returns inserted row
- `sb_patch(table, id_col, id_val, body, token)`: PATCH with `eq.{id_val}` filter
- `sb_delete(table, id_col, id_val, token)`: DELETE with filter
- `sb_rpc(fn, params, token)`: POST to `/rest/v1/rpc/{fn}`
- `sb_auth_login(email, password)`: POST to `/auth/v1/token?grant_type=password`
- `sb_auth_register(email, password)`: POST to `/auth/v1/signup`
- `sb_auth_refresh(refresh_token)`: POST to `/auth/v1/token?grant_type=refresh_token`

#### `R/effectsize.R`
- `compute_effect_size(input_list)`: Main entry point; dispatches to design-specific functions
- `es_control_treatment(input)`: Hedges g and t-stat paths
- `es_correlation(input)`: Direct r, covariance, and t-stat paths
- `es_regression(input)`: t-stat and beta × SD paths; handles `multiple_predictors`
- `es_interaction_a(input)`: Explicit interaction term
- `es_interaction_b(input_a, input_b)`: Difference-in-differences
- `convert_var_to_sd(var_value, var_type, n)`: SE / CI / IQR → SD conversion
- `fisher_z(r, n, se_r)`: Computes z and var_z

#### `R/duplicates.R`
- `clean_doi(doi)`: Strips prefixes, lowercases, trims
- `clean_title(title)`: Lowercase, remove punctuation, trim
- `check_duplicates(new_df, existing_df)`: Returns data frame of flagged rows with `match_type` and `similarity_score`

#### `R/export.R`
- `unnest_labels(metadata_df, label_schema)`: Flattens JSONB label data into wide-format columns
- `build_full_export(project_id, filters, token)`: Assembles full export data frame
- `build_meta_export(project_id, filters, token)`: Assembles meta-ready data frame with `yi`, `vi` columns

#### `R/auth.R`
- `check_session(session)`: Returns TRUE if token is valid and not expired
- `refresh_if_needed(session)`: Refreshes token if within 60s of expiry
- `route_guard(session, output)`: Redirects to login page if session is invalid

#### `sql/01_create_tables.sql`
All CREATE TABLE statements in this order: `users`, `projects`, `project_members`, `labels`, `articles`, `uploads`, `article_metadata_json`, `effect_sizes`, `audit_log`.

#### `sql/02_rls_policies.sql`
`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` and all `CREATE POLICY` statements per table, as specified in Section 4.10.

#### `sql/03_triggers.sql`
Supabase trigger to mirror new `auth.users` rows into `public.users`:
```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (user_id, email, created_at)
  VALUES (NEW.id, NEW.email, NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
```

#### `.Renviron.example`
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key-here
SUPABASE_SERVICE_KEY=your-service-key-here
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
```

#### `README.md`
- Project overview
- Prerequisites (R 4.3+, package list)
- Setup: clone repo, copy `.Renviron.example` to `.Renviron`, fill in credentials, run SQL scripts in Supabase dashboard, run `renv::restore()`, run `shiny::runApp()`
- Development: branch-per-phase workflow

#### `DEVELOPMENT.md`
- Phase checklist (one section per phase)
- Validation gate description and pass/fail criteria
- Known issues and decisions log

---

## 11. Phased Implementation Specification

Each phase produces a working, runnable app. Phases build on each other. **Never proceed past a validation gate until all tests pass.**

---

### Phase 1: Project Scaffold & Supabase Connection

**Deliverables:**
- `app.R` with basic `ui/server` skeleton using `bslib`
- `R/supabase.R` with all CRUD wrapper functions
- `.Renviron` with credentials
- `sql/01_create_tables.sql` executed in Supabase dashboard

**Steps:**
1. Create Supabase project (use a dev project, separate from production)
2. Run `sql/01_create_tables.sql` in Supabase SQL Editor
3. Write `R/supabase.R` with `sb_get`, `sb_post`, `sb_patch`, `sb_delete`
4. Write `app.R` with placeholder UI
5. Smoke test all CRUD functions from R console

**Validation Gate 1:**
From R console (not browser): create a `projects` row, read it back, update the description, then delete it. All four operations return expected data. Repeat with anon key and service key.

---

### Phase 2: Authentication

**Deliverables:**
- Login / register page (`modules/mod_auth.R`)
- `R/auth.R` with session management and route guard
- JWT stored in `reactiveValues()` session object

**Steps:**
1. Build login/register UI with email, password, and two buttons
2. Implement `sb_auth_login` and `sb_auth_register` in `R/supabase.R`
3. On successful login, populate session reactive values
4. Implement `route_guard` to redirect unauthenticated users
5. Add Logout button to navbar

**Validation Gate 2:**
Open two browser tabs. Log in as User A in tab 1, User B in tab 2. Verify each sees only their own session. Log out User A; confirm tab 1 redirects to login while tab 2 remains active.

---

### Phase 3: Dashboard & Projects

**Deliverables:**
- Dashboard page (`modules/mod_dashboard.R`)
- Project CRUD and membership logic
- Invite Member modal

**Steps:**
1. Build dashboard with "My Projects" and "Joined Projects" columns
2. Implement Create Project modal (title + description)
3. Implement Edit Project modal (pre-populated)
4. Implement Invite Member modal (lookup by email; insert into `project_members`)
5. Implement Leave Project button (remove from `project_members`; blocked for owner)
6. Enable RLS: run `sql/02_rls_policies.sql` in Supabase

**Validation Gate 3:**
User A creates a project. User A invites User B by email. User B logs in and sees the project under Joined Projects. User B leaves the project and it disappears from their dashboard. User A still sees it. Confirm User A cannot see a project created by a third user they haven't joined.

---

### Phase 4: Label Builder

**Deliverables:**
- Label builder tab (`modules/mod_label_builder.R`)
- All variable types supported in the Add Label modal
- JSON preview panel

**Steps:**
1. Build label list with Add, Edit, Delete, and reorder controls
2. Implement Add Label modal with all fields
3. Implement Add Label Group (creates group container; child labels added within)
4. Implement drag-or-arrow reorder updating `order_index`
5. Block delete if any article has data for the label
6. Render JSON preview of full label schema

**Validation Gate 4:**
Create a project with: 3 single labels (`text`, `select one`, `boolean`), 1 label group with 2 child labels, and 1 `effect_size` label. Save and reload. Verify all labels appear in correct order. Edit one label name. Verify the change persists on reload.

---

### Phase 5: Article Upload

**Deliverables:**
- Article upload tab (`modules/mod_article_upload.R`)
- Duplicate detection (`R/duplicates.R`)
- Upload management tab (`modules/mod_upload_management.R`)

**Steps:**
1. Build CSV file input with column validation and 10-row preview
2. Implement `R/duplicates.R` with all four detection methods
3. On upload: run duplicate detection, show flagged rows table, allow reviewer to accept/reject each
4. Insert non-flagged (and accepted) rows into `articles`
5. Record upload batch in `uploads` table
6. Build Upload Management tab showing all batches with row counts and flagged items

**Validation Gate 5:**
Upload a CSV of 20 articles. Then upload a second CSV containing 2 exact DOI duplicates, 1 title-year duplicate, 1 fuzzy title match (one word changed), and 5 new articles. Verify: 3 clear duplicates flagged and not inserted by default; fuzzy match shown with warning and similarity score; reviewer can accept it; 5 new articles inserted.

---

### Phase 6: Google Drive Folder Integration

**Deliverables:**
- `R/gdrive.R` with all Drive functions
- Drive folder URL field in Edit Project modal
- Sync Now button and sync summary display
- `pdf_drive_link` populated in `articles` table after sync

**Steps:**
1. Register a Google Cloud project and enable the Drive API; obtain OAuth 2.0 Client ID and Secret
2. Add `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` to `.Renviron`
3. Write `R/gdrive.R`: `extract_drive_folder_id()`, `gdrive_list_pdfs()`, `parse_article_id_from_filename()`, `sync_drive_folder()`
4. Add Drive folder URL text input to Edit Project modal
5. On save: extract folder ID, store in `projects.drive_folder_id`
6. Implement **Sync Now** button: calls `sync_drive_folder()`, upserts `pdf_drive_link` for matched articles, updates `drive_last_synced`, displays sync summary
7. Add Drive folder status panel to project home showing last sync time and a Sync button

**Drive folder must be shared as "Anyone with the link can view" for the API to list its contents.**

**Validation Gate 6:**
Create a Drive folder shared publicly. Add 3 PDFs named with valid article IDs (e.g. `1.pdf`, `2.pdf`, `3.pdf`) and 1 with an invalid name (`notes.pdf`). Paste the folder URL into the project. Click Sync Now. Verify: `pdf_drive_link` is populated for the 3 matching articles; `notes.pdf` appears in the skipped list; `drive_last_synced` is updated. Open a matched article in the review interface and confirm the Display PDF button opens the correct PDF.

---

### Phase 7: Review Interface

**Deliverables:**
- Review interface (`modules/mod_review.R`)
- Dynamic label rendering
- Save / Next / Skip logic
- Concurrency warning

**Steps:**
1. Build search bar filtering by ID, title, author
2. Render article header (title, abstract, DOI, Display PDF button)
3. Dynamically render label inputs from project label schema
4. Implement label group instance add/remove with card UI
5. Implement Save (upsert `article_metadata_json`, write `audit_log`)
6. Implement Next (Save + load next unreviewed)
7. Implement Skip (set `review_status = skipped`, write `audit_log`)
8. Implement concurrency check on Save
9. Show progress bar (reviewed / total)

**Validation Gate 7:**
Review 3 articles end-to-end: one with all label types filled, one with a label group with 3 instances, one skipped. Reload the app and verify all data persisted exactly. Have two reviewers open the same article simultaneously; one saves; verify the other receives the conflict warning.

---

### Phase 8: Effect Size Engine

**Deliverables:**
- `R/effectsize.R` with all conversion functions
- `tests/test_effectsize.R` with all unit tests passing

**Steps:**
1. Write `compute_effect_size(input_list)` entry point
2. Implement `es_control_treatment()` with Hedges g and t-stat paths
3. Implement `convert_var_to_sd()` for SE / CI / IQR
4. Implement `es_correlation()` with all three paths
5. Implement `es_regression()` for single and multiple predictor cases
6. Implement `es_interaction_a()` and `es_interaction_b()`
7. Implement `fisher_z()` for z and var_z
8. Write all unit tests in `tests/test_effectsize.R`
9. Run `testthat::test_file("tests/test_effectsize.R")`; fix until 0 failures

**Validation Gate 8:**
All unit tests pass with 0 failures (`devtools::test()`). Manually verify the Pathway B difference-in-differences result against a hand-calculated example.

---

### Phase 9: Effect Size UI

**Deliverables:**
- Effect size sub-form (`modules/mod_effect_size_ui.R`)
- Conditional panels per design
- Pathway A / B tabs for interactions
- Small SD toggle
- Effect size result display after Save

**Steps:**
1. Build design selector dropdown triggering conditional panels
2. Implement each design-specific field set with tooltips matching Section 8
3. When `interaction_effect = true`: show Pathway A / B selector
4. Implement Pathway B with two tabPanels (Group A, Group B), each with full design selector
5. Implement small SD toggle (visible only when means present, all other stats absent)
6. After Save, display computed r, z, var_z, effect_status, and warnings

**Validation Gate 9:**
Review one article for each of the 5 study designs. For interaction, test both Pathway A and Pathway B. Verify computed values after Save match the unit test expected values when the same inputs are used. Verify the small SD toggle appears only under the correct condition.

---

### Phase 10: Export System

**Deliverables:**
- Export tab (`modules/mod_export.R`)
- `R/export.R` with full and meta-ready export functions
- `tests/test_export.R`

**Steps:**
1. Build export tab with filter controls
2. Implement `unnest_labels()` in `R/export.R`
3. Implement `build_full_export()` assembling all columns
4. Implement `build_meta_export()` with `yi`/`vi` column names
5. Wire download buttons to `downloadHandler()`
6. Write unit tests for `unnest_labels()` and column naming

**Validation Gate 10:**
Export a project with 10+ reviewed articles, at least 2 with label group instances. Open in Excel: verify no missing columns, all JSONB data unnested, no `[object Object]`. Run the meta-ready export and execute `metafor::rma(yi=yi, vi=vi, data=df)` in R; confirm it runs without error.

---

### Phase 11: Audit Log & Polish

**Deliverables:**
- Audit log viewer tab (`modules/mod_audit_log.R`; visible to all project members)
- `sql/02_rls_policies.sql` fully applied
- UI polish: bslib theme, loading spinners, error toasts
- All tooltips reviewed

**Steps:**
1. Build audit log viewer (table: timestamp, user, article, action, diff)
2. Verify all `audit_log` writes from Save/Skip/Delete are complete
3. Run `sql/02_rls_policies.sql`; test RLS with a reviewer account via direct API call
4. Add `shinycssloaders` spinners to all async operations
5. Add `shinytoastr` (or equivalent) error toasts for failed API calls
6. Review all tooltips with a non-statistician

**Validation Gate 11:**
Log in as a reviewer who is a member of Project A but not Project B. Attempt a direct API call to read articles from Project B using the reviewer's JWT. Confirm a 403 is returned. Concurrent save test: two browser windows, same user, same article — save in both; confirm `audit_log` has two entries and the database contains the most recent save's data.

---

## 12. Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Incorrect df entry by reviewer | High | Tooltip with concrete examples for t(df) and F(df1, df2) formats; computed r shown immediately after Save for sanity check |
| Misapplication of unstandardised beta | High | Explicit `multiple_predictors` checkbox; warning message displayed when checked |
| Small SD approximation inflating effect sizes | Medium | Automatic `small_sd_used` flag; included in all exports; user filters externally for sensitivity analysis |
| IQR-to-SD conversion assumes normality | Medium | Automatic `iqr_sd_used` flag and warning message; included in all exports |
| Missing variance (var_z = NULL) | Medium | Exported as NA; `metafor` handles NA variance via listwise deletion by default |
| Concurrent reviewer overwrite | Medium | Conflict warning shown to second reviewer on Save; full audit log with snapshots for recovery; last-write-wins |
| Drive folder not shared publicly | Medium | On sync, catch 403 from Drive API and show clear error: *"Folder is not accessible. Set sharing to 'Anyone with the link can view' and try again."* |
| PDF filename does not match article ID | Low | Skipped files listed in sync summary with their filenames; owner can rename files and re-sync |
| Drive folder re-synced after articles deleted | Low | Sync only upserts `pdf_drive_link`; it never deletes articles or overwrites existing review data |
| CSV upload with non-UTF-8 encoding | Low | Detect with `readr::guess_encoding()`; show friendly re-save error |
| Supabase free tier limits | Low | Free tier supports 500MB database; sufficient for most systematic reviews; monitor via Supabase dashboard |
| JWT expiry mid-session | Low | Auto-refresh when within 60s of expiry; graceful re-login prompt if refresh fails |

---

*End of Document — Ecological Effect Size Coding Platform v3.2*
