-- ============================================================
-- sql/11_sequence_grants.sql — Fix: grant sequence usage to
--                              authenticated role
-- ============================================================
-- sql/07_gdrive_columns.sql added article_num with a
-- DEFAULT nextval(articles_article_num_seq), but did not grant
-- USAGE and SELECT on the sequence to the authenticated role.
-- Without these grants, any article INSERT that relies on the
-- auto-assigned default (i.e. no article_num column in the CSV)
-- fails with a permission error.
--
-- Run this once in the Supabase SQL Editor if uploads report
-- sequence permission errors, or as a precaution on any fresh
-- deployment.
-- ============================================================

GRANT USAGE, SELECT ON SEQUENCE public.articles_article_num_seq TO authenticated;
