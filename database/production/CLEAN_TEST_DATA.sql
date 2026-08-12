-- ====================================================================
-- VIBESLINX TEST DATA CLEAN-UP SCRIPT FOR PRODUCTION MIGRATION
-- ====================================================================
-- This script safely deletes all test bookings, payments, logs, and history
-- from Supabase while preserving:
-- 1. All client accounts (auth.users & profiles)
-- 2. All Admin Users (super_admin, finance_admin, support_admin, etc.)
-- 3. Global system settings config (with updated_by references cleared)
--
-- BUT deletes everything for providers (role = 'provider'):
-- - Auth users & login credentials are deleted
-- - Profiles, wallets, stats, and settings are fully purged
-- ====================================================================

-- 1. Disable triggers and foreign keys for this session to prevent constraint conflicts
SET session_replication_role = 'replica';

-- 2. Prevent foreign key failure on profiles/settings when truncating logs/history
UPDATE public.profiles SET referred_by_user_id = NULL;
UPDATE public.system_settings SET updated_by = NULL;

-- Reset client subscription statuses to inactive since we are clearing test subscriptions
UPDATE public.profiles SET subscription_status = 'inactive';

-- 3. Clear transactional, history, and booking logs completely
TRUNCATE TABLE public.bookings CASCADE;
TRUNCATE TABLE public.transactions CASCADE;
TRUNCATE TABLE public.wallet_transactions CASCADE;
TRUNCATE TABLE public.escrow_transactions CASCADE;
TRUNCATE TABLE public.withdrawal_requests CASCADE;
TRUNCATE TABLE public.escrow_payments CASCADE;
TRUNCATE TABLE public.notifications CASCADE;
TRUNCATE TABLE public.reviews CASCADE;
TRUNCATE TABLE public.subscriptions CASCADE;

-- Clear referral and admin log tables
TRUNCATE TABLE public.referral_earnings CASCADE;
TRUNCATE TABLE public.referral_payouts CASCADE;
TRUNCATE TABLE public.referral_fraud_flags CASCADE;
TRUNCATE TABLE public.admin_activity_log CASCADE;
TRUNCATE TABLE public.admin_sessions CASCADE;
TRUNCATE TABLE public.user_actions CASCADE;
TRUNCATE TABLE public.user_flags CASCADE;
TRUNCATE TABLE public.booking_disputes CASCADE;
TRUNCATE TABLE public.booking_admin_notes CASCADE;
TRUNCATE TABLE public.wallet_adjustments CASCADE;
TRUNCATE TABLE public.escrow_admin_actions CASCADE;
TRUNCATE TABLE public.withdrawal_admin_actions CASCADE;
TRUNCATE TABLE public.platform_revenue CASCADE;
TRUNCATE TABLE public.wallet_reconciliation CASCADE;
TRUNCATE TABLE public.transaction_summaries CASCADE;

-- 4. Delete all provider users from auth.users (which cascades to public.profiles, etc.)
-- Keeping ONLY client users and admin users
DELETE FROM auth.users 
WHERE id NOT IN (
  SELECT id FROM public.profiles WHERE role = 'client'
)
AND id NOT IN (
  SELECT user_id FROM public.admin_users
)
AND COALESCE(raw_user_meta_data->>'role', '') != 'client';

-- 5. Delete stats, ratings, wallets, and balances associated with deleted provider users
-- (Cleans up orphan records not covered by cascades, if any)
DELETE FROM public.wallets 
WHERE user_id NOT IN (
  SELECT id FROM public.profiles WHERE role = 'client'
)
AND user_id NOT IN (
  SELECT user_id FROM public.admin_users
);

DELETE FROM public.wallet_balances 
WHERE user_id NOT IN (
  SELECT id FROM public.profiles WHERE role = 'client'
)
AND user_id NOT IN (
  SELECT user_id FROM public.admin_users
);

DELETE FROM public.provider_stats;
DELETE FROM public.provider_ratings;

-- 6. Reset wallets and legacy balances for the remaining client users to 0.00
UPDATE public.wallets
SET 
  available_balance = 0.00,
  locked_balance = 0.00,
  total_deposited = 0.00,
  total_withdrawn = 0.00,
  status = 'active',
  updated_at = NOW();

UPDATE public.wallet_balances
SET
  available_balance = 0.00,
  escrow_balance = 0.00,
  total_earned = 0.00,
  total_spent = 0.00,
  total_withdrawn = 0.00,
  updated_at = NOW();

-- 7. Reset remaining client statistics and rating caches
TRUNCATE TABLE public.client_stats CASCADE;
INSERT INTO public.client_stats (
  client_id, total_bookings, completed_bookings, average_rating, total_reviews, last_active_at, created_at, updated_at
)
SELECT 
  id, 0, 0, 0.00, 0, NULL, NOW(), NOW()
FROM public.profiles
WHERE role = 'client'
ON CONFLICT (client_id) DO UPDATE 
SET 
  total_bookings = 0,
  completed_bookings = 0,
  average_rating = 0.00,
  total_reviews = 0,
  last_active_at = NULL,
  updated_at = NOW();

TRUNCATE TABLE public.client_ratings CASCADE;
INSERT INTO public.client_ratings (
  client_id, average_rating, total_reviews, 
  five_star_count, four_star_count, three_star_count, two_star_count, one_star_count,
  last_review_at, updated_at
)
SELECT 
  id, 0.00, 0, 
  0, 0, 0, 0, 0, 
  NULL, NOW()
FROM public.profiles
WHERE role = 'client'
ON CONFLICT (client_id) DO UPDATE
SET
  average_rating = 0.00,
  total_reviews = 0,
  five_star_count = 0,
  four_star_count = 0,
  three_star_count = 0,
  two_star_count = 0,
  one_star_count = 0,
  last_review_at = NULL,
  updated_at = NOW();

-- 8. Reset referral wallets for surviving client profiles
TRUNCATE TABLE public.referral_wallets CASCADE;
INSERT INTO public.referral_wallets (user_id, balance, total_earned, total_paid_out, last_updated_at)
SELECT id, 0.00, 0.00, 0.00, NOW()
FROM public.profiles
WHERE role = 'client'
ON CONFLICT (user_id) DO UPDATE
SET
  balance = 0.00,
  total_earned = 0.00,
  total_paid_out = 0.00,
  last_updated_at = NOW();

-- 9. Restore triggers and foreign keys for the database
SET session_replication_role = 'origin';
