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

**Pre-flight — run `sql/07_gdrive_columns.sql` in Supabase SQL Editor before testing Gate 6.**

**Implementation notes:**
- `R/gdrive.R` implements four functions: `gdrive_init_oauth()` (one-time interactive auth), `gdrive_init()` (load cached token at startup), `gdrive_list_pdfs()` (Drive API v3 via `httr2`), `sync_drive_folder()` (match + upsert loop).
- PDF files must be named `[article_num].pdf` where `article_num` is the integer column added to `articles` by `sql/07_gdrive_columns.sql`. Existing articles are back-filled automatically.
- `global.R` calls `gdrive_init()` at app startup. If no token is cached, Drive features are silently disabled — the app continues to work normally.
- The **Edit Project** modal now has a Drive Folder URL text input, a "Last synced" timestamp, and a **Sync Now** inline button. The URL and `drive_folder_id` are saved to the `projects` row when **Save Changes** is clicked, or immediately when **Sync Now** is pressed (so sync can run even without clicking Save).
- Sync result is displayed inline in the modal: files found / matched / skipped, with skipped filenames listed for naming-error diagnosis.
- Pagination is handled in `gdrive_list_pdfs()` via `nextPageToken` loop (supports folders with > 1 000 PDFs).
- `gdrive_is_authed()` helper checks token availability; functions fail gracefully with an instructive error if not authed.
- `gargle` is a dependency of `googledrive`; no separate install needed.

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
  - `openstreetmap_location` → `textInput` (Phase 11 can add autocomplete)
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

**Status:** [ ] Not started  [x] In progress  [ ] Gate passed

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

**Status:** [ ] Not started

---

## Phase 11: Audit Log & Polish

**Branch:** `phase-11-polish`

**Deliverables:**
- `modules/mod_audit_log.R`
- Full RLS tested
- Loading spinners and error toasts

**Validation Gate 11:**
Reviewer JWT cannot access another project's articles directly (API returns 403). Two-window concurrent save test produces two audit_log entries.

**Status:** [ ] Not started

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

---

*See `EcologyApp_Design_Spec_v3.2.md` for the full technical specification.*
