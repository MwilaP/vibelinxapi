-- ============================================
-- VIBESLINX CORE SCHEMA - PRODUCTION v1.0
-- Profiles, Authentication, Storage & Base RLS
-- ============================================
-- This migration creates the foundational schema for user profiles,
-- authentication triggers, storage buckets, and base security policies.
-- Includes all fixes from: 013_fix_city_case_insensitive.sql
-- ============================================

-- ============================================
-- 1. CREATE PROFILES TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  phone TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('client', 'provider')),
  date_of_birth DATE,
  city TEXT,
  languages TEXT,
  bio TEXT,
  interests TEXT[],
  looking_for TEXT[],
  photos TEXT[],
  services JSONB[],
  payout_method TEXT,
  payout_phone TEXT,
  onboarding_completed BOOLEAN DEFAULT FALSE,
  subscription_status TEXT DEFAULT 'inactive' CHECK (subscription_status IN ('active', 'inactive', 'expired')),
  search_vector tsvector,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 2. CREATE INDEXES ON PROFILES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_city_lower ON public.profiles(LOWER(city)) WHERE role = 'provider';
CREATE INDEX IF NOT EXISTS idx_profiles_role_active ON public.profiles(role) 
  WHERE role = 'provider' AND onboarding_completed = TRUE;
CREATE INDEX IF NOT EXISTS idx_profiles_subscription_status ON public.profiles(subscription_status);
CREATE INDEX IF NOT EXISTS idx_profiles_search_vector ON public.profiles USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_profiles_interests_gin ON public.profiles USING GIN(interests);
CREATE INDEX IF NOT EXISTS idx_profiles_looking_for_gin ON public.profiles USING GIN(looking_for);
CREATE INDEX IF NOT EXISTS idx_profiles_available_providers ON public.profiles(role, updated_at DESC) 
  WHERE role = 'provider' AND onboarding_completed = TRUE;

-- ============================================
-- 3. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Function to handle new user creation (bypasses RLS with SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, phone, role)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'display_name',
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'role'
  );
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update profile search vector
CREATE OR REPLACE FUNCTION public.update_profile_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.display_name, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.bio, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.city, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.languages, '')), 'C') ||
    setweight(to_tsvector('english', COALESCE(array_to_string(NEW.interests, ' '), '')), 'C');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS on_profile_updated ON public.profiles;
CREATE TRIGGER on_profile_updated
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS update_search_vector ON public.profiles;
CREATE TRIGGER update_search_vector
  BEFORE INSERT OR UPDATE OF display_name, bio, city, languages, interests
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_search_vector();

-- ============================================
-- 5. SETUP STORAGE BUCKET
-- ============================================

-- Create storage bucket for profile photos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile-photos', 
  'profile-photos', 
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];

-- ============================================
-- 6. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 7. CREATE PROFILES RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Clients can view provider profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can delete own profile" ON public.profiles;
DROP POLICY IF EXISTS "Service role can insert profiles" ON public.profiles;

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id);

-- Clients can view all provider profiles
CREATE POLICY "Clients can view provider profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (role = 'provider');

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Allow service role to insert profiles (for trigger)
CREATE POLICY "Service role can insert profiles"
ON public.profiles FOR INSERT
TO service_role
WITH CHECK (true);

-- Authenticated users can insert their own profile
CREATE POLICY "Users can insert own profile"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Users can delete their own profile
CREATE POLICY "Users can delete own profile"
ON public.profiles FOR DELETE
TO authenticated
USING (auth.uid() = id);

-- ============================================
-- 8. CREATE STORAGE RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload own photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own photos" ON storage.objects;

-- Anyone can view profile photos (public bucket)
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-photos');

-- Authenticated users can upload their own photos
CREATE POLICY "Users can upload own photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile-photos' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can update their own photos
CREATE POLICY "Users can update own photos"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile-photos' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can delete their own photos
CREATE POLICY "Users can delete own photos"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile-photos' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ============================================
-- 9. CREATE SEARCH HELPER FUNCTIONS
-- ============================================

-- Search providers by text query (with case-insensitive city search)
CREATE OR REPLACE FUNCTION public.search_providers(
  search_query TEXT DEFAULT NULL,
  search_city TEXT DEFAULT NULL,
  min_rating DECIMAL DEFAULT NULL,
  limit_count INTEGER DEFAULT 20,
  offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  city TEXT,
  bio TEXT,
  photos TEXT[],
  services JSONB[],
  average_rating DECIMAL,
  total_reviews INTEGER,
  rank REAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.display_name,
    p.city,
    p.bio,
    p.photos,
    p.services,
    COALESCE(pr.average_rating, 0) as average_rating,
    COALESCE(pr.total_reviews, 0) as total_reviews,
    CASE 
      WHEN search_query IS NOT NULL THEN
        ts_rank(p.search_vector, plainto_tsquery('english', search_query))
      ELSE 0
    END as rank
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  WHERE 
    p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND (search_query IS NULL OR p.search_vector @@ plainto_tsquery('english', search_query))
    AND (search_city IS NULL OR LOWER(TRIM(p.city)) = LOWER(TRIM(search_city)))
    AND (min_rating IS NULL OR COALESCE(pr.average_rating, 0) >= min_rating)
  ORDER BY 
    CASE WHEN search_query IS NOT NULL THEN rank ELSE 0 END DESC,
    pr.average_rating DESC NULLS LAST,
    p.updated_at DESC
  LIMIT limit_count
  OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Get nearby providers (case-insensitive city match)
CREATE OR REPLACE FUNCTION public.get_nearby_providers(
  user_city TEXT,
  limit_count INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  city TEXT,
  photos TEXT[],
  average_rating DECIMAL,
  total_reviews INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.display_name,
    p.city,
    p.photos,
    COALESCE(pr.average_rating, 0) as average_rating,
    COALESCE(pr.total_reviews, 0) as total_reviews
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  WHERE 
    p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND LOWER(TRIM(p.city)) = LOWER(TRIM(user_city))
  ORDER BY pr.average_rating DESC NULLS LAST
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Get providers by service type
CREATE OR REPLACE FUNCTION public.get_providers_by_service(
  service_name_search TEXT,
  limit_count INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  city TEXT,
  photos TEXT[],
  services JSONB[],
  average_rating DECIMAL,
  total_reviews INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.display_name,
    p.city,
    p.photos,
    p.services,
    COALESCE(pr.average_rating, 0) as average_rating,
    COALESCE(pr.total_reviews, 0) as total_reviews
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  WHERE 
    p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(
        CASE 
          WHEN p.services IS NULL THEN '[]'::jsonb
          ELSE array_to_json(p.services)::jsonb
        END
      ) AS service
      WHERE LOWER(service->>'name') LIKE LOWER('%' || service_name_search || '%')
    )
  ORDER BY pr.average_rating DESC NULLS LAST
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================
-- 10. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
GRANT EXECUTE ON FUNCTION public.search_providers TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_providers_by_service TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_nearby_providers TO authenticated;

-- ============================================
-- CORE SCHEMA SETUP COMPLETE
-- ============================================
