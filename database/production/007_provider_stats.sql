-- ============================================
-- VIBESLINX PROVIDER STATS & ANALYTICS - PRODUCTION v1.0
-- Provider Performance Tracking & Analytics
-- ============================================
-- This migration creates the provider stats system with automated
-- triggers for tracking bookings, earnings, and performance metrics.
-- Includes all fixes from: 015_fix_provider_stats_permissions.sql,
-- 016_fix_trigger_security.sql, 017_fix_provider_stats_trigger_final.sql,
-- 028_add_increment_profile_views_function.sql
-- ============================================

-- ============================================
-- 1. CREATE PROVIDER STATS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.provider_stats (
  provider_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Booking Stats
  total_bookings INTEGER DEFAULT 0,
  pending_bookings INTEGER DEFAULT 0,
  confirmed_bookings INTEGER DEFAULT 0,
  completed_bookings INTEGER DEFAULT 0,
  cancelled_bookings INTEGER DEFAULT 0,
  declined_bookings INTEGER DEFAULT 0,
  
  -- Financial Stats
  total_earned DECIMAL(10, 2) DEFAULT 0,
  total_withdrawn DECIMAL(10, 2) DEFAULT 0,
  current_balance DECIMAL(10, 2) DEFAULT 0,
  
  -- Performance Metrics
  average_rating DECIMAL(3, 2) DEFAULT 0,
  total_reviews INTEGER DEFAULT 0,
  response_rate DECIMAL(5, 2) DEFAULT 0,
  completion_rate DECIMAL(5, 2) DEFAULT 0,
  
  -- Engagement Stats
  profile_views INTEGER DEFAULT 0,
  last_active_at TIMESTAMPTZ,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT valid_stats CHECK (
    total_bookings >= 0 AND
    pending_bookings >= 0 AND
    confirmed_bookings >= 0 AND
    completed_bookings >= 0 AND
    cancelled_bookings >= 0 AND
    declined_bookings >= 0 AND
    total_earned >= 0 AND
    total_withdrawn >= 0 AND
    current_balance >= 0 AND
    profile_views >= 0 AND
    response_rate >= 0 AND response_rate <= 100 AND
    completion_rate >= 0 AND completion_rate <= 100
  )
);

-- ============================================
-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_provider_stats_rating ON public.provider_stats(average_rating DESC);
CREATE INDEX IF NOT EXISTS idx_provider_stats_completed ON public.provider_stats(completed_bookings DESC);
CREATE INDEX IF NOT EXISTS idx_provider_stats_earned ON public.provider_stats(total_earned DESC);
CREATE INDEX IF NOT EXISTS idx_provider_stats_active ON public.provider_stats(last_active_at DESC);

-- ============================================
-- 3. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Initialize stats for new providers
CREATE OR REPLACE FUNCTION public.initialize_provider_stats()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role = 'provider' THEN
    INSERT INTO public.provider_stats (provider_id, last_active_at)
    VALUES (NEW.id, NOW())
    ON CONFLICT (provider_id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update booking stats when booking status changes
CREATE OR REPLACE FUNCTION public.update_booking_stats()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  old_status TEXT;
  new_status TEXT;
BEGIN
  old_status := COALESCE(OLD.status, 'none');
  new_status := NEW.status;
  
  -- Ensure provider stats exist
  INSERT INTO public.provider_stats (provider_id)
  VALUES (NEW.provider_id)
  ON CONFLICT (provider_id) DO NOTHING;
  
  -- Handle new booking
  IF TG_OP = 'INSERT' THEN
    UPDATE public.provider_stats
    SET 
      total_bookings = total_bookings + 1,
      pending_bookings = CASE WHEN new_status = 'pending' THEN pending_bookings + 1 ELSE pending_bookings END,
      confirmed_bookings = CASE WHEN new_status = 'confirmed' THEN confirmed_bookings + 1 ELSE confirmed_bookings END,
      updated_at = NOW()
    WHERE provider_id = NEW.provider_id;
    
  -- Handle status change
  ELSIF TG_OP = 'UPDATE' AND old_status != new_status THEN
    
    -- Decrement old status count
    UPDATE public.provider_stats
    SET 
      pending_bookings = CASE WHEN old_status = 'pending' THEN GREATEST(pending_bookings - 1, 0) ELSE pending_bookings END,
      confirmed_bookings = CASE WHEN old_status = 'confirmed' THEN GREATEST(confirmed_bookings - 1, 0) ELSE confirmed_bookings END,
      updated_at = NOW()
    WHERE provider_id = NEW.provider_id;
    
    -- Increment new status count
    UPDATE public.provider_stats
    SET 
      pending_bookings = CASE WHEN new_status = 'pending' THEN pending_bookings + 1 ELSE pending_bookings END,
      confirmed_bookings = CASE WHEN new_status = 'confirmed' THEN confirmed_bookings + 1 ELSE confirmed_bookings END,
      completed_bookings = CASE WHEN new_status = 'completed' THEN completed_bookings + 1 ELSE completed_bookings END,
      cancelled_bookings = CASE WHEN new_status = 'cancelled' THEN cancelled_bookings + 1 ELSE cancelled_bookings END,
      declined_bookings = CASE WHEN new_status = 'declined' THEN declined_bookings + 1 ELSE declined_bookings END,
      updated_at = NOW()
    WHERE provider_id = NEW.provider_id;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recalculate provider performance metrics
CREATE OR REPLACE FUNCTION public.recalculate_provider_metrics(p_provider_id UUID)
RETURNS void 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_bookings INTEGER;
  v_completed_bookings INTEGER;
  v_responded_bookings INTEGER;
  v_total_earned DECIMAL(10, 2);
  v_total_withdrawn DECIMAL(10, 2);
  v_current_balance DECIMAL(10, 2);
  v_avg_rating DECIMAL(3, 2);
  v_total_reviews INTEGER;
BEGIN
  -- Get booking counts
  SELECT 
    COUNT(*) FILTER (WHERE status IN ('pending', 'confirmed', 'completed', 'declined', 'cancelled')),
    COUNT(*) FILTER (WHERE status = 'completed'),
    COUNT(*) FILTER (WHERE status IN ('confirmed', 'completed', 'declined'))
  INTO v_total_bookings, v_completed_bookings, v_responded_bookings
  FROM public.bookings
  WHERE provider_id = p_provider_id;
  
  -- Get financial stats
  SELECT 
    COALESCE(available_balance, 0),
    COALESCE(total_earned, 0),
    COALESCE(total_withdrawn, 0)
  INTO v_current_balance, v_total_earned, v_total_withdrawn
  FROM public.wallet_balances
  WHERE user_id = p_provider_id;
  
  -- Get rating stats
  SELECT 
    COALESCE(average_rating, 0),
    COALESCE(total_reviews, 0)
  INTO v_avg_rating, v_total_reviews
  FROM public.provider_ratings
  WHERE provider_id = p_provider_id;
  
  -- Update stats
  UPDATE public.provider_stats
  SET 
    total_earned = v_total_earned,
    total_withdrawn = v_total_withdrawn,
    current_balance = v_current_balance,
    average_rating = v_avg_rating,
    total_reviews = v_total_reviews,
    response_rate = CASE 
      WHEN v_total_bookings > 0 THEN 
        ROUND((v_responded_bookings::DECIMAL / v_total_bookings::DECIMAL * 100), 2)
      ELSE 0 
    END,
    completion_rate = CASE 
      WHEN v_total_bookings > 0 THEN 
        ROUND((v_completed_bookings::DECIMAL / v_total_bookings::DECIMAL * 100), 2)
      ELSE 0 
    END,
    updated_at = NOW()
  WHERE provider_id = p_provider_id;
  
END;
$$ LANGUAGE plpgsql;

-- Function to increment profile views
CREATE OR REPLACE FUNCTION public.increment_profile_views(p_provider_id UUID)
RETURNS void
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ensure provider stats record exists
  INSERT INTO public.provider_stats (provider_id, profile_views)
  VALUES (p_provider_id, 1)
  ON CONFLICT (provider_id) 
  DO UPDATE SET 
    profile_views = provider_stats.profile_views + 1,
    last_active_at = NOW(),
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS initialize_provider_stats_on_signup ON public.profiles;
CREATE TRIGGER initialize_provider_stats_on_signup
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.initialize_provider_stats();

DROP TRIGGER IF EXISTS update_booking_stats_on_change ON public.bookings;
CREATE TRIGGER update_booking_stats_on_change
  AFTER INSERT OR UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_booking_stats();

-- ============================================
-- 5. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.provider_stats ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. CREATE RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Providers can view own stats" ON public.provider_stats;
DROP POLICY IF EXISTS "Service role can manage stats" ON public.provider_stats;

CREATE POLICY "Providers can view own stats"
ON public.provider_stats FOR SELECT
TO authenticated
USING (auth.uid() = provider_id);

CREATE POLICY "Service role can manage stats"
ON public.provider_stats
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 7. CREATE ANALYTICS VIEWS
-- ============================================

-- View for provider leaderboard
CREATE OR REPLACE VIEW public.provider_leaderboard AS
SELECT 
  ps.provider_id,
  p.display_name,
  p.city,
  p.photos,
  ps.average_rating,
  ps.total_reviews,
  ps.completed_bookings,
  ps.total_earned,
  ps.completion_rate,
  ps.response_rate,
  RANK() OVER (ORDER BY ps.average_rating DESC, ps.total_reviews DESC) as rating_rank,
  RANK() OVER (ORDER BY ps.completed_bookings DESC) as bookings_rank
FROM public.provider_stats ps
JOIN public.profiles p ON p.id = ps.provider_id
WHERE p.role = 'provider' AND p.onboarding_completed = TRUE
ORDER BY ps.average_rating DESC, ps.total_reviews DESC;

GRANT SELECT ON public.provider_leaderboard TO authenticated;

-- ============================================
-- 8. GRANT PERMISSIONS
-- ============================================

GRANT SELECT ON public.provider_stats TO authenticated;
GRANT ALL ON public.provider_stats TO service_role;
GRANT EXECUTE ON FUNCTION public.recalculate_provider_metrics(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_profile_views(UUID) TO authenticated;

-- ============================================
-- 9. INITIALIZE STATS FOR EXISTING PROVIDERS
-- ============================================

-- Create stats records for existing providers
INSERT INTO public.provider_stats (provider_id, last_active_at)
SELECT id, NOW() FROM public.profiles WHERE role = 'provider'
ON CONFLICT (provider_id) DO NOTHING;

-- ============================================
-- PROVIDER STATS & ANALYTICS COMPLETE
-- ============================================
