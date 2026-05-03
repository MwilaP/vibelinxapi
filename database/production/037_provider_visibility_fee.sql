-- ============================================
-- PROVIDER VISIBILITY FEE SYSTEM
-- ============================================

-- 1. Add visibility fee to system_settings
INSERT INTO public.system_settings (setting_key, setting_value, setting_type, display_name, description)
VALUES 
  (
    'provider_visibility_fee',
    '100'::jsonb,
    'currency',
    'Provider Visibility Fee',
    'One-time fee (in Kwacha) for providers to make their profile visible in search results'
  )
ON CONFLICT (setting_key) DO NOTHING;

-- 2. Add visibility_status and visibility_expires_at to profiles
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'visibility_status'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN visibility_status TEXT DEFAULT 'pending' CHECK (visibility_status IN ('pending', 'active', 'expired'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'visibility_expires_at'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN visibility_expires_at TIMESTAMPTZ;
  END IF;
END $$;

-- 3. Create index for visibility status
CREATE INDEX IF NOT EXISTS idx_profiles_visibility_status ON public.profiles(visibility_status) WHERE role = 'provider';

-- 4. Update search_providers function to filter by visibility_status
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
    AND p.visibility_status = 'active'
    AND (search_query IS NULL OR p.search_vector @@ plainto_tsquery('english', search_query))
    AND (search_city IS NULL OR LOWER(p.city) = LOWER(search_city))
    AND (min_rating IS NULL OR COALESCE(pr.average_rating, 0) >= min_rating)
  ORDER BY 
    CASE WHEN search_query IS NOT NULL THEN rank ELSE 0 END DESC,
    pr.average_rating DESC NULLS LAST,
    p.updated_at DESC
  LIMIT limit_count
  OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 5. Update get_providers_by_service function
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
    AND p.visibility_status = 'active'
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

-- 6. Update get_nearby_providers function
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
    AND p.visibility_status = 'active'
    AND LOWER(p.city) = LOWER(user_city)
  ORDER BY pr.average_rating DESC NULLS LAST
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 7. Update top_providers materialized view
CREATE OR REPLACE FUNCTION public.refresh_top_providers_with_visibility()
RETURNS void AS $$
BEGIN
  DROP MATERIALIZED VIEW IF EXISTS public.top_providers;
  
  CREATE MATERIALIZED VIEW public.top_providers AS
  SELECT 
    p.id,
    p.display_name,
    p.city,
    p.bio,
    p.photos,
    p.services,
    pr.average_rating,
    pr.total_reviews,
    COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'completed') as completed_bookings
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  LEFT JOIN public.bookings b ON b.provider_id = p.id
  WHERE p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND p.visibility_status = 'active'
  GROUP BY p.id, p.display_name, p.city, p.bio, p.photos, p.services, pr.average_rating, pr.total_reviews
  ORDER BY pr.average_rating DESC NULLS LAST, pr.total_reviews DESC;

  CREATE UNIQUE INDEX IF NOT EXISTS idx_top_providers_id ON public.top_providers(id);
  CREATE INDEX IF NOT EXISTS idx_top_providers_rating ON public.top_providers(average_rating DESC);
  
  GRANT SELECT ON public.top_providers TO authenticated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run the refresh once
SELECT public.refresh_top_providers_with_visibility();
