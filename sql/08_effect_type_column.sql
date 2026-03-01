-- ============================================================
-- sql/08_effect_type_column.sql
-- Adds the effect_type column to effect_sizes.
-- Run this in the Supabase SQL Editor before using Phase 9.
-- ============================================================

ALTER TABLE public.effect_sizes
  ADD COLUMN IF NOT EXISTS effect_type TEXT NOT NULL DEFAULT 'zero_order'
    CHECK (effect_type IN ('zero_order', 'partial'));
