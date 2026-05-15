-- ============================================
-- VIBESLINX REVIEWS & RATINGS SYSTEM - PRODUCTION v1.0
-- Review Management & Automated Rating Calculations
-- ============================================
-- This migration creates the reviews and provider ratings system
-- with automated rating recalculation triggers and validation.
-- ============================================

-- ============================================
-- 1. CREATE REVIEWS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  
  -- Parties
  reviewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Review Content
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  is_anonymous BOOLEAN DEFAULT FALSE,
  
  -- Moderation
  is_flagged BOOLEAN DEFAULT FALSE,
  is_hidden BOOLEAN DEFAULT FALSE,
  flagged_reason TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT unique_review_per_booking UNIQUE (booking_id, reviewer_id),
  CONSTRAINT different_users CHECK (reviewer_id != reviewee_id)
);

-- ============================================
-- 2. CREATE PROVIDER RATINGS CACHE TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.provider_ratings (
  provider_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Rating Stats
  average_rating DECIMAL(3, 2) DEFAULT 0 CHECK (average_rating >= 0 AND average_rating <= 5),
  total_reviews INTEGER DEFAULT 0,
  
  -- Rating Distribution
  five_star_count INTEGER DEFAULT 0,
  four_star_count INTEGER DEFAULT 0,
  three_star_count INTEGER DEFAULT 0,
  two_star_count INTEGER DEFAULT 0,
  one_star_count INTEGER DEFAULT 0,
  
  -- Timestamps
  last_review_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT valid_counts CHECK (
    five_star_count >= 0 AND
    four_star_count >= 0 AND
    three_star_count >= 0 AND
    two_star_count >= 0 AND
    one_star_count >= 0
  )
);

-- ============================================
-- 2b. CREATE CLIENT RATINGS CACHE TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.client_ratings (
  client_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Rating Stats
  average_rating DECIMAL(3, 2) DEFAULT 0 CHECK (average_rating >= 0 AND average_rating <= 5),
  total_reviews INTEGER DEFAULT 0,
  
  -- Rating Distribution
  five_star_count INTEGER DEFAULT 0,
  four_star_count INTEGER DEFAULT 0,
  three_star_count INTEGER DEFAULT 0,
  two_star_count INTEGER DEFAULT 0,
  one_star_count INTEGER DEFAULT 0,
  
  -- Timestamps
  last_review_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT valid_counts_client CHECK (
    five_star_count >= 0 AND
    four_star_count >= 0 AND
    three_star_count >= 0 AND
    two_star_count >= 0 AND
    one_star_count >= 0
  )
);

-- ============================================
-- 3. CREATE INDEXES
-- ============================================

-- Reviews indexes
CREATE INDEX IF NOT EXISTS idx_reviews_booking_id ON public.reviews(booking_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer_id ON public.reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee_id ON public.reviews(reviewee_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON public.reviews(rating);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON public.reviews(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_not_hidden ON public.reviews(reviewee_id) WHERE is_hidden = FALSE;

-- Provider ratings indexes
CREATE INDEX IF NOT EXISTS idx_provider_ratings_avg ON public.provider_ratings(average_rating DESC);
CREATE INDEX IF NOT EXISTS idx_provider_ratings_total ON public.provider_ratings(total_reviews DESC);

-- Client ratings indexes
CREATE INDEX IF NOT EXISTS idx_client_ratings_avg ON public.client_ratings(average_rating DESC);
CREATE INDEX IF NOT EXISTS idx_client_ratings_total ON public.client_ratings(total_reviews DESC);

-- ============================================
-- 4. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Function to update review timestamp
CREATE OR REPLACE FUNCTION public.handle_review_updated()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to recalculate user rating (handles both providers and clients)
CREATE OR REPLACE FUNCTION public.recalculate_user_rating()
RETURNS TRIGGER AS $$
DECLARE
  target_user_id UUID;
  user_role TEXT;
  avg_rating DECIMAL(3, 2);
  total_count INTEGER;
  star_counts INTEGER[];
BEGIN
  -- Determine which user to update
  IF TG_OP = 'DELETE' THEN
    target_user_id := OLD.reviewee_id;
  ELSE
    target_user_id := NEW.reviewee_id;
  END IF;

  -- Get user role
  SELECT role INTO user_role FROM public.profiles WHERE id = target_user_id;
  
  -- Calculate new average rating and counts
  SELECT 
    COALESCE(ROUND(AVG(rating)::numeric, 2), 0),
    COUNT(*),
    ARRAY[
      COUNT(*) FILTER (WHERE rating = 5),
      COUNT(*) FILTER (WHERE rating = 4),
      COUNT(*) FILTER (WHERE rating = 3),
      COUNT(*) FILTER (WHERE rating = 2),
      COUNT(*) FILTER (WHERE rating = 1)
    ]
  INTO avg_rating, total_count, star_counts
  FROM public.reviews
  WHERE reviewee_id = target_user_id AND is_hidden = FALSE;
  
  IF user_role = 'provider' THEN
    -- Ensure provider rating record exists
    INSERT INTO public.provider_ratings (provider_id)
    VALUES (target_user_id)
    ON CONFLICT (provider_id) DO NOTHING;
    
    -- Update provider rating
    UPDATE public.provider_ratings
    SET 
      average_rating = avg_rating,
      total_reviews = total_count,
      five_star_count = star_counts[1],
      four_star_count = star_counts[2],
      three_star_count = star_counts[3],
      two_star_count = star_counts[4],
      one_star_count = star_counts[5],
      last_review_at = CASE WHEN total_count > 0 THEN NOW() ELSE last_review_at END,
      updated_at = NOW()
    WHERE provider_id = target_user_id;
  ELSE
    -- Ensure client rating record exists
    INSERT INTO public.client_ratings (client_id)
    VALUES (target_user_id)
    ON CONFLICT (client_id) DO NOTHING;
    
    -- Update client rating
    UPDATE public.client_ratings
    SET 
      average_rating = avg_rating,
      total_reviews = total_count,
      five_star_count = star_counts[1],
      four_star_count = star_counts[2],
      three_star_count = star_counts[3],
      two_star_count = star_counts[4],
      one_star_count = star_counts[5],
      last_review_at = CASE WHEN total_count > 0 THEN NOW() ELSE last_review_at END,
      updated_at = NOW()
    WHERE client_id = target_user_id;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate review eligibility and mark booking as reviewed
CREATE OR REPLACE FUNCTION public.validate_review_eligibility()
RETURNS TRIGGER AS $$
DECLARE
  booking_record RECORD;
BEGIN
  -- Get booking details
  SELECT * INTO booking_record
  FROM public.bookings
  WHERE id = NEW.booking_id;
  
  -- Check if booking exists
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  
  -- Check if booking is completed
  IF booking_record.status != 'completed' THEN
    RAISE EXCEPTION 'Can only review completed bookings';
  END IF;
  
  -- Check if reviewer is part of the booking
  IF NEW.reviewer_id != booking_record.client_id AND NEW.reviewer_id != booking_record.provider_id THEN
    RAISE EXCEPTION 'Only booking participants can leave reviews';
  END IF;
  
  -- Set the reviewee_id and update booking review flags
  IF NEW.reviewer_id = booking_record.client_id THEN
    NEW.reviewee_id := booking_record.provider_id;
    
    UPDATE public.bookings 
    SET client_reviewed = TRUE 
    WHERE id = NEW.booking_id;
  ELSE
    NEW.reviewee_id := booking_record.client_id;
    
    UPDATE public.bookings 
    SET provider_reviewed = TRUE 
    WHERE id = NEW.booking_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS on_review_updated ON public.reviews;
CREATE TRIGGER on_review_updated
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_review_updated();

DROP TRIGGER IF EXISTS validate_review_before_insert ON public.reviews;
CREATE TRIGGER validate_review_before_insert
  BEFORE INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_review_eligibility();

DROP TRIGGER IF EXISTS update_rating_after_review_insert ON public.reviews;
CREATE TRIGGER update_rating_after_review_insert
  AFTER INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.recalculate_user_rating();

DROP TRIGGER IF EXISTS update_rating_after_review_update ON public.reviews;
CREATE TRIGGER update_rating_after_review_update
  AFTER UPDATE ON public.reviews
  FOR EACH ROW
  WHEN (OLD.rating IS DISTINCT FROM NEW.rating OR OLD.is_hidden IS DISTINCT FROM NEW.is_hidden)
  EXECUTE FUNCTION public.recalculate_user_rating();

DROP TRIGGER IF EXISTS update_rating_after_review_delete ON public.reviews;
CREATE TRIGGER update_rating_after_review_delete
  AFTER DELETE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.recalculate_user_rating();

-- ============================================
-- 6. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_ratings ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 7. CREATE RLS POLICIES
-- ============================================

-- Reviews policies
DROP POLICY IF EXISTS "Users can view reviews for providers" ON public.reviews;
DROP POLICY IF EXISTS "Users can view their own reviews" ON public.reviews;
DROP POLICY IF EXISTS "Users can create reviews" ON public.reviews;
DROP POLICY IF EXISTS "Users can update own reviews" ON public.reviews;
DROP POLICY IF EXISTS "Service role can manage reviews" ON public.reviews;

-- Anyone can view non-hidden reviews for providers
CREATE POLICY "Users can view reviews for providers"
ON public.reviews FOR SELECT
TO authenticated
USING (is_hidden = FALSE);

-- Users can view their own reviews even if hidden
CREATE POLICY "Users can view their own reviews"
ON public.reviews FOR SELECT
TO authenticated
USING (auth.uid() = reviewer_id OR auth.uid() = reviewee_id);

-- Users can create reviews for completed bookings
CREATE POLICY "Users can create reviews"
ON public.reviews FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = reviewer_id);

-- Users can update their own reviews within 7 days
CREATE POLICY "Users can update own reviews"
ON public.reviews FOR UPDATE
TO authenticated
USING (
  auth.uid() = reviewer_id AND
  created_at > NOW() - INTERVAL '7 days'
)
WITH CHECK (auth.uid() = reviewer_id);

CREATE POLICY "Service role can manage reviews"
ON public.reviews
TO service_role
USING (true)
WITH CHECK (true);

-- Provider ratings policies
DROP POLICY IF EXISTS "Anyone can view provider ratings" ON public.provider_ratings;
DROP POLICY IF EXISTS "Service role can manage ratings" ON public.provider_ratings;

CREATE POLICY "Anyone can view provider ratings"
ON public.provider_ratings FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Service role can manage ratings"
ON public.provider_ratings
TO service_role
USING (true)
WITH CHECK (true);

-- Client ratings policies
DROP POLICY IF EXISTS "Anyone can view client ratings" ON public.client_ratings;
DROP POLICY IF EXISTS "Service role can manage client ratings" ON public.client_ratings;

CREATE POLICY "Anyone can view client ratings"
ON public.client_ratings FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Service role can manage client ratings"
ON public.client_ratings
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 8. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT, UPDATE ON public.reviews TO authenticated;
GRANT ALL ON public.reviews TO service_role;

GRANT SELECT ON public.provider_ratings TO authenticated;
GRANT ALL ON public.provider_ratings TO service_role;

GRANT SELECT ON public.client_ratings TO authenticated;
GRANT ALL ON public.client_ratings TO service_role;

-- ============================================
-- 9. INITIALIZE PROVIDER RATINGS
-- ============================================

-- Create rating records for existing providers
INSERT INTO public.provider_ratings (provider_id)
SELECT id FROM public.profiles WHERE role = 'provider'
ON CONFLICT (provider_id) DO NOTHING;

-- Create rating records for existing clients
INSERT INTO public.client_ratings (client_id)
SELECT id FROM public.profiles WHERE role = 'client'
ON CONFLICT (client_id) DO NOTHING;

-- ============================================
-- REVIEWS & RATINGS SYSTEM COMPLETE
-- ============================================
