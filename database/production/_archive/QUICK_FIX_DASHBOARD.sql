-- ============================================
-- QUICK FIX: Dashboard Permissions
-- ============================================
-- Copy and paste this ENTIRE script into Supabase SQL Editor
-- Then click "Run" to execute it
-- ============================================

-- Grant SELECT on all admin views to authenticated users
GRANT SELECT ON public.admin_dashboard_stats TO authenticated;
GRANT SELECT ON public.pending_approvals TO authenticated;
GRANT SELECT ON public.flagged_users_summary TO authenticated;
GRANT SELECT ON public.active_disputes TO authenticated;
GRANT SELECT ON public.wallet_summary TO authenticated;
GRANT SELECT ON public.revenue_summary TO authenticated;
GRANT SELECT ON public.recent_transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests_summary TO authenticated;
GRANT SELECT ON public.admin_activity_summary TO authenticated;

-- Grant SELECT on core tables
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.bookings TO authenticated;
GRANT SELECT ON public.wallets TO authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT SELECT ON public.transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests TO authenticated;
GRANT SELECT ON public.escrow_transactions TO authenticated;
GRANT SELECT ON public.user_flags TO authenticated;
GRANT SELECT ON public.booking_disputes TO authenticated;
GRANT SELECT ON public.platform_revenue TO authenticated;
GRANT SELECT ON public.admin_activity_log TO authenticated;
GRANT SELECT ON public.admin_users TO authenticated;

-- Test if it works
SELECT 'Permissions granted successfully!' as status;
SELECT * FROM public.admin_dashboard_stats;
