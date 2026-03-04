# DEVELOPMENT.md
## Phase-by-Phase Developer Notes & Validation Gate Checklist

---

## How to Work Through the Phases

Each phase produces a working, runnable app. Always run the validation gate for each phase before starting the next.

**Branch workflow:**
```
# Start a new phase branch
git checkout main
git checkout -b phase-N-name

# After validation gate passes:
git checkout main
git merge phase-N-name --no-ff -m "Phase N: <name> — validation gate passed"
```

---

## Phase 1: Project Scaffold & Supabase Connection ✅ (current)

**Branch:** `phase-1-scaffold`

**Validation Gate 1:**
From R console (NOT browser), run the following smoke tests:

```r
## First make sure the packages are installed:
install.packages(c("shiny","bslib","shinyjs","httr2","jsonlite,"stringr","stringdist","readr","data.table", "writexl","tools","testthat"))

source("R/utils.R")
source("R/supabase.R")
readRenviron(".Renviron")

# MY_TOKEN must be your SUPABASE_SERVICE_KEY (a long JWT starting with eyJ...).
# It is NOT a UUID. Read it directly from .Renviron:
MY_TOKEN <- Sys.getenv("SUPABASE_SERVICE_KEY")
stopifnot(nchar(MY_TOKEN) > 50)   # quick sanity check

# owner_id must be a UUID from Supabase Auth, NOT an email address.
# How to get your UUID:
#   Supabase dashboard → Authentication → Users → copy the UUID next to your email.
# If you have not registered yet, do so via the app Login page first (or
# use Authentication → Add user in the Supabase dashboard).
MY_USER_UUID <- "a1b2c3d4-1234-5678-abcd-ef0123456789"  

# Step 1: insert the user into public.users (only needed for smoke test;
#         in normal use this is done automatically by the trigger in 03_triggers.sql)
sb_post("users",
  list(user_id = MY_USER_UUID, email = "deviveytia@hotmail.com"),
  token = MY_TOKEN)

# 1. Create a projects row
new_proj <- sb_post("projects",
  list(owner_id = MY_USER_UUID,
       title = "Test Project",
       description = "Smoke test"),
  token = MY_TOKEN)
cat("Created:", new_proj$project_id, "\n")

# 2. Read it back
rows <- sb_get("projects",
  filters = list(owner_id = MY_USER_UUID),
  token   = MY_TOKEN)
print(rows)

# 3. Update description
updated <- sb_patch("projects", "project_id", new_proj$project_id,
  list(description = "Updated description"),
  token = MY_TOKEN)
cat("Updated description:", updated$description, "\n")

# 4. Delete it
sb_delete("projects", "project_id", new_proj$project_id, token = MY_TOKEN)
cat("Deleted OK\n")
```

**Pass criteria:** All four operations return expected data without errors.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 2: Authentication ✅ 

**Branch:** `phase-2-auth`

**Deliverables:**
- `modules/mod_auth.R` — full login/register implementation
- `R/auth.R` — session management and token refresh
- JWT stored in `reactiveValues()` session object

**Validation Gate 2:**
Open two browser tabs. Log in as User A in tab 1, User B in tab 2. Verify each sees only their own session. Log out User A; confirm tab 1 redirects to login while tab 2 remains active.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 3: Dashboard & Projects ✅ (current)

**Branch:** `phase-3-dashboard`

**Deliverables:**
- `modules/mod_dashboard.R` — full project CRUD
- `modules/mod_project_home.R` — project home tabs
- RLS: run `sql/02_rls_policies.sql`

**Validation Gate 3:**
User A creates a project. User A invites User B by email. User B logs in and sees the project under Joined Projects. User B leaves the project. User A still sees it. User A cannot see a third user's project.

**Implementation notes:**
- `Shiny.setInputValue()` in onclick attributes passes the project UUID as the input value, avoiding fragile per-project dynamic observers
- `sb_delete_where()` added to `R/supabase.R` to handle composite-key DELETE on `project_members`
- Service key used server-side only for email → user_id lookup (never sent to browser)
- `server.R` now has a three-state page router: login / dashboard / project_home
- Both module servers are initialised once after login; `project_id` is passed as a reactive so the project home reacts when app_state changes
- `mod_project_home_server` signature changed: now takes `app_state` in addition to `project_id` and `session_rv`

**RLS notes:**
- Every `CREATE POLICY` must include `TO authenticated` — omitting it (which defaults to `TO PUBLIC`) causes Supabase PostgREST to reject writes with `42501`.
- `auth.uid()` replaced with `public.current_user_id()` which reads the JWT `sub` claim directly from PostgREST GUC variables (`request.jwt.claim.sub`).

**Pre-flight: run `sql/02_rls_policies.sql` in Supabase SQL Editor before testing Gate 3.**

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 4: Label Builder

**Branch:** `phase-4-labels`

**Deliverables:**
- `modules/mod_label_builder.R` — all variable types, group containers, reorder ✅

**Validation Gate 4:**
Create 3 single labels (text, select one, boolean), 1 group with 2 children, 1 effect_size label. Save and reload. Edit one label name and verify persistence.

**Implementation notes:**
- Label builder is owner-only; reviewers see a read-only notice.
- All 10 variable types supported in the Add Label modal (`text`, `integer`, `numeric`, `boolean`, `select one`, `select multiple`, `YYYY-MM-DD`, `bounding_box`, `openstreetmap_location`, `effect_size`).
- `allowed_values` textarea (newline-separated) shown for `select one` / `select multiple` types.
- `Add Label Group` creates a row with `label_type = 'group'`, `variable_type = 'text'` (placeholder to satisfy DB CHECK constraint; groups are containers, not inputs).
- Child labels are added via the **+ Add Child Label** button within a group row; `parent_label_id` is set to the group's UUID.
- Up/down arrows reorder within the same sibling scope (top-level vs. children use separate scopes). Swaps `order_index` values between adjacent rows via two `sb_patch` calls.
- Delete confirmation warns (but does not block) if the project has any reviewed articles.
- JSON Schema Preview panel renders a live preview of the label schema using `jsonlite::toJSON`. Groups show as `{ type: "group", items: { ... } }`.
- Machine name auto-derived from display name (JS inline: lowercase + underscores). User can override; override is locked once they manually edit the field.
- `mod_label_builder_server` is called inside `mod_project_home_server`; the labels tab `renderUI` renders `mod_label_builder_ui(ns("label_builder"))`.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed


---

## Phase 5: Article Upload

**Branch:** `phase-5-article-upload`

**Deliverables:**
- `modules/mod_article_upload.R` — full CSV upload with duplicate detection ✅
- `R/duplicates.R` — all four detection methods fully implemented ✅
- `modules/mod_upload_management.R` — upload history + accept/reject duplicate flags ✅
- `sql/05_duplicate_flags.sql` — persistent duplicate flag queue table ✅
- `tests/test_duplicates.R` — 20 unit tests, all passing ✅

**Validation Gate 5:**
Upload 20 articles. Upload second CSV with 2 exact DOI duplicates, 1 title-year dup, 1 fuzzy match, 5 new. Verify correct flagging and reviewer accept/reject workflow.

**Pre-flight — run `sql/05_duplicate_flags.sql` in Supabase SQL Editor before testing Gate 5.**

**Implementation notes:**
- `check_duplicates(new_df, existing_df)` runs four staged checks per incoming row — stopping at the first match:
  1. Exact DOI (after cleaning) — flags as `exact_doi`
  2. Normalised title + year — flags as `title_year`
  3. Year + first 15 chars of DOI — flags as `partial_doi`
  4. Jaro-Winkler distance < 0.05, same year — flags as `fuzzy` with similarity score
- `read_upload_csv()` and `validate_upload_columns()` are helpers added to `R/duplicates.R` for re-use.
- `readr`, `stringdist`, and `jsonlite` added to `global.R` library list.
- On upload, clean articles are inserted immediately to `articles`; flagged rows are written to `duplicate_flags` (new table) with `status = 'pending'`.
- `mod_upload_management_server` takes an optional `upload_refresh` reactiveVal shared with `mod_article_upload_server`; incrementing it triggers an automatic refresh of the management tab after every upload.
- `mod_project_home_server` now owns the shared `upload_refresh <- reactiveVal(0)` and passes it to both sub-module servers.
- Accept decision: inserts the article from `article_data` JSONB, updates `duplicate_flags.status = 'accepted'`.
- Reject decision: sets `duplicate_flags.status = 'rejected'` (no article inserted).
- `shinyjs::reset("csv_file")` clears the file input after a successful upload so the user can upload a second batch immediately.
- Upload batch record (`uploads` table) is created before article inserts; `rows_uploaded` = clean rows, `rows_flagged` = flagged rows.
- **Optional `article_num` column:** CSV/TXT files may include an `article_num` integer column to supply the article number explicitly. When present, the value overrides the auto-sequence and is stored directly in the `article_num BIGINT` column on `articles`. This allows users to pre-assign numbers that match their Drive PDF filenames (`[article_num].pdf`) so Google Drive sync works immediately after upload. If the column is absent, `article_num` is assigned automatically by the DB sequence as before. The preview table shows a `#` column when `article_num` is detected. Non-integer values are silently ignored (NULL/sequence falls back). The `article_num` value is also preserved in `duplicate_flags.article_data` JSONB and restored when a flagged row is accepted. Test file: `tests/test_data/gate5_with_article_num.txt`.
- **Sequence grant:** `sql/07_gdrive_columns.sql` creates `articles_article_num_seq` but does not grant `USAGE` to `authenticated`. Run `sql/11_sequence_grants.sql` once to fix this — required for uploads that do not supply an explicit `article_num` column (the DEFAULT calls `nextval()` which needs the grant).
- **Robust upload error handling:** The upload handler now validates `batch_id` is non-null before entering the article loop. Per-row errors are collected individually (one bad row no longer aborts the whole batch). A "Partial upload" warning notification is shown when any rows fail, and the per-row error details are written to the R console (`message()`). Fatal batch-creation errors show the exact API error message.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 6: Google Drive Integration

**Branch:** `phase-6-google-drive`

**Deliverables:**
- `R/gdrive.R` — full implementation ✅
- Drive folder URL field in Edit Project modal ✅
- Sync Now button and summary display ✅
- `sql/07_gdrive_columns.sql` — schema migration ✅

**Validation Gate 6:**
Create public Drive folder. Add 3 valid PDFs + 1 invalid name. Paste URL, click Sync. Verify pdf_drive_link populated for 3 articles, 1 skipped in summary.

**Pre-flight — run `sql/07_gdrive_columns.sql` and `sql/11_sequence_grants.sql` in Supabase SQL Editor before testing Gate 6.**

**Implementation notes:**
- `R/gdrive.R` implements four functions: `gdrive_init_oauth()` (no-op stub kept for backward compat — not used), `gdrive_init()` (checks for `GOOGLE_API_KEY` at startup), `gdrive_list_pdfs()` (Drive API v3 via `httr2` + API key), `sync_drive_folder()` (match + upsert loop).
- **No OAuth required.** Drive folders must be shared as "Anyone with the link can view". A single `GOOGLE_API_KEY` in `.Renviron` is the only credential needed; it is shared across all users and all their Drive folders.
- PDF files must be named `[article_num].pdf` where `article_num` is the integer column added to `articles` by `sql/07_gdrive_columns.sql`. Existing articles are back-filled automatically.
- `global.R` calls `gdrive_init()` at app startup. If `GOOGLE_API_KEY` is not set, Drive features are silently disabled — the app continues to work normally.
- The **Edit Project** modal now has a Drive Folder URL text input, a "Last synced" timestamp, and a **Sync Now** inline button. The URL and `drive_folder_id` are saved to the `projects` row when **Save Changes** is clicked, or immediately when **Sync Now** is pressed (so sync can run even without clicking Save).
- Sync result is displayed inline in the modal: files found / matched / skipped, with skipped filenames listed for naming-error diagnosis.
- Pagination is handled in `gdrive_list_pdfs()` via `nextPageToken` loop (supports folders with > 1 000 PDFs).
- `gdrive_is_authed()` checks whether `GOOGLE_API_KEY` is set in the environment; functions fail gracefully with an instructive error if it is absent.

**Google Drive setup — one-time steps (human action required, see below):**

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 7: Review Interface

**Branch:** `phase-7-review`

**Deliverables:**
- `modules/mod_review.R` — full implementation ✅

**Validation Gate 7:**
Review 3 articles end-to-end (all labels, label group with 3 instances, skip). Verify with label types: text, select one, select multiple, boolean, openstreetmap_location. Reload and verify data persisted. Two reviewers open same article simultaneously; second save receives conflict warning.

**Implementation notes:**
- Two-column layout: scrollable article list sidebar (col-lg-3) + review panel (col-lg-9).
- Article sidebar shows status icons (reviewed ✅ / skipped ⏩ / unreviewed ●), title truncated at 52 chars, author and year sub-text. Active article highlighted in blue.
- Search bar filters the article list by article_num, title, or author (case-insensitive).
- Progress badge shows "Progress: N / Total" based on `review_status` in `articles`.
- On project load, the first `unreviewed` article is auto-selected. If all are reviewed/skipped, the first article is selected.
- Label form rendered from `project_labels` reactive (fetched via `sb_get("labels", ...)`). Labels sorted by `order_index`.
- All 10 variable types rendered:
  - `text` → `textInput`; `integer` / `numeric` → `numericInput`; `boolean` → `checkboxInput`
  - `select one` → `selectInput`; `select multiple` → `checkboxGroupInput`
  - `YYYY-MM-DD` → `dateInput`; `bounding_box` → 4×`numericInput` (lon_min/max, lat_min/max)
  - `openstreetmap_location` → `selectizeInput` with live Nominatim search (≥3 chars). Dropdown entries are colour-coded by geometry type: **green** = Polygon/MultiPolygon, **yellow** = Point (or other geometry), **red** = no geometry data returned. A colour legend is shown below the field. Selected items retain their colour stripe. The `geom_type` field is stored on each selectize item (not persisted to DB) so colours survive re-render from saved data.
  - `effect_size` → stub alert panel (Phase 9 will replace with `mod_effect_size_ui`)
- Label groups: rendered as collapsible instance cards. Each instance gets a unique key (`inst_key`) so multiple instances of the same group have distinct Shiny input IDs: `lbl_{name}__{key}`.
- `group_instances` reactiveVal stores `list(group_name = list(key1, key2, ...))`. Adding an instance appends a new key; removing slides it out. The form re-renders via `output$label_form` which reads `group_instances()`.
- On article load, existing group instances in `article_metadata_json` are counted; one instance key is created per existing entry so prior data is restored into the correct input IDs.
- **Save** action: calls `sb_upsert("article_metadata_json", ...)` (`on_conflict = "article_id"`), then `sb_patch("articles", ...)` setting `review_status = "reviewed"`, then writes an `audit_log` entry with `action = "save"` and old/new JSON snapshots.
- **Next** action: saves first (same as Save), then navigates to the next `unreviewed` article.
- **Skip** action: patches `review_status = "skipped"` without saving metadata, writes `audit_log` entry with `action = "skip"`, then navigates to next unreviewed.
- **Concurrency check** (spec §7.3): on every Save, `audit_log` is queried for any row where `article_id = current`, `action = save`, `user_id != current_user`, and `timestamp > loaded_at`. If found, a 12-second warning toast is shown. Save is never blocked; last-write-wins.
- `mod_review_server` is called once in `mod_project_home_server`; `project_id` is passed as a reactive.
- Effect size section (Phase 9) is a placeholder alert. The `effect_size` variable_type is recognised but renders a stub; no `effect_sizes` table writes in Phase 7.

**Pre-flight:** No new SQL required for Phase 7 (all tables already exist).

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 8: Effect Size Engine ✅

**Branch:** `phase-8-effectsize`

**Deliverables:**
- `R/effectsize.R` — all conversion functions ✅
- `tests/test_effectsize.R` — all 11 spec tests + 1 smoke test + 1 time_trend bonus = 37 assertions, 0 failures ✅

**Validation Gate 8:**
`devtools::test()` → 0 failures. Hand-calculate Pathway B difference-in-differences and verify against app output. Also test effect size calculations for other types of study methods to verify.

**Implementation notes:**
- `compute_effect_size(input_list)` is the single entry point; routes on `input_list$study_design`
- `time_trend` design is aliased to `regression` internally
- Design helpers all return `list(r, n, se_r, status, warnings)`
- Pathway B (`es_interaction_b`) calls `compute_effect_size` recursively for each group, then computes `z_diff = atanh(r_A) - atanh(r_B)` and `var_z_diff = var_z_A + var_z_B`; returns pre-built `z` and `var_z` so the main function skips a second Fisher Z call
- `convert_var_to_sd()` handles SE → SD (×√n), 95% CI → SD (÷1.96), IQR → SD (÷1.35); IQR conversion appends `"IQR used for SD"` to warnings
- `fisher_z()` returns `var_z = 1/(n-3)` if `n > 3`; fallback `(se_r / (1-r²))²` if `se_r` present; NULL otherwise
- Small SD approximation (`use_small_sd_approx = TRUE`): SD = 0.01 × |mean|; sets `effect_status = "small_sd_used"`; save is never blocked
- `%||%` null-coalescing operator designed to pass vectors (not just scalars) so warning arrays are preserved through the call stack

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 9: Effect Size UI

**Branch:** `phase-9-effectsize-ui`

**Deliverables:**
- `modules/mod_effect_size_ui.R` — conditional panels per design

**Validation Gate 9:**
Review one article for each of 5 study designs. Test Pathway A and B for interaction. Verify computed values match unit test expectations. Verify small SD toggle visibility.

**Implementation notes:**
- `mod_effect_size_ui_ui()` renders a full effect size sub-form with:
  - General fields (study_method, response_scale, response/predictor distribution, variable names, units, interaction_effect checkbox)
  - Study design selector (control_treatment, correlation, regression, interaction, time_trend)
  - Conditional panels per design with all fields from spec §8
  - Tooltips matching spec §8 for t-stat, F-stat, df, r, etc.
  - Interaction Pathway A (explicit interaction term) and Pathway B (two sub-forms with full design selectors for Group A / Group B, using navset_card_tab)
  - Small SD toggle (visible only when means present but no variability stats or test statistics)
  - Effect size result display card showing r, z, var_z, status badge, and warnings after Save
- `mod_effect_size_ui_server()` receives `article_id_reactive` and `on_save_trigger` from the review module:
  - On article change: loads existing `effect_sizes` row, populates all fields, shows stored result
  - On save trigger: collects all inputs → calls `compute_effect_size()` → upserts to `effect_sizes` table
  - Returns `list(collect_inputs, result)` for parent module access
- Wired into `mod_review.R`:
  - `es_save_trigger` reactiveVal added to State section
  - `mod_effect_size_ui_server()` called once in server, before project change observer
  - Effect size form rendered as its own card in `review_panel`, separate from `label_form` (so label-group changes don't destroy ES inputs)
  - `"effect_size"` variable_type in `.render_field()` shows an info note pointing to the ES card below
  - `.do_save()` increments `es_save_trigger` after metadata upsert, before audit log write
- Pathway B sub-forms use `"grpA_"` and `"grpB_"` prefixes for all field IDs to avoid namespace collisions
- No new SQL required (effect_sizes table created in Phase 1)
- **Pathway colour coding:** Each study design's fields are wrapped in colour-coded `div`s indicating which conversion pathway they belong to:
  - **Green** (`es-pathway-a`) — Primary pathway (e.g. means + variability → Hedges g → r)
  - **Blue** (`es-pathway-b`) — Fallback 1 (e.g. t-stat + df → r)
  - **Amber** (`es-pathway-c`) — Fallback 2 (e.g. F-stat + df → t → r)
  - A colour legend is shown at the top of each design's field set via `.pathway_legend()`
  - CSS classes defined in `www/custom.css` (border-left + tinted background)
- **"Calculate effect size" button:** `actionButton(ns("btn_calculate"))` at the bottom of the form runs `compute_effect_size()` and updates the result display without saving to the database, allowing users to preview results without scrolling to Save

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 10: Export System

**Branch:** `phase-10-export`

**Deliverables:**
- `modules/mod_export.R`
- `R/export.R` — full implementation
- `tests/test_export.R`
- `tests/test_map.R` — plots a map of the coded locations in the entire corpus, by binning all the openstreetmap_locations to a standard 1 degree x 1 degree grid. For example, if 'Paris' is coded twice and covers 3 grid cells, each cell will have a value of (n instances of location)/(n cells covered by location) = 2/3. This is done for all locations and then summed per cell. 

**Validation Gate 10:**
Export 10+ articles (some with label groups). Open in Excel: no `[object Object]`, all columns present. Run meta-ready export in `metafor::rma(yi=yi, vi=vi, data=df)` without error. Plot a test map using `tests/test_map.R`.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---


## Phase 11: clone a project

**Branch:** `phase-11-clone`

**Deliverables:**
- `clone_labels_to_project()` added to `R/utils.R` — copies all labels (single + groups + children) with parent_label_id remapping ✅
- New Project modal in `modules/mod_dashboard.R` updated with "Clone from" dropdown ✅

**Validation Gate 11:**
- When creating a new project, a dropdown list is added where a reviewer can choose to clone an existing project. 
- Articles can be imported into the new cloned project without affecting the origin project
- in the review tab, the reviewer can see all the labels displayed and able to fill in, exactly as in the source project, but with the new articles.
- the article data with the corresponding labels exports correctly. 

**Pre-flight:** No new SQL required for Phase 11 (all tables already exist).

**Implementation notes:**
- The **New Project** modal now includes a `selectInput` dropdown labelled "Clone labels from an existing project". It lists all projects the user owns or has joined; the default is "(Blank project)" (no clone).
- When a source project is selected: a live preview shows the count of labels that will be cloned (N single, M groups with K children). The project description is auto-filled from the source if the description field is still empty.
- On "Create" click: the project is created first via `sb_post("projects", ...)`, then `clone_labels_to_project()` is called if a source was selected.
- `clone_labels_to_project()` in `R/utils.R`:
  1. Fetches all labels from the source project.
  2. Inserts top-level labels (no `parent_label_id`) first, collecting an `id_map` (old UUID → new UUID).
  3. Inserts child labels second, remapping `parent_label_id` to the new group UUID via `id_map`.
  4. All label metadata is preserved: `label_type`, `variable_type`, `allowed_values`, `category`, `instructions`, `mandatory`, `order_index`.
- Only the label schema is copied. Articles, collaborators, review data, effect sizes, and audit log entries are NOT copied.
- `helpText` in the modal clarifies what is and is not copied.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Phase 12: Audit Log & Polish

**Branch:** `phase-12-audit`

**Deliverables:**
- `modules/mod_audit_log.R` — Full audit log viewer with filters (action, user, date range), timestamped table, diff modal showing before/after JSON snapshots
- `mod_project_home.R` updated — audit log tab wired to real module (stub replaced)
- Loading spinners (`shinycssloaders`) added to: article list, review panel, export preview, dashboard projects, audit log table
- Error toasts (`shinytoastr`) — `toast_error()`, `toast_success()`, `toast_warning()` helpers added to `R/utils.R`; `useToastr()` added to `ui.R`; key review save/skip actions converted to toasts
- CSS polish: audit log diff styling, spinner min-height override
- `global.R` updated with `shinycssloaders` + `shinytoastr` library calls
- `DESCRIPTION` updated with new package dependencies

**Validation Gate 12:**

Reviewer JWT cannot access another project's articles directly (API returns 403). Two-window concurrent save test produces two `audit_log` entries and the database contains the most recent save's data.

### How to Run Validation Gate 12 — Step-by-Step

**Prerequisites:**  
You need two things set up before you start:
1. The app must be deployed or runnable locally (`shiny::runApp()`)  
2. You need at least one Supabase user account. Ideally two: one **owner** and one **reviewer**. If you only have one, you can still test the audit log (just not the cross-project RLS test).

---

**Part A: Verify the Audit Log UI works**

1. Open your terminal/R console and run the app:
   ```r
   shiny::runApp()
   ```
2. Log in with your account credentials.
3. Open (or create) a project that has at least one uploaded article.
4. Click the **"Review"** tab → select any article → fill in some fields → click **"Save"**.
5. Click the **"Audit Log"** tab (the clipboard icon in the project tabs).
6. **Check:** You should see a table with at least one row showing:
   - Your save action with a timestamp
   - Your username/email
   - The article title
   - Action = "save" (in green)
   - A blue diff button (↔ icon)
7. Click the **diff button** → a modal should open showing "Before" (old JSON) and "After" (new JSON) side by side.
8. **Check:** The JSON should show the label values you just saved.
9. Try the **filters**: change "Action" to "save" only, change the date range, check that the table updates correctly.
10. Go back to the Review tab → select the same article → click **"Skip"**.
11. Return to the Audit Log tab → click **Refresh**.
12. **Check:** You should now see both a "save" entry AND a "skip" entry.

**Pass criteria for Part A:** Audit log shows all save/skip actions with correct timestamps, users, and viewable JSON diffs.

---

**Part B: RLS Cross-Project Security Test**

This test verifies that a reviewer in Project A cannot read articles from Project B.

1.  **Set up:** You need a user who is a member of Project A but NOT Project B. If you only have one user who owns both projects, create a second user account (register a new email in the app), then invite that user to Project A only.

2.  **Get the reviewer's JWT token.** The easiest way:
    - Log in as the reviewer in the app.
    - In R, find the session token (or add a temporary `cat(session_rv$token)` to server.R).
    - Alternatively, use the Supabase Dashboard → Authentication → Users → pick the reviewer → use the Supabase client to generate a JWT.

3.  **Make a direct API call** using the reviewer's JWT to try to read articles from Project B (a project they are NOT a member of). Run in R console:
    ```r
    source("R/supabase.R")
    readRenviron(".Renviron")
    
    # Replace with the reviewer's actual JWT token
    REVIEWER_TOKEN <- "eyJ..."
    
    # Replace with a project_id the reviewer does NOT have access to
    OTHER_PROJECT_ID <- "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    
    result <- tryCatch(
      sb_get("articles",
             filters = list(project_id = OTHER_PROJECT_ID),
             token   = REVIEWER_TOKEN),
      error = function(e) e$message
    )
    print(result)
    ```

4. **Check:** The result should be an empty data frame (0 rows) or a 403/401 error. The reviewer must NOT see any articles from Project B.

**If you only have one user / one project**, you can verify RLS is enabled by running this in the Supabase SQL Editor:
```sql
SELECT tablename, policyname, cmd, roles
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename = 'articles'
ORDER BY policyname;
```
You should see SELECT/INSERT/UPDATE/DELETE policies with `TO authenticated` and `user_can_access_project` checks.

**Pass criteria for Part B:** Reviewer cannot see articles from a project they don't belong to.

---

**Part C: Concurrent Save Test (two-window test)**

1. Open the app in **two separate browser windows** (or tabs). Log in as the **same user** in both.
2. In both windows, open the **same project** → go to the **Review** tab → select the **same article**.
3. In **Window 1**: change a label value (e.g. type "test value 1" in a text field) → click **Save**.
4. In **Window 2** (WITHOUT refreshing): change the same or a different label value (e.g. "test value 2") → click **Save**.
5. **Check in Window 2:** You should see a **yellow/orange warning toast** saying:  
   *"Another reviewer saved changes to this article since you loaded it. Your save has been recorded. Review the audit log to check for conflicts."*
6. Go to the **Audit Log** tab and click **Refresh**.
7. **Check:** You should see **two separate "save" entries** for the same article, with slightly different timestamps.
8. Click the diff button on each entry to verify they contain different before/after snapshots.

**Pass criteria for Part C:** Both saves are recorded in the audit log. The concurrency warning appears on the second save.

---

**Part D: UI Polish Verification**

1. **Loading spinners:** Navigate between tabs (Dashboard → project → Review → Export → Audit Log). While data loads, you should see small green spinner animations (not blank white space).
2. **Error toasts:** Temporarily break your internet connection or set an invalid `SUPABASE_URL` in `.Renviron`. Try to save an article. You should see a red toast notification in the top-right corner (not a plain grey Shiny notification).
3. **Tooltips:** In the Review tab, hover over or click any ❓ icon next to label fields. A tooltip should appear with plain-language guidance.

**Pass criteria for Part D:** Spinners appear during loading; error toasts are styled (red background, top-right); tooltips work.

---

**All gates passed when:** Parts A + B + C + D all pass.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

## Phase 13: Additional PAMS features

**Branch:** `PAMS-features`

**Deliverables:**
- `modules/mod_label_builder.R` — Updated with:
  - Value-level definitions for `select one` / `select multiple` labels (JSON stored in `instructions` field as structured data)
  - Export Label Schema button (downloads JSON with definitions)
  - Import Label Schema button (uploads JSON, creates labels)
- `modules/mod_review.R` — Updated with:
  - Rich tooltip display: clicking ❓ icon shows label definition + value definitions in a popover
  - Data preservation when adding/removing group instances (collects current input values before re-render)
  - Unsaved changes warning when navigating away from an article
  - Two-column layout for label form fields (better space use)
  - Responsive layout: article sidebar hidden on narrow screens, main panel always visible
- `R/export.R` — Updated with:
  - `unnest_labels()` handles nested label groups (groups within groups) with Cartesian row expansion
- `R/utils.R` — Updated with:
  - `build_label_schema_json()` — exports label schema with definitions
  - `import_label_schema()` — imports JSON schema and creates labels in DB
- `www/custom.css` — Updated with multi-column review layout CSS, responsive breakpoints

**Implementation notes:**
- **Value-level definitions** are stored as a JSON string in the `instructions` field of each label. The format is: `{"label_def": "The definition...", "value_defs": {"Value1": "Definition 1", "Value2": "Definition 2"}}`. For labels without value definitions, `instructions` remains a plain text string (backward compatible).
- **Tooltip rendering** in the Review tab uses `tooltip_icon_rich()` helper which builds HTML content including the label definition and a styled list of value definitions. Bootstrap popovers (not tooltips) are used for rich HTML content.
- **Data preservation on add/remove instance**: Before re-rendering the group form, `.collect_values()` is called to snapshot current input values into `current_meta()`. The re-render then restores values from this snapshot.
- **Unsaved changes detection**: A `dirty` reactiveVal is set TRUE whenever an input changes after article load. Navigating to another article or away from the review tab triggers a confirmation modal if `dirty()` is TRUE.
- **Two-column label layout**: Labels are rendered in a Bootstrap `row` with two `col-md-6` columns. Effect size labels and label groups span the full width.
- **Responsive sidebar**: CSS media query `@media (max-width: 992px)` hides `.col-lg-3` (article list) and expands `.col-lg-9` to full width. A toggle button appears to show/hide the sidebar.
- **Label schema export** produces JSON matching the example format with `definition` (from label instructions) and value-level `definition` entries.
- **Label schema import** parses the JSON, creates groups first (to get UUIDs), then single/child labels with remapped parent IDs.

**Pre-flight:** No new SQL required — all features use existing `labels`, `instructions`, and `allowed_values` columns.

**Validation Gate 13:**

### Gate 13A — Value-Level Definitions

1. Open the app and navigate to a project's **Labels** tab.
2. Add a new label with type `select one`. Enter display name "Habitat Type", allowed values: `Forest`, `Grassland`, `Wetland`.
3. In the Instructions field, type a label definition like "The primary habitat type of the study site".
4. **New feature check:** Below the allowed values, you should see a **"Value Definitions"** section with one text input per allowed value. Enter definitions:
   - Forest: "Temperate or tropical forest ecosystem"
   - Grassland: "Open grass-dominated landscape"
   - Wetland: "Water-saturated ecosystem"
5. Click Save.
6. **Check:** Reload the page. Edit the same label. All value definitions should persist.

**Pass criteria:** Value definitions save and reload correctly for `select one` and `select multiple` label types.
[x] Gate Passed

---

### Gate 13B — Tooltip Display in Review Tab

1. Navigate to the **Review** tab. Select an article.
2. Find the "Habitat Type" label you created in Gate 13A.
3. **Check:** A ❓ icon should appear next to the label name.
4. Click the ❓ icon.
5. **Check:** A popover/tooltip should appear showing:
   - The label definition: "The primary habitat type of the study site"
   - Value definitions listed below:
     - **Forest:** Temperate or tropical forest ecosystem
     - **Grassland:** Open grass-dominated landscape
     - **Wetland:** Water-saturated ecosystem
6. Click outside the popover to dismiss it.
7. **Check:** Labels inside label groups also show ❓ icons with their instructions.

**Pass criteria:** All labels with definitions (including children in groups) show clickable ❓ icons with rich tooltips containing both label and value definitions.

[x] In progress:  icon displayed for normal labels, but nothing happens when icon is clicked. No icons display at all when a label is a child label in a label group
---

### Gate 13C — Label Schema Export

1. Go to the **Labels** tab. Ensure you have at least 2 labels (one `select one` with value definitions, one `text` without).
2. Click the **"Export Schema"** button in the toolbar.
3. **Check:** A JSON file downloads. Open it in a text editor.
4. **Check:** The JSON structure should look like:
   ```json
   {
     "habitat_type": {
       "type": "select one",
       "display": "Habitat Type",
       "mandatory": false,
       "definition": "The primary habitat type of the study site",
       "values": [
         { "value": "Forest", "definition": "Temperate or tropical forest ecosystem" },
         { "value": "Grassland", "definition": "Open grass-dominated landscape" },
         { "value": "Wetland", "definition": "Water-saturated ecosystem" }
       ]
     }
   }
   ```
5. **Check:** Labels without value definitions have a plain `"definition"` field (or none if empty). Label groups appear as `"type": "group"` with their child labels under `"items"`.

**Pass criteria:** Exported JSON has correct structure with definitions at both label and value level.

[x] Gate Passed
---

### Gate 13D — Label Schema Import

1. Create a new blank project (no labels).
2. Go to the **Labels** tab. Click **"Import Schema"**.
3. Select the JSON file exported in Gate 13C (or create a test JSON file).
4. **Check:** After import, the labels list shows all labels from the JSON, including groups with children.
5. **Check:** Edit one of the imported labels — the definition and value definitions should be populated.
6. Go to the **Review** tab. Upload some articles. Select one.
7. **Check:** All imported labels render correctly in the review form (correct types, allowed values, tooltips).

**Pass criteria:** Imported labels are fully functional — correct types, allowed values, definitions, group/child structure.

[x] Gate Passed
---

### Gate 13E — Data Preservation on Add Instance

1. Go to the **Review** tab. Select an article.
2. Find a label group (e.g. "Study Site") with at least one instance.
3. Fill in values for Instance 1 (text, select, etc.).
4. **Without clicking Save**, click **"+ Add Instance"**.
5. **Check:** Instance 1's values should still be visible and unchanged (NOT erased).
6. Fill in Instance 2 with different values.
7. Click **"Remove"** on Instance 2.
8. **Check:** Instance 1's values remain intact.
9. Now click Save.
10. **Check:** Data persists correctly after save.

**Pass criteria:** Adding or removing group instances never erases data entered in other instances.

[x] Gate passed
---

### Gate 13F — Unsaved Changes Warning

1. Review tab: select an article. Change a label value (type text in a field).
2. **Without saving**, click a different article in the sidebar.
3. **Check:** A confirmation dialog/modal appears: "You have unsaved changes. Discard and continue, or go back to save?"
4. Click "Go back" — you remain on the current article with your unsaved changes.
5. Make a change again, click another article, and this time click "Discard".
6. **Check:** Navigation proceeds to the new article. The unsaved data is lost (expected).

**Pass criteria:** Unsaved changes trigger a warning. "Go back" preserves data; "Discard" navigates away.

[x] Gate passed
---

### Gate 13G — Two-Column Review Layout

1. Review tab: select an article with many labels.
2. **Check:** Single/simple labels (text, numeric, select, boolean, date) are arranged in two columns side by side, not stacked vertically.
3. **Check:** Label groups and effect_size labels span the full width (not squeezed into a column).
4. **Check:** On a narrow screen or split-screen (< 992px), the article sidebar disappears and the main review panel takes full width.
5. **Check:** A small toggle button appears (e.g., hamburger icon) to show/hide the article list when in narrow mode.

**Pass criteria:** Two-column layout works for simple fields. Groups span full width. Sidebar hides on narrow screens with a toggle.

[x] Gate passed
---

**All gates passed when:** Gates 13A + 13B + 13C + 13D + 13E + 13F + 13G all pass.

**Status:** [ ] Not started  [ ] In progress  [ ] Gate passed

---

## Last Phase: Run in a docker container

**Branch:** `phase-13-docker`

**Deliverables:**
- `Dockerfile` — multi-stage image build based on `rocker/shiny`
- `docker-compose.yml` — single-command local dev + production deployment
- `.dockerignore` — excludes secrets, caches, and test artefacts
- `shiny-server.conf` _(optional override)_ — custom port / logging settings

---

### 13.1 Prerequisites

| Tool | Minimum version | Purpose |
|------|----------------|---------|
| Docker Desktop (or Docker Engine on Linux) | 24.x | Build & run the container |
| Docker Compose V2 (`docker compose`) | 2.24 | Orchestrate the container + env vars |
| Supabase project | any | Backend (no change from previous phases) |
| `.Renviron` file with all secrets | — | Mounted as env vars at runtime |

---
Delivers: Docker-file, `.dockerignore`, `docker-compose.yml`, `.env`



Drive sync uses a **Google API key** — no OAuth flow, no cached token file, no
per-user credentials. The key is passed as an environment variable and works for
any Drive folder that is shared as **"Anyone with the link can view"**.

**One-time setup (≈ 2 minutes):**

1. Go to [console.cloud.google.com](https://console.cloud.google.com).
2. Select your project and ensure the **Google Drive API** is enabled
   (_APIs & Services → Library → search "Drive API" → Enable_).
3. Go to _APIs & Services → Credentials → + CREATE CREDENTIALS → API key_.
4. Copy the key shown (starts with `AIza...`).
5. Add it to your `.env` file: `GOOGLE_API_KEY=AIza...`

The same API key works for every user's Drive folder, provided each folder is
shared publicly. No token file, no volume mount, no re-authorisation needed.

If `GOOGLE_API_KEY` is absent from the environment, `gdrive_init()` logs a
warning at startup and Drive features are silently disabled — the rest of the
app continues normally.

---

### Build & Run

```bash
# Build the image (first time: ~5–10 min due to R package installs)
docker compose build

# Start the container (detached)
docker compose up -d

# Tail logs
docker compose logs -f shiny

# Open in browser
# http://localhost:3838/ecology-effect-size-app

# Stop
docker compose down
```

**Rebuilding after source changes** (no package changes):

```bash
docker compose build --no-cache && docker compose up -d
```

---

### 13.8 Custom `shiny-server.conf` _(optional)_

If you need to change the port, enable bookmarks, or tune timeouts, add this
file at the project root and uncomment the `COPY` line in the Dockerfile:

```
# shiny-server.conf
run_as shiny;

server {
  listen 3838;

  location /ecology-effect-size-app {
    site_dir /srv/shiny-server/ecology-effect-size-app;
    log_dir  /var/log/shiny-server;
    directory_index on;

    # Keep idle sessions alive for 1 hour
    app_idle_timeout 3600;

    # Allow large file uploads (matches options(shiny.maxRequestSize) in global.R)
    sanitize_errors off;
  }
}
```

Add to Dockerfile (before the `EXPOSE` line):
```dockerfile
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf
```


### Docker Production Deployment Notes

| Concern | Recommendation |
|---------|---------------|
| **Reverse proxy / HTTPS** | Put Nginx or Caddy in front (separate container). Terminate TLS there; proxy to `http://shiny:3838`. |
| **Multiple workers** | Use [ShinyProxy](https://www.shinyproxy.io/) as the outer container manager; it spins up a fresh container per user session, eliminating Shiny's single-process concurrency limits. |
| **Image registry** | Push the built image to a container registry (GHCR, ECR, Docker Hub) and deploy from there rather than building on the production host. |
| **Secret management** | In production, prefer Docker Secrets or a secrets manager (AWS Secrets Manager, HashiCorp Vault) over a plain `.env` file. |
| **Log rotation** | Configure `logrotate` on the host for the `./logs/shiny-server` volume, or ship logs to a centralised sink (CloudWatch, Loki). |
| **R package caching** | In CI/CD, cache the Docker layer that installs R packages (the `pak::pak(...)` `RUN` step) by pinning exact package versions so the layer hash is stable across builds. |

---

### Validation Gate 13

**Part A — Local smoke test**

1. Ensure `.env` exists with valid Supabase credentials.
2. Run `docker compose build` — build must complete without errors.
3. Run `docker compose up -d`.
4. Open `http://localhost:3838/ecology-effect-size-app` in a browser.
5. **Check:** Login page loads. Log in; create a project; upload a CSV; review an article; export. All phases 1–12 features work inside the container.
6. Run `docker compose logs -f shiny` — no R `ERROR` or `FATAL` lines.

**Part B — Secrets not in image**

```bash
# Verify .Renviron was not copied into the image
docker run --rm ecology-effect-size-app:latest test -f /srv/shiny-server/ecology-effect-size-app/.Renviron \
  && echo "FAIL: .Renviron found in image" \
  || echo "PASS: .Renviron not in image"

# Verify SUPABASE_SERVICE_KEY is not baked into any image layer
docker history --no-trunc ecology-effect-size-app:latest | grep -i supabase \
  && echo "FAIL: secret found in history" \
  || echo "PASS: no secrets in image history"
```

**Part C — Environment variables are read correctly**

```bash
# Exec into the running container and verify env vars are visible to R
docker exec ecology-effect-size-app Rscript -e \
  "stopifnot(nchar(Sys.getenv('SUPABASE_URL')) > 10); cat('PASS\n')"
```

**Pass criteria:** Parts A, B, and C all pass.

**Status:** [ ] Not started  [ ] In progress  [x] Gate passed

---

## Known Issues & Decisions Log

| Date | Issue / Decision | Resolution |
|------|-----------------|------------|
| 2026-02-21 | Phase 1 scaffold initialised | All stubs created; SQL ready to run |
| 2026-02-21 | Phase 2 authentication implemented | `R/auth.R` refresh/guard fully implemented; `server.R` gains `refresh_token` field and 30 s auto-refresh timer |
| 2026-02-21 | Phase 3 dashboard & projects implemented | Full project CRUD, invite/leave membership, project home with tab stubs. `sb_delete_where` added to `R/supabase.R`. `server.R` updated to three-state page router. `mod_project_home_server` now receives `app_state`. Run `sql/02_rls_policies.sql` before Gate 3 validation. |
| 2026-02-22 | Phase 6 Google Drive integration implemented | `R/gdrive.R` fully implemented; `sql/07_gdrive_columns.sql` adds `article_num` to articles and ensures Drive columns exist on projects. Edit Project modal gains Drive URL + Sync Now. `global.R` calls `gdrive_init()` at startup. |
| 2026-02-22 | Phase 7 Review Interface implemented | `modules/mod_review.R` fully implemented; wired into `mod_project_home.R` replacing the Phase 7 stub. Dynamic label form (all 10 variable types), label groups with multi-instance add/remove, Save/Next/Skip actions, concurrency conflict detection, audit log writes. Effect size fields stubbed for Phase 9. |
| 2026-02-22 | Phase 8 Effect Size Engine implemented | `R/effectsize.R` fully implemented with all design pathways (control/treatment Hedges g, correlation, regression, interaction Pathway A & B, time_trend). `tests/test_effectsize.R` has 37 passing assertions (0 failures). `%||%` null-coalesce allows vector warnings to propagate correctly. |
| 2026-02-22 | Phase 9 Effect Size UI implemented | `modules/mod_effect_size_ui.R` fully implemented with general fields, all 5 study designs, conditional panels, Interaction Pathway A/B (Pathway B with full sub-forms per group), small SD toggle, result display. Wired into `mod_review.R`: effect_size variable_type renders the real module; save triggers computation and upsert to `effect_sizes` table. |
| 2026-02-22 | Phase 10 Export System implemented | `R/export.R` fully implemented: `unnest_labels()` flattens JSONB label groups into wide-format rows, `.flatten_raw_effect()` prefixes raw fields with `raw_`, `build_full_export()` merges articles+labels+effects, `build_meta_export()` renames z→yi / var_z→vi for metafor. `modules/mod_export.R`: owner-only UI with reviewer/status/date/effect_status filters, preview table, Full Export + Meta-Ready CSV downloads. `tests/test_export.R` has 52 passing assertions. `tests/test_map.R`: 1° grid binning + base-R plot (9 assertions pass). |
| 2026-03-01 | Phase 11 Clone a Project implemented | `clone_labels_to_project()` added to `R/utils.R`; New Project modal in `mod_dashboard.R` updated with "Clone from" dropdown, label preview, and auto-fill description. Labels (single + groups + children) are copied with parent_label_id remapping. Articles, collaborators, and review data are NOT copied. |
| 2026-03-01 | Phase 12 Audit Log & Polish implemented | `modules/mod_audit_log.R` fully implemented with filters (action/user/date), timestamped table, diff modal. Wired into `mod_project_home.R` (stub replaced). `shinycssloaders` spinners added to article list, review panel, export preview, dashboard, audit log. `shinytoastr` error toasts added via `toast_error/success/warning` helpers in `R/utils.R`; key review actions converted. `global.R` + `DESCRIPTION` updated. CSS polish for audit log and spinner styling. |

---

*See `EcologyApp_Design_Spec_v3.2.md` for the full technical specification.*
