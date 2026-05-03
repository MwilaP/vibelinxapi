-- ============================================
-- VIBESLINX REFERRAL SYSTEM - PRODUCTION v1.0
-- ============================================

-- 1. EXTEND PROFILES TABLE WITH REFERRAL COLUMNS
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'referral_code') THEN
    ALTER TABLE public.profiles ADD COLUMN referral_code VARCHAR(20) UNIQUE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'referred_by_user_id') THEN
    ALTER TABLE public.profiles ADD COLUMN referred_by_user_id UUID REFERENCES public.profiles(id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'referral_code_used') THEN
    ALTER TABLE public.profiles ADD COLUMN referral_code_used VARCHAR(20);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'referral_joined_at') THEN
    ALTER TABLE public.profiles ADD COLUMN referral_joined_at TIMESTAMPTZ;
  END IF;
END $$;

-- 2. CREATE REFERRAL EARNINGS TABLE
DO $$ BEGIN
    CREATE TYPE referral_event_type AS ENUM (
      'client_subscription',
      'provider_visibility',
      'booking_platform_fee',
      'subscription_renewal'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE referral_earning_status AS ENUM (
      'pending',
      'confirmed',
      'missed',
      'paid_out'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.referral_earnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id UUID NOT NULL REFERENCES public.profiles(id),
  referred_user_id UUID NOT NULL REFERENCES public.profiles(id),
  event_type referral_event_type NOT NULL,
  source_id UUID NOT NULL, -- FK to the triggering record (booking id, subscription id, etc.)
  gross_amount DECIMAL(10,2) NOT NULL,
  reward_rate DECIMAL(5,4) NOT NULL,
  reward_amount DECIMAL(10,2) NOT NULL,
  status referral_earning_status DEFAULT 'pending',
  referrer_was_active BOOLEAN NOT NULL,
  missed_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. CREATE REFERRAL WALLETS TABLE
CREATE TABLE IF NOT EXISTS public.referral_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) UNIQUE,
  balance DECIMAL(10,2) DEFAULT 0.00,
  total_earned DECIMAL(10,2) DEFAULT 0.00,
  total_paid_out DECIMAL(10,2) DEFAULT 0.00,
  last_updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CREATE REFERRAL PAYOUTS TABLE
DO $$ BEGIN
    CREATE TYPE referral_payout_method AS ENUM (
      'mobile_money',
      'bank_transfer',
      'platform_credit'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE referral_payout_status AS ENUM (
      'requested',
      'processing',
      'completed',
      'rejected',
      'failed'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.referral_payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  amount DECIMAL(10,2) NOT NULL,
  method referral_payout_method NOT NULL,
  status referral_payout_status DEFAULT 'requested',
  reference VARCHAR(100),
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ -- Legacy field for completion
);

-- 5. CREATE REFERRAL FRAUD FLAGS TABLE
CREATE TABLE IF NOT EXISTS public.referral_fraud_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  flag_reason TEXT NOT NULL,
  ip_address VARCHAR(50),
  device_fingerprint VARCHAR(200),
  flagged_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed BOOLEAN DEFAULT FALSE,
  reviewed_by UUID REFERENCES public.profiles(id)
);

-- 6. CREATE INDEXES
CREATE INDEX IF NOT EXISTS idx_profiles_referral_code ON public.profiles(referral_code);
CREATE INDEX IF NOT EXISTS idx_profiles_referred_by_user_id ON public.profiles(referred_by_user_id);
CREATE INDEX IF NOT EXISTS idx_referral_earnings_referrer_status ON public.referral_earnings(referrer_user_id, status);
CREATE INDEX IF NOT EXISTS idx_referral_earnings_referred_user ON public.referral_earnings(referred_user_id);
CREATE INDEX IF NOT EXISTS idx_referral_earnings_source_id ON public.referral_earnings(source_id);
CREATE INDEX IF NOT EXISTS idx_referral_wallets_user_id ON public.referral_wallets(user_id);

-- 7. ADD DEFAULT SETTINGS TO system_settings
INSERT INTO public.system_settings (setting_key, setting_value, setting_type, display_name, description)
VALUES 
  ('referral_client_sub_rate', '0.15'::jsonb, 'number', 'Referral Client Sub Rate', 'Reward rate for client subscription referrals (15%)'),
  ('referral_visibility_rate', '0.15'::jsonb, 'number', 'Referral Visibility Rate', 'Reward rate for provider visibility referrals (15%)'),
  ('referral_booking_fee_rate', '0.20'::jsonb, 'number', 'Referral Booking Fee Rate', 'Reward rate for booking platform fees (20%)'),
  ('referral_min_payout', '20.00'::jsonb, 'currency', 'Minimum Referral Payout', 'Minimum amount required for a referral payout (K20)'),
  ('referral_sub_period_days', '30'::jsonb, 'number', 'Referral Subscription Period', 'Default subscription period in days (30)'),
  ('referral_fraud_threshold', '3'::jsonb, 'number', 'Referral Fraud Threshold', 'Max referrals from same IP/device per 24h'),
  ('referral_enabled', 'true'::jsonb, 'boolean', 'Referral System Enabled', 'Master toggle for the referral system')
ON CONFLICT (setting_key) DO NOTHING;

-- 8. UPDATE handle_new_user TRIGGER
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_first_name TEXT;
  v_random_digits TEXT;
  v_referral_code TEXT;
  v_referrer_id UUID;
  v_referral_code_used TEXT;
BEGIN
  -- 1. Extract first name and normalize
  v_first_name := UPPER(SPLIT_PART(NEW.raw_user_meta_data->>'display_name', ' ', 1));
  IF v_first_name = '' OR v_first_name IS NULL THEN
    v_first_name := 'USER';
  END IF;

  -- 2. Generate unique referral code: {FIRSTNAME}-{4-digits}
  LOOP
    v_random_digits := LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    v_referral_code := v_first_name || '-' || v_random_digits;
    
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_referral_code);
  END LOOP;

  -- 3. Check for referral code in metadata
  v_referral_code_used := NEW.raw_user_meta_data->>'referral_code';
  
  IF v_referral_code_used IS NOT NULL THEN
    -- Look up referrer
    SELECT id INTO v_referrer_id 
    FROM public.profiles 
    WHERE referral_code = UPPER(v_referral_code_used)
    AND id != NEW.id; -- Prevent self-referral
  END IF;

  -- 4. Insert into profiles
  INSERT INTO public.profiles (
    id, 
    display_name, 
    phone, 
    role, 
    referral_code, 
    referred_by_user_id, 
    referral_code_used,
    referral_joined_at
  )
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'display_name',
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'role',
    v_referral_code,
    v_referrer_id,
    v_referral_code_used,
    CASE WHEN v_referrer_id IS NOT NULL THEN NOW() ELSE NULL END
  );

  -- 5. Initialize referral wallet
  INSERT INTO public.referral_wallets (user_id) VALUES (NEW.id);

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9. ENABLE RLS
ALTER TABLE public.referral_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_fraud_flags ENABLE ROW LEVEL SECURITY;

-- 10. RLS POLICIES
DROP POLICY IF EXISTS "Users can view own referral earnings" ON public.referral_earnings;
CREATE POLICY "Users can view own referral earnings" ON public.referral_earnings FOR SELECT TO authenticated USING (referrer_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view own referral wallet" ON public.referral_wallets;
CREATE POLICY "Users can view own referral wallet" ON public.referral_wallets FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view own referral payouts" ON public.referral_payouts;
CREATE POLICY "Users can view own referral payouts" ON public.referral_payouts FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view all referral data" ON public.referral_earnings;
CREATE POLICY "Admins can view all referral data" ON public.referral_earnings TO authenticated USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()));

-- 11. HELPER FUNCTION TO CHECK IF REFERRER IS ACTIVE
CREATE OR REPLACE FUNCTION public.is_referrer_active(p_user_id UUID)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_active BOOLEAN := FALSE;
  v_role TEXT;
BEGIN
  -- Get user role
  SELECT role INTO v_role FROM public.profiles WHERE id = p_user_id;

  IF v_role = 'client' THEN
    -- Check client subscription
    SELECT EXISTS (
      SELECT 1 FROM public.subscriptions
      WHERE user_id = p_user_id
      AND status = 'active'
      AND end_date > NOW()
    ) INTO v_is_active;
  ELSIF v_role = 'provider' THEN
    -- Check provider visibility
    SELECT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = p_user_id
      AND visibility_status = 'active'
      AND (visibility_expires_at IS NULL OR visibility_expires_at > NOW())
    ) INTO v_is_active;
  END IF;

  RETURN v_is_active;
END;
$$ LANGUAGE plpgsql STABLE;

-- 12. PERMISSIONS
GRANT SELECT ON public.referral_earnings TO authenticated;
GRANT SELECT ON public.referral_wallets TO authenticated;
GRANT SELECT ON public.referral_payouts TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_referrer_active(UUID) TO authenticated;

GRANT ALL ON TABLE public.referral_earnings TO postgres, service_role;
GRANT ALL ON TABLE public.referral_wallets TO postgres, service_role;
GRANT ALL ON TABLE public.referral_payouts TO postgres, service_role;
GRANT ALL ON TABLE public.referral_fraud_flags TO postgres, service_role;
