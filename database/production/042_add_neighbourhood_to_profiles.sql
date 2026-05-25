-- Add neighbourhood column to profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS neighbourhood TEXT;

-- Create index on neighbourhood for filtering
CREATE INDEX IF NOT EXISTS idx_profiles_neighbourhood ON public.profiles(neighbourhood);

-- Update search vector trigger function to include neighbourhood
CREATE OR REPLACE FUNCTION public.update_profile_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.display_name, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.bio, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.city, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.neighbourhood, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.languages, '')), 'C') ||
    setweight(to_tsvector('english', COALESCE(array_to_string(NEW.interests, ' '), '')), 'C');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger to watch neighbourhood as well
DROP TRIGGER IF EXISTS update_search_vector ON public.profiles;
CREATE TRIGGER update_search_vector
  BEFORE INSERT OR UPDATE OF display_name, bio, city, neighbourhood, languages, interests
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_search_vector();

-- Drop and recreate search_providers function to return neighbourhood
DROP FUNCTION IF EXISTS public.search_providers(TEXT, TEXT, DECIMAL, INTEGER, INTEGER);
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
  neighbourhood TEXT,
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
    p.neighbourhood,
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
    AND (
      (p.visibility_status = 'active' AND (p.visibility_expires_at IS NULL OR p.visibility_expires_at > NOW()))
      OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE)
    )
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

-- Drop and recreate get_providers_by_service function to return neighbourhood
DROP FUNCTION IF EXISTS public.get_providers_by_service(TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.get_providers_by_service(
  service_name_search TEXT,
  limit_count INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  city TEXT,
  neighbourhood TEXT,
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
    p.neighbourhood,
    p.photos,
    p.services,
    COALESCE(pr.average_rating, 0) as average_rating,
    COALESCE(pr.total_reviews, 0) as total_reviews
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  WHERE 
    p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND (
      (p.visibility_status = 'active' AND (p.visibility_expires_at IS NULL OR p.visibility_expires_at > NOW()))
      OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE)
    )
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

-- Drop and recreate get_nearby_providers function to return neighbourhood
DROP FUNCTION IF EXISTS public.get_nearby_providers(TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.get_nearby_providers(
  user_city TEXT,
  limit_count INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  city TEXT,
  neighbourhood TEXT,
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
    p.neighbourhood,
    p.photos,
    COALESCE(pr.average_rating, 0) as average_rating,
    COALESCE(pr.total_reviews, 0) as total_reviews
  FROM public.profiles p
  LEFT JOIN public.provider_ratings pr ON pr.provider_id = p.id
  WHERE 
    p.role = 'provider' 
    AND p.onboarding_completed = TRUE
    AND (
      (p.visibility_status = 'active' AND (p.visibility_expires_at IS NULL OR p.visibility_expires_at > NOW()))
      OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE)
    )
    AND LOWER(p.city) = LOWER(user_city)
  ORDER BY pr.average_rating DESC NULLS LAST
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Update top_providers materialized view refresh function to include neighbourhood
CREATE OR REPLACE FUNCTION public.refresh_top_providers_with_visibility()
RETURNS void AS $$
BEGIN
  DROP MATERIALIZED VIEW IF EXISTS public.top_providers;
  
  CREATE MATERIALIZED VIEW public.top_providers AS
  SELECT 
    p.id,
    p.display_name,
    p.city,
    p.neighbourhood,
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
    AND (
      (p.visibility_status = 'active' AND (p.visibility_expires_at IS NULL OR p.visibility_expires_at > NOW()))
      OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE)
    )
  GROUP BY p.id, p.display_name, p.city, p.neighbourhood, p.bio, p.photos, p.services, pr.average_rating, pr.total_reviews
  ORDER BY pr.average_rating DESC NULLS LAST, pr.total_reviews DESC;

  CREATE UNIQUE INDEX IF NOT EXISTS idx_top_providers_id ON public.top_providers(id);
  CREATE INDEX IF NOT EXISTS idx_top_providers_rating ON public.top_providers(average_rating DESC);
  CREATE INDEX IF NOT EXISTS idx_top_providers_neighbourhood ON public.top_providers(neighbourhood);
  
  GRANT SELECT ON public.top_providers TO authenticated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run refresh once to update view schema
SELECT public.refresh_top_providers_with_visibility();
