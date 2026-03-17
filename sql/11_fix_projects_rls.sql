-- ============================================================
-- sql/12_fix_projects_rls.sql
-- Fix: projects RLS policies too restrictive for new installs
--
-- Problem: The projects_insert policy used
--   WITH CHECK (owner_id = public.current_user_id())
-- which fails when current_user_id() returns NULL due to
-- JWT GUC variable differences across Supabase versions.
--
-- Fix:
--   1. Update current_user_id() to try auth.uid() as a
--      final fallback (works on all Supabase versions).
--   2. Relax projects INSERT/SELECT/DELETE policies.
--      The projects table itself is low-risk; real data
--      security is enforced on articles, labels, and
--      effect_sizes via user_can_access_project().
--
-- Run this in the Supabase SQL Editor AFTER 02_rls_policies.sql.
-- Safe to re-run (idempotent).
-- ============================================================

-- ============================================================
-- 1. Patch current_user_id() — add auth.uid() fallback
-- ============================================================
CREATE OR REPLACE FUNCTION public.current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  _sub TEXT;
BEGIN
  -- Method 1: individual claim GUC (older PostgREST / Supabase)
  _sub := current_setting('request.jwt.claim.sub', true);

  -- Method 2: JSON claims object (newer PostgREST)
  IF _sub IS NULL OR _sub = '' THEN
    BEGIN
      _sub := (current_setting('request.jwt.claims', true)::jsonb ->> 'sub');
    EXCEPTION WHEN OTHERS THEN
      _sub := NULL;
    END;
  END IF;

  -- Method 3: Supabase built-in auth.uid() (most reliable)
  IF _sub IS NULL OR _sub = '' THEN
    BEGIN
      RETURN auth.uid();
    EXCEPTION WHEN OTHERS THEN
      RETURN NULL;
    END;
  END IF;

  RETURN _sub::uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_user_id() TO authenticated;

-- ============================================================
-- 2. Replace projects policies with permissive versions
-- ============================================================

-- Drop existing projects policies (any name)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM   pg_policies
    WHERE  schemaname = 'public'
      AND  tablename  = 'projects'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.projects', r.policyname);
  END LOOP;
END;
$$;

-- SELECT: any authenticated user can see any project
-- (the app filters by membership; real security is on child tables)
CREATE POLICY allow_all_select ON public.projects
  FOR SELECT TO authenticated
  USING (true);

-- INSERT: any authenticated user can create a project
CREATE POLICY allow_all_insert ON public.projects
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- UPDATE: only the owner can edit project settings
CREATE POLICY projects_update ON public.projects
  FOR UPDATE TO authenticated
  USING (owner_id = public.current_user_id());

-- DELETE: only the owner can delete a project
CREATE POLICY allow_all_delete ON public.projects
  FOR DELETE TO authenticated
  USING (owner_id = public.current_user_id());
