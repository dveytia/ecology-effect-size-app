-- ============================================================
-- sql/07_gdrive_columns.sql  — Phase 6: Google Drive Integration
-- ============================================================
-- Run this in the Supabase SQL Editor BEFORE testing Gate 6.
--
-- What this script does:
--   1. Ensures the three Drive columns exist on the projects table.
--      (They are already in 01_create_tables.sql, so this is safe to
--      run on databases created from that file — the IF NOT EXISTS
--      clauses prevent errors.)
--   2. Adds article_num — a globally-unique integer assigned to every
--      article. Reviewers name their Drive PDFs [article_num].pdf
--      (e.g. 42.pdf) so the sync function can match files to rows.
-- ============================================================

-- ---- 1. Drive columns on projects (idempotent) -------------------------

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS drive_folder_url  TEXT;

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS drive_folder_id   TEXT;

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS drive_last_synced TIMESTAMPTZ;

-- ---- 2. pdf_drive_link on articles (idempotent) ------------------------

ALTER TABLE public.articles
  ADD COLUMN IF NOT EXISTS pdf_drive_link TEXT;

-- ---- 3. article_num — sequential integer per article -------------------
-- Creates a dedicated sequence so numbers are stable and never reused.

CREATE SEQUENCE IF NOT EXISTS public.articles_article_num_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

ALTER TABLE public.articles
  ADD COLUMN IF NOT EXISTS article_num BIGINT
  DEFAULT nextval('public.articles_article_num_seq');

-- Back-fill any existing rows that were inserted before this column existed.
UPDATE public.articles
  SET article_num = nextval('public.articles_article_num_seq')
WHERE article_num IS NULL;

-- Verify
SELECT
  COUNT(*)                                      AS total_articles,
  COUNT(article_num)                            AS articles_with_num,
  COUNT(*) - COUNT(article_num)                 AS missing_num
FROM public.articles;
