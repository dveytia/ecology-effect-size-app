-- ============================================================
-- sql/08_policies_with_custom_uid.sql
-- FULL replacement for 02/06_rls_policies.sql
--
-- Uses public.current_user_id() instead of auth.uid() to
-- completely bypass any permission/resolution issues with the
-- auth schema functions.
--
-- Run this if Section D of 07_progressive_debug.sql revealed
-- that auth.uid() returns NULL during policy evaluation.
-- ============================================================

-- ============================================================
-- 0. Grants
-- ============================================================
GRANT USAGE ON SCHEMA public TO authenticated, anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.users               TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_members     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.labels              TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.uploads             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.articles            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.article_metadata_json TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.effect_sizes        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.audit_log           TO authenticated;

-- Also ensure auth schema access (belt and suspenders)
GRANT USAGE ON SCHEMA auth TO authenticated, anon;

-- ============================================================
-- 1. Custom UID function — reads JWT sub claim directly from
--    PostgREST GUC variables, avoiding auth.uid() entirely.
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
  -- PostgREST v10+ sets individual claim keys
  _sub := current_setting('request.jwt.claim.sub', true);

  -- Fallback: older PostgREST puts all claims in one JSON blob
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
GRANT EXECUTE ON FUNCTION public.current_user_id() TO anon;

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
-- 3. Helper function — uses current_user_id() internally
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
GRANT EXECUTE ON FUNCTION public.user_can_access_project(UUID) TO anon;

-- ============================================================
-- 4. users policies
-- ============================================================
DROP POLICY IF EXISTS users_select ON public.users;
CREATE POLICY users_select ON public.users
  FOR SELECT USING (user_id = public.current_user_id());

DROP POLICY IF EXISTS users_insert ON public.users;
CREATE POLICY users_insert ON public.users
  FOR INSERT WITH CHECK (user_id = public.current_user_id());

DROP POLICY IF EXISTS users_update ON public.users;
CREATE POLICY users_update ON public.users
  FOR UPDATE USING (user_id = public.current_user_id());

-- ============================================================
-- 5. projects policies
-- ============================================================

-- Also drop any leftover debug policies
DROP POLICY IF EXISTS projects_insert_debug ON public.projects;

DROP POLICY IF EXISTS projects_select ON public.projects;
CREATE POLICY projects_select ON public.projects
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS projects_insert ON public.projects;
CREATE POLICY projects_insert ON public.projects
  FOR INSERT WITH CHECK (owner_id = public.current_user_id());

DROP POLICY IF EXISTS projects_update ON public.projects;
CREATE POLICY projects_update ON public.projects
  FOR UPDATE USING (owner_id = public.current_user_id());

DROP POLICY IF EXISTS projects_delete ON public.projects;
CREATE POLICY projects_delete ON public.projects
  FOR DELETE USING (owner_id = public.current_user_id());

-- ============================================================
-- 6. project_members policies
-- ============================================================
DROP POLICY IF EXISTS pm_select ON public.project_members;
CREATE POLICY pm_select ON public.project_members
  FOR SELECT USING (
    user_id = public.current_user_id()
    OR public.user_can_access_project(project_id)
  );

DROP POLICY IF EXISTS pm_insert ON public.project_members;
CREATE POLICY pm_insert ON public.project_members
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = public.current_user_id()
    )
  );

DROP POLICY IF EXISTS pm_delete ON public.project_members;
CREATE POLICY pm_delete ON public.project_members
  FOR DELETE USING (
    user_id = public.current_user_id()
    OR EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = public.current_user_id()
    )
  );

-- ============================================================
-- 7. labels policies
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
-- 8. uploads policies
-- ============================================================
DROP POLICY IF EXISTS uploads_select ON public.uploads;
CREATE POLICY uploads_select ON public.uploads
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS uploads_insert ON public.uploads;
CREATE POLICY uploads_insert ON public.uploads
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

-- ============================================================
-- 9. articles policies
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
-- 10. article_metadata_json policies
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
-- 11. effect_sizes policies
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
-- 12. audit_log policies
-- ============================================================
DROP POLICY IF EXISTS auditlog_select ON public.audit_log;
CREATE POLICY auditlog_select ON public.audit_log
  FOR SELECT USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS auditlog_insert ON public.audit_log;
CREATE POLICY auditlog_insert ON public.audit_log
  FOR INSERT WITH CHECK (
    user_id = public.current_user_id()
    AND public.user_can_access_project(project_id)
  );

-- ============================================================
-- Smoke test: verify current_user_id works in SET ROLE context
-- ============================================================
DO $$
DECLARE
  _uid UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
    '564c9186-f70d-47f2-b285-55baee74f705', true);
  SET LOCAL ROLE authenticated;

  _uid := public.current_user_id();
  RAISE NOTICE 'current_user_id() = %', _uid;

  IF _uid IS NULL THEN
    RAISE WARNING 'current_user_id() returned NULL — check PostgREST GUC configuration!';
  ELSE
    RAISE NOTICE 'current_user_id() works correctly.';
  END IF;

  RESET ROLE;
END;
$$;
