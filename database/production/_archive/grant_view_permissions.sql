-- ============================================
-- GRANT PERMISSIONS ON ADMIN VIEWS
-- ============================================
-- This script grants SELECT permissions on all admin views
-- to authenticated users (admins)
-- ============================================

-- Grant SELECT on all admin dashboard views
GRANT SELECT ON public.admin_dashboard_stats TO authenticated;
GRANT SELECT ON public.pending_approvals TO authenticated;
GRANT SELECT ON public.flagged_users_summary TO authenticated;
GRANT SELECT ON public.active_disputes TO authenticated;
GRANT SELECT ON public.wallet_summary TO authenticated;
GRANT SELECT ON public.revenue_summary TO authenticated;
GRANT SELECT ON public.recent_transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests_summary TO authenticated;
GRANT SELECT ON public.admin_activity_summary TO authenticated;

-- Grant SELECT on core tables that admins need to query
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.bookings TO authenticated;
GRANT SELECT ON public.wallets TO authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT SELECT ON public.transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests TO authenticated;
GRANT SELECT ON public.escrow_transactions TO authenticated;

-- Verify the grants
SELECT 
    grantee, 
    table_schema,
    table_name, 
    privilege_type 
FROM 
    information_schema.role_table_grants 
WHERE 
    table_schema = 'public'
    AND grantee = 'authenticated'
    AND table_name IN (
        'admin_dashboard_stats',
        'pending_approvals',
        'flagged_users_summary',
        'active_disputes',
        'wallet_summary',
        'revenue_summary',
        'recent_transactions',
        'withdrawal_requests_summary',
        'admin_activity_summary'
    )
ORDER BY table_name;
