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

## Phase 2: Authentication ✅ (current)

**Branch:** `phase-2-auth`

**Deliverables:**
- `modules/mod_auth.R` — full login/register implementation
- `R/auth.R` — session management and token refresh
- JWT stored in `reactiveValues()` session object

**Validation Gate 2:**
Open two browser tabs. Log in as User A in tab 1, User B in tab 2. Verify each sees only their own session. Log out User A; confirm tab 1 redirects to login while tab 2 remains active.

**Status:** [ ] Not started  [x] In progress  [ ] Gate passed

---

## Phase 3: Dashboard & Projects

**Branch:** `phase-3-dashboard`

**Deliverables:**
- `modules/mod_dashboard.R` — full project CRUD
- `modules/mod_project_home.R` — project home tabs
- RLS: run `sql/02_rls_policies.sql`

**Validation Gate 3:**
User A creates a project. User A invites User B by email. User B logs in and sees the project under Joined Projects. User B leaves the project. User A still sees it. User A cannot see a third user's project.

**Status:** [ ] Not started

---

## Phase 4: Label Builder

**Branch:** `phase-4-labels`

**Deliverables:**
- `modules/mod_label_builder.R` — all variable types, group containers, reorder

**Validation Gate 4:**
Create 3 single labels, 1 group with 2 children, 1 effect_size label. Save and reload. Edit one label name and verify persistence.

**Status:** [ ] Not started

---

## Phase 5: Article Upload

**Branch:** `phase-5-upload`

**Deliverables:**
- `modules/mod_article_upload.R`
- `R/duplicates.R` — all four detection methods
- `modules/mod_upload_management.R`

**Validation Gate 5:**
Upload 20 articles. Upload second CSV with 2 exact DOI duplicates, 1 title-year dup, 1 fuzzy match, 5 new. Verify correct flagging and reviewer accept/reject workflow.

**Status:** [ ] Not started

---

## Phase 6: Google Drive Integration

**Branch:** `phase-6-gdrive`

**Deliverables:**
- `R/gdrive.R` — full implementation
- Drive folder URL field in Edit Project modal
- Sync Now button and summary display

**Validation Gate 6:**
Create public Drive folder. Add 3 valid PDFs + 1 invalid name. Paste URL, click Sync. Verify pdf_drive_link populated for 3 articles, 1 skipped in summary.

**Status:** [ ] Not started

---

## Phase 7: Review Interface

**Branch:** `phase-7-review`

**Deliverables:**
- `modules/mod_review.R` — full implementation

**Validation Gate 7:**
Review 3 articles end-to-end (all labels, label group with 3 instances, skip). Reload and verify data persisted. Two reviewers open same article simultaneously; second save receives conflict warning.

**Status:** [ ] Not started

---

## Phase 8: Effect Size Engine

**Branch:** `phase-8-effectsize`

**Deliverables:**
- `R/effectsize.R` — all conversion functions
- `tests/test_effectsize.R` — all 11 unit tests passing

**Validation Gate 8:**
`devtools::test()` → 0 failures. Hand-calculate Pathway B difference-in-differences and verify against app output.

**Status:** [ ] Not started

---

## Phase 9: Effect Size UI

**Branch:** `phase-9-effectsize-ui`

**Deliverables:**
- `modules/mod_effect_size_ui.R` — conditional panels per design

**Validation Gate 9:**
Review one article for each of 5 study designs. Test Pathway A and B for interaction. Verify computed values match unit test expectations. Verify small SD toggle visibility.

**Status:** [ ] Not started

---

## Phase 10: Export System

**Branch:** `phase-10-export`

**Deliverables:**
- `modules/mod_export.R`
- `R/export.R` — full implementation
- `tests/test_export.R`

**Validation Gate 10:**
Export 10+ articles (some with label groups). Open in Excel: no `[object Object]`, all columns present. Run meta-ready export in `metafor::rma(yi=yi, vi=vi, data=df)` without error.

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

---

*See `EcologyApp_Design_Spec_v3.2.md` for the full technical specification.*
