-- ============================================
-- FIX ADMIN DASHBOARD PERMISSIONS
-- ============================================
-- Run this in Supabase SQL Editor to fix dashboard showing zeros
-- ============================================

-- Step 1: Grant SELECT permissions on all admin views
GRANT SELECT ON public.admin_dashboard_stats TO authenticated;
GRANT SELECT ON public.pending_approvals TO authenticated;
GRANT SELECT ON public.flagged_users_summary TO authenticated;
GRANT SELECT ON public.active_disputes TO authenticated;
GRANT SELECT ON public.wallet_summary TO authenticated;
GRANT SELECT ON public.revenue_summary TO authenticated;
GRANT SELECT ON public.recent_transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests_summary TO authenticated;
GRANT SELECT ON public.admin_activity_summary TO authenticated;

-- Step 2: Grant SELECT on core tables needed by the views
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

-- Step 3: Enable RLS on views (if not already enabled)
-- Note: Views inherit RLS from underlying tables, but we ensure access

-- Step 4: Create a policy to allow admins to read from views
-- This is a fallback in case RLS is blocking access
DO $$
BEGIN
    -- Check if profiles table has RLS enabled
    IF EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = 'profiles'
    ) THEN
        -- Ensure authenticated users can read profiles
        DROP POLICY IF EXISTS "Allow authenticated users to read profiles" ON public.profiles;
        CREATE POLICY "Allow authenticated users to read profiles"
        ON public.profiles
        FOR SELECT
        TO authenticated
        USING (true);
    END IF;

    -- Ensure authenticated users can read bookings
    IF EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = 'bookings'
    ) THEN
        DROP POLICY IF EXISTS "Allow authenticated users to read bookings" ON public.bookings;
        CREATE POLICY "Allow authenticated users to read bookings"
        ON public.bookings
        FOR SELECT
        TO authenticated
        USING (true);
    END IF;

    -- Ensure authenticated users can read wallets
    IF EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = 'wallets'
    ) THEN
        DROP POLICY IF EXISTS "Allow authenticated users to read wallets" ON public.wallets;
        CREATE POLICY "Allow authenticated users to read wallets"
        ON public.wallets
        FOR SELECT
        TO authenticated
        USING (true);
    END IF;
END $$;

-- Step 5: Test the view access
SELECT 
    'Testing admin_dashboard_stats view...' as test,
    COUNT(*) as view_exists
FROM information_schema.views 
WHERE table_schema = 'public' 
AND table_name = 'admin_dashboard_stats';

-- Step 6: Try to query the view (this will show if it works)
SELECT * FROM public.admin_dashboard_stats;

-- Step 7: Verify permissions
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
        'profiles',
        'bookings',
        'wallets'
    )
ORDER BY table_name, privilege_type;

-- ============================================
-- TROUBLESHOOTING NOTES
-- ============================================
-- If you still see zeros:
-- 1. Check browser console for specific error messages
-- 2. Verify you're logged in as an admin user
-- 3. Check that admin_users table has your user_id with status='active'
-- 4. Verify the underlying tables (profiles, bookings, wallets) have data
-- ============================================
