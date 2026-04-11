-- ============================================
-- PROVIDER WITHDRAWAL & PAYOUT SYSTEM
-- Lencopay Integration for Provider Withdrawals
-- ============================================

-- ============================================
-- 1. UPDATE WITHDRAWAL REQUESTS TABLE
-- ============================================

-- Add new columns for fee tracking and Lenco integration
ALTER TABLE public.withdrawal_requests 
ADD COLUMN IF NOT EXISTS fee_amount DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS net_amount DECIMAL(10, 2),
ADD COLUMN IF NOT EXISTS lenco_reference VARCHAR(100),
ADD COLUMN IF NOT EXISTS lenco_payout_id VARCHAR(100),
ADD COLUMN IF NOT EXISTS external_transaction_id VARCHAR(100),
ADD COLUMN IF NOT EXISTS fee_tier VARCHAR(20);

-- Add comment for clarity
COMMENT ON COLUMN public.withdrawal_requests.fee_amount IS 'Lencopay fee deducted from withdrawal amount';
COMMENT ON COLUMN public.withdrawal_requests.net_amount IS 'Amount provider receives after fees (amount - fee_amount)';
COMMENT ON COLUMN public.withdrawal_requests.lenco_reference IS 'Unique reference for Lencopay payout tracking';
COMMENT ON COLUMN public.withdrawal_requests.lenco_payout_id IS 'Lencopay payout ID from API response';

-- ============================================
-- 2. CREATE PAYOUT METHODS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.payout_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('mtn', 'airtel', 'zamtel')),
  payment_phone VARCHAR(20) NOT NULL,
  account_name VARCHAR(100),
  is_default BOOLEAN NOT NULL DEFAULT false,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_user_phone UNIQUE(user_id, payment_phone)
);

COMMENT ON TABLE public.payout_methods IS 'Saved payout methods for provider withdrawals';

-- ============================================
-- 3. CREATE INDEXES
-- ============================================

-- Withdrawal requests indexes
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_lenco_reference 
ON public.withdrawal_requests(lenco_reference);

CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status_created 
ON public.withdrawal_requests(status, created_at DESC);

-- Payout methods indexes
CREATE INDEX IF NOT EXISTS idx_payout_methods_user_id 
ON public.payout_methods(user_id);

CREATE INDEX IF NOT EXISTS idx_payout_methods_is_default 
ON public.payout_methods(user_id, is_default) 
WHERE is_default = true;

CREATE INDEX IF NOT EXISTS idx_payout_methods_last_used 
ON public.payout_methods(user_id, last_used_at DESC);

-- ============================================
-- 4. ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on payout_methods
ALTER TABLE public.payout_methods ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own payout methods" ON public.payout_methods;
DROP POLICY IF EXISTS "Users can insert their own payout methods" ON public.payout_methods;
DROP POLICY IF EXISTS "Users can update their own payout methods" ON public.payout_methods;
DROP POLICY IF EXISTS "Users can delete their own payout methods" ON public.payout_methods;
DROP POLICY IF EXISTS "Admins can view all payout methods" ON public.payout_methods;

-- Users can manage their own payout methods
CREATE POLICY "Users can view their own payout methods"
ON public.payout_methods
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own payout methods"
ON public.payout_methods
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own payout methods"
ON public.payout_methods
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own payout methods"
ON public.payout_methods
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- Admins can view all payout methods
CREATE POLICY "Admins can view all payout methods"
ON public.payout_methods
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE admin_users.user_id = auth.uid()
    AND admin_users.status = 'active'
  )
);

-- Update withdrawal_requests policies for provider access
DROP POLICY IF EXISTS "Providers can view their own withdrawal requests" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Providers can create withdrawal requests" ON public.withdrawal_requests;

CREATE POLICY "Providers can view their own withdrawal requests"
ON public.withdrawal_requests
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Providers can create withdrawal requests"
ON public.withdrawal_requests
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- ============================================
-- 5. TRIGGER FUNCTIONS
-- ============================================

-- Function to ensure only one default payout method per user
CREATE OR REPLACE FUNCTION public.ensure_single_default_payout_method()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_default = true THEN
    -- Unset other default methods for this user
    UPDATE public.payout_methods
    SET is_default = false, updated_at = NOW()
    WHERE user_id = NEW.user_id 
    AND id != NEW.id 
    AND is_default = true;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to enforce single default payout method
DROP TRIGGER IF EXISTS trigger_ensure_single_default_payout_method ON public.payout_methods;
CREATE TRIGGER trigger_ensure_single_default_payout_method
BEFORE INSERT OR UPDATE ON public.payout_methods
FOR EACH ROW
EXECUTE FUNCTION public.ensure_single_default_payout_method();

-- Function to update payout method timestamp
CREATE OR REPLACE FUNCTION public.update_payout_method_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update payout method timestamp
DROP TRIGGER IF EXISTS trigger_update_payout_method_timestamp ON public.payout_methods;
CREATE TRIGGER trigger_update_payout_method_timestamp
BEFORE UPDATE ON public.payout_methods
FOR EACH ROW
EXECUTE FUNCTION public.update_payout_method_timestamp();

-- ============================================
-- 6. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_methods TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.withdrawal_requests TO authenticated;

-- ============================================
-- 7. VERIFICATION QUERIES
-- ============================================

-- Verify withdrawal_requests columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'withdrawal_requests'
AND column_name IN ('fee_amount', 'net_amount', 'lenco_reference', 'lenco_payout_id', 'external_transaction_id', 'fee_tier');

-- Verify payout_methods table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'payout_methods'
ORDER BY ordinal_position;

-- Verify indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
AND (tablename = 'withdrawal_requests' OR tablename = 'payout_methods')
AND indexname LIKE '%withdrawal%' OR indexname LIKE '%payout%'
ORDER BY tablename, indexname;

-- Verify RLS policies
SELECT tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
AND tablename IN ('withdrawal_requests', 'payout_methods')
ORDER BY tablename, policyname;
