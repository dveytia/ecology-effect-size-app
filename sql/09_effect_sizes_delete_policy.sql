-- ============================================================
-- sql/09_effect_sizes_delete_policy.sql
-- Adds the missing DELETE RLS policy for effect_sizes.
--
-- Without this policy, sb_delete_where("effect_sizes", ...)
-- silently deletes 0 rows (RLS filters everything out),
-- causing stale rows to accumulate and the delete-and-reinsert
-- save pattern to fail.
-- ============================================================

DROP POLICY IF EXISTS es_delete ON public.effect_sizes;

CREATE POLICY es_delete ON public.effect_sizes
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.articles a
      WHERE a.article_id = effect_sizes.article_id
        AND public.user_can_access_project(a.project_id)
    )
  );
