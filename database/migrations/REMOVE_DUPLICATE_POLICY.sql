-- ============================================
-- REMOVE DUPLICATE POLICY
-- Run this in Supabase SQL Editor
-- ============================================

-- Remove the duplicate "Users can view their own wallet" policy
-- This one has role 'public' which might be conflicting
DROP POLICY IF EXISTS "Users can view their own wallet" ON wallets;

-- Verify only the correct policies remain
SELECT 
  tablename,
  policyname,
  roles,
  cmd
FROM pg_policies 
WHERE tablename = 'wallets'
ORDER BY policyname;

-- You should see only these 4 policies:
-- 1. Enable insert for authenticated users
-- 2. Enable read for authenticated users
-- 3. Enable update for authenticated users
-- 4. Service role full access

-- ============================================
-- DONE!
-- ============================================
