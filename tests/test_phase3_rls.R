# ============================================================
# tests/test_phase3_rls.R — RLS diagnostic for Phase 3
# ============================================================
# Run each section interactively in the R console.
# This script pinpoints exactly where the 42501 error occurs.
#
# BEFORE RUNNING:
#   1. Run sql/08_policies_with_custom_uid.sql in Supabase SQL Editor
#      (this replaces ALL policies with ones that use current_user_id()
#       instead of auth.uid(), fixing the known policy-evaluation issue)
#   2. Ensure .Renviron has SUPABASE_URL, SUPABASE_KEY,
#      SUPABASE_SERVICE_KEY
# ============================================================

source("R/utils.R")
source("R/supabase.R")
readRenviron(".Renviron")

# Enable debug logging
options(sb.debug = TRUE)

cat("============================================================\n")
cat("STEP 1: Login to get a real user JWT\n")
cat("============================================================\n")

# ---- Fill in your test credentials --------------------------
TEST_EMAIL    <- "deviveytia@hotmail.com"
TEST_PASSWORD <- "Alphie1851"

auth_result <- sb_auth_login(TEST_EMAIL, TEST_PASSWORD)
USER_TOKEN   <- auth_result$access_token
USER_ID      <- auth_result$user$id

cat("Login OK\n")
cat("  user_id (from auth response):", USER_ID, "\n")
cat("  token preview:", substr(USER_TOKEN, 1, 30), "...\n")

# ---- Decode JWT to check claims ----------------------------
cat("\n============================================================\n")
cat("STEP 2: Decode JWT to inspect claims\n")
cat("============================================================\n")

jwt_parts <- strsplit(USER_TOKEN, "\\.")[[1]]
jwt_payload_raw <- rawToChar(jsonlite::base64url_dec(jwt_parts[2]))
jwt_payload <- jsonlite::fromJSON(jwt_payload_raw)

cat("  sub  (should match user_id):", jwt_payload$sub, "\n")
cat("  role (should be 'authenticated'):", jwt_payload$role, "\n")
cat("  aud  :", jwt_payload$aud, "\n")
cat("  exp  :", as.POSIXct(jwt_payload$exp, origin = "1970-01-01"), "\n")

stopifnot(
  "JWT sub != user_id from auth response!" =
    jwt_payload$sub == USER_ID
)
cat("  PASS: sub matches user_id\n")

stopifnot(
  "JWT role is not 'authenticated'!" =
    jwt_payload$role == "authenticated"
)
cat("  PASS: role is 'authenticated'\n")

# ---- Verify current_user_id() via RPC ---------------------
cat("\n============================================================\n")
cat("STEP 3: Call current_user_id() and auth.uid() via RPC\n")
cat("============================================================\n")

# Test current_user_id() — our custom replacement
tryCatch({
  rpc_uid <- sb_rpc("current_user_id", token = USER_TOKEN)
  cat("  current_user_id() via RPC:", rpc_uid, "\n")
  if (!is.null(rpc_uid) && rpc_uid == USER_ID) {
    cat("  PASS: current_user_id() returns correct UUID\n")
  } else {
    cat("  FAIL: current_user_id() returned unexpected value!\n")
  }
}, error = function(e) {
  cat("  SKIP: current_user_id() RPC failed. Run sql/08_policies_with_custom_uid.sql first.\n")
  cat("  Error:", e$message, "\n")
})

# Also test auth.uid() for comparison
tryCatch({
  rpc_uid2 <- sb_rpc("debug_auth_uid", token = USER_TOKEN)
  cat("  auth.uid() via RPC:        ", rpc_uid2, "\n")
}, error = function(e) {
  cat("  (debug_auth_uid not available — that's OK)\n")
})

# ---- Verify public.users row exists ----------------------
cat("\n============================================================\n")
cat("STEP 4: Check public.users row exists (using service key)\n")
cat("============================================================\n")

SVC_KEY <- Sys.getenv("SUPABASE_SERVICE_KEY")
stopifnot("SUPABASE_SERVICE_KEY not set!" = nchar(SVC_KEY) > 50)

user_rows <- sb_get("users",
                     filters = list(user_id = USER_ID),
                     token   = SVC_KEY)

if (is.data.frame(user_rows) && nrow(user_rows) > 0) {
  cat("  PASS: public.users row exists for", USER_ID, "\n")
  print(user_rows)
} else {
  cat("  FAIL: No public.users row! The FK on projects.owner_id will fail.\n")
  cat("  FIX: Insert the row manually:\n")
  cat(sprintf('    sb_post("users", list(user_id = "%s", email = "%s"), token = SVC_KEY)\n',
              USER_ID, TEST_EMAIL))
}

# ---- Verify SELECT works with user token -------------------
cat("\n============================================================\n")
cat("STEP 5: SELECT from projects with user token\n")
cat("============================================================\n")

tryCatch({
  projects <- sb_get("projects",
                     filters = list(owner_id = USER_ID),
                     token   = USER_TOKEN)
  cat("  PASS: SELECT returned", nrow(projects), "rows\n")
}, error = function(e) {
  cat("  FAIL:", e$message, "\n")
})

# ---- THE CRITICAL TEST: INSERT into projects ---------------
cat("\n============================================================\n")
cat("STEP 6: INSERT into projects with user token (THE FAILING OP)\n")
cat("============================================================\n")

tryCatch({
  new_proj <- sb_post("projects",
    list(owner_id    = USER_ID,
         title       = "Phase 3 RLS Test",
         description = "Delete me — diagnostic test"),
    token = USER_TOKEN)
  cat("  *** PASS: Project created! ***\n")
  cat("  project_id:", new_proj$project_id, "\n")

  # Clean up
  sb_delete("projects", "project_id", new_proj$project_id,
            token = USER_TOKEN)
  cat("  Cleaned up test project.\n")

}, error = function(e) {
  cat("  FAIL:", e$message, "\n\n")

  # If it failed, try with service key to rule out everything except RLS
  cat("  Trying same INSERT with SERVICE KEY (bypasses RLS)...\n")
  tryCatch({
    new_proj <- sb_post("projects",
      list(owner_id    = USER_ID,
           title       = "Phase 3 RLS Test (svc key)",
           description = "Delete me"),
      token = SVC_KEY)
    cat("  Service key INSERT succeeded -> RLS is the problem.\n")
    sb_delete("projects", "project_id", new_proj$project_id,
              token = SVC_KEY)
    cat("  Cleaned up.\n")

    cat("\n  DIAGNOSIS: The INSERT body is correct but RLS blocks it.\n")
    cat("  ACTION: Run sql/08_policies_with_custom_uid.sql which\n")
    cat("          replaces auth.uid() with current_user_id().\n")
  }, error = function(e2) {
    cat("  Service key also failed:", e2$message, "\n")
    cat("  -> Problem is NOT RLS. Check FK constraints or column types.\n")
  })
})

# ---- INSERT into project_members ---------------------------
cat("\n============================================================\n")
cat("STEP 7: INSERT into project_members (owner adds reviewer)\n")
cat("============================================================\n")

tryCatch({
  # First create a project to test with
  test_proj <- sb_post("projects",
    list(owner_id = USER_ID, title = "PM Test", description = "temp"),
    token = USER_TOKEN)
  cat("  Created test project:", test_proj$project_id, "\n")

  # Try adding a member (use the same user for simplicity)
  sb_post("project_members",
    list(project_id = test_proj$project_id,
         user_id    = USER_ID,
         role       = "owner"),
    token = USER_TOKEN)
  cat("  PASS: project_members INSERT succeeded\n")

  # Clean up
  sb_delete_where("project_members",
    filters = list(project_id = test_proj$project_id, user_id = USER_ID),
    token = USER_TOKEN)
  sb_delete("projects", "project_id", test_proj$project_id,
            token = USER_TOKEN)
  cat("  Cleaned up.\n")

}, error = function(e) {
  cat("  FAIL:", e$message, "\n")
  cat("  (This is expected to fail if Step 6 also failed.)\n")
})

cat("\n============================================================\n")
cat("DIAGNOSTIC COMPLETE\n")
cat("============================================================\n")
cat("\nIf Step 6 failed:\n")
cat("  1. Run sql/07_progressive_debug.sql Section A in Supabase SQL Editor\n")
cat("     and report ALL results.\n")
cat("  2. Then run Section C (pass-through policy) and test from R.\n")
cat("  3. Work through Sections D1-D3 to isolate the exact failure.\n")
cat("\nIf Step 6 passed: Phase 3 RLS is working! Proceed to Gate 3.\n")
