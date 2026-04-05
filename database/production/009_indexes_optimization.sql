-- ============================================
-- VIBESLINX INDEXES & OPTIMIZATION - PRODUCTION v1.0
-- Performance Optimization & Materialized Views
-- ============================================
-- This migration creates additional performance indexes and
-- materialized views for optimized queries.
-- Consolidated from: 010_search_indexes.sql
-- ============================================

-- ============================================
-- 1. CREATE MATERIALIZED VIEW FOR TOP PROVIDERS
-- ============================================

CREATE MATERIALIZED VIEW IF NOT EXISTS public.top_providers AS
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
WHERE p.role = 'provider' AND p.onboarding_completed = TRUE
GROUP BY p.id, p.display_name, p.city, p.bio, p.photos, p.services, pr.average_rating, pr.total_reviews
ORDER BY pr.average_rating DESC NULLS LAST, pr.total_reviews DESC;

-- Create indexes on materialized view
CREATE UNIQUE INDEX IF NOT EXISTS idx_top_providers_id ON public.top_providers(id);
CREATE INDEX IF NOT EXISTS idx_top_providers_rating ON public.top_providers(average_rating DESC);
CREATE INDEX IF NOT EXISTS idx_top_providers_city ON public.top_providers(city);

-- Grant access
GRANT SELECT ON public.top_providers TO authenticated;

-- ============================================
-- 2. CREATE FUNCTION TO REFRESH MATERIALIZED VIEW
-- ============================================

-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION public.refresh_top_providers()
RETURNS void 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.top_providers;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.refresh_top_providers() TO service_role;

-- ============================================
-- 3. ADDITIONAL COMPOSITE INDEXES
-- ============================================

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_bookings_provider_status_date 
  ON public.bookings(provider_id, status, booking_date DESC);

CREATE INDEX IF NOT EXISTS idx_bookings_client_status_date 
  ON public.bookings(client_id, status, booking_date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_user_type_status 
  ON public.transactions(user_id, type, status);

CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_type_date 
  ON public.wallet_transactions(wallet_id, transaction_type, created_at DESC);

-- ============================================
-- 4. PARTIAL INDEXES FOR COMMON FILTERS
-- ============================================

-- Active bookings only
CREATE INDEX IF NOT EXISTS idx_bookings_active 
  ON public.bookings(provider_id, booking_date) 
  WHERE status IN ('pending', 'confirmed', 'in_progress');

-- Completed transactions only
CREATE INDEX IF NOT EXISTS idx_transactions_completed 
  ON public.transactions(user_id, created_at DESC) 
  WHERE status = 'completed';

-- Active wallets only
CREATE INDEX IF NOT EXISTS idx_wallets_active 
  ON public.wallets(user_id) 
  WHERE status = 'active';

-- Pending withdrawal requests
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_pending 
  ON public.withdrawal_requests(created_at DESC) 
  WHERE status = 'pending';

-- ============================================
-- 5. COVERING INDEXES FOR COMMON QUERIES
-- ============================================

-- Booking list with essential fields
CREATE INDEX IF NOT EXISTS idx_bookings_list_covering 
  ON public.bookings(client_id, created_at DESC) 
  INCLUDE (provider_id, service_name, total_amount, status);

-- Transaction history with details
CREATE INDEX IF NOT EXISTS idx_transactions_history_covering 
  ON public.transactions(user_id, created_at DESC) 
  INCLUDE (amount, type, status, description);

-- ============================================
-- 6. EXPRESSION INDEXES
-- ============================================

-- Case-insensitive email search (if needed in future)
CREATE INDEX IF NOT EXISTS idx_profiles_phone_lower 
  ON public.profiles(LOWER(phone));

-- Date-based booking queries
CREATE INDEX IF NOT EXISTS idx_bookings_date_trunc_month 
  ON public.bookings(DATE_TRUNC('month', booking_date));

-- ============================================
-- INDEXES & OPTIMIZATION COMPLETE
-- ============================================
