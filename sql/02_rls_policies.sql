-- ============================================================
-- sql/02_rls_policies.sql
-- Row-Level Security policies for all tables
-- Run AFTER 01_create_tables.sql in the Supabase SQL Editor
--
-- IMPORTANT: Every policy explicitly targets TO authenticated.
-- Omitting TO (which defaults to PUBLIC) causes Supabase
-- PostgREST to reject writes with 42501 even when the
-- WITH CHECK expression is correct.
--
-- Uses public.current_user_id() instead of auth.uid() to
-- read the JWT sub claim directly from PostgREST GUC variables.
-- ============================================================

-- ============================================================
-- 0. Grants
-- ============================================================
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT USAGE ON SCHEMA auth   TO authenticated, anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.users               TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_members     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.labels              TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.uploads             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.articles            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.article_metadata_json TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.effect_sizes        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log           TO authenticated;

-- ============================================================
-- 1. Cleanup: drop ALL existing policies on managed tables
-- ============================================================
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM   pg_policies
    WHERE  schemaname = 'public'
      AND  tablename IN (
        'users','projects','project_members','labels',
        'uploads','articles','article_metadata_json',
        'effect_sizes','audit_log'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  END LOOP;
END;
$$;

-- ============================================================
-- 2. Enable RLS
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
-- 3. Custom UID function — reads JWT sub claim directly from
--    PostgREST GUC variables
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
  _sub := current_setting('request.jwt.claim.sub', true);
  IF _sub IS NULL OR _sub = '' THEN
    BEGIN
      _sub := (current_setting('request.jwt.claims', true)::jsonb ->> 'sub');
    EXCEPTION WHEN OTHERS THEN
      _sub := NULL;
    END;
  END IF;
  IF _sub IS NULL OR _sub = '' THEN
    RETURN NULL;
  END IF;
  RETURN _sub::uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.current_user_id() TO authenticated;

-- ============================================================
-- 4. Helper: project access check
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
  _uid := public.current_user_id();
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

GRANT EXECUTE ON FUNCTION public.user_can_access_project(UUID) TO authenticated;

-- ============================================================
-- 5. users — TO authenticated
-- ============================================================
CREATE POLICY users_select ON public.users
  FOR SELECT TO authenticated
  USING (user_id = public.current_user_id());

CREATE POLICY users_insert ON public.users
  FOR INSERT TO authenticated
  WITH CHECK (user_id = public.current_user_id());

CREATE POLICY users_update ON public.users
  FOR UPDATE TO authenticated
  USING (user_id = public.current_user_id());

-- ============================================================
-- 6. projects — TO authenticated
-- ============================================================
CREATE POLICY projects_select ON public.projects
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY projects_insert ON public.projects
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = public.current_user_id());

CREATE POLICY projects_update ON public.projects
  FOR UPDATE TO authenticated
  USING (owner_id = public.current_user_id());

CREATE POLICY projects_delete ON public.projects
  FOR DELETE TO authenticated
  USING (owner_id = public.current_user_id());

-- ============================================================
-- 7. project_members — TO authenticated
-- ============================================================
CREATE POLICY pm_select ON public.project_members
  FOR SELECT TO authenticated
  USING (
    user_id = public.current_user_id()
    OR public.user_can_access_project(project_id)
  );

CREATE POLICY pm_insert ON public.project_members
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = public.current_user_id()
    )
  );

CREATE POLICY pm_delete ON public.project_members
  FOR DELETE TO authenticated
  USING (
    user_id = public.current_user_id()
    OR EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = public.current_user_id()
    )
  );

-- ============================================================
-- 8. labels — TO authenticated
-- ============================================================
CREATE POLICY labels_select ON public.labels
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY labels_insert ON public.labels
  FOR INSERT TO authenticated
  WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY labels_update ON public.labels
  FOR UPDATE TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY labels_delete ON public.labels
  FOR DELETE TO authenticated
  USING (public.user_can_access_project(project_id));

-- ============================================================
-- 9. uploads — TO authenticated
-- ============================================================
CREATE POLICY uploads_select ON public.uploads
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY uploads_insert ON public.uploads
  FOR INSERT TO authenticated
  WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY uploads_update ON public.uploads
  FOR UPDATE TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY uploads_delete ON public.uploads
  FOR DELETE TO authenticated
  USING (public.user_can_access_project(project_id));

-- ============================================================
-- 10. articles — TO authenticated
-- ============================================================
CREATE POLICY articles_select ON public.articles
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY articles_insert ON public.articles
  FOR INSERT TO authenticated
  WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY articles_update ON public.articles
  FOR UPDATE TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY articles_delete ON public.articles
  FOR DELETE TO authenticated
  USING (
    public.user_can_access_project(project_id)
    AND review_status IN ('unreviewed', 'skipped')
  );

-- ============================================================
-- 11. article_metadata_json — TO authenticated
-- ============================================================
CREATE POLICY amj_select ON public.article_metadata_json
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY amj_insert ON public.article_metadata_json
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY amj_update ON public.article_metadata_json
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- 12. effect_sizes — TO authenticated
-- ============================================================
CREATE POLICY es_select ON public.effect_sizes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY es_insert ON public.effect_sizes
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY es_update ON public.effect_sizes
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- 13. audit_log — TO authenticated
-- ============================================================
CREATE POLICY auditlog_select ON public.audit_log
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY auditlog_insert ON public.audit_log
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.current_user_id()
    AND public.user_can_access_project(project_id)
  );

-- ============================================================
-- Verification: list all policies to confirm TO authenticated
-- ============================================================
SELECT tablename, policyname, permissive, roles, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
ORDER BY tablename, policyname;