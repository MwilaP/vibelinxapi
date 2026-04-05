-- ============================================
-- VIBESLINX SUBSCRIPTION SYSTEM - PRODUCTION v1.0
-- Client Subscription Management
-- ============================================
-- This migration creates the subscription system for clients
-- with automated status updates and wallet integration.
-- Includes all fixes from: 033_fix_subscription_wallet_permissions.sql,
-- 035_secure_subscription_purchase.sql
-- ============================================

-- ============================================
-- 1. CREATE SUBSCRIPTIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Subscription details
  plan_type TEXT NOT NULL CHECK (plan_type IN ('monthly', 'annual')),
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'cancelled')) DEFAULT 'active',
  
  -- Dates
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ NOT NULL,
  
  -- Payment
  amount_paid DECIMAL(10, 2) NOT NULL,
  transaction_id UUID REFERENCES public.transactions(id),
  
  -- Settings
  auto_renew BOOLEAN DEFAULT true,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT valid_amount CHECK (amount_paid > 0),
  CONSTRAINT valid_dates CHECK (end_date > start_date)
);

-- ============================================
-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_end_date ON public.subscriptions(end_date);

-- ============================================
-- 3. CREATE FUNCTIONS
-- ============================================

-- Function to check if user has active subscription
CREATE OR REPLACE FUNCTION public.check_subscription_status(p_user_id UUID)
RETURNS BOOLEAN 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  has_active_subscription BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 
    FROM public.subscriptions 
    WHERE user_id = p_user_id 
    AND status = 'active' 
    AND end_date > NOW()
  ) INTO has_active_subscription;
  
  RETURN has_active_subscription;
END;
$$ LANGUAGE plpgsql;

-- Function to update profile subscription status
CREATE OR REPLACE FUNCTION public.update_profile_subscription_status()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update profile subscription_status based on subscription
  IF NEW.status = 'active' AND NEW.end_date > NOW() THEN
    UPDATE public.profiles
    SET subscription_status = 'active'
    WHERE id = NEW.user_id;
  ELSIF NEW.status = 'expired' OR NEW.end_date <= NOW() THEN
    UPDATE public.profiles
    SET subscription_status = 'expired'
    WHERE id = NEW.user_id;
  ELSIF NEW.status = 'cancelled' THEN
    UPDATE public.profiles
    SET subscription_status = 'inactive'
    WHERE id = NEW.user_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to expire subscriptions (run via cron)
CREATE OR REPLACE FUNCTION public.expire_subscriptions()
RETURNS void 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update expired subscriptions
  UPDATE public.subscriptions
  SET status = 'expired', updated_at = NOW()
  WHERE status = 'active' 
  AND end_date <= NOW();
  
  -- Update profile statuses for expired subscriptions
  UPDATE public.profiles p
  SET subscription_status = 'expired'
  WHERE p.id IN (
    SELECT user_id 
    FROM public.subscriptions 
    WHERE status = 'expired'
  );
END;
$$ LANGUAGE plpgsql;

-- Function to calculate subscription end date
CREATE OR REPLACE FUNCTION public.calculate_subscription_end_date(
  p_plan_type TEXT,
  p_start_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TIMESTAMPTZ AS $$
BEGIN
  CASE p_plan_type
    WHEN 'monthly' THEN
      RETURN p_start_date + INTERVAL '1 month';
    WHEN 'annual' THEN
      RETURN p_start_date + INTERVAL '1 year';
    ELSE
      RAISE EXCEPTION 'Invalid plan type: %', p_plan_type;
  END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get subscription price
CREATE OR REPLACE FUNCTION public.get_subscription_price(p_plan_type TEXT)
RETURNS DECIMAL AS $$
BEGIN
  CASE p_plan_type
    WHEN 'monthly' THEN
      RETURN 50.00;
    WHEN 'annual' THEN
      RETURN 500.00;
    ELSE
      RAISE EXCEPTION 'Invalid plan type: %', p_plan_type;
  END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Secure function to purchase subscription with wallet
CREATE OR REPLACE FUNCTION public.purchase_subscription_with_wallet(
  p_user_id UUID,
  p_plan_type TEXT
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_price DECIMAL(10, 2);
  v_wallet_balance DECIMAL(10, 2);
  v_subscription_id UUID;
  v_transaction_id UUID;
  v_end_date TIMESTAMPTZ;
BEGIN
  -- Verify user is authenticated
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: Can only purchase subscription for yourself';
  END IF;
  
  -- Get subscription price
  v_price := public.get_subscription_price(p_plan_type);
  
  -- Get user's wallet balance
  SELECT available_balance INTO v_wallet_balance
  FROM public.wallet_balances
  WHERE user_id = p_user_id;
  
  -- Check if user has sufficient balance
  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;
  
  -- Calculate end date
  v_end_date := public.calculate_subscription_end_date(p_plan_type, NOW());
  
  -- Create transaction record
  INSERT INTO public.transactions (
    user_id,
    amount,
    type,
    status,
    payment_method,
    description,
    completed_at
  ) VALUES (
    p_user_id,
    -v_price,
    'payment',
    'completed',
    'wallet',
    'Subscription purchase: ' || p_plan_type,
    NOW()
  )
  RETURNING id INTO v_transaction_id;
  
  -- Deduct from wallet
  UPDATE public.wallet_balances
  SET 
    available_balance = available_balance - v_price,
    total_spent = total_spent + v_price,
    updated_at = NOW()
  WHERE user_id = p_user_id;
  
  -- Create subscription
  INSERT INTO public.subscriptions (
    user_id,
    plan_type,
    status,
    start_date,
    end_date,
    amount_paid,
    transaction_id
  ) VALUES (
    p_user_id,
    p_plan_type,
    'active',
    NOW(),
    v_end_date,
    v_price,
    v_transaction_id
  )
  RETURNING id INTO v_subscription_id;
  
  RETURN v_subscription_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. CREATE TRIGGERS
-- ============================================

-- Update profile subscription status when subscription changes
DROP TRIGGER IF EXISTS on_subscription_changed ON public.subscriptions;
CREATE TRIGGER on_subscription_changed
  AFTER INSERT OR UPDATE ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_profile_subscription_status();

-- Update subscription updated_at timestamp
DROP TRIGGER IF EXISTS on_subscription_updated ON public.subscriptions;
CREATE TRIGGER on_subscription_updated
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ============================================
-- 5. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. CREATE RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Users can view own subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Users can insert own subscriptions" ON public.subscriptions;
DROP POLICY IF EXISTS "Service role can manage subscriptions" ON public.subscriptions;

-- Users can view their own subscriptions
CREATE POLICY "Users can view own subscriptions"
ON public.subscriptions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Users can insert their own subscriptions (via secure function)
CREATE POLICY "Users can insert own subscriptions"
ON public.subscriptions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Service role can manage all subscriptions
CREATE POLICY "Service role can manage subscriptions"
ON public.subscriptions
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 7. CREATE SUBSCRIPTION VIEW
-- ============================================

CREATE OR REPLACE VIEW public.user_subscription_status AS
SELECT 
  p.id as user_id,
  p.display_name,
  p.subscription_status,
  s.id as subscription_id,
  s.plan_type,
  s.status,
  s.start_date,
  s.end_date,
  s.amount_paid,
  s.auto_renew,
  CASE 
    WHEN s.end_date > NOW() THEN EXTRACT(DAY FROM (s.end_date - NOW()))
    ELSE 0
  END as days_remaining
FROM public.profiles p
LEFT JOIN public.subscriptions s ON s.user_id = p.id 
  AND s.status = 'active' 
  AND s.end_date > NOW()
WHERE p.role = 'client';

GRANT SELECT ON public.user_subscription_status TO authenticated;

-- ============================================
-- 8. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT ON public.subscriptions TO authenticated;
GRANT ALL ON public.subscriptions TO service_role;

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION public.check_subscription_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_subscription_end_date(TEXT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_subscription_price(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.purchase_subscription_with_wallet(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_subscriptions() TO service_role;

-- ============================================
-- SUBSCRIPTION SYSTEM COMPLETE
-- ============================================
