-- ============================================
-- SYSTEM SETTINGS TABLE
-- Admin-Configurable Platform Settings
-- ============================================

-- ============================================
-- 1. CREATE SYSTEM SETTINGS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.system_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key TEXT NOT NULL UNIQUE,
  setting_value JSONB NOT NULL,
  setting_type TEXT NOT NULL CHECK (setting_type IN ('currency', 'number', 'text', 'boolean', 'json')),
  description TEXT,
  display_name TEXT NOT NULL,
  updated_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.system_settings IS 'Admin-configurable platform settings';
COMMENT ON COLUMN public.system_settings.setting_key IS 'Unique identifier for the setting';
COMMENT ON COLUMN public.system_settings.setting_value IS 'JSONB value allowing flexible data types';
COMMENT ON COLUMN public.system_settings.setting_type IS 'Type of setting for validation and display';
COMMENT ON COLUMN public.system_settings.updated_by IS 'Admin user who last updated this setting';

-- ============================================
-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_system_settings_key ON public.system_settings(setting_key);
CREATE INDEX IF NOT EXISTS idx_system_settings_updated_at ON public.system_settings(updated_at DESC);

-- ============================================
-- 3. INSERT DEFAULT SETTINGS
-- ============================================

INSERT INTO public.system_settings (setting_key, setting_value, setting_type, display_name, description)
VALUES 
  (
    'min_withdrawal_amount',
    '50'::jsonb,
    'currency',
    'Minimum Withdrawal Amount',
    'Minimum amount (in Kwacha) that providers can withdraw from their wallet'
  ),
  (
    'monthly_subscription_fee',
    '50'::jsonb,
    'currency',
    'Monthly Subscription Fee',
    'Monthly subscription fee (in Kwacha) for client users'
  ),
  (
    'annual_subscription_fee',
    '500'::jsonb,
    'currency',
    'Annual Subscription Fee',
    'Annual subscription fee (in Kwacha) for client users'
  )
ON CONFLICT (setting_key) DO NOTHING;

-- ============================================
-- 4. HELPER FUNCTIONS
-- ============================================

-- Function to get setting value
CREATE OR REPLACE FUNCTION public.get_setting_value(p_setting_key TEXT)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_value JSONB;
BEGIN
  SELECT setting_value INTO v_value
  FROM public.system_settings
  WHERE setting_key = p_setting_key;
  
  RETURN v_value;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get setting as decimal (for currency/number types)
CREATE OR REPLACE FUNCTION public.get_setting_decimal(p_setting_key TEXT)
RETURNS DECIMAL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_value DECIMAL;
BEGIN
  SELECT (setting_value)::text::decimal INTO v_value
  FROM public.system_settings
  WHERE setting_key = p_setting_key;
  
  RETURN COALESCE(v_value, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to update setting (with audit trail)
CREATE OR REPLACE FUNCTION public.update_setting(
  p_setting_key TEXT,
  p_setting_value JSONB,
  p_updated_by UUID
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  -- Check if user is an active admin
  SELECT EXISTS(
    SELECT 1 FROM public.admin_users
    WHERE user_id = p_updated_by
    AND status = 'active'
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Only active admins can update settings';
  END IF;
  
  -- Update the setting
  UPDATE public.system_settings
  SET 
    setting_value = p_setting_value,
    updated_by = p_updated_by,
    updated_at = NOW()
  WHERE setting_key = p_setting_key;
  
  RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Admins can view all settings" ON public.system_settings;
DROP POLICY IF EXISTS "Admins can update settings" ON public.system_settings;
DROP POLICY IF EXISTS "Authenticated users can view settings" ON public.system_settings;

-- Authenticated users can view settings (read-only for non-admins)
CREATE POLICY "Authenticated users can view settings"
ON public.system_settings
FOR SELECT
TO authenticated
USING (true);

-- Only admins can update settings
CREATE POLICY "Admins can update settings"
ON public.system_settings
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE admin_users.user_id = auth.uid()
    AND admin_users.status = 'active'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE admin_users.user_id = auth.uid()
    AND admin_users.status = 'active'
  )
);

-- ============================================
-- 6. GRANT PERMISSIONS
-- ============================================

GRANT SELECT ON public.system_settings TO authenticated;
GRANT UPDATE ON public.system_settings TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_setting_value(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_setting_decimal(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_setting(TEXT, JSONB, UUID) TO authenticated;

-- ============================================
-- 7. VERIFICATION QUERIES
-- ============================================

-- Verify table structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'system_settings'
ORDER BY ordinal_position;

-- Verify default settings
SELECT setting_key, setting_value, setting_type, display_name
FROM public.system_settings
ORDER BY setting_key;

-- ============================================
-- SYSTEM SETTINGS COMPLETE
-- ============================================
