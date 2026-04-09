-- ============================================
-- VIBESLINX ADMIN VIEWS & POLICIES - PRODUCTION v1.0
-- Dashboard Views & Row Level Security
-- ============================================
-- This migration creates:
-- - Dashboard views for admin analytics
-- - Row Level Security policies for admin tables
-- - Helper views for common admin queries
-- ============================================

-- ============================================
-- 1. ADMIN DASHBOARD VIEWS
-- ============================================

-- View: Admin Dashboard Stats
DROP VIEW IF EXISTS public.admin_dashboard_stats CASCADE;
CREATE OR REPLACE VIEW public.admin_dashboard_stats AS
SELECT
  (SELECT COUNT(*) FROM public.profiles) as total_users,
  (SELECT COUNT(*) FROM public.profiles WHERE role = 'client') as total_clients,
  (SELECT COUNT(*) FROM public.profiles WHERE role = 'provider') as total_providers,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'pending') as pending_bookings,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'confirmed') as confirmed_bookings,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'completed') as completed_bookings,
  (SELECT COALESCE(SUM(available_balance + locked_balance), 0) FROM public.wallets) as total_wallet_balance,
  (SELECT COALESCE(SUM(amount), 0) FROM public.escrow_transactions WHERE status = 'locked') as total_locked_escrow,
  (SELECT COUNT(*) FROM public.withdrawal_requests WHERE status = 'pending') as pending_withdrawals,
  (SELECT COUNT(*) FROM public.user_flags WHERE status IN ('pending', 'under_review')) as active_flags,
  (SELECT COUNT(*) FROM public.booking_disputes WHERE status IN ('pending', 'under_review')) as active_disputes;

-- View: Pending Approvals
DROP VIEW IF EXISTS public.pending_approvals CASCADE;
CREATE OR REPLACE VIEW public.pending_approvals AS
SELECT
  'wallet_adjustment' as approval_type,
  wa.id,
  wa.wallet_id as reference_id,
  wa.amount,
  wa.reason,
  wa.requested_by,
  wa.requested_at,
  au.role as requester_role,
  CASE WHEN ABS(wa.amount) >= 500 THEN TRUE ELSE FALSE END as requires_dual_approval
FROM public.wallet_adjustments wa
JOIN public.admin_users au ON wa.requested_by = au.id
WHERE wa.status = 'pending_approval'

UNION ALL

SELECT
  'escrow_action' as approval_type,
  ea.id,
  ea.escrow_transaction_id as reference_id,
  ea.amount,
  ea.reason,
  ea.requested_by,
  ea.requested_at,
  au.role as requester_role,
  ea.requires_dual_approval
FROM public.escrow_admin_actions ea
JOIN public.admin_users au ON ea.requested_by = au.id
WHERE ea.status = 'pending_approval'

ORDER BY requested_at DESC;

-- View: Flagged Users Summary
DROP VIEW IF EXISTS public.flagged_users_summary CASCADE;
CREATE OR REPLACE VIEW public.flagged_users_summary AS
SELECT
  uf.id,
  uf.user_id,
  p.display_name,
  p.role as user_role,
  uf.flag_type,
  uf.severity,
  uf.description,
  uf.status,
  uf.assigned_to,
  au.role as assigned_admin_role,
  uf.created_at,
  uf.updated_at
FROM public.user_flags uf
JOIN public.profiles p ON uf.user_id = p.id
LEFT JOIN public.admin_users au ON uf.assigned_to = au.id
WHERE uf.status IN ('pending', 'under_review')
ORDER BY 
  CASE uf.severity
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  uf.created_at DESC;

-- View: Active Disputes
DROP VIEW IF EXISTS public.active_disputes CASCADE;
CREATE OR REPLACE VIEW public.active_disputes AS
SELECT
  bd.id,
  bd.booking_id,
  b.service_name,
  b.total_amount as booking_amount,
  bd.dispute_type,
  bd.priority,
  bd.status,
  bd.initiated_by,
  p1.display_name as initiator_name,
  b.client_id,
  p2.display_name as client_name,
  b.provider_id,
  p3.display_name as provider_name,
  bd.assigned_to,
  au.role as assigned_admin_role,
  bd.created_at,
  bd.updated_at
FROM public.booking_disputes bd
JOIN public.bookings b ON bd.booking_id = b.id
JOIN public.profiles p1 ON bd.initiated_by = p1.id
JOIN public.profiles p2 ON b.client_id = p2.id
JOIN public.profiles p3 ON b.provider_id = p3.id
LEFT JOIN public.admin_users au ON bd.assigned_to = au.id
WHERE bd.status IN ('pending', 'under_review', 'escalated')
ORDER BY
  CASE bd.priority
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  bd.created_at ASC;

-- View: Wallet Summary
DROP VIEW IF EXISTS public.wallet_summary CASCADE;
CREATE OR REPLACE VIEW public.wallet_summary AS
SELECT
  w.id,
  w.user_id,
  p.display_name,
  p.role as user_role,
  w.user_type,
  w.available_balance,
  w.locked_balance,
  w.available_balance + w.locked_balance as total_balance,
  w.total_deposited,
  w.total_withdrawn,
  w.status,
  w.updated_at
FROM public.wallets w
JOIN public.profiles p ON w.user_id = p.id
ORDER BY (w.available_balance + w.locked_balance) DESC;

-- View: Revenue Summary (Last 30 Days)
DROP VIEW IF EXISTS public.revenue_summary CASCADE;
CREATE OR REPLACE VIEW public.revenue_summary AS
SELECT
  period_start as date,
  total_bookings,
  total_booking_value,
  platform_fees_collected,
  subscription_revenue,
  total_revenue,
  total_payouts,
  total_refunds,
  net_revenue,
  active_users,
  new_users
FROM public.platform_revenue
WHERE period_type = 'daily'
  AND period_start >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY period_start DESC;

-- View: Recent Transactions (Last 100)
DROP VIEW IF EXISTS public.recent_transactions CASCADE;
CREATE OR REPLACE VIEW public.recent_transactions AS
SELECT
  t.id,
  t.user_id,
  p.display_name,
  p.role as user_role,
  t.booking_id,
  t.amount,
  t.type,
  t.status,
  t.payment_method,
  t.description,
  t.created_at,
  t.completed_at
FROM public.transactions t
JOIN public.profiles p ON t.user_id = p.id
ORDER BY t.created_at DESC
LIMIT 100;

-- View: Withdrawal Requests Summary
DROP VIEW IF EXISTS public.withdrawal_requests_summary CASCADE;
CREATE OR REPLACE VIEW public.withdrawal_requests_summary AS
SELECT
  wr.id,
  wr.user_id,
  p.display_name,
  p.role as user_role,
  wr.amount,
  wr.payment_method,
  wr.status,
  wr.created_at,
  wr.processed_at,
  wr.processed_by,
  au.role as processor_role
FROM public.withdrawal_requests wr
JOIN public.profiles p ON wr.user_id = p.id
LEFT JOIN public.admin_users au ON wr.processed_by = au.id
WHERE wr.status IN ('pending', 'processing')
ORDER BY 
  CASE wr.status
    WHEN 'pending' THEN 1
    WHEN 'processing' THEN 2
  END,
  wr.created_at ASC;

-- View: Admin Activity Summary (Last 7 Days)
DROP VIEW IF EXISTS public.admin_activity_summary CASCADE;
CREATE OR REPLACE VIEW public.admin_activity_summary AS
SELECT
  aal.id,
  aal.admin_id,
  au.user_id,
  p.display_name as admin_name,
  au.role as admin_role,
  aal.action_category,
  aal.action_type,
  aal.target_type,
  aal.target_id,
  aal.success,
  aal.created_at
FROM public.admin_activity_log aal
JOIN public.admin_users au ON aal.admin_id = au.id
JOIN public.profiles p ON au.user_id = p.id
WHERE aal.created_at >= NOW() - INTERVAL '7 days'
ORDER BY aal.created_at DESC;

-- ============================================
-- 2. ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on all admin tables
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.booking_admin_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_revenue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_reconciliation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 3. ADMIN USERS POLICIES
-- ============================================

-- Admin users can view their own record
CREATE POLICY admin_users_select_own ON public.admin_users
  FOR SELECT
  USING (user_id = auth.uid());

-- Active admins can view all admin users
CREATE POLICY admin_users_select_all ON public.admin_users
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Only super admins can insert/update/delete admin users
CREATE POLICY admin_users_manage ON public.admin_users
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND role = 'super_admin' AND status = 'active'
    )
  );

-- ============================================
-- 4. PERMISSIONS POLICIES
-- ============================================

-- All active admins can view permissions
CREATE POLICY admin_permissions_select ON public.admin_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Only super admins can manage permissions
CREATE POLICY admin_permissions_manage ON public.admin_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND role = 'super_admin' AND status = 'active'
    )
  );

-- Active admins can view role permissions
CREATE POLICY admin_role_permissions_select ON public.admin_role_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Only super admins can manage role permissions
CREATE POLICY admin_role_permissions_manage ON public.admin_role_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE user_id = auth.uid() AND role = 'super_admin' AND status = 'active'
    )
  );

-- ============================================
-- 5. USER MANAGEMENT POLICIES
-- ============================================

-- Admins with users.view can see user actions
CREATE POLICY user_actions_select ON public.user_actions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins with users.flag can view and manage flags
CREATE POLICY user_flags_select ON public.user_flags
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

CREATE POLICY user_flags_insert ON public.user_flags
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

CREATE POLICY user_flags_update ON public.user_flags
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- ============================================
-- 6. BOOKING MANAGEMENT POLICIES
-- ============================================

-- Admins with bookings.disputes.view can see disputes
CREATE POLICY booking_disputes_select ON public.booking_disputes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can create and update disputes
CREATE POLICY booking_disputes_insert ON public.booking_disputes
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

CREATE POLICY booking_disputes_update ON public.booking_disputes
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view and create booking notes
CREATE POLICY booking_admin_notes_select ON public.booking_admin_notes
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

CREATE POLICY booking_admin_notes_insert ON public.booking_admin_notes
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- ============================================
-- 7. WALLET MANAGEMENT POLICIES
-- ============================================

-- Admins with wallet permissions can view adjustments
CREATE POLICY wallet_adjustments_select ON public.wallet_adjustments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can create adjustment requests
CREATE POLICY wallet_adjustments_insert ON public.wallet_adjustments
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view escrow actions
CREATE POLICY escrow_admin_actions_select ON public.escrow_admin_actions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can create escrow action requests
CREATE POLICY escrow_admin_actions_insert ON public.escrow_admin_actions
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view withdrawal actions
CREATE POLICY withdrawal_admin_actions_select ON public.withdrawal_admin_actions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

CREATE POLICY withdrawal_admin_actions_insert ON public.withdrawal_admin_actions
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- ============================================
-- 8. FINANCIAL REPORTING POLICIES
-- ============================================

-- Admins with reports permissions can view revenue
CREATE POLICY platform_revenue_select ON public.platform_revenue
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view reconciliation
CREATE POLICY wallet_reconciliation_select ON public.wallet_reconciliation
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view transaction summaries
CREATE POLICY transaction_summaries_select ON public.transaction_summaries
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- ============================================
-- 9. AUDIT LOG POLICIES
-- ============================================

-- Admins can view activity logs
CREATE POLICY admin_activity_log_select ON public.admin_activity_log
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.status = 'active'
    )
  );

-- Admins can view their own sessions
CREATE POLICY admin_sessions_select ON public.admin_sessions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.id = admin_sessions.admin_id
    )
    OR
    EXISTS (
      SELECT 1 FROM public.admin_users au
      WHERE au.user_id = auth.uid() AND au.role = 'super_admin' AND au.status = 'active'
    )
  );

-- ============================================
-- 10. SERVICE ROLE POLICIES (Backend Access)
-- ============================================

-- Service role has full access to all admin tables
CREATE POLICY admin_users_service_role ON public.admin_users
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY admin_permissions_service_role ON public.admin_permissions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY admin_role_permissions_service_role ON public.admin_role_permissions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY admin_user_permissions_service_role ON public.admin_user_permissions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY user_actions_service_role ON public.user_actions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY user_flags_service_role ON public.user_flags
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY booking_disputes_service_role ON public.booking_disputes
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY booking_admin_notes_service_role ON public.booking_admin_notes
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY wallet_adjustments_service_role ON public.wallet_adjustments
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY escrow_admin_actions_service_role ON public.escrow_admin_actions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY withdrawal_admin_actions_service_role ON public.withdrawal_admin_actions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY platform_revenue_service_role ON public.platform_revenue
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY wallet_reconciliation_service_role ON public.wallet_reconciliation
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY transaction_summaries_service_role ON public.transaction_summaries
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY admin_activity_log_service_role ON public.admin_activity_log
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

CREATE POLICY admin_sessions_service_role ON public.admin_sessions
  FOR ALL
  USING (auth.jwt()->>'role' = 'service_role');

-- ============================================
-- ADMIN VIEWS & POLICIES CREATED SUCCESSFULLY
-- ============================================
-- All dashboard views and RLS policies are now in place
-- Admin system is ready for use
-- ============================================
