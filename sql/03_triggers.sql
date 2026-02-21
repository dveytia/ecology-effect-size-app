-- ============================================================
-- sql/03_triggers.sql
-- Supabase database triggers
-- Run AFTER 01_create_tables.sql in the Supabase SQL Editor
-- ============================================================

-- ============================================================
-- Trigger: mirror new auth.users rows into public.users
-- 
-- When a user registers via Supabase Auth, this trigger
-- automatically creates a corresponding row in public.users.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (user_id, email, created_at)
  VALUES (NEW.id, NEW.email, NOW())
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop if exists so this script is idempotent
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();
