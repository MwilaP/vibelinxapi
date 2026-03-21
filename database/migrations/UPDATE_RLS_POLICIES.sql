-- ============================================
-- UPDATE RLS POLICIES FOR FRONTEND ACCESS
-- Run this in Supabase SQL Editor
-- ============================================

-- The current policies only work with service_role
-- We need to allow authenticated users to access their own data

-- 1. DROP existing restrictive policies
DROP POLICY IF EXISTS "Users can view their own wallets" ON wallets;
DROP POLICY IF EXISTS "Service role can manage all wallets" ON wallets;

-- 2. CREATE new policies that work with authenticated users
CREATE POLICY "Users can view their own wallets"
  ON wallets FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own wallets"
  ON wallets FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role can manage all wallets"
  ON wallets FOR ALL
  TO service_role
  USING (true);

-- 3. UPDATE wallet_transactions policies
DROP POLICY IF EXISTS "Users can view their wallet transactions" ON wallet_transactions;
DROP POLICY IF EXISTS "Service role can manage all wallet transactions" ON wallet_transactions;

CREATE POLICY "Users can view their wallet transactions"
  ON wallet_transactions FOR SELECT
  TO authenticated
  USING (
    wallet_id IN (
      SELECT id FROM wallets WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage all wallet transactions"
  ON wallet_transactions FOR ALL
  TO service_role
  USING (true);

-- 4. UPDATE escrow_transactions policies
DROP POLICY IF EXISTS "Users can view their escrow transactions" ON escrow_transactions;
DROP POLICY IF EXISTS "Service role can manage all escrow transactions" ON escrow_transactions;

CREATE POLICY "Users can view their escrow transactions"
  ON escrow_transactions FOR SELECT
  TO authenticated
  USING (
    client_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
    OR provider_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role can manage all escrow transactions"
  ON escrow_transactions FOR ALL
  TO service_role
  USING (true);

-- 5. UPDATE withdrawal_requests policies
DROP POLICY IF EXISTS "Users can view their withdrawal requests" ON withdrawal_requests;
DROP POLICY IF EXISTS "Users can create withdrawal requests" ON withdrawal_requests;
DROP POLICY IF EXISTS "Service role can manage all withdrawal requests" ON withdrawal_requests;

CREATE POLICY "Users can view their withdrawal requests"
  ON withdrawal_requests FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can create withdrawal requests"
  ON withdrawal_requests FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role can manage all withdrawal requests"
  ON withdrawal_requests FOR ALL
  TO service_role
  USING (true);

-- ============================================
-- VERIFY POLICIES
-- ============================================
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies 
WHERE tablename IN ('wallets', 'wallet_transactions', 'escrow_transactions', 'withdrawal_requests')
ORDER BY tablename, policyname;

-- ============================================
-- POLICIES UPDATED!
-- ============================================
-- Now authenticated users can access their own wallet data
-- Refresh your frontend and it should work
-- ============================================
