-- ============================================
-- VIBESLINX BOOKINGS SYSTEM - PRODUCTION v1.0
-- Booking Management, Status Tracking & RLS
-- ============================================
-- This migration creates the bookings table with all payment tracking,
-- status management, and automated timestamp triggers.
-- Includes all fixes from: 014_add_commitment_percentage.sql, 
-- 018_fix_booking_profile_access.sql, 019_add_payment_tracking.sql,
-- 026_remove_booking_date_constraint.sql, 030_add_wallet_payment_type.sql
-- ============================================

-- ============================================
-- 1. CREATE BOOKINGS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Service Details
  service_name TEXT NOT NULL,
  service_duration TEXT NOT NULL,
  service_price DECIMAL(10, 2) NOT NULL,
  
  -- Booking Details
  booking_date DATE NOT NULL,
  booking_time TIME NOT NULL,
  duration_minutes INTEGER NOT NULL DEFAULT 120,
  
  -- Location
  location_type TEXT NOT NULL CHECK (location_type IN ('my', 'provider', 'hotel')),
  location_details TEXT,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'in_progress', 'completed', 'cancelled', 'declined')),
  
  -- Pricing
  platform_fee DECIMAL(10, 2) NOT NULL DEFAULT 0,
  commitment_fee DECIMAL(10, 2) NOT NULL,
  commitment_percentage DECIMAL(5, 4) NOT NULL DEFAULT 0.10,
  balance_due DECIMAL(10, 2) NOT NULL,
  total_amount DECIMAL(10, 2) NOT NULL,
  
  -- Payment Tracking
  payment_type TEXT CHECK (payment_type IN ('commitment', 'balance', 'full', 'wallet')),
  commitment_paid BOOLEAN DEFAULT FALSE,
  commitment_transaction_id TEXT,
  commitment_paid_at TIMESTAMPTZ,
  balance_paid BOOLEAN DEFAULT FALSE,
  balance_transaction_id TEXT,
  balance_paid_at TIMESTAMPTZ,
  full_payment_transaction_id TEXT,
  full_payment_at TIMESTAMPTZ,
  
  -- Notifications
  notification_sent BOOLEAN DEFAULT FALSE,
  notification_sent_at TIMESTAMPTZ,
  
  -- Notes
  client_notes TEXT,
  provider_notes TEXT,
  cancellation_reason TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  confirmed_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  declined_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT valid_prices CHECK (
    service_price > 0 AND 
    commitment_fee >= 0 AND 
    balance_due >= 0 AND 
    total_amount > 0
  ),
  CONSTRAINT different_users CHECK (client_id != provider_id)
);

COMMENT ON COLUMN public.bookings.commitment_percentage IS 'Percentage of total amount required as commitment fee (e.g., 0.10 for 10%)';

-- ============================================
-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_bookings_client_id ON public.bookings(client_id);
CREATE INDEX IF NOT EXISTS idx_bookings_provider_id ON public.bookings(provider_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_date ON public.bookings(booking_date);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at ON public.bookings(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_commitment_paid ON public.bookings(commitment_paid);
CREATE INDEX IF NOT EXISTS idx_bookings_balance_paid ON public.bookings(balance_paid);

-- Composite index for provider's pending bookings
CREATE INDEX IF NOT EXISTS idx_bookings_provider_pending ON public.bookings(provider_id, status) 
  WHERE status IN ('pending', 'confirmed');

-- Composite index for client's active bookings
CREATE INDEX IF NOT EXISTS idx_bookings_client_active ON public.bookings(client_id, status) 
  WHERE status IN ('pending', 'confirmed', 'in_progress');

-- ============================================
-- 3. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Function to update booking timestamps
CREATE OR REPLACE FUNCTION public.handle_booking_updated()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  
  -- Set timestamp based on status change
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
    NEW.confirmed_at = NOW();
  END IF;
  
  IF NEW.status = 'in_progress' AND OLD.status != 'in_progress' THEN
    NEW.started_at = NOW();
  END IF;
  
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at = NOW();
  END IF;
  
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    NEW.cancelled_at = NOW();
  END IF;
  
  IF NEW.status = 'declined' AND OLD.status != 'declined' THEN
    NEW.declined_at = NOW();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS on_booking_updated ON public.bookings;
CREATE TRIGGER on_booking_updated
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_booking_updated();

-- ============================================
-- 5. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. CREATE RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Clients can view own bookings" ON public.bookings;
DROP POLICY IF EXISTS "Providers can view their bookings" ON public.bookings;
DROP POLICY IF EXISTS "Clients can create bookings" ON public.bookings;
DROP POLICY IF EXISTS "Clients can update own pending bookings" ON public.bookings;
DROP POLICY IF EXISTS "Providers can update their bookings" ON public.bookings;
DROP POLICY IF EXISTS "Service role can manage bookings" ON public.bookings;

-- Clients can view their own bookings
CREATE POLICY "Clients can view own bookings"
ON public.bookings FOR SELECT
TO authenticated
USING (auth.uid() = client_id);

-- Providers can view bookings where they are the provider
CREATE POLICY "Providers can view their bookings"
ON public.bookings FOR SELECT
TO authenticated
USING (auth.uid() = provider_id);

-- Clients can create bookings
CREATE POLICY "Clients can create bookings"
ON public.bookings FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = client_id AND
  status = 'pending'
);

-- Clients can update their own pending bookings (to cancel)
CREATE POLICY "Clients can update own pending bookings"
ON public.bookings FOR UPDATE
TO authenticated
USING (
  auth.uid() = client_id AND
  status IN ('pending', 'confirmed')
)
WITH CHECK (
  auth.uid() = client_id
);

-- Providers can update bookings where they are the provider
CREATE POLICY "Providers can update their bookings"
ON public.bookings FOR UPDATE
TO authenticated
USING (
  auth.uid() = provider_id
)
WITH CHECK (
  auth.uid() = provider_id
);

-- Service role can manage all bookings
CREATE POLICY "Service role can manage bookings"
ON public.bookings
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 7. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT, UPDATE ON public.bookings TO authenticated;
GRANT ALL ON public.bookings TO service_role;

-- ============================================
-- BOOKINGS SYSTEM COMPLETE
-- ============================================
