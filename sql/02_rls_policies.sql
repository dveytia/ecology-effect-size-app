-- ============================================================
-- sql/02_rls_policies.sql
-- Row-Level Security policies for all tables
-- Run AFTER 01_create_tables.sql in the Supabase SQL Editor
-- ============================================================

-- ---- Enable RLS on every table ----------------------------
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
-- Helper: check if a project is accessible to the current user
-- (owner OR member)
-- ============================================================
CREATE OR REPLACE FUNCTION public.user_can_access_project(p_project_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   public.projects p
    WHERE  p.project_id = p_project_id
      AND  (
        p.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.project_members pm
          WHERE pm.project_id = p_project_id
            AND pm.user_id    = auth.uid()
        )
      )
  );
$$;

-- ============================================================
-- users: each user sees only their own row
-- ============================================================
CREATE POLICY users_select ON public.users
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY users_update ON public.users
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================================
-- projects
-- ============================================================
CREATE POLICY projects_select ON public.projects
  FOR SELECT USING (public.user_can_access_project(project_id));

CREATE POLICY projects_insert ON public.projects
  FOR INSERT WITH CHECK (owner_id = auth.uid());

CREATE POLICY projects_update ON public.projects
  FOR UPDATE USING (owner_id = auth.uid());

CREATE POLICY projects_delete ON public.projects
  FOR DELETE USING (owner_id = auth.uid());

-- ============================================================
-- project_members
-- ============================================================
CREATE POLICY pm_select ON public.project_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.user_can_access_project(project_id)
  );

CREATE POLICY pm_insert ON public.project_members
  FOR INSERT WITH CHECK (
    -- Only the project owner can add members
    EXISTS (
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = auth.uid()
    )
  );

CREATE POLICY pm_delete ON public.project_members
  FOR DELETE USING (
    user_id = auth.uid()     -- member can leave
    OR EXISTS (              -- or owner can remove
      SELECT 1 FROM public.projects
      WHERE project_id = project_members.project_id
        AND owner_id   = auth.uid()
    )
  );

-- ============================================================
-- labels
-- ============================================================
CREATE POLICY labels_select ON public.labels
  FOR SELECT USING (public.user_can_access_project(project_id));

CREATE POLICY labels_insert ON public.labels
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY labels_update ON public.labels
  FOR UPDATE USING (public.user_can_access_project(project_id));

CREATE POLICY labels_delete ON public.labels
  FOR DELETE USING (public.user_can_access_project(project_id));

-- ============================================================
-- uploads
-- ============================================================
CREATE POLICY uploads_select ON public.uploads
  FOR SELECT USING (public.user_can_access_project(project_id));

CREATE POLICY uploads_insert ON public.uploads
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

-- ============================================================
-- articles
-- ============================================================
CREATE POLICY articles_select ON public.articles
  FOR SELECT USING (public.user_can_access_project(project_id));

CREATE POLICY articles_insert ON public.articles
  FOR INSERT WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY articles_update ON public.articles
  FOR UPDATE USING (public.user_can_access_project(project_id));

CREATE POLICY articles_delete ON public.articles
  FOR DELETE USING (
    public.user_can_access_project(project_id)
    AND review_status = 'unreviewed'   -- reviewed articles cannot be deleted
  );

-- ============================================================
-- article_metadata_json (linked via article_id → articles)
-- ============================================================
CREATE POLICY amj_select ON public.article_metadata_json
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY amj_insert ON public.article_metadata_json
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY amj_update ON public.article_metadata_json
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = article_metadata_json.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- effect_sizes (linked via article_id → articles)
-- ============================================================
CREATE POLICY es_select ON public.effect_sizes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY es_insert ON public.effect_sizes
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

CREATE POLICY es_update ON public.effect_sizes
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );

-- ============================================================
-- audit_log
-- READ: any project member; WRITE: any project member
-- ============================================================
CREATE POLICY auditlog_select ON public.audit_log
  FOR SELECT USING (public.user_can_access_project(project_id));

CREATE POLICY auditlog_insert ON public.audit_log
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND public.user_can_access_project(project_id)
  );
