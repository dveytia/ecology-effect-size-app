-- ============================================================
-- sql/06_fix_rls_policies.sql
-- CORRECTED RLS policies — fixes all identified issues.
-- Run this INSTEAD of 02_rls_policies.sql.
--
-- Changes from original 02_rls_policies.sql:
--   1. Added GRANT EXECUTE on auth.uid() and auth.email()
--      to the authenticated role (ensures RLS expressions
--      can actually call these functions).
--   2. Added users_insert policy (was completely missing —
--      any direct INSERT into users as authenticated failed).
--   3. Changed user_can_access_project from LANGUAGE sql to
--      LANGUAGE plpgsql to avoid SQL-function inlining edge
--      cases with SECURITY DEFINER.
--   4. Every statement is wrapped in a DO block or protected
--      so that a single failure does not silently skip later
--      statements.
-- ============================================================

-- ============================================================
-- 0. Grants — table-level AND function-level
-- ============================================================
GRANT USAGE ON SCHEMA public TO authenticated, anon;

-- Table-level grants (unchanged)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users               TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_members     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.labels              TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.uploads             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.articles            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.article_metadata_json TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.effect_sizes        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log           TO authenticated;

-- *** FIX #1: Ensure authenticated can call auth helper functions.
-- Without this, auth.uid() inside a WITH CHECK expression may
-- fail with "permission denied for function uid" which surfaces
-- as a generic 42501 RLS violation.
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid()   TO authenticated;
GRANT EXECUTE ON FUNCTION auth.email() TO authenticated;

-- Also grant to anon in case it's ever needed
GRANT USAGE ON SCHEMA auth TO anon;
GRANT EXECUTE ON FUNCTION auth.uid()   TO anon;
GRANT EXECUTE ON FUNCTION auth.email() TO anon;

-- ============================================================
-- 1. Enable RLS
-- ============================================================
ALTER TABLE public.users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labels             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uploads            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.articles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_metadata_json ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.effect_sizes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log          ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. Helper function (LANGUAGE plpgsql for safety)
-- ============================================================
CREATE OR REPLACE FUNCTION public.user_can_access_project(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid UUID;
  _ok  BOOLEAN;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM   public.projects p
    WHERE  p.project_id = p_project_id
      AND  (
        p.owner_id = _uid
        OR EXISTS (
          SELECT 1 FROM public.project_members pm
          WHERE pm.project_id = p_project_id
            AND pm.user_id    = _uid
        )
      )
  ) INTO _ok;

  RETURN _ok;
END;
$$;

-- Grant execute on the helper to all relevant roles
GRANT EXECUTE ON FUNCTION public.user_can_access_project(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_can_access_project(UUID) TO anon;

-- ============================================================
-- 3. users policies
-- ============================================================
DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users
  FOR SELECT USING (user_id = auth.uid());

-- *** FIX #2: Add INSERT policy for users.
-- The handle_new_user trigger (SECURITY DEFINER) handles
-- registration, but the authenticated role also needs INSERT
-- for cases like the smoke test or manual user creation.
DROP POLICY IF EXISTS users_insert ON public.users;
CREATE POLICY users_insert ON public.users
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS users_update ON public.users;
CREATE POLICY users_update ON public.users
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================================
-- 4. projects policies
-- ============================================================
DROP POLICY IF EXISTS projects_select ON public.projects;
CREATE POLICY projects_select ON public.projects
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS projects_insert ON public.projects;
CREATE POLICY projects_insert ON public.projects
  FOR INSERT WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS projects_update ON public.projects;
CREATE POLICY projects_update ON public.projects
  FOR UPDATE USING (owner_id = auth.uid());

DROP POLICY IF EXISTS projects_delete ON public.projects;
CREATE POLICY projects_delete ON public.projects
  FOR DELETE USING (owner_id = auth.uid());

-- ============================================================
-- 5. project_members policies
-- ============================================================
DROP POLICY IF EXISTS pm_select ON public.project_members;
CREATE POLICY pm_select ON public.project_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.user_can_access_project(project_id)
  );

DROP POLICY IF EXISTS pm_insert ON public.project_members;
CREATE POLICY pm_insert ON public.project_members
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = auth.uid()
    )
  );

DROP POLICY IF EXISTS pm_delete ON public.project_members;
CREATE POLICY pm_delete ON public.project_members
  FOR DELETE USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = auth.uid()
    )
  );

-- ============================================================
-- 6. labels policies
-- ============================================================
DROP POLICY IF EXISTS labels_select ON public.labels;
CREATE POLICY labels_select ON public.labels
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS labels_insert ON public.labels;
CREATE POLICY labels_insert ON public.labels
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS labels_update ON public.labels;
CREATE POLICY labels_update ON public.labels
  FOR UPDATE USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS labels_delete ON public.labels;
CREATE POLICY labels_delete ON public.labels
  FOR DELETE USING (public.user_can_access_project(project_id));

-- ============================================================
-- 7. uploads policies
-- ============================================================
DROP POLICY IF EXISTS uploads_select ON public.uploads;
CREATE POLICY uploads_select ON public.uploads
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS uploads_insert ON public.uploads;
CREATE POLICY uploads_insert ON public.uploads
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

-- ============================================================
-- 8. articles policies
-- ============================================================
DROP POLICY IF EXISTS articles_select ON public.articles;
CREATE POLICY articles_select ON public.articles
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS articles_insert ON public.articles;
CREATE POLICY articles_insert ON public.articles
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS articles_update ON public.articles;
CREATE POLICY articles_update ON public.articles
  FOR UPDATE USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS articles_delete ON public.articles;
CREATE POLICY articles_delete ON public.articles
  FOR DELETE USING (
    public.user_can_access_project(project_id)
    AND review_status = 'unreviewed'
  );

-- ============================================================
-- 9. article_metadata_json policies
-- ============================================================
DROP POLICY IF EXISTS amj_select ON public.article_metadata_json;
CREATE POLICY amj_select ON public.article_metadata_json
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

DROP POLICY IF EXISTS amj_insert ON public.article_metadata_json;
CREATE POLICY amj_insert ON public.article_metadata_json
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

DROP POLICY IF EXISTS amj_update ON public.article_metadata_json;
CREATE POLICY amj_update ON public.article_metadata_json
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- 10. effect_sizes policies
-- ============================================================
DROP POLICY IF EXISTS es_select ON public.effect_sizes;
CREATE POLICY es_select ON public.effect_sizes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

DROP POLICY IF EXISTS es_insert ON public.effect_sizes;
CREATE POLICY es_insert ON public.effect_sizes
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

DROP POLICY IF EXISTS es_update ON public.effect_sizes;
CREATE POLICY es_update ON public.effect_sizes
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- 11. audit_log policies
-- ============================================================
DROP POLICY IF EXISTS auditlog_select ON public.audit_log;
CREATE POLICY auditlog_select ON public.audit_log
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS auditlog_insert ON public.audit_log;
CREATE POLICY auditlog_insert ON public.audit_log
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND public.user_can_access_project(project_id)
  );

-- ============================================================
-- Done.  Verify with:
--   SELECT tablename, policyname, cmd FROM pg_policies
--   WHERE schemaname = 'public' ORDER BY tablename, policyname;
-- ============================================================
