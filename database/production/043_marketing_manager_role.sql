-- ================================================================
-- VIBESLINX MARKETING MANAGER SYSTEM - Migration 043
-- ================================================================
-- This migration adds marketing manager support to the referral system.
-- Marketing managers:
--   - Have role = 'marketing_manager' in profiles
--   - Are always considered "active" (no subscription required)
--   - Earn 25% on client_subscription and provider_visibility events
--   - Withdrawals are automatically disbursed via PawaPay

-- 1. ADD 'marketing_manager' TO ROLE ENUM
DO $$ BEGIN
  ALTER TYPE public.user_role ADD VALUE IF NOT EXISTS 'marketing_manager';
EXCEPTION
  WHEN duplicate_object THEN null;
  WHEN others THEN
    -- If user_role is a plain text column, this block handles it gracefully
    RAISE NOTICE 'Could not add enum value: %', SQLERRM;
END $$;

-- If role is stored as text (not enum), add a check constraint instead
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles'
    AND column_name = 'role'
    AND data_type = 'text'
  ) THEN
    -- Drop old constraint if exists, recreate with new value
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
      CHECK (role IN ('client', 'provider', 'marketing_manager'));
  END IF;
END $$;

-- 2. ADD MARKETING MANAGER COMMISSION RATE SETTINGS
INSERT INTO public.system_settings (setting_key, setting_value, setting_type, display_name, description)
VALUES
  ('marketing_manager_sub_rate', '0.25'::jsonb, 'number',
   'MM Client Subscription Rate',
   'Commission rate for marketing managers on client subscription events (25%)'),
  ('marketing_manager_visibility_rate', '0.25'::jsonb, 'number',
   'MM Provider Visibility Rate',
   'Commission rate for marketing managers on provider visibility fee events (25%)')
ON CONFLICT (setting_key) DO UPDATE
  SET setting_value = EXCLUDED.setting_value,
      updated_at = NOW();

-- 3. ADD pawapay_payout_id COLUMN TO referral_payouts
ALTER TABLE public.referral_payouts
  ADD COLUMN IF NOT EXISTS pawapay_payout_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ DEFAULT NOW();

COMMENT ON COLUMN public.referral_payouts.pawapay_payout_id IS
  'The PawaPay payout UUID returned when automatic disbursement is initiated';
COMMENT ON COLUMN public.referral_payouts.requested_at IS
  'Timestamp when the payout was requested by the marketing manager';

-- 4. UPDATE is_referrer_active() TO ALWAYS RETURN TRUE FOR MARKETING MANAGERS
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

  -- Marketing managers are always active
  IF v_role = 'marketing_manager' THEN
    RETURN TRUE;
  END IF;

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

-- 5. CREATE ADMIN VIEW FOR MARKETING MANAGERS
CREATE OR REPLACE VIEW public.admin_marketing_managers_view AS
SELECT
  p.id                                                    AS user_id,
  p.display_name,
  p.phone,
  p.referral_code,
  p.created_at                                            AS joined_at,
  -- Wallet stats
  COALESCE(rw.balance, 0)                                 AS available_balance,
  COALESCE(rw.total_earned, 0)                            AS total_earned,
  COALESCE(rw.total_paid_out, 0)                          AS total_paid_out,
  -- Referral counts
  COALESCE(referral_counts.total_referred, 0)             AS total_referred_users,
  -- Earnings breakdown
  COALESCE(earnings_stats.total_subscriptions, 0)         AS total_subscription_events,
  COALESCE(earnings_stats.total_visibility, 0)            AS total_visibility_events,
  COALESCE(earnings_stats.confirmed_commission, 0)        AS confirmed_commission,
  -- Payout stats
  COALESCE(payout_stats.pending_payouts, 0)               AS pending_payouts,
  COALESCE(payout_stats.completed_payouts, 0)             AS completed_payouts,
  COALESCE(payout_stats.total_payout_amount, 0)           AS total_payout_amount
FROM public.profiles p
LEFT JOIN public.referral_wallets rw ON rw.user_id = p.id
LEFT JOIN LATERAL (
  SELECT COUNT(*) AS total_referred
  FROM public.profiles
  WHERE referred_by_user_id = p.id
) referral_counts ON TRUE
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE event_type IN ('client_subscription','subscription_renewal')) AS total_subscriptions,
    COUNT(*) FILTER (WHERE event_type = 'provider_visibility')                          AS total_visibility,
    SUM(reward_amount) FILTER (WHERE status = 'confirmed')                              AS confirmed_commission
  FROM public.referral_earnings
  WHERE referrer_user_id = p.id
) earnings_stats ON TRUE
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE status IN ('requested','processing'))     AS pending_payouts,
    COUNT(*) FILTER (WHERE status = 'completed')                     AS completed_payouts,
    COALESCE(SUM(amount) FILTER (WHERE status = 'completed'), 0)     AS total_payout_amount
  FROM public.referral_payouts
  WHERE user_id = p.id
) payout_stats ON TRUE
WHERE p.role = 'marketing_manager'
ORDER BY p.created_at DESC;

-- Grant access to the view
GRANT SELECT ON public.admin_marketing_managers_view TO authenticated, service_role;

-- 6. RLS POLICIES FOR MARKETING MANAGERS ON REFERRAL TABLES

-- Referral earnings
DROP POLICY IF EXISTS "Marketing managers can view own referral earnings" ON public.referral_earnings;
CREATE POLICY "Marketing managers can view own referral earnings"
  ON public.referral_earnings FOR SELECT TO authenticated
  USING (referrer_user_id = auth.uid());

-- Referral wallets
DROP POLICY IF EXISTS "Marketing managers can view own referral wallet" ON public.referral_wallets;
CREATE POLICY "Marketing managers can view own referral wallet"
  ON public.referral_wallets FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Referral payouts
DROP POLICY IF EXISTS "Marketing managers can view own referral payouts" ON public.referral_payouts;
CREATE POLICY "Marketing managers can view own referral payouts"
  ON public.referral_payouts FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 7. FUNCTION TO REGISTER A MARKETING MANAGER PROFILE
-- Called by service role after Supabase Auth user creation
CREATE OR REPLACE FUNCTION public.create_marketing_manager_profile(
  p_user_id UUID,
  p_display_name TEXT,
  p_phone TEXT
)
RETURNS TEXT -- returns the generated referral code
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_first_name TEXT;
  v_random_digits TEXT;
  v_referral_code TEXT;
BEGIN
  v_first_name := UPPER(SPLIT_PART(p_display_name, ' ', 1));
  IF v_first_name = '' OR v_first_name IS NULL THEN
    v_first_name := 'MM';
  END IF;

  -- Generate unique referral code: {FIRSTNAME}-{4-digits}
  LOOP
    v_random_digits := LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    v_referral_code := v_first_name || '-' || v_random_digits;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_referral_code);
  END LOOP;

  -- Insert profile
  INSERT INTO public.profiles (id, display_name, phone, role, referral_code, onboarding_completed)
  VALUES (p_user_id, p_display_name, p_phone, 'marketing_manager', v_referral_code, TRUE)
  ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        phone = EXCLUDED.phone,
        role = 'marketing_manager',
        referral_code = COALESCE(profiles.referral_code, EXCLUDED.referral_code);

  -- Create referral wallet
  INSERT INTO public.referral_wallets (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN v_referral_code;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.create_marketing_manager_profile(UUID, TEXT, TEXT) TO service_role;

-- Done
