-- ============================================================
-- sql/04_indexes.sql
-- Performance indexes
-- Run after 01_create_tables.sql
-- ============================================================

-- projects: look up by owner
CREATE INDEX IF NOT EXISTS idx_projects_owner_id
  ON public.projects(owner_id);

-- project_members: look up all members of a project
CREATE INDEX IF NOT EXISTS idx_project_members_project_id
  ON public.project_members(project_id);

-- project_members: look up all projects a user belongs to
CREATE INDEX IF NOT EXISTS idx_project_members_user_id
  ON public.project_members(user_id);

-- articles: filter by project (primary query pattern)
CREATE INDEX IF NOT EXISTS idx_articles_project_id
  ON public.articles(project_id);

-- articles: duplicate detection by DOI
CREATE INDEX IF NOT EXISTS idx_articles_doi_clean
  ON public.articles(doi_clean)
  WHERE doi_clean IS NOT NULL;

-- articles: filter by review status
CREATE INDEX IF NOT EXISTS idx_articles_review_status
  ON public.articles(project_id, review_status);

-- effect_sizes: look up by article
CREATE INDEX IF NOT EXISTS idx_effect_sizes_article_id
  ON public.effect_sizes(article_id);

-- audit_log: most recent entries for a project
CREATE INDEX IF NOT EXISTS idx_audit_log_project_timestamp
  ON public.audit_log(project_id, timestamp DESC);

-- audit_log: most recent entries for an article
CREATE INDEX IF NOT EXISTS idx_audit_log_article_id
  ON public.audit_log(article_id);

-- labels: all labels for a project in display order
CREATE INDEX IF NOT EXISTS idx_labels_project_order
  ON public.labels(project_id, order_index);
