-- ============================================================
-- sql/06_phase5_rls_patch.sql
-- Patch missing RLS policies exposed during Phase 5 testing
-- Run in Supabase SQL Editor after 02_rls_policies.sql
-- ============================================================

-- 1. uploads — add DELETE policy (was missing; blocked batch deletion)
DROP POLICY IF EXISTS uploads_delete ON public.uploads;
CREATE POLICY uploads_delete ON public.uploads
  FOR DELETE TO authenticated
  USING (public.user_can_access_project(project_id));

-- 2. uploads — add UPDATE policy (needed for Phase 6 Drive sync timestamp)
DROP POLICY IF EXISTS uploads_update ON public.uploads;
CREATE POLICY uploads_update ON public.uploads
  FOR UPDATE TO authenticated
  USING (public.user_can_access_project(project_id));

-- 3. articles — expand DELETE to also allow deleting 'skipped' articles
--    (skipped articles have no coded data; treating them like unreviewed
--     for the purpose of batch cleanup is safe)
DROP POLICY IF EXISTS articles_delete ON public.articles;
CREATE POLICY articles_delete ON public.articles
  FOR DELETE TO authenticated
  USING (
    public.user_can_access_project(project_id)
    AND review_status IN ('unreviewed', 'skipped')
  );
