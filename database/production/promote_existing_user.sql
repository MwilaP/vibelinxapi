-- ============================================
-- PROMOTE EXISTING CLIENT TO SUPER ADMIN
-- ============================================
-- Quick script to make an existing user a super admin
-- ============================================

-- Option 1: Promote by Phone Number (EASIEST)
-- Just update the phone number below and run this:

INSERT INTO public.admin_users (user_id, role, status)
SELECT 
  p.id,
  'super_admin',
  'active'
FROM public.profiles p
WHERE p.phone = '0971234567'  -- 👈 CHANGE THIS to the user's phone number
ON CONFLICT (user_id) 
DO UPDATE SET 
  role = 'super_admin',
  status = 'active',
  updated_at = NOW();

-- Verify it worked
SELECT 
  'SUCCESS! User is now Super Admin' as message,
  au.role as admin_role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  au.created_at
FROM public.admin_users au
JOIN public.profiles p ON au.user_id = p.id
JOIN auth.users u ON au.user_id = u.id
WHERE p.phone = '0971234567';  -- 👈 CHANGE THIS to match above


-- ============================================
-- Option 2: If you need to set a password too
-- ============================================
-- If the user doesn't have a password set, run this:

/*
-- Set password for the user
UPDATE auth.users 
SET encrypted_password = crypt('Admin@123', gen_salt('bf'))  -- 👈 CHANGE PASSWORD
WHERE email = '0971234567@vibeslinx.com';  -- 👈 CHANGE PHONE

-- Then promote to admin (same as Option 1)
INSERT INTO public.admin_users (user_id, role, status)
SELECT 
  p.id,
  'super_admin',
  'active'
FROM public.profiles p
WHERE p.phone = '0971234567'
ON CONFLICT (user_id) 
DO UPDATE SET 
  role = 'super_admin',
  status = 'active',
  updated_at = NOW();
*/


-- ============================================
-- FIND YOUR USER FIRST (if you don't know the phone)
-- ============================================
-- Uncomment and run this to find users:

/*
SELECT 
  p.id as user_id,
  p.display_name,
  p.phone,
  p.role,
  u.email,
  p.created_at
FROM public.profiles p
JOIN auth.users u ON p.id = u.id
WHERE p.role = 'client'  -- Show all clients
ORDER BY p.created_at DESC
LIMIT 10;
*/
