-- ============================================================
-- sql/07_progressive_debug.sql
-- Progressive INSERT debugging for Phase 3 RLS 42501 error
--
-- Run EACH section one at a time in Supabase SQL Editor and
-- then immediately test the INSERT from R between sections.
-- This isolates exactly which part of the policy expression
-- is failing.
-- ============================================================

-- ============================================================
-- SECTION A: State check — run this first, report ALL results
-- ============================================================

-- A1. What does auth.uid() actually look like? (from SQL editor = superuser context)
SELECT pg_get_functiondef(oid) AS auth_uid_definition
FROM   pg_proc
WHERE  proname = 'uid'
  AND  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'auth');

-- A2. Can the 'authenticated' role execute auth.uid()?
SELECT has_function_privilege('authenticated', 'auth.uid()', 'EXECUTE')
  AS auth_can_call_uid;

-- A3. All policies currently on projects (look for RESTRICTIVE ones!)
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'projects'
ORDER BY policyname;

-- A4. Grants on projects for authenticated
SELECT grantee, privilege_type
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'projects'
  AND  grantee      = 'authenticated';

-- A5. Check for any triggers on the projects table
SELECT trigger_name, event_manipulation, action_statement
FROM   information_schema.triggers
WHERE  event_object_schema = 'public'
  AND  event_object_table  = 'projects';


-- ============================================================
-- SECTION B: Simulate PostgREST context (SET ROLE authenticated)
--
-- Run this as a SINGLE block.  This is exactly what PostgREST
-- does when it receives an INSERT request.
-- ============================================================

DO $$
DECLARE
  _uid  UUID;
  _test UUID;
BEGIN
  -- Simulate PostgREST: switch to authenticated and set JWT claims
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub',
                     '564c9186-f70d-47f2-b285-55baee74f705', true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"564c9186-f70d-47f2-b285-55baee74f705","role":"authenticated","aud":"authenticated"}',
    true);

  SET LOCAL ROLE authenticated;

  -- Check what auth.uid() returns in this context
  _uid := auth.uid();
  RAISE NOTICE 'auth.uid() = %', _uid;

  IF _uid IS NULL THEN
    RAISE NOTICE 'PROBLEM: auth.uid() returned NULL in authenticated context!';
  ELSIF _uid::text = '564c9186-f70d-47f2-b285-55baee74f705' THEN
    RAISE NOTICE 'auth.uid() matches expected UUID';
  ELSE
    RAISE NOTICE 'PROBLEM: auth.uid() returned unexpected value: %', _uid;
  END IF;

  -- Try the actual INSERT
  BEGIN
    INSERT INTO public.projects (owner_id, title, description)
    VALUES ('564c9186-f70d-47f2-b285-55baee74f705'::uuid,
            'SIMULATION TEST', 'delete me')
    RETURNING project_id INTO _test;

    RAISE NOTICE 'INSERT SUCCEEDED! project_id = %', _test;

    -- Clean up
    DELETE FROM public.projects WHERE project_id = _test;
    RAISE NOTICE 'Cleaned up test project.';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'INSERT FAILED with 42501 (insufficient_privilege)';
    RAISE NOTICE 'auth.uid() was % during the attempt', _uid;
  END;

  RESET ROLE;
END;
$$;


-- ============================================================
-- SECTION C: If Section B's INSERT also failed, run this.
-- It replaces the projects_insert policy with one that always
-- passes, to confirm the mechanism works at all.
--
-- After running this, retry the INSERT from R.
-- If it works → the policy expression is the problem.
-- If it still fails → something else is blocking the INSERT.
-- ============================================================

-- C1. Drop the real policy and add a pass-everything policy
DROP POLICY IF EXISTS projects_insert ON public.projects;
CREATE POLICY projects_insert_debug ON public.projects
  FOR INSERT WITH CHECK (true);

-- >>> NOW TEST FROM R: <<<
-- source("R/utils.R"); source("R/supabase.R"); readRenviron(".Renviron")
-- auth <- sb_auth_login("YOUR_EMAIL", "YOUR_PASSWORD")
-- sb_post("projects", list(owner_id = auth$user$id, title = "Test C"), token = auth$access_token)
--
-- If this WORKS → proceed to Section D.
-- If this FAILS → the issue is NOT the policy expression at all.
--                 Check grants and table structure.


-- ============================================================
-- SECTION D: Narrow down — is auth.uid() NULL or is it a type
-- mismatch?  Run this AFTER Section C succeeds.
-- ============================================================

-- D1. Policy that only checks auth.uid() IS NOT NULL
DROP POLICY IF EXISTS projects_insert_debug ON public.projects;
CREATE POLICY projects_insert_debug ON public.projects
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- >>> TEST FROM R AGAIN <<<
-- If this WORKS → auth.uid() is NOT NULL.  Proceed to D2.
-- If this FAILS → auth.uid() IS NULL during policy evaluation.
--                 The GRANT EXECUTE on auth.uid() is not working.
--                 See Section F below.


-- D2. Policy that checks auth.uid() = a hardcoded UUID
--     (YOUR actual user UUID)
DROP POLICY IF EXISTS projects_insert_debug ON public.projects;
CREATE POLICY projects_insert_debug ON public.projects
  FOR INSERT WITH CHECK (
    auth.uid() = '564c9186-f70d-47f2-b285-55baee74f705'::uuid
  );

-- >>> TEST FROM R AGAIN <<<
-- If this WORKS → auth.uid() returns the right value and
--                 comparison works.  The original policy
--                 (owner_id = auth.uid()) should also work.
-- If this FAILS → type mismatch or auth.uid() returns a
--                 different UUID than expected.


-- D3. Policy that checks owner_id = hardcoded UUID
--     (bypasses auth.uid() entirely)
DROP POLICY IF EXISTS projects_insert_debug ON public.projects;
CREATE POLICY projects_insert_debug ON public.projects
  FOR INSERT WITH CHECK (
    owner_id = '564c9186-f70d-47f2-b285-55baee74f705'::uuid
  );

-- >>> TEST FROM R AGAIN <<<
-- If this WORKS + D2 WORKS → the comparison works fine.
--                             Restore original policy (Section E).
-- If this WORKS + D2 FAILS → auth.uid() is the problem.


-- ============================================================
-- SECTION E: Restore the real policy (run after debugging)
-- ============================================================

DROP POLICY IF EXISTS projects_insert_debug ON public.projects;
DROP POLICY IF EXISTS projects_insert ON public.projects;
CREATE POLICY projects_insert ON public.projects
  FOR INSERT WITH CHECK (owner_id = auth.uid());


-- ============================================================
-- SECTION F: Nuclear option — if auth.uid() returns NULL
-- during policy evaluation but works in RPC
-- ============================================================

-- This can happen if there are MULTIPLE overloads of auth.uid()
-- and the policy resolves to the wrong one. Check:
SELECT p.oid, p.proname, p.proargtypes, p.prorettype::regtype,
       p.prosecdef, p.provolatile
FROM   pg_proc p
JOIN   pg_namespace n ON p.pronamespace = n.oid
WHERE  n.nspname = 'auth' AND p.proname = 'uid';

-- If there are multiple rows, the GRANT may have applied to
-- the wrong overload.  Grant to all of them:
-- (uncomment and run if needed)
-- DO $$
-- DECLARE r RECORD;
-- BEGIN
--   FOR r IN
--     SELECT p.oid
--     FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
--     WHERE n.nspname = 'auth' AND p.proname = 'uid'
--   LOOP
--     EXECUTE format('GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated');
--   END LOOP;
-- END $$;


-- ============================================================
-- SECTION G: Alternative — bypass auth.uid() entirely with a
-- custom claims-reading function that we KNOW works
-- ============================================================

-- Create our own function that reads the JWT sub claim directly
CREATE OR REPLACE FUNCTION public.current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  _sub TEXT;
BEGIN
  -- Try the flat claim first (PostgREST v10+)
  _sub := current_setting('request.jwt.claim.sub', true);

  -- Fall back to the JSON blob (older PostgREST)
  IF _sub IS NULL OR _sub = '' THEN
    _sub := (current_setting('request.jwt.claims', true)::jsonb ->> 'sub');
  END IF;

  IF _sub IS NULL OR _sub = '' THEN
    RETURN NULL;
  END IF;

  RETURN _sub::uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_id() TO anon;

-- Test it: uncomment and run after creating the function
-- SET LOCAL ROLE authenticated;
-- SELECT set_config('request.jwt.claim.sub',
--   '564c9186-f70d-47f2-b285-55baee74f705', true);
-- SELECT public.current_user_id();
-- RESET ROLE;

-- If current_user_id() works, replace ALL policies that use
-- auth.uid() with public.current_user_id() instead.
-- See sql/08_policies_with_custom_uid.sql
