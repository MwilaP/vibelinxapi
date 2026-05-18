-- ============================================
-- QUICK FIX: Disable RLS on admin_users
-- ============================================
-- Run this immediately to fix the infinite recursion error
-- ============================================

-- Disable RLS on admin_users table
ALTER TABLE public.admin_users DISABLE ROW LEVEL SECURITY;

-- Verify it's disabled
SELECT 
  tablename, 
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'admin_users';

-- Test that it works
SELECT 
  id,
  role,
  status,
  created_at
FROM public.admin_users
LIMIT 5;

-- Success message
SELECT 'RLS disabled on admin_users - infinite recursion fixed!' as status;
