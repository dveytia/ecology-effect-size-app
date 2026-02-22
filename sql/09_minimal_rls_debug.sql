-- ============================================================
-- sql/09_minimal_rls_debug.sql
-- MINIMAL isolation test — run each section one at a time
-- and report the output BEFORE proceeding to the next section.
-- ============================================================

-- ================================================================
-- SECTION A: What policies ACTUALLY exist right now on projects?
-- Run this FIRST and report EVERY row.
-- ================================================================
SELECT policyname, permissive, roles, cmd, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'projects'
ORDER BY policyname;

-- ================================================================
-- SECTION B: Does current_user_id() exist and work?
-- ================================================================
-- B1: Does the function exist?
SELECT proname, prorettype::regtype, prosrc
FROM   pg_proc
WHERE  proname = 'current_user_id'
  AND  pronamespace = 'public'::regnamespace;

-- B2: Test it in authenticated context
DO $$
DECLARE _uid UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
    '564c9186-f70d-47f2-b285-55baee74f705', true);
  SET LOCAL ROLE authenticated;
  _uid := public.current_user_id();
  RAISE NOTICE 'current_user_id() = %', _uid;
  RESET ROLE;
END;
$$;

-- ================================================================
-- SECTION C: Nuclear test — drop ALL policies on projects,
-- create ONE trivial policy, test INSERT from R.
--
-- Run this, then IMMEDIATELY test from R console:
--   source("R/utils.R"); source("R/supabase.R"); readRenviron(".Renviron")
--   a <- sb_auth_login("deviveytia@hotmail.com", "YOUR_PASSWORD")
--   sb_post("projects", list(owner_id=a$user$id, title="TEST"), token=a$access_token)
-- ================================================================

-- C1: Drop EVERY policy on projects (not just named ones)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'projects'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.projects', r.policyname);
    RAISE NOTICE 'Dropped policy: %', r.policyname;
  END LOOP;
END;
$$;

-- C2: Verify all policies are gone
SELECT count(*) AS remaining_policies
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename = 'projects';
-- Should return 0

-- C3: Create ONE policy that allows everything
CREATE POLICY allow_all_insert ON public.projects
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY allow_all_select ON public.projects
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY allow_all_delete ON public.projects
  FOR DELETE TO authenticated
  USING (true);

-- C4: Verify grants exist
SELECT has_table_privilege('authenticated', 'public.projects', 'INSERT') AS can_insert,
       has_table_privilege('authenticated', 'public.projects', 'SELECT') AS can_select,
       has_table_privilege('authenticated', 'public.projects', 'DELETE') AS can_delete;

-- C5: List what we have now
SELECT policyname, permissive, roles, cmd, with_check
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename = 'projects';

-- >>> NOW TEST FROM R <<<
-- If this works → the problem was in the policy expression.
-- If this STILL fails → the problem is NOT the policy. It's either:
--    (a) grants, (b) a trigger blocking the insert, (c) FK constraint,
--    or (d) PostgREST not using the 'authenticated' role at all.


-- ================================================================
-- SECTION D: If Section C STILL fails, run this to check
-- what role PostgREST is actually using.
-- Add a logging trigger to projects to capture the role.
-- ================================================================

-- D1: Create a debug log table
CREATE TABLE IF NOT EXISTS public._debug_log (
  id SERIAL PRIMARY KEY,
  ts TIMESTAMPTZ DEFAULT now(),
  current_role TEXT,
  current_user_name TEXT,
  jwt_sub TEXT,
  jwt_claims TEXT
);
GRANT ALL ON public._debug_log TO authenticated, anon;
ALTER TABLE public._debug_log DISABLE ROW LEVEL SECURITY;

-- D2: Create a BEFORE INSERT trigger that logs context
CREATE OR REPLACE FUNCTION public._debug_projects_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  INSERT INTO public._debug_log (current_role, current_user_name, jwt_sub, jwt_claims)
  VALUES (
    current_setting('role', true),
    current_user::text,
    current_setting('request.jwt.claim.sub', true),
    current_setting('request.jwt.claims', true)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS debug_projects_insert ON public.projects;
CREATE TRIGGER debug_projects_insert
  BEFORE INSERT ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION public._debug_projects_insert();

-- >>> NOW TRY THE INSERT FROM R AGAIN <<<
-- Then check what was logged:
-- SELECT * FROM public._debug_log ORDER BY ts DESC LIMIT 5;
--
-- This will show:
--   current_role: should be 'authenticated'
--   jwt_sub: should be your UUID
-- If jwt_sub is NULL → PostgREST is not setting the GUC variables
-- If current_role is 'anon' → PostgREST is ignoring your JWT


-- ================================================================
-- SECTION E: Alternative — try inserting via RPC to bypass
-- PostgREST's RLS entirely
-- ================================================================

CREATE OR REPLACE FUNCTION public.create_project(
  p_title TEXT,
  p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid UUID;
  _pid UUID;
BEGIN
  -- Get user ID from JWT
  _uid := public.current_user_id();

  IF _uid IS NULL THEN
    -- Fallback to auth.uid()
    _uid := auth.uid();
  END IF;

  IF _uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated: both current_user_id() and auth.uid() returned NULL';
  END IF;

  INSERT INTO public.projects (owner_id, title, description)
  VALUES (_uid, p_title, p_description)
  RETURNING project_id INTO _pid;

  RETURN _pid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_project(TEXT, TEXT) TO authenticated;

-- Test from R:
-- pid <- sb_rpc("create_project",
--               list(p_title = "RPC Test", p_description = "test"),
--               token = USER_TOKEN)
-- cat("Created via RPC:", pid, "\n")


-- ================================================================
-- SECTION F: Cleanup (run after debugging is complete)
-- ================================================================
-- DROP TRIGGER IF EXISTS debug_projects_insert ON public.projects;
-- DROP FUNCTION IF EXISTS public._debug_projects_insert();
-- DROP TABLE IF EXISTS public._debug_log;
-- Then re-run sql/08_policies_with_custom_uid.sql to restore real policies.
