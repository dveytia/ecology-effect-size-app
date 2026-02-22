-- ============================================================
-- sql/05_diagnostic.sql
-- Run this in Supabase SQL Editor to diagnose RLS issues.
-- It checks every component that must be correct for the
-- Phase 3 INSERT to succeed.
-- ============================================================

-- 1. Verify auth.uid() works in the current session
--    (When run in SQL Editor you are superuser, so this shows
--     the function definition rather than a real JWT value.)
SELECT auth.uid() AS current_auth_uid;

-- 2. Check that the authenticated role has EXECUTE on auth.uid()
SELECT has_function_privilege('authenticated', 'auth.uid()', 'EXECUTE')
  AS authenticated_can_call_auth_uid;

-- 3. Check that RLS is enabled on all Phase 3 tables
SELECT tablename,
       rowsecurity AS rls_enabled
FROM   pg_tables
WHERE  schemaname = 'public'
  AND  tablename IN ('users','projects','project_members')
ORDER BY tablename;

-- 4. List ALL policies on the three Phase 3 tables
SELECT schemaname, tablename, policyname, permissive,
       roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('users','projects','project_members')
ORDER BY tablename, policyname;

-- 5. Check grants on the three Phase 3 tables for 'authenticated'
SELECT grantee, table_name, privilege_type
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name IN ('users','projects','project_members')
  AND  grantee = 'authenticated'
ORDER BY table_name, privilege_type;

-- 6. Verify user_can_access_project function exists
SELECT proname, prosecdef, prolang, proowner::regrole
FROM   pg_proc
WHERE  proname = 'user_can_access_project'
  AND  pronamespace = 'public'::regnamespace;

-- 7. Verify handle_new_user trigger function exists
SELECT proname, prosecdef, proowner::regrole
FROM   pg_proc
WHERE  proname = 'handle_new_user'
  AND  pronamespace = 'public'::regnamespace;

-- 8. Verify the trigger on auth.users exists
SELECT trigger_name, event_manipulation, action_timing
FROM   information_schema.triggers
WHERE  trigger_name = 'on_auth_user_created';

-- 9. Check that public.users has at least one row for your test user
--    (replace with your UUID if needed)
SELECT user_id, email, created_at
FROM   public.users
LIMIT 5;

-- 10. Simulate exact INSERT context for 'authenticated' role
--     Replace <YOUR-USER-UUID> with the UUID from step 9
--     This reproduces what PostgREST does when it receives a POST.
/*
  -- Uncomment and fill in to run:
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claim.sub = '<YOUR-USER-UUID>';
  SET LOCAL request.jwt.claims = '{"sub":"<YOUR-USER-UUID>","role":"authenticated"}';

  SELECT auth.uid() AS simulated_uid;

  INSERT INTO public.projects (owner_id, title, description)
  VALUES (
    '<YOUR-USER-UUID>'::uuid,
    'RLS Diagnostic Test',
    'Delete me after testing'
  )
  RETURNING project_id, owner_id;

  RESET ROLE;
*/
