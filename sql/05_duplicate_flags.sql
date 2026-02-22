-- ============================================================
-- sql/05_duplicate_flags.sql
-- Persistent duplicate flag queue for article upload (Phase 5)
-- Run in Supabase SQL Editor AFTER 01_create_tables.sql
-- ============================================================

-- ------------------------------------------------------------
-- Table: duplicate_flags
-- Stores incoming CSV rows that matched an existing article
-- during upload. The reviewer resolves each flag (accept /
-- reject) from the Upload History tab.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.duplicate_flags (
  flag_id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  upload_batch_id    UUID        NOT NULL REFERENCES public.uploads(upload_batch_id) ON DELETE CASCADE,
  project_id         UUID        NOT NULL REFERENCES public.projects(project_id)    ON DELETE CASCADE,
  article_data       JSONB       NOT NULL,  -- incoming row: title, abstract, author, year, doi_clean
  matched_article_id UUID        REFERENCES public.articles(article_id) ON DELETE SET NULL,
  match_type         TEXT        NOT NULL
                     CHECK (match_type IN ('exact_doi','title_year','partial_doi','fuzzy')),
  similarity_score   NUMERIC,
  status             TEXT        NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','accepted','rejected')),
  resolved_at        TIMESTAMPTZ,
  resolved_by        UUID        REFERENCES public.users(user_id),
  note               TEXT
);

-- Grant access to authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON public.duplicate_flags TO authenticated;

-- Enable RLS
ALTER TABLE public.duplicate_flags ENABLE ROW LEVEL SECURITY;

-- RLS policies: project members only
CREATE POLICY dup_flags_select ON public.duplicate_flags
  FOR SELECT TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY dup_flags_insert ON public.duplicate_flags
  FOR INSERT TO authenticated
  WITH CHECK (public.user_can_access_project(project_id));

CREATE POLICY dup_flags_update ON public.duplicate_flags
  FOR UPDATE TO authenticated
  USING (public.user_can_access_project(project_id));

CREATE POLICY dup_flags_delete ON public.duplicate_flags
  FOR DELETE TO authenticated
  USING (public.user_can_access_project(project_id));

-- Index for fast lookup by upload batch and status
CREATE INDEX IF NOT EXISTS idx_dup_flags_batch
  ON public.duplicate_flags (upload_batch_id);

CREATE INDEX IF NOT EXISTS idx_dup_flags_project_status
  ON public.duplicate_flags (project_id, status);
