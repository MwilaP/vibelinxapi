-- ============================================
-- FIX ADMIN_USERS PERMISSIONS
-- ============================================
-- Grant necessary permissions for authenticated users
-- to access admin_users table
-- ============================================

-- Grant SELECT permission to authenticated users
GRANT SELECT ON public.admin_users TO authenticated;
GRANT SELECT ON public.admin_users TO anon;

-- Grant UPDATE permission for last_login_at
GRANT UPDATE (last_login_at) ON public.admin_users TO authenticated;

-- Verify permissions
SELECT 
  grantee, 
  privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'admin_users' 
AND table_schema = 'public';

-- Test query
SELECT 
  id,
  user_id,
  role,
  status
FROM public.admin_users
LIMIT 1;

SELECT 'Permissions granted successfully!' as status;
