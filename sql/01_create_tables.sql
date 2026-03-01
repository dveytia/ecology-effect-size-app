-- ============================================================
-- sql/01_create_tables.sql
-- ALL CREATE TABLE statements in dependency order
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor)
-- ============================================================

-- Extensions (Supabase enables these by default; included for completeness)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------
-- 1. users
-- Mirrors auth.users; populated automatically by trigger in
-- sql/03_triggers.sql whenever a user registers.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
  user_id    UUID PRIMARY KEY,          -- matches auth.users.id
  email      TEXT NOT NULL,
  username   TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 2. projects
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.projects (
  project_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id         UUID NOT NULL REFERENCES public.users(user_id),
  title            TEXT NOT NULL,
  description      TEXT,
  drive_folder_url TEXT,
  drive_folder_id  TEXT,
  drive_last_synced TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 3. project_members
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.project_members (
  project_id UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('owner', 'reviewer')),
  PRIMARY KEY (project_id, user_id)
);

-- ------------------------------------------------------------
-- 4. labels
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.labels (
  label_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id      UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  label_type      TEXT NOT NULL CHECK (label_type IN ('single', 'group')),
  parent_label_id UUID REFERENCES public.labels(label_id) ON DELETE CASCADE,
  category        TEXT,
  name            TEXT NOT NULL,   -- machine-readable key
  display_name    TEXT NOT NULL,   -- shown in UI
  instructions    TEXT,
  variable_type   TEXT NOT NULL CHECK (variable_type IN (
    'text', 'integer', 'numeric', 'boolean',
    'select one', 'select multiple',
    'YYYY-MM-DD', 'bounding_box', 'openstreetmap_location', 'effect_size'
  )),
  allowed_values  TEXT[],
  mandatory       BOOLEAN NOT NULL DEFAULT FALSE,
  order_index     INTEGER NOT NULL DEFAULT 0
);

-- ------------------------------------------------------------
-- 5. uploads
-- (must precede articles because articles FK → uploads)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.uploads (
  upload_batch_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id      UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  filename        TEXT,
  upload_date     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  rows_uploaded   INTEGER,
  rows_flagged    INTEGER
);

-- ------------------------------------------------------------
-- 6. articles
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.articles (
  article_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id       UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  title            TEXT NOT NULL,
  abstract         TEXT,
  author           TEXT,
  year             INTEGER,
  doi_clean        TEXT,
  pdf_drive_link   TEXT,
  upload_batch_id  UUID REFERENCES public.uploads(upload_batch_id),
  reviewed_by      UUID REFERENCES public.users(user_id),
  reviewed_at      TIMESTAMPTZ,
  review_status    TEXT NOT NULL DEFAULT 'unreviewed'
                   CHECK (review_status IN ('unreviewed', 'reviewed', 'skipped'))
);

-- ------------------------------------------------------------
-- 7. article_metadata_json
-- One row per article; JSONB stores all coded label values.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.article_metadata_json (
  article_id UUID PRIMARY KEY REFERENCES public.articles(article_id) ON DELETE CASCADE,
  json_data  JSONB NOT NULL DEFAULT '{}'::JSONB
);

-- ------------------------------------------------------------
-- 8. effect_sizes
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.effect_sizes (
  effect_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  article_id        UUID NOT NULL REFERENCES public.articles(article_id) ON DELETE CASCADE,
  group_instance_id TEXT,
  raw_effect_json   JSONB NOT NULL DEFAULT '{}'::JSONB,
  r                 NUMERIC,
  z                 NUMERIC,
  var_z             NUMERIC,
  effect_status     TEXT NOT NULL DEFAULT 'insufficient_data'
                    CHECK (effect_status IN (
                      'calculated', 'insufficient_data', 'small_sd_used',
                      'calculated_relative', 'iqr_sd_used'
                    )),
  effect_type       TEXT NOT NULL DEFAULT 'zero_order'
                    CHECK (effect_type IN ('zero_order', 'partial')),
  effect_warnings   TEXT[],
  computed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 9. audit_log
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
  log_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES public.projects(project_id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(user_id),
  article_id UUID REFERENCES public.articles(article_id),
  action     TEXT NOT NULL CHECK (action IN ('save', 'skip', 'delete', 'effect_computed')),
  old_json   JSONB,
  new_json   JSONB,
  timestamp  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
