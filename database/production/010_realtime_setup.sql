-- ============================================
-- VIBESLINX REALTIME SETUP - PRODUCTION v1.0
-- Enable Supabase Realtime for Live Updates
-- ============================================
-- This migration enables Supabase Realtime subscriptions for
-- tables that need live updates in the frontend.
-- Consolidated from: 022_enable_realtime_transactions.sql
-- ============================================

-- ============================================
-- 1. ENABLE REPLICA IDENTITY FOR REALTIME TABLES
-- ============================================

-- Enable replica identity for transactions table (required for realtime)
ALTER TABLE public.transactions REPLICA IDENTITY FULL;

-- Enable replica identity for bookings table
ALTER TABLE public.bookings REPLICA IDENTITY FULL;

-- Enable replica identity for notifications table
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- Enable replica identity for wallet_balances table
ALTER TABLE public.wallet_balances REPLICA IDENTITY FULL;

-- Enable replica identity for wallet_transactions table
ALTER TABLE public.wallet_transactions REPLICA IDENTITY FULL;

-- Enable replica identity for escrow_payments table
ALTER TABLE public.escrow_payments REPLICA IDENTITY FULL;

-- Enable replica identity for reviews table
ALTER TABLE public.reviews REPLICA IDENTITY FULL;

-- Enable replica identity for provider_stats table
ALTER TABLE public.provider_stats REPLICA IDENTITY FULL;

-- ============================================
-- 2. PUBLICATION NOTES
-- ============================================

-- Note: To enable realtime in Supabase, you need to:
-- 1. Go to Database > Replication in Supabase Dashboard
-- 2. Enable replication for the following tables:
--    - transactions
--    - bookings
--    - notifications
--    - wallet_balances
--    - wallet_transactions
--    - escrow_payments
--    - reviews
--    - provider_stats
--
-- Or run the following in SQL Editor:
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_balances;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_transactions;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.escrow_payments;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.provider_stats;

-- ============================================
-- REALTIME SETUP COMPLETE
-- ============================================
-- RLS policies already exist from previous migrations
-- Clients will only receive realtime updates for rows they have access to
-- ============================================
