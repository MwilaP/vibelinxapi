-- ============================================
-- 044 PROVIDER SHARE SYSTEM
-- Adds slug, share_image_url, is_verified to profiles
-- Creates database views for column-level security
-- ============================================

-- ============================================
-- 1. ALTER TABLE public.profiles
-- ============================================
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS share_image_url TEXT,
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;

-- Create index on slug for fast lookups
CREATE INDEX IF NOT EXISTS idx_profiles_slug ON public.profiles(slug);

-- ============================================
-- 2. CREATE SLUG GENERATION FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION public.generate_provider_slug(p_display_name TEXT, p_city TEXT)
RETURNS TEXT AS $$
DECLARE
  base_slug TEXT;
  temp_slug TEXT;
  random_suffix TEXT;
  is_unique BOOLEAN := FALSE;
  attempts INTEGER := 0;
BEGIN
  -- Lowercase, replace non-alphanumeric characters with hyphens
  base_slug := LOWER(COALESCE(p_display_name, 'profile'));
  base_slug := REGEXP_REPLACE(base_slug, '[^a-z0-9]+', '-', 'g');
  -- Remove leading/trailing hyphens
  base_slug := TRIM(BOTH '-' FROM base_slug);
  
  IF p_city IS NOT NULL AND p_city <> '' THEN
    DECLARE
      city_slug TEXT;
    BEGIN
      city_slug := LOWER(p_city);
      city_slug := REGEXP_REPLACE(city_slug, '[^a-z0-9]+', '-', 'g');
      city_slug := TRIM(BOTH '-' FROM city_slug);
      base_slug := base_slug || '-' || city_slug;
    END;
  END IF;

  WHILE NOT is_unique AND attempts < 10 LOOP
    -- Generate 6 character random hex string
    random_suffix := SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6);
    temp_slug := base_slug || '-' || random_suffix;
    
    -- Check if unique
    SELECT NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE slug = temp_slug
    ) INTO is_unique;
    
    attempts := attempts + 1;
  END LOOP;
  
  RETURN temp_slug;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 3. CREATE TRIGGER FUNCTION & TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_provider_slug_trigger()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'provider' THEN
    IF NEW.slug IS NULL THEN
      -- Generate initial slug
      NEW.slug := public.generate_provider_slug(NEW.display_name, NEW.city);
    ELSIF OLD.city IS NULL AND NEW.city IS NOT NULL AND NEW.slug NOT LIKE '%' || LOWER(NEW.city) || '%' THEN
      -- If city is added for the first time (e.g. after onboarding completion), regenerate slug to include it
      NEW.slug := public.generate_provider_slug(NEW.display_name, NEW.city);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_provider_slug_trigger ON public.profiles;
CREATE TRIGGER on_provider_slug_trigger
  BEFORE INSERT OR UPDATE OF display_name, city ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_provider_slug_trigger();

-- ============================================
-- 4. BACKFILL EXISTING PROVIDERS
-- ============================================
UPDATE public.profiles 
SET slug = public.generate_provider_slug(display_name, city)
WHERE role = 'provider' AND slug IS NULL;

-- ============================================
-- 5. CREATE DATABASE VIEWS
-- ============================================

-- Public View (exposing only basic info, no premium data)
CREATE OR REPLACE VIEW public.public_provider_view AS
SELECT 
  id,
  display_name,
  slug,
  bio,
  CASE 
    WHEN photos IS NOT NULL AND array_length(photos, 1) > 0 THEN ARRAY[photos[1]]
    ELSE ARRAY[]::TEXT[]
  END as photos,
  city,
  neighbourhood,
  is_verified,
  share_image_url
FROM public.profiles
WHERE role = 'provider' AND onboarding_completed = TRUE;

-- Premium View (accessible to active subscribers or owner themselves)
CREATE OR REPLACE VIEW public.premium_provider_view AS
SELECT 
  p.id,
  p.display_name,
  p.phone,
  p.date_of_birth,
  p.city,
  p.neighbourhood,
  p.languages,
  p.bio,
  p.photos,
  p.services,
  p.slug,
  p.share_image_url,
  p.is_verified,
  p.created_at,
  p.updated_at
FROM public.profiles p
WHERE p.role = 'provider' 
  AND p.onboarding_completed = TRUE
  AND (
    public.check_subscription_status(auth.uid()) = TRUE
    OR auth.uid() = p.id
  );

-- ============================================
-- 6. UPDATE ROW LEVEL SECURITY POLICIES ON PROFILES
-- ============================================

-- Restrict SELECT access on provider profiles to active subscribers or the provider themselves
DROP POLICY IF EXISTS "Clients can view provider profiles" ON public.profiles;
CREATE POLICY "Clients can view provider profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (
  role = 'provider' 
  AND (
    public.check_subscription_status(auth.uid()) = TRUE 
    OR auth.uid() = id
  )
);

-- ============================================
-- 7. GRANT PERMISSIONS
-- ============================================
GRANT SELECT ON public.public_provider_view TO anon, authenticated;
GRANT SELECT ON public.premium_provider_view TO authenticated;
