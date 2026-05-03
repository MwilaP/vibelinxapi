-- Add province column to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS province TEXT;

-- Create index on province for filtering
CREATE INDEX IF NOT EXISTS idx_profiles_province ON public.profiles(province);
