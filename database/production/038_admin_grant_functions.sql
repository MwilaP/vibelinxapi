-- ============================================
-- ADMIN GRANT FUNCTIONS
-- ============================================

-- Function: Grant Subscription to a Client
CREATE OR REPLACE FUNCTION public.admin_grant_subscription(
  p_user_id UUID,
  p_plan_type TEXT
) RETURNS VOID AS $$
DECLARE
  v_admin_id UUID;
  v_end_date TIMESTAMPTZ;
BEGIN
  -- 1. Check if requester is an admin
  SELECT id INTO v_admin_id FROM public.admin_users WHERE user_id = auth.uid() AND status = 'active';
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Requester is not an active admin';
  END IF;

  -- 2. Calculate end date
  IF p_plan_type = 'monthly' THEN
    v_end_date := NOW() + INTERVAL '30 days';
  ELSIF p_plan_type = 'annual' THEN
    v_end_date := NOW() + INTERVAL '365 days';
  ELSE
    RAISE EXCEPTION 'Invalid plan type: Must be monthly or annual';
  END IF;

  -- 3. Create subscription record
  INSERT INTO public.subscriptions (
    user_id,
    plan_type,
    status,
    start_date,
    end_date,
    amount_paid,
    transaction_id,
    auto_renew,
    metadata
  ) VALUES (
    p_user_id,
    p_plan_type,
    'active',
    NOW(),
    v_end_date,
    0,
    'admin-grant-' || extract(epoch from now())::text,
    FALSE,
    jsonb_build_object('granted_by', v_admin_id)
  );

  -- 4. Update profile
  UPDATE public.profiles
  SET 
    subscription_status = 'active',
    updated_at = NOW()
  WHERE id = p_user_id;

  -- 5. Log action
  INSERT INTO public.admin_activity_log (
    admin_id,
    action_category,
    action_type,
    target_type,
    target_id,
    action_details,
    success
  ) VALUES (
    v_admin_id,
    'subscription_management',
    'grant_subscription',
    'user',
    p_user_id::text,
    jsonb_build_object('plan_type', p_plan_type),
    TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Grant Visibility to a Provider
CREATE OR REPLACE FUNCTION public.admin_grant_visibility(
  p_user_id UUID,
  p_days INTEGER DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_admin_id UUID;
  v_expires_at TIMESTAMPTZ := NULL;
BEGIN
  -- 1. Check if requester is an admin
  SELECT id INTO v_admin_id FROM public.admin_users WHERE user_id = auth.uid() AND status = 'active';
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Requester is not an active admin';
  END IF;

  -- 2. Calculate expiration
  IF p_days IS NOT NULL THEN
    v_expires_at := NOW() + (p_days || ' days')::INTERVAL;
  END IF;

  -- 3. Update profile
  UPDATE public.profiles
  SET 
    visibility_status = 'active',
    visibility_expires_at = v_expires_at,
    updated_at = NOW()
  WHERE id = p_user_id AND role = 'provider';

  -- 4. Log action
  INSERT INTO public.admin_activity_log (
    admin_id,
    action_category,
    action_type,
    target_type,
    target_id,
    action_details,
    success
  ) VALUES (
    v_admin_id,
    'provider_management',
    'grant_visibility',
    'user',
    p_user_id::text,
    jsonb_build_object('days', p_days),
    TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Remove Subscription from a Client
CREATE OR REPLACE FUNCTION public.admin_remove_subscription(
  p_user_id UUID
) RETURNS VOID AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- 1. Check if requester is an admin
  SELECT id INTO v_admin_id FROM public.admin_users WHERE user_id = auth.uid() AND status = 'active';
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Requester is not an active admin';
  END IF;

  -- 2. Cancel all active subscriptions
  UPDATE public.subscriptions
  SET 
    status = 'cancelled',
    updated_at = NOW()
  WHERE user_id = p_user_id AND status = 'active';

  -- 3. Update profile
  UPDATE public.profiles
  SET 
    subscription_status = 'inactive',
    updated_at = NOW()
  WHERE id = p_user_id;

  -- 4. Log action
  INSERT INTO public.admin_activity_log (
    admin_id,
    action_category,
    action_type,
    target_type,
    target_id,
    action_details,
    success
  ) VALUES (
    v_admin_id,
    'subscription_management',
    'remove_subscription',
    'user',
    p_user_id::text,
    jsonb_build_object('action', 'removal'),
    TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Remove Visibility from a Provider
CREATE OR REPLACE FUNCTION public.admin_remove_visibility(
  p_user_id UUID
) RETURNS VOID AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- 1. Check if requester is an admin
  SELECT id INTO v_admin_id FROM public.admin_users WHERE user_id = auth.uid() AND status = 'active';
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Requester is not an active admin';
  END IF;

  -- 2. Update profile
  UPDATE public.profiles
  SET 
    visibility_status = 'pending',
    visibility_expires_at = NULL,
    updated_at = NOW()
  WHERE id = p_user_id AND role = 'provider';

  -- 3. Log action
  INSERT INTO public.admin_activity_log (
    admin_id,
    action_category,
    action_type,
    target_type,
    target_id,
    action_details,
    success
  ) VALUES (
    v_admin_id,
    'provider_management',
    'remove_visibility',
    'user',
    p_user_id::text,
    jsonb_build_object('action', 'removal'),
    TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
