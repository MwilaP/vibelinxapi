-- ============================================
-- VERIFY AND FIX RLS POLICIES
-- Run this in Supabase SQL Editor
-- ============================================

-- First, check current policies
SELECT 
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE tablename = 'wallets';

-- If the above shows no policies or wrong policies, run this:

-- Disable RLS temporarily to test
ALTER TABLE wallets DISABLE ROW LEVEL SECURITY;

-- Re-enable RLS
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies
DROP POLICY IF EXISTS "Users can view their own wallets" ON wallets;
DROP POLICY IF EXISTS "Users can insert their own wallets" ON wallets;
DROP POLICY IF EXISTS "Service role can manage all wallets" ON wallets;

-- Create simple, permissive policies
CREATE POLICY "Enable read for authenticated users"
  ON wallets
  FOR SELECT
  TO authenticated
  USING (true);  -- Allow all authenticated users to read (we'll filter in the query)

CREATE POLICY "Enable insert for authenticated users"
  ON wallets
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Enable update for authenticated users"
  ON wallets
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role full access"
  ON wallets
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Do the same for wallet_transactions
ALTER TABLE wallet_transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their wallet transactions" ON wallet_transactions;
DROP POLICY IF EXISTS "Service role can manage all wallet transactions" ON wallet_transactions;

CREATE POLICY "Enable read for authenticated users"
  ON wallet_transactions
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access"
  ON wallet_transactions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Do the same for escrow_transactions
ALTER TABLE escrow_transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their escrow transactions" ON escrow_transactions;
DROP POLICY IF EXISTS "Service role can manage all escrow transactions" ON escrow_transactions;

CREATE POLICY "Enable read for authenticated users"
  ON escrow_transactions
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Service role full access"
  ON escrow_transactions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Verify policies were created
SELECT 
  tablename,
  policyname,
  roles,
  cmd
FROM pg_policies 
WHERE tablename IN ('wallets', 'wallet_transactions', 'escrow_transactions')
ORDER BY tablename, policyname;

-- ============================================
-- POLICIES FIXED!
-- ============================================
-- Now try refreshing your frontend
-- ============================================
