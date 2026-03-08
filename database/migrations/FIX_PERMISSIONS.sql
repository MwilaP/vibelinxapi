-- ============================================
-- FIX WALLET PERMISSIONS
-- Run this in Supabase SQL Editor
-- ============================================

-- First, verify the tables exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'wallets') THEN
        RAISE EXCEPTION 'Table wallets does not exist! Run RUN_THIS_IN_SUPABASE.sql first';
    END IF;
END $$;

-- Grant ALL permissions to service_role on all wallet tables
GRANT ALL ON TABLE public.wallets TO service_role;
GRANT ALL ON TABLE public.wallet_transactions TO service_role;
GRANT ALL ON TABLE public.escrow_transactions TO service_role;
GRANT ALL ON TABLE public.withdrawal_requests TO service_role;

-- Grant usage on sequences (for auto-incrementing IDs if any)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Ensure service_role can insert/update/delete
ALTER TABLE public.wallets OWNER TO postgres;
ALTER TABLE public.wallet_transactions OWNER TO postgres;
ALTER TABLE public.escrow_transactions OWNER TO postgres;
ALTER TABLE public.withdrawal_requests OWNER TO postgres;

-- Re-grant permissions
GRANT ALL PRIVILEGES ON TABLE public.wallets TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.wallet_transactions TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.escrow_transactions TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.withdrawal_requests TO service_role;

-- Verify permissions
SELECT 
    tablename,
    tableowner,
    has_table_privilege('service_role', schemaname || '.' || tablename, 'SELECT') as can_select,
    has_table_privilege('service_role', schemaname || '.' || tablename, 'INSERT') as can_insert,
    has_table_privilege('service_role', schemaname || '.' || tablename, 'UPDATE') as can_update,
    has_table_privilege('service_role', schemaname || '.' || tablename, 'DELETE') as can_delete
FROM pg_tables 
WHERE tablename IN ('wallets', 'wallet_transactions', 'escrow_transactions', 'withdrawal_requests')
AND schemaname = 'public';

-- ============================================
-- PERMISSIONS FIXED!
-- ============================================
-- You should see TRUE for all can_* columns above
-- Now restart your backend server
-- ============================================
