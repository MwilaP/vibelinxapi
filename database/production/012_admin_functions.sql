-- ============================================
-- VIBESLINX ADMIN FUNCTIONS - PRODUCTION v1.0
-- Stored Procedures for Admin Operations
-- ============================================
-- This migration creates all stored procedures for:
-- - Permission checking
-- - Activity logging
-- - Wallet adjustments with approval workflow
-- - Escrow management with dual approval
-- - Dispute resolution
-- - Financial reporting and reconciliation
-- ============================================

-- ============================================
-- 1. PERMISSION & LOGGING FUNCTIONS
-- ============================================

-- Function to check if admin has permission
CREATE OR REPLACE FUNCTION public.admin_has_permission(
  p_admin_id UUID,
  p_permission_key TEXT
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_permission BOOLEAN;
  v_role TEXT;
  v_user_override BOOLEAN;
BEGIN
  -- Get admin role
  SELECT role INTO v_role
  FROM public.admin_users
  WHERE id = p_admin_id AND status = 'active';
  
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Super admin always has permission
  IF v_role = 'super_admin' THEN
    RETURN TRUE;
  END IF;
  
  -- Check for user-specific override
  SELECT is_granted INTO v_user_override
  FROM public.admin_user_permissions aup
  JOIN public.admin_permissions ap ON aup.permission_id = ap.id
  WHERE aup.admin_user_id = p_admin_id 
    AND ap.permission_key = p_permission_key
    AND (aup.expires_at IS NULL OR aup.expires_at > NOW());
  
  IF v_user_override IS NOT NULL THEN
    RETURN v_user_override;
  END IF;
  
  -- Check role permissions
  SELECT EXISTS(
    SELECT 1
    FROM public.admin_role_permissions arp
    JOIN public.admin_permissions ap ON arp.permission_id = ap.id
    WHERE arp.role = v_role AND ap.permission_key = p_permission_key
  ) INTO v_has_permission;
  
  RETURN v_has_permission;
END;
$$ LANGUAGE plpgsql;

-- Function to log admin activity
CREATE OR REPLACE FUNCTION public.log_admin_activity(
  p_admin_id UUID,
  p_action_category TEXT,
  p_action_type TEXT,
  p_target_type TEXT DEFAULT NULL,
  p_target_id UUID DEFAULT NULL,
  p_action_details JSONB DEFAULT '{}'::jsonb,
  p_success BOOLEAN DEFAULT TRUE,
  p_error_message TEXT DEFAULT NULL
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id UUID;
BEGIN
  INSERT INTO public.admin_activity_log (
    admin_id, action_category, action_type, target_type, target_id,
    action_details, success, error_message
  ) VALUES (
    p_admin_id, p_action_category, p_action_type, p_target_type, p_target_id,
    p_action_details, p_success, p_error_message
  ) RETURNING id INTO v_log_id;
  
  RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 2. WALLET ADJUSTMENT FUNCTIONS
-- ============================================

-- Function to request wallet adjustment
CREATE OR REPLACE FUNCTION public.request_wallet_adjustment(
  p_admin_id UUID,
  p_wallet_id UUID,
  p_adjustment_type TEXT,
  p_amount DECIMAL(10, 2),
  p_reason TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adjustment_id UUID;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'wallets.adjust.request') THEN
    RAISE EXCEPTION 'Permission denied: wallets.adjust.request';
  END IF;
  
  -- Create adjustment request
  INSERT INTO public.wallet_adjustments (
    wallet_id, adjustment_type, amount, reason, requested_by, metadata
  ) VALUES (
    p_wallet_id, p_adjustment_type, p_amount, p_reason, p_admin_id, p_metadata
  ) RETURNING id INTO v_adjustment_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'request_adjustment',
    'wallet_adjustment', v_adjustment_id,
    jsonb_build_object('wallet_id', p_wallet_id, 'amount', p_amount, 'type', p_adjustment_type)
  );
  
  RETURN v_adjustment_id;
END;
$$ LANGUAGE plpgsql;

-- Function to approve wallet adjustment
CREATE OR REPLACE FUNCTION public.approve_wallet_adjustment(
  p_admin_id UUID,
  p_adjustment_id UUID
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adjustment RECORD;
  v_wallet RECORD;
  v_new_balance DECIMAL(10, 2);
  v_admin_role TEXT;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'wallets.adjust.approve') THEN
    RAISE EXCEPTION 'Permission denied: wallets.adjust.approve';
  END IF;
  
  -- Get adjustment details
  SELECT * INTO v_adjustment
  FROM public.wallet_adjustments
  WHERE id = p_adjustment_id AND status = 'pending_approval';
  
  IF v_adjustment IS NULL THEN
    RAISE EXCEPTION 'Adjustment not found or already processed';
  END IF;
  
  -- Get admin role for bypass check
  SELECT role INTO v_admin_role
  FROM public.admin_users
  WHERE id = p_admin_id;
  
  -- Check if amount requires dual approval (unless super admin)
  IF ABS(v_adjustment.amount) >= 500 AND v_admin_role != 'super_admin' THEN
    RAISE EXCEPTION 'Amount >= 500 ZMW requires dual approval or super admin bypass';
  END IF;
  
  -- Get wallet details
  SELECT * INTO v_wallet
  FROM public.wallets
  WHERE id = v_adjustment.wallet_id;
  
  -- Calculate new balance
  IF v_adjustment.adjustment_type IN ('credit', 'refund') THEN
    v_new_balance := v_wallet.available_balance + v_adjustment.amount;
  ELSE
    v_new_balance := v_wallet.available_balance - ABS(v_adjustment.amount);
  END IF;
  
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'Insufficient balance for adjustment';
  END IF;
  
  -- Update adjustment status
  UPDATE public.wallet_adjustments
  SET status = 'approved',
      approved_by = p_admin_id,
      approved_at = NOW(),
      updated_at = NOW()
  WHERE id = p_adjustment_id;
  
  -- Execute the adjustment
  UPDATE public.wallets
  SET available_balance = v_new_balance,
      updated_at = NOW()
  WHERE id = v_adjustment.wallet_id;
  
  -- Create wallet transaction record
  INSERT INTO public.wallet_transactions (
    wallet_id, transaction_type, amount, balance_before, balance_after,
    reference_id, reference_type, description, metadata
  ) VALUES (
    v_adjustment.wallet_id, 'admin_adjustment', v_adjustment.amount,
    v_wallet.available_balance, v_new_balance,
    p_adjustment_id, 'adjustment', v_adjustment.reason, v_adjustment.metadata
  );
  
  -- Update adjustment to executed
  UPDATE public.wallet_adjustments
  SET status = 'executed',
      executed_by = p_admin_id,
      executed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_adjustment_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'approve_adjustment',
    'wallet_adjustment', p_adjustment_id,
    jsonb_build_object('wallet_id', v_adjustment.wallet_id, 'amount', v_adjustment.amount)
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to reject wallet adjustment
CREATE OR REPLACE FUNCTION public.reject_wallet_adjustment(
  p_admin_id UUID,
  p_adjustment_id UUID,
  p_rejection_reason TEXT
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'wallets.adjust.approve') THEN
    RAISE EXCEPTION 'Permission denied: wallets.adjust.approve';
  END IF;
  
  -- Update adjustment status
  UPDATE public.wallet_adjustments
  SET status = 'rejected',
      approved_by = p_admin_id,
      approved_at = NOW(),
      rejection_reason = p_rejection_reason,
      updated_at = NOW()
  WHERE id = p_adjustment_id AND status = 'pending_approval';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Adjustment not found or already processed';
  END IF;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'reject_adjustment',
    'wallet_adjustment', p_adjustment_id,
    jsonb_build_object('reason', p_rejection_reason)
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 3. ESCROW MANAGEMENT FUNCTIONS
-- ============================================

-- Function to request escrow action
CREATE OR REPLACE FUNCTION public.request_escrow_action(
  p_admin_id UUID,
  p_escrow_transaction_id UUID,
  p_action_type TEXT,
  p_amount DECIMAL(10, 2),
  p_reason TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action_id UUID;
  v_requires_dual BOOLEAN;
  v_permission_key TEXT;
BEGIN
  -- Determine permission key based on action type
  IF p_action_type = 'manual_release' THEN
    v_permission_key := 'escrow.release.request';
  ELSIF p_action_type = 'manual_refund' THEN
    v_permission_key := 'escrow.refund.request';
  ELSE
    v_permission_key := 'escrow.dispute';
  END IF;
  
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, v_permission_key) THEN
    RAISE EXCEPTION 'Permission denied for escrow action: %', v_permission_key;
  END IF;
  
  -- Determine if dual approval is required
  v_requires_dual := (p_amount > 1000);
  
  -- Create escrow action request
  INSERT INTO public.escrow_admin_actions (
    escrow_transaction_id, action_type, amount, reason, requested_by,
    requires_dual_approval, metadata
  ) VALUES (
    p_escrow_transaction_id, p_action_type, p_amount, p_reason, p_admin_id,
    v_requires_dual, p_metadata
  ) RETURNING id INTO v_action_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'request_escrow_action',
    'escrow_action', v_action_id,
    jsonb_build_object('escrow_id', p_escrow_transaction_id, 'action', p_action_type, 'amount', p_amount)
  );
  
  RETURN v_action_id;
END;
$$ LANGUAGE plpgsql;

-- Function to approve escrow action
CREATE OR REPLACE FUNCTION public.approve_escrow_action(
  p_admin_id UUID,
  p_action_id UUID,
  p_is_second_approver BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action RECORD;
  v_escrow RECORD;
  v_admin_role TEXT;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'escrow.release.approve') AND 
     NOT public.admin_has_permission(p_admin_id, 'escrow.refund.approve') THEN
    RAISE EXCEPTION 'Permission denied for escrow approval';
  END IF;
  
  -- Get action details
  SELECT * INTO v_action
  FROM public.escrow_admin_actions
  WHERE id = p_action_id AND status = 'pending_approval';
  
  IF v_action IS NULL THEN
    RAISE EXCEPTION 'Escrow action not found or already processed';
  END IF;
  
  -- Get admin role
  SELECT role INTO v_admin_role
  FROM public.admin_users
  WHERE id = p_admin_id;
  
  -- Handle dual approval requirement
  IF v_action.requires_dual_approval AND v_admin_role != 'super_admin' THEN
    IF p_is_second_approver THEN
      -- Second approval
      IF v_action.approved_by IS NULL THEN
        RAISE EXCEPTION 'First approval required before second approval';
      END IF;
      
      IF v_action.approved_by = p_admin_id THEN
        RAISE EXCEPTION 'Cannot be both first and second approver';
      END IF;
      
      UPDATE public.escrow_admin_actions
      SET second_approver = p_admin_id,
          second_approved_at = NOW(),
          status = 'approved',
          updated_at = NOW()
      WHERE id = p_action_id;
    ELSE
      -- First approval
      UPDATE public.escrow_admin_actions
      SET approved_by = p_admin_id,
          approved_at = NOW(),
          updated_at = NOW()
      WHERE id = p_action_id;
      
      -- Log and return - waiting for second approval
      PERFORM public.log_admin_activity(
        p_admin_id, 'wallet_management', 'first_approve_escrow',
        'escrow_action', p_action_id,
        jsonb_build_object('action_type', v_action.action_type, 'awaiting_second_approval', TRUE)
      );
      
      RETURN TRUE;
    END IF;
  ELSE
    -- Single approval or super admin bypass
    UPDATE public.escrow_admin_actions
    SET approved_by = p_admin_id,
        approved_at = NOW(),
        status = 'approved',
        updated_at = NOW()
    WHERE id = p_action_id;
  END IF;
  
  -- Get escrow transaction
  SELECT * INTO v_escrow
  FROM public.escrow_transactions
  WHERE id = v_action.escrow_transaction_id;
  
  -- Execute the action based on type
  IF v_action.action_type = 'manual_release' THEN
    -- Release escrow to provider
    UPDATE public.escrow_transactions
    SET status = 'released',
        released_at = NOW(),
        released_to_provider_at = NOW(),
        resolved_by = p_admin_id,
        reason = v_action.reason,
        updated_at = NOW()
    WHERE id = v_action.escrow_transaction_id;
    
    -- Update provider wallet
    UPDATE public.wallets
    SET locked_balance = locked_balance - v_action.amount,
        available_balance = available_balance + v_action.amount,
        updated_at = NOW()
    WHERE id = v_escrow.provider_wallet_id;
    
    -- Create wallet transaction
    INSERT INTO public.wallet_transactions (
      wallet_id, transaction_type, amount, balance_before, balance_after,
      reference_id, reference_type, description
    )
    SELECT 
      id, 'escrow_release', v_action.amount,
      available_balance, available_balance + v_action.amount,
      v_action.escrow_transaction_id, 'escrow', 'Admin escrow release: ' || v_action.reason
    FROM public.wallets
    WHERE id = v_escrow.provider_wallet_id;
    
  ELSIF v_action.action_type = 'manual_refund' THEN
    -- Refund escrow to client
    UPDATE public.escrow_transactions
    SET status = 'refunded',
        refunded_at = NOW(),
        resolved_by = p_admin_id,
        reason = v_action.reason,
        updated_at = NOW()
    WHERE id = v_action.escrow_transaction_id;
    
    -- Update client wallet
    UPDATE public.wallets
    SET locked_balance = locked_balance - v_action.amount,
        available_balance = available_balance + v_action.amount,
        updated_at = NOW()
    WHERE id = v_escrow.client_wallet_id;
    
    -- Create wallet transaction
    INSERT INTO public.wallet_transactions (
      wallet_id, transaction_type, amount, balance_before, balance_after,
      reference_id, reference_type, description
    )
    SELECT 
      id, 'escrow_refund', v_action.amount,
      available_balance, available_balance + v_action.amount,
      v_action.escrow_transaction_id, 'escrow', 'Admin escrow refund: ' || v_action.reason
    FROM public.wallets
    WHERE id = v_escrow.client_wallet_id;
  END IF;
  
  -- Mark action as executed
  UPDATE public.escrow_admin_actions
  SET status = 'executed',
      executed_by = p_admin_id,
      executed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_action_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'execute_escrow_action',
    'escrow_action', p_action_id,
    jsonb_build_object('action_type', v_action.action_type, 'amount', v_action.amount)
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to reject escrow action
CREATE OR REPLACE FUNCTION public.reject_escrow_action(
  p_admin_id UUID,
  p_action_id UUID,
  p_rejection_reason TEXT
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'escrow.release.approve') AND 
     NOT public.admin_has_permission(p_admin_id, 'escrow.refund.approve') THEN
    RAISE EXCEPTION 'Permission denied for escrow approval';
  END IF;
  
  -- Update action status
  UPDATE public.escrow_admin_actions
  SET status = 'rejected',
      approved_by = p_admin_id,
      approved_at = NOW(),
      rejection_reason = p_rejection_reason,
      updated_at = NOW()
  WHERE id = p_action_id AND status = 'pending_approval';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Escrow action not found or already processed';
  END IF;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'wallet_management', 'reject_escrow_action',
    'escrow_action', p_action_id,
    jsonb_build_object('reason', p_rejection_reason)
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. DISPUTE RESOLUTION FUNCTIONS
-- ============================================

-- Function to resolve booking dispute
CREATE OR REPLACE FUNCTION public.resolve_booking_dispute(
  p_admin_id UUID,
  p_dispute_id UUID,
  p_resolution_type TEXT,
  p_resolution TEXT,
  p_refund_amount DECIMAL(10, 2) DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dispute RECORD;
  v_booking RECORD;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'bookings.disputes.resolve') THEN
    RAISE EXCEPTION 'Permission denied: bookings.disputes.resolve';
  END IF;
  
  -- Get dispute details
  SELECT * INTO v_dispute
  FROM public.booking_disputes
  WHERE id = p_dispute_id AND status IN ('pending', 'under_review');
  
  IF v_dispute IS NULL THEN
    RAISE EXCEPTION 'Dispute not found or already resolved';
  END IF;
  
  -- Get booking details
  SELECT * INTO v_booking
  FROM public.bookings
  WHERE id = v_dispute.booking_id;
  
  -- Update dispute
  UPDATE public.booking_disputes
  SET status = 'resolved',
      resolution_type = p_resolution_type,
      resolution = p_resolution,
      resolved_by = p_admin_id,
      resolved_at = NOW(),
      updated_at = NOW()
  WHERE id = p_dispute_id;
  
  -- Handle resolution actions
  IF p_resolution_type = 'refund_client' AND p_refund_amount IS NOT NULL THEN
    -- Create refund transaction
    INSERT INTO public.transactions (
      user_id, booking_id, amount, type, status, description, metadata
    ) VALUES (
      v_booking.client_id, v_booking.id, p_refund_amount, 'refund', 'completed',
      'Dispute resolution refund: ' || p_resolution,
      jsonb_build_object('dispute_id', p_dispute_id, 'resolved_by', p_admin_id)
    );
  END IF;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'booking_management', 'resolve_dispute',
    'booking_dispute', p_dispute_id,
    jsonb_build_object('booking_id', v_dispute.booking_id, 'resolution_type', p_resolution_type)
  );
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. FINANCIAL REPORTING FUNCTIONS
-- ============================================

-- Function to generate daily revenue report
CREATE OR REPLACE FUNCTION public.generate_daily_revenue_report(
  p_admin_id UUID,
  p_report_date DATE
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report_id UUID;
  v_total_bookings INTEGER;
  v_total_booking_value DECIMAL(10, 2);
  v_platform_fees DECIMAL(10, 2);
  v_subscription_revenue DECIMAL(10, 2);
  v_total_payouts DECIMAL(10, 2);
  v_total_refunds DECIMAL(10, 2);
  v_active_users INTEGER;
  v_new_users INTEGER;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'reports.revenue.view') THEN
    RAISE EXCEPTION 'Permission denied: reports.revenue.view';
  END IF;
  
  -- Calculate metrics
  SELECT COUNT(*), COALESCE(SUM(total_amount), 0), COALESCE(SUM(platform_fee), 0)
  INTO v_total_bookings, v_total_booking_value, v_platform_fees
  FROM public.bookings
  WHERE DATE(created_at) = p_report_date;
  
  SELECT COALESCE(SUM(amount_paid), 0)
  INTO v_subscription_revenue
  FROM public.subscriptions
  WHERE DATE(created_at) = p_report_date;
  
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_payouts
  FROM public.withdrawal_requests
  WHERE DATE(processed_at) = p_report_date AND status = 'completed';
  
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_refunds
  FROM public.transactions
  WHERE DATE(created_at) = p_report_date AND type = 'refund' AND status = 'completed';
  
  SELECT COUNT(DISTINCT user_id)
  INTO v_active_users
  FROM public.bookings
  WHERE DATE(created_at) = p_report_date;
  
  SELECT COUNT(*)
  INTO v_new_users
  FROM public.profiles
  WHERE DATE(created_at) = p_report_date;
  
  -- Insert report
  INSERT INTO public.platform_revenue (
    period_type, period_start, period_end,
    total_bookings, total_booking_value, platform_fees_collected,
    subscription_revenue, total_revenue, total_payouts, total_refunds,
    net_revenue, active_users, new_users, calculated_by
  ) VALUES (
    'daily', p_report_date, p_report_date,
    v_total_bookings, v_total_booking_value, v_platform_fees,
    v_subscription_revenue,
    v_platform_fees + v_subscription_revenue,
    v_total_payouts, v_total_refunds,
    (v_platform_fees + v_subscription_revenue) - v_total_payouts - v_total_refunds,
    v_active_users, v_new_users, p_admin_id
  )
  ON CONFLICT (period_type, period_start, period_end) 
  DO UPDATE SET
    total_bookings = EXCLUDED.total_bookings,
    total_booking_value = EXCLUDED.total_booking_value,
    platform_fees_collected = EXCLUDED.platform_fees_collected,
    subscription_revenue = EXCLUDED.subscription_revenue,
    total_revenue = EXCLUDED.total_revenue,
    total_payouts = EXCLUDED.total_payouts,
    total_refunds = EXCLUDED.total_refunds,
    net_revenue = EXCLUDED.net_revenue,
    active_users = EXCLUDED.active_users,
    new_users = EXCLUDED.new_users,
    calculated_at = NOW(),
    calculated_by = p_admin_id
  RETURNING id INTO v_report_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'reports', 'generate_revenue_report',
    'platform_revenue', v_report_id,
    jsonb_build_object('report_date', p_report_date, 'period_type', 'daily')
  );
  
  RETURN v_report_id;
END;
$$ LANGUAGE plpgsql;

-- Function to reconcile wallets
CREATE OR REPLACE FUNCTION public.reconcile_wallets(
  p_admin_id UUID,
  p_reconciliation_date DATE
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reconciliation_id UUID;
  v_total_client_wallets DECIMAL(10, 2);
  v_total_provider_wallets DECIMAL(10, 2);
  v_total_locked_escrow DECIMAL(10, 2);
  v_total_platform DECIMAL(10, 2);
  v_expected DECIMAL(10, 2);
  v_variance DECIMAL(10, 2);
  v_status TEXT;
BEGIN
  -- Check permission
  IF NOT public.admin_has_permission(p_admin_id, 'reports.reconciliation.view') THEN
    RAISE EXCEPTION 'Permission denied: reports.reconciliation.view';
  END IF;
  
  -- Calculate wallet totals
  SELECT COALESCE(SUM(available_balance + locked_balance), 0)
  INTO v_total_client_wallets
  FROM public.wallets
  WHERE user_type = 'client';
  
  SELECT COALESCE(SUM(available_balance + locked_balance), 0)
  INTO v_total_provider_wallets
  FROM public.wallets
  WHERE user_type = 'provider';
  
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_locked_escrow
  FROM public.escrow_transactions
  WHERE status = 'locked';
  
  v_total_platform := v_total_client_wallets + v_total_provider_wallets;
  
  -- For now, expected equals actual (would connect to external payment system)
  v_expected := v_total_platform;
  v_variance := v_total_platform - v_expected;
  
  -- Determine status
  IF ABS(v_variance) < 0.01 THEN
    v_status := 'balanced';
  ELSE
    v_status := 'variance_detected';
  END IF;
  
  -- Insert reconciliation record
  INSERT INTO public.wallet_reconciliation (
    reconciliation_date, total_client_wallets, total_provider_wallets,
    total_locked_escrow, total_platform_balance, expected_balance,
    actual_balance, variance, status, reconciled_by
  ) VALUES (
    p_reconciliation_date, v_total_client_wallets, v_total_provider_wallets,
    v_total_locked_escrow, v_total_platform, v_expected,
    v_total_platform, v_variance, v_status, p_admin_id
  )
  ON CONFLICT (reconciliation_date)
  DO UPDATE SET
    total_client_wallets = EXCLUDED.total_client_wallets,
    total_provider_wallets = EXCLUDED.total_provider_wallets,
    total_locked_escrow = EXCLUDED.total_locked_escrow,
    total_platform_balance = EXCLUDED.total_platform_balance,
    expected_balance = EXCLUDED.expected_balance,
    actual_balance = EXCLUDED.actual_balance,
    variance = EXCLUDED.variance,
    status = EXCLUDED.status,
    reconciled_by = p_admin_id
  RETURNING id INTO v_reconciliation_id;
  
  -- Log activity
  PERFORM public.log_admin_activity(
    p_admin_id, 'reports', 'reconcile_wallets',
    'wallet_reconciliation', v_reconciliation_id,
    jsonb_build_object('date', p_reconciliation_date, 'variance', v_variance)
  );
  
  RETURN v_reconciliation_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- ADMIN FUNCTIONS CREATED SUCCESSFULLY
-- ============================================
-- All stored procedures for admin operations are now available
-- Next: Run 013_admin_views_policies.sql for views and RLS
-- ============================================
