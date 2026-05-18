-- ============================================
-- REQUIRE PROVIDER VISIBILITY FEE SYSTEM SETTING
-- ============================================

-- 1. Add require_visibility_fee to system_settings
INSERT INTO public.system_settings (setting_key, setting_value, setting_type, display_name, description)
VALUES 
  (
    'require_visibility_fee',
    'true'::jsonb,
    'boolean',
    'Require Visibility Fee',
    'Control whether new providers are required to pay a visibility fee to appear in search results'
  )
ON CONFLICT (setting_key) DO NOTHING;

-- 2. Create trigger function for automatic visibility activation if fee not required
CREATE OR REPLACE FUNCTION public.handle_provider_onboarding_visibility()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_require_fee BOOLEAN;
BEGIN
  -- Check if user is a provider and onboarding completed is being set to true
  IF NEW.role = 'provider' AND NEW.onboarding_completed = TRUE AND (OLD.onboarding_completed = FALSE OR OLD.onboarding_completed IS NULL) THEN
    -- Fetch require_visibility_fee setting
    SELECT (setting_value)::text::boolean INTO v_require_fee
    FROM public.system_settings
    WHERE setting_key = 'require_visibility_fee';
    
    -- If fee is not required, automatically activate visibility
    IF COALESCE(v_require_fee, TRUE) = FALSE THEN
      NEW.visibility_status := 'active';
    ELSE
      -- Otherwise, default to pending if not set
      IF NEW.visibility_status IS NULL THEN
        NEW.visibility_status := 'pending';
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create the trigger on profiles table
DROP TRIGGER IF EXISTS on_provider_onboarding_visibility ON public.profiles;
CREATE TRIGGER on_provider_onboarding_visibility
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_provider_onboarding_visibility();

-- 4. Update search_providers function to respect the require_visibility_fee setting
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
    AND (p.visibility_status = 'active' OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE))
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

-- 5. Update get_providers_by_service function to respect require_visibility_fee setting
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
    AND (p.visibility_status = 'active' OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE))
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

-- 6. Update get_nearby_providers function to respect require_visibility_fee setting
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
    AND (p.visibility_status = 'active' OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE))
    AND LOWER(p.city) = LOWER(user_city)
  ORDER BY pr.average_rating DESC NULLS LAST
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 7. Update top_providers materialized view query to respect require_visibility_fee setting
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
    AND (p.visibility_status = 'active' OR NOT COALESCE((public.get_setting_value('require_visibility_fee'))::text::boolean, TRUE))
  GROUP BY p.id, p.display_name, p.city, p.bio, p.photos, p.services, pr.average_rating, pr.total_reviews
  ORDER BY pr.average_rating DESC NULLS LAST, pr.total_reviews DESC;

  CREATE UNIQUE INDEX IF NOT EXISTS idx_top_providers_id ON public.top_providers(id);
  CREATE INDEX IF NOT EXISTS idx_top_providers_rating ON public.top_providers(average_rating DESC);
  
  GRANT SELECT ON public.top_providers TO authenticated;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run refresh once
SELECT public.refresh_top_providers_with_visibility();
