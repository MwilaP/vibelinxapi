-- ============================================
-- PROMOTE EXISTING USER TO ADMIN
-- ============================================
-- Use this if you already have a user account
-- and want to make it an admin
-- ============================================

-- Option 1: Promote by Phone Number
-- UPDATE the phone number below:

INSERT INTO public.admin_users (user_id, role, status)
SELECT 
  p.id,
  'super_admin',
  'active'
FROM public.profiles p
WHERE p.phone = '0971234567'  -- 👈 CHANGE THIS to your phone number
ON CONFLICT (user_id) 
DO UPDATE SET 
  role = 'super_admin',
  status = 'active',
  updated_at = NOW();

-- Verify it worked
SELECT 
  au.role as admin_role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  au.created_at
FROM public.admin_users au
JOIN public.profiles p ON au.user_id = p.id
JOIN auth.users u ON au.user_id = u.id
WHERE p.phone = '0971234567'  -- 👈 CHANGE THIS to match above
LIMIT 1;


-- ============================================
-- OR Option 2: Promote by User ID
-- ============================================
-- If you know the user ID, use this instead:

/*
INSERT INTO public.admin_users (user_id, role, status)
VALUES (
  'YOUR-USER-ID-HERE',  -- 👈 CHANGE THIS to your user ID
  'super_admin',
  'active'
)
ON CONFLICT (user_id) 
DO UPDATE SET 
  role = 'super_admin',
  status = 'active',
  updated_at = NOW();
*/


-- ============================================
-- FIND YOUR USER ID
-- ============================================
-- If you don't know your user ID, run this:

/*
SELECT 
  p.id as user_id,
  p.display_name,
  p.phone,
  p.role,
  u.email
FROM public.profiles p
JOIN auth.users u ON p.id = u.id
WHERE p.phone LIKE '%1234567%'  -- 👈 CHANGE THIS to part of your phone
ORDER BY p.created_at DESC;
*/


-- ============================================
-- LIST ALL ADMIN USERS
-- ============================================
-- To see all current admins:

SELECT 
  au.id,
  au.role as admin_role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  au.last_login_at,
  au.created_at
FROM public.admin_users au
JOIN public.profiles p ON au.user_id = p.id
JOIN auth.users u ON au.user_id = u.id
ORDER BY au.created_at DESC;
