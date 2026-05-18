-- ============================================================
-- VIBESLINX PRODUCTION DATABASE SETUP
-- STEP 1: Run All Migrations (psql / command-line version)
-- ============================================================
-- USE THIS FILE with psql only. It uses \i to include each
-- migration file. The \echo commands require psql as well.
--
-- If you're using Supabase SQL Editor, run the individual
-- numbered files (001_*.sql → 040_*.sql) one at a time in order.
-- See README.md for the full execution order.
--
-- PSQL USAGE:
--   export DB="postgresql://postgres:[PASSWORD]@[REF].supabase.co:5432/postgres"
--   psql $DB -f STEP_1_run_migrations.sql
--
-- (Run this file from the production/ directory so \i paths resolve)
-- ============================================================

\echo ''
\echo '============================================================'
\echo ' VIBESLINX: Production Database Setup - Step 1/2'
\echo '============================================================'
\echo ''

\echo '[01/22] Core Schema (Profiles, Auth, Storage)...'
\i 001_core_schema.sql
\echo '[01/22] DONE'

\echo '[02/22] Bookings System...'
\i 002_bookings_system.sql
\echo '[02/22] DONE'

\echo '[03/22] Transactions & Payments...'
\i 003_transactions_payments.sql
\echo '[03/22] DONE'

\echo '[04/22] Wallet & Escrow System...'
\i 004_wallet_escrow_system.sql
\echo '[04/22] DONE'

\echo '[05/22] Reviews & Ratings...'
\i 005_reviews_ratings.sql
\echo '[05/22] DONE'

\echo '[06/22] Notifications...'
\i 006_notifications.sql
\echo '[06/22] DONE'

\echo '[07/22] Provider Stats...'
\i 007_provider_stats.sql
\echo '[07/22] DONE'

\echo '[08/22] Subscriptions...'
\i 008_subscriptions.sql
\echo '[08/22] DONE'

\echo '[09/22] Indexes & Optimization...'
\i 009_indexes_optimization.sql
\echo '[09/22] DONE'

\echo '[10/22] Realtime Setup...'
\i 010_realtime_setup.sql
\echo '[10/22] DONE'

\echo '[11/22] Admin System Tables...'
\i 011_admin_system.sql
\echo '[11/22] DONE'

\echo '[12/22] Admin Functions (Stored Procedures)...'
\i 012_admin_functions.sql
\echo '[12/22] DONE'

\echo '[13/22] Admin Views & Policies...'
\i 013_admin_views_policies.sql
\echo '[13/22] DONE'

\echo '[14/22] Fix Admin RLS (Infinite Recursion)...'
\i 014_fix_admin_rls.sql
\echo '[14/22] DONE'

\echo '[15/22] Withdrawal & Payout System...'
\i 015_withdrawal_payout_system.sql
\echo '[15/22] DONE'

\echo '[16/22] System Settings...'
\i 016_system_settings.sql
\echo '[16/22] DONE'

\echo '[17/22] Referral System...'
\i 017_referral_system.sql
\echo '[17/22] DONE'

\echo '[18/22] Add Province to Profiles...'
\i 036_add_province_to_profiles.sql
\echo '[18/22] DONE'

\echo '[19/22] Provider Visibility Fee System...'
\i 037_provider_visibility_fee.sql
\echo '[19/22] DONE'

\echo '[20/22] Admin Grant Functions...'
\i 038_admin_grant_functions.sql
\echo '[20/22] DONE'

\echo '[21/23] Admin Revenue Stats...'
\i 039_admin_revenue_stats.sql
\echo '[21/23] DONE'

\echo '[22/23] Referral Payout Details...'
\i 040_referral_payout_details.sql
\echo '[22/23] DONE'

\echo '[23/23] Require Visibility Fee System Setting...'
\i 041_require_visibility_fee_setting.sql
\echo '[23/23] DONE'

-- ============================================================
-- Final permission grants (consolidated from fix scripts)
-- ============================================================
\echo 'Applying final permission grants...'

GRANT SELECT ON public.admin_dashboard_stats TO authenticated;
GRANT SELECT ON public.pending_approvals TO authenticated;
GRANT SELECT ON public.flagged_users_summary TO authenticated;
GRANT SELECT ON public.active_disputes TO authenticated;
GRANT SELECT ON public.wallet_summary TO authenticated;
GRANT SELECT ON public.revenue_summary TO authenticated;
GRANT SELECT ON public.recent_transactions TO authenticated;
GRANT SELECT ON public.withdrawal_requests_summary TO authenticated;
GRANT SELECT ON public.admin_activity_summary TO authenticated;

GRANT SELECT ON public.admin_users TO authenticated;
GRANT SELECT ON public.admin_users TO anon;
GRANT UPDATE (last_login_at) ON public.admin_users TO authenticated;

\echo ''
\echo '============================================================'
\echo ' STEP 1 COMPLETE!'
\echo ' Now run: psql $DB -f STEP_2_create_admin.sql'
\echo ' (or open STEP_2_create_admin.sql in Supabase SQL Editor)'
\echo '============================================================'
\echo ''

-- Quick verification
SELECT
  COUNT(*)::text || ' tables created' AS result
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE';
