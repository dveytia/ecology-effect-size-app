-- ============================================================
-- sql/12_reviewer_presence.sql
-- Reviewer presence tracking for the Review tab
-- ============================================================

CREATE TABLE IF NOT EXISTS public.reviewer_presence (
  project_id         UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  user_id            UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  reviewer_label     TEXT,
  current_article_id UUID REFERENCES public.articles(article_id) ON DELETE SET NULL,
  last_seen          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (project_id, user_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.reviewer_presence TO authenticated;

ALTER TABLE public.reviewer_presence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reviewer_presence_select ON public.reviewer_presence;
CREATE POLICY reviewer_presence_select ON public.reviewer_presence
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

DROP POLICY IF EXISTS reviewer_presence_insert ON public.reviewer_presence;
CREATE POLICY reviewer_presence_insert ON public.reviewer_presence
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.current_user_id()
    AND public.user_can_access_project(project_id)
  );

DROP POLICY IF EXISTS reviewer_presence_update ON public.reviewer_presence;
CREATE POLICY reviewer_presence_update ON public.reviewer_presence
  FOR UPDATE TO authenticated
  USING (
    user_id = public.current_user_id()
    AND public.user_can_access_project(project_id)
  );

DROP POLICY IF EXISTS reviewer_presence_delete ON public.reviewer_presence;
CREATE POLICY reviewer_presence_delete ON public.reviewer_presence
  FOR DELETE TO authenticated
  USING (
    user_id = public.current_user_id()
    AND public.user_can_access_project(project_id)
  );

CREATE INDEX IF NOT EXISTS idx_reviewer_presence_project_last_seen
  ON public.reviewer_presence(project_id, last_seen DESC);
