-- ============================================
-- VIBESLINX ADMIN SYSTEM - PRODUCTION v1.0
-- Admin Tables, Permissions & Core Schema
-- ============================================
-- This migration creates the admin system core tables including:
-- - Admin users and role management
-- - Granular permission system
-- - User management and flagging
-- - Booking dispute resolution
-- - Wallet & escrow approval workflows
-- - Financial reporting tables
-- - Audit trail and activity logging
-- ============================================

-- ============================================
-- 1. ADMIN ROLES & PERMISSIONS SYSTEM
-- ============================================

-- Admin Users Table
CREATE TABLE IF NOT EXISTS public.admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'finance_admin', 'support_admin', 'operations_admin')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'revoked')),
  assigned_by UUID REFERENCES public.admin_users(id),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Admin Permissions Table
CREATE TABLE IF NOT EXISTS public.admin_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_key TEXT UNIQUE NOT NULL,
  permission_name TEXT NOT NULL,
  permission_category TEXT NOT NULL CHECK (permission_category IN ('users', 'bookings', 'wallets', 'reports', 'system')),
  description TEXT,
  is_sensitive BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Admin Role Permissions Mapping
CREATE TABLE IF NOT EXISTS public.admin_role_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role TEXT NOT NULL CHECK (role IN ('super_admin', 'finance_admin', 'support_admin', 'operations_admin')),
  permission_id UUID NOT NULL REFERENCES public.admin_permissions(id) ON DELETE CASCADE,
  granted_by UUID REFERENCES public.admin_users(id),
  granted_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(role, permission_id)
);

-- Admin User Permission Overrides
CREATE TABLE IF NOT EXISTS public.admin_user_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID NOT NULL REFERENCES public.admin_users(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.admin_permissions(id) ON DELETE CASCADE,
  is_granted BOOLEAN NOT NULL,
  granted_by UUID REFERENCES public.admin_users(id),
  granted_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  UNIQUE(admin_user_id, permission_id)
);

-- ============================================
-- 2. USER MANAGEMENT FEATURES
-- ============================================

-- User Actions Log
CREATE TABLE IF NOT EXISTS public.user_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES public.admin_users(id),
  action_type TEXT NOT NULL CHECK (action_type IN ('suspend', 'unsuspend', 'verify', 'flag', 'delete', 'update_profile')),
  reason TEXT,
  previous_state JSONB,
  new_state JSONB,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Flags
CREATE TABLE IF NOT EXISTS public.user_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  flag_type TEXT NOT NULL CHECK (flag_type IN ('fraud', 'inappropriate_content', 'policy_violation', 'suspicious_activity')),
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  description TEXT NOT NULL,
  flagged_by UUID NOT NULL,
  flagged_by_type TEXT NOT NULL CHECK (flagged_by_type IN ('admin', 'user', 'system')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'resolved', 'dismissed')),
  assigned_to UUID REFERENCES public.admin_users(id),
  resolution_notes TEXT,
  resolved_by UUID REFERENCES public.admin_users(id),
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 3. BOOKING MANAGEMENT & DISPUTE RESOLUTION
-- ============================================

-- Booking Disputes
CREATE TABLE IF NOT EXISTS public.booking_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  initiated_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dispute_type TEXT NOT NULL CHECK (dispute_type IN ('service_not_provided', 'payment_issue', 'quality_issue', 'cancellation_dispute')),
  description TEXT NOT NULL,
  evidence JSONB[] DEFAULT ARRAY[]::JSONB[],
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'resolved', 'escalated', 'closed')),
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  assigned_to UUID REFERENCES public.admin_users(id),
  resolution TEXT,
  resolution_type TEXT CHECK (resolution_type IN ('refund_client', 'pay_provider', 'partial_refund', 'no_action')),
  resolved_by UUID REFERENCES public.admin_users(id),
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(booking_id)
);

-- Booking Admin Notes
CREATE TABLE IF NOT EXISTS public.booking_admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES public.admin_users(id),
  note TEXT NOT NULL,
  is_internal BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 4. WALLET & ESCROW MANAGEMENT WITH APPROVAL WORKFLOW
-- ============================================

-- Wallet Adjustments
CREATE TABLE IF NOT EXISTS public.wallet_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
  adjustment_type TEXT NOT NULL CHECK (adjustment_type IN ('credit', 'debit', 'correction', 'refund', 'penalty')),
  amount DECIMAL(10, 2) NOT NULL CHECK (amount != 0),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending_approval' CHECK (status IN ('pending_approval', 'approved', 'rejected', 'executed')),
  requested_by UUID NOT NULL REFERENCES public.admin_users(id),
  approved_by UUID REFERENCES public.admin_users(id),
  executed_by UUID REFERENCES public.admin_users(id),
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  executed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Escrow Admin Actions
CREATE TABLE IF NOT EXISTS public.escrow_admin_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  escrow_transaction_id UUID NOT NULL REFERENCES public.escrow_transactions(id) ON DELETE CASCADE,
  action_type TEXT NOT NULL CHECK (action_type IN ('manual_release', 'manual_refund', 'dispute_resolution', 'cancel')),
  amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending_approval' CHECK (status IN ('pending_approval', 'approved', 'rejected', 'executed')),
  requested_by UUID NOT NULL REFERENCES public.admin_users(id),
  approved_by UUID REFERENCES public.admin_users(id),
  executed_by UUID REFERENCES public.admin_users(id),
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  executed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  requires_dual_approval BOOLEAN DEFAULT FALSE,
  second_approver UUID REFERENCES public.admin_users(id),
  second_approved_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Withdrawal Admin Actions
CREATE TABLE IF NOT EXISTS public.withdrawal_admin_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_request_id UUID NOT NULL REFERENCES public.withdrawal_requests(id) ON DELETE CASCADE,
  action_type TEXT NOT NULL CHECK (action_type IN ('approve', 'reject', 'mark_completed', 'mark_failed')),
  notes TEXT,
  admin_id UUID NOT NULL REFERENCES public.admin_users(id),
  payment_reference TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 5. FINANCIAL REPORTING & ACCOUNTING
-- ============================================

-- Platform Revenue
CREATE TABLE IF NOT EXISTS public.platform_revenue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_type TEXT NOT NULL CHECK (period_type IN ('daily', 'weekly', 'monthly', 'yearly')),
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  total_bookings INTEGER DEFAULT 0,
  total_booking_value DECIMAL(10, 2) DEFAULT 0,
  platform_fees_collected DECIMAL(10, 2) DEFAULT 0,
  subscription_revenue DECIMAL(10, 2) DEFAULT 0,
  total_revenue DECIMAL(10, 2) DEFAULT 0,
  total_payouts DECIMAL(10, 2) DEFAULT 0,
  total_refunds DECIMAL(10, 2) DEFAULT 0,
  net_revenue DECIMAL(10, 2) DEFAULT 0,
  active_users INTEGER DEFAULT 0,
  new_users INTEGER DEFAULT 0,
  calculated_at TIMESTAMPTZ DEFAULT NOW(),
  calculated_by UUID REFERENCES public.admin_users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(period_type, period_start, period_end)
);

-- Wallet Reconciliation
CREATE TABLE IF NOT EXISTS public.wallet_reconciliation (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reconciliation_date DATE NOT NULL UNIQUE,
  total_client_wallets DECIMAL(10, 2) DEFAULT 0,
  total_provider_wallets DECIMAL(10, 2) DEFAULT 0,
  total_locked_escrow DECIMAL(10, 2) DEFAULT 0,
  total_platform_balance DECIMAL(10, 2) DEFAULT 0,
  expected_balance DECIMAL(10, 2) DEFAULT 0,
  actual_balance DECIMAL(10, 2) DEFAULT 0,
  variance DECIMAL(10, 2) DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'balanced' CHECK (status IN ('balanced', 'variance_detected', 'under_review', 'resolved')),
  notes TEXT,
  reconciled_by UUID REFERENCES public.admin_users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Transaction Summaries
CREATE TABLE IF NOT EXISTS public.transaction_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  summary_date DATE NOT NULL UNIQUE,
  total_transactions INTEGER DEFAULT 0,
  total_deposits DECIMAL(10, 2) DEFAULT 0,
  total_withdrawals DECIMAL(10, 2) DEFAULT 0,
  total_escrow_locked DECIMAL(10, 2) DEFAULT 0,
  total_escrow_released DECIMAL(10, 2) DEFAULT 0,
  total_refunds DECIMAL(10, 2) DEFAULT 0,
  total_platform_fees DECIMAL(10, 2) DEFAULT 0,
  payment_method_breakdown JSONB DEFAULT '{}'::jsonb,
  calculated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 6. ADMIN ACTIVITY LOGGING & AUDIT TRAIL
-- ============================================

-- Admin Activity Log
CREATE TABLE IF NOT EXISTS public.admin_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES public.admin_users(id),
  action_category TEXT NOT NULL CHECK (action_category IN ('user_management', 'booking_management', 'wallet_management', 'reports', 'system')),
  action_type TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  action_details JSONB DEFAULT '{}'::jsonb,
  ip_address INET,
  user_agent TEXT,
  success BOOLEAN DEFAULT TRUE,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Admin Sessions
CREATE TABLE IF NOT EXISTS public.admin_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES public.admin_users(id),
  session_token TEXT UNIQUE NOT NULL,
  ip_address INET,
  user_agent TEXT,
  login_at TIMESTAMPTZ DEFAULT NOW(),
  logout_at TIMESTAMPTZ,
  last_activity_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 7. CREATE INDEXES
-- ============================================

-- Admin users indexes
CREATE INDEX IF NOT EXISTS idx_admin_users_user_id ON public.admin_users(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_users_role ON public.admin_users(role);
CREATE INDEX IF NOT EXISTS idx_admin_users_status ON public.admin_users(status);

-- Admin permissions indexes
CREATE INDEX IF NOT EXISTS idx_admin_permissions_category ON public.admin_permissions(permission_category);
CREATE INDEX IF NOT EXISTS idx_admin_permissions_key ON public.admin_permissions(permission_key);

-- User actions indexes
CREATE INDEX IF NOT EXISTS idx_user_actions_target_user ON public.user_actions(target_user_id);
CREATE INDEX IF NOT EXISTS idx_user_actions_admin ON public.user_actions(admin_id);
CREATE INDEX IF NOT EXISTS idx_user_actions_created_at ON public.user_actions(created_at DESC);

-- User flags indexes
CREATE INDEX IF NOT EXISTS idx_user_flags_user_id ON public.user_flags(user_id);
CREATE INDEX IF NOT EXISTS idx_user_flags_status ON public.user_flags(status);
CREATE INDEX IF NOT EXISTS idx_user_flags_severity ON public.user_flags(severity);
CREATE INDEX IF NOT EXISTS idx_user_flags_assigned_to ON public.user_flags(assigned_to);

-- Booking disputes indexes
CREATE INDEX IF NOT EXISTS idx_booking_disputes_booking_id ON public.booking_disputes(booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_disputes_status ON public.booking_disputes(status);
CREATE INDEX IF NOT EXISTS idx_booking_disputes_assigned_to ON public.booking_disputes(assigned_to);
CREATE INDEX IF NOT EXISTS idx_booking_disputes_priority ON public.booking_disputes(priority);

-- Wallet adjustments indexes
CREATE INDEX IF NOT EXISTS idx_wallet_adjustments_wallet_id ON public.wallet_adjustments(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_adjustments_status ON public.wallet_adjustments(status);
CREATE INDEX IF NOT EXISTS idx_wallet_adjustments_requested_by ON public.wallet_adjustments(requested_by);

-- Escrow admin actions indexes
CREATE INDEX IF NOT EXISTS idx_escrow_admin_actions_escrow_id ON public.escrow_admin_actions(escrow_transaction_id);
CREATE INDEX IF NOT EXISTS idx_escrow_admin_actions_status ON public.escrow_admin_actions(status);
CREATE INDEX IF NOT EXISTS idx_escrow_admin_actions_requested_by ON public.escrow_admin_actions(requested_by);

-- Withdrawal admin actions indexes
CREATE INDEX IF NOT EXISTS idx_withdrawal_admin_actions_withdrawal_id ON public.withdrawal_admin_actions(withdrawal_request_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_admin_actions_admin_id ON public.withdrawal_admin_actions(admin_id);

-- Platform revenue indexes
CREATE INDEX IF NOT EXISTS idx_platform_revenue_period ON public.platform_revenue(period_type, period_start);

-- Admin activity log indexes
CREATE INDEX IF NOT EXISTS idx_admin_activity_log_admin_id ON public.admin_activity_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_activity_log_category ON public.admin_activity_log(action_category);
CREATE INDEX IF NOT EXISTS idx_admin_activity_log_created_at ON public.admin_activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_activity_log_target ON public.admin_activity_log(target_type, target_id);

-- Admin sessions indexes
CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id ON public.admin_sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_is_active ON public.admin_sessions(is_active);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_token ON public.admin_sessions(session_token);

-- ============================================
-- 8. SEED ADMIN PERMISSIONS
-- ============================================

-- Insert all admin permissions
INSERT INTO public.admin_permissions (permission_key, permission_name, permission_category, description, is_sensitive) VALUES
-- User Management Permissions
('users.view', 'View Users', 'users', 'View user profiles and details', FALSE),
('users.search', 'Search Users', 'users', 'Search and filter users', FALSE),
('users.suspend', 'Suspend Users', 'users', 'Suspend user accounts', TRUE),
('users.unsuspend', 'Unsuspend Users', 'users', 'Reactivate suspended accounts', TRUE),
('users.verify', 'Verify Users', 'users', 'Verify user profiles', FALSE),
('users.flag', 'Flag Users', 'users', 'Flag users for review', FALSE),
('users.delete', 'Delete Users', 'users', 'Permanently delete user accounts', TRUE),

-- Booking Management Permissions
('bookings.view', 'View Bookings', 'bookings', 'View all bookings', FALSE),
('bookings.update', 'Update Bookings', 'bookings', 'Update booking details', TRUE),
('bookings.cancel', 'Cancel Bookings', 'bookings', 'Cancel bookings', TRUE),
('bookings.disputes.view', 'View Disputes', 'bookings', 'View booking disputes', FALSE),
('bookings.disputes.assign', 'Assign Disputes', 'bookings', 'Assign disputes to admins', FALSE),
('bookings.disputes.resolve', 'Resolve Disputes', 'bookings', 'Resolve booking disputes', TRUE),

-- Wallet Management Permissions
('wallets.view', 'View Wallets', 'wallets', 'View wallet balances', FALSE),
('wallets.adjust.request', 'Request Wallet Adjustments', 'wallets', 'Request wallet balance adjustments', TRUE),
('wallets.adjust.approve', 'Approve Wallet Adjustments', 'wallets', 'Approve wallet adjustments', TRUE),
('wallets.transactions.view', 'View Wallet Transactions', 'wallets', 'View wallet transaction history', FALSE),
('withdrawals.process', 'Process Withdrawals', 'wallets', 'Process withdrawal requests', TRUE),
('withdrawals.approve', 'Approve Withdrawals', 'wallets', 'Approve withdrawal requests', TRUE),

-- Escrow Management Permissions
('escrow.view', 'View Escrow', 'wallets', 'View escrow transactions', FALSE),
('escrow.release.request', 'Request Escrow Release', 'wallets', 'Request escrow release', TRUE),
('escrow.release.approve', 'Approve Escrow Release', 'wallets', 'Approve escrow release', TRUE),
('escrow.refund.request', 'Request Escrow Refund', 'wallets', 'Request escrow refund', TRUE),
('escrow.refund.approve', 'Approve Escrow Refund', 'wallets', 'Approve escrow refund', TRUE),
('escrow.dispute', 'Dispute Escrow', 'wallets', 'Mark escrow as disputed', TRUE),

-- Financial Reports Permissions
('reports.revenue.view', 'View Revenue Reports', 'reports', 'View revenue reports', FALSE),
('reports.transactions.view', 'View Transaction Reports', 'reports', 'View transaction reports', FALSE),
('reports.reconciliation.view', 'View Reconciliation Reports', 'reports', 'View reconciliation reports', FALSE),
('reports.export', 'Export Reports', 'reports', 'Export financial reports', FALSE),

-- System Permissions
('system.admin.create', 'Create Admins', 'system', 'Create new admin users', TRUE),
('system.admin.permissions', 'Manage Permissions', 'system', 'Manage admin permissions', TRUE),
('system.logs.view', 'View Logs', 'system', 'View admin activity logs', FALSE),
('system.settings', 'Manage Settings', 'system', 'Manage system settings', TRUE)
ON CONFLICT (permission_key) DO NOTHING;

-- ============================================
-- 9. SEED DEFAULT ROLE PERMISSIONS
-- ============================================

-- Super Admin gets all permissions
INSERT INTO public.admin_role_permissions (role, permission_id)
SELECT 'super_admin', id FROM public.admin_permissions
ON CONFLICT (role, permission_id) DO NOTHING;

-- Finance Admin permissions
INSERT INTO public.admin_role_permissions (role, permission_id)
SELECT 'finance_admin', id FROM public.admin_permissions 
WHERE permission_key IN (
  'users.view', 'users.search',
  'bookings.view', 'bookings.disputes.view',
  'wallets.view', 'wallets.adjust.request', 'wallets.adjust.approve', 'wallets.transactions.view',
  'withdrawals.process', 'withdrawals.approve',
  'escrow.view', 'escrow.release.request', 'escrow.release.approve', 'escrow.refund.request', 'escrow.refund.approve',
  'reports.revenue.view', 'reports.transactions.view', 'reports.reconciliation.view', 'reports.export',
  'system.logs.view'
)
ON CONFLICT (role, permission_id) DO NOTHING;

-- Support Admin permissions
INSERT INTO public.admin_role_permissions (role, permission_id)
SELECT 'support_admin', id FROM public.admin_permissions 
WHERE permission_key IN (
  'users.view', 'users.search', 'users.suspend', 'users.unsuspend', 'users.verify', 'users.flag',
  'bookings.view', 'bookings.update', 'bookings.cancel', 'bookings.disputes.view', 'bookings.disputes.assign', 'bookings.disputes.resolve',
  'wallets.view', 'wallets.transactions.view',
  'escrow.view', 'escrow.dispute',
  'system.logs.view'
)
ON CONFLICT (role, permission_id) DO NOTHING;

-- Operations Admin permissions
INSERT INTO public.admin_role_permissions (role, permission_id)
SELECT 'operations_admin', id FROM public.admin_permissions 
WHERE permission_key IN (
  'users.view', 'users.search', 'users.verify',
  'bookings.view', 'bookings.update', 'bookings.disputes.view',
  'wallets.view', 'wallets.transactions.view',
  'withdrawals.process',
  'escrow.view',
  'reports.revenue.view', 'reports.transactions.view',
  'system.logs.view'
)
ON CONFLICT (role, permission_id) DO NOTHING;

-- ============================================
-- 10. TRIGGER FUNCTIONS FOR TIMESTAMPS
-- ============================================

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_admin_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_admin_users_updated_at
  BEFORE UPDATE ON public.admin_users
  FOR EACH ROW
  EXECUTE FUNCTION public.update_admin_updated_at();

CREATE TRIGGER update_user_flags_updated_at
  BEFORE UPDATE ON public.user_flags
  FOR EACH ROW
  EXECUTE FUNCTION public.update_admin_updated_at();

CREATE TRIGGER update_booking_disputes_updated_at
  BEFORE UPDATE ON public.booking_disputes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_admin_updated_at();

CREATE TRIGGER update_wallet_adjustments_updated_at
  BEFORE UPDATE ON public.wallet_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_admin_updated_at();

CREATE TRIGGER update_escrow_admin_actions_updated_at
  BEFORE UPDATE ON public.escrow_admin_actions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_admin_updated_at();

-- ============================================
-- ADMIN SYSTEM TABLES CREATED SUCCESSFULLY
-- ============================================
-- Next steps:
-- 1. Run 012_admin_functions.sql for stored procedures
-- 2. Run 013_admin_views_policies.sql for views and RLS policies
-- 3. Create first super admin user
-- ============================================
