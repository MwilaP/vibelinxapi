-- ============================================================
-- VIBESLINX PRODUCTION DATABASE SETUP
-- STEP 2 OF 2: Create Your First Super Admin
-- ============================================================
-- Prerequisites: STEP_1_run_migrations.sql must have run first.
--
-- HOW TO USE:
--   1. Update the three variables below (phone, name, password)
--   2. Copy this entire file into the Supabase SQL Editor
--   3. Click "Run"
--   4. Note your login credentials from the output
-- ============================================================

DO $$
DECLARE
  -- ============================================================
  -- ⚠️  UPDATE THESE THREE LINES WITH YOUR DETAILS:
  admin_phone    TEXT := '0971234567';   -- Your phone number
  admin_name     TEXT := 'Super Admin';  -- Your display name
  admin_password TEXT := 'Admin@123';    -- Your login password (CHANGE THIS!)
  -- ============================================================

  v_user_id UUID;
  v_email   TEXT;
BEGIN
  v_email := admin_phone || '@vibeslinx.com';

  RAISE NOTICE '========================================';
  RAISE NOTICE 'Creating admin user...';
  RAISE NOTICE 'Phone: %', admin_phone;
  RAISE NOTICE 'Email: %', v_email;
  RAISE NOTICE '========================================';

  -- Check if user already exists
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NULL THEN
    RAISE NOTICE 'User not found. Creating new auth user...';

    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      v_email,
      crypt(admin_password, gen_salt('bf')),
      NOW(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('phone', admin_phone, 'display_name', admin_name, 'role', 'client'),
      NOW(), NOW(), '', '', '', ''
    ) RETURNING id INTO v_user_id;

    -- Create profile manually in case the trigger hasn't fired yet
    INSERT INTO public.profiles (id, display_name, phone, role, onboarding_completed)
    VALUES (v_user_id, admin_name, admin_phone, 'client', true)
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE '✓ Created auth user: %', v_user_id;
  ELSE
    RAISE NOTICE 'User already exists (ID: %)', v_user_id;
  END IF;

  -- Create or promote admin record
  INSERT INTO public.admin_users (user_id, role, status)
  VALUES (v_user_id, 'super_admin', 'active')
  ON CONFLICT (user_id) DO UPDATE SET
    role      = 'super_admin',
    status    = 'active',
    updated_at = NOW();

  RAISE NOTICE '✓ Admin record created/updated';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ SUCCESS!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Login at: http://localhost:3001 (or your admin URL)';
  RAISE NOTICE '  Phone:    %', admin_phone;
  RAISE NOTICE '  Password: %', admin_password;
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  Change your password after first login!';
  RAISE NOTICE '========================================';
END $$;

-- ============================================================
-- Verify the admin was created successfully
-- ============================================================
SELECT
  '✅ Admin Created' AS result,
  au.role            AS admin_role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  au.created_at
FROM public.admin_users au
JOIN public.profiles    p ON au.user_id = p.id
JOIN auth.users         u ON au.user_id = u.id
WHERE au.role = 'super_admin'
ORDER BY au.created_at DESC
LIMIT 1;

-- ============================================================
-- ALTERNATIVE: Promote an existing app user instead
-- ============================================================
-- If you already have a user account in the app, comment out
-- the DO block above and uncomment this instead:

/*
INSERT INTO public.admin_users (user_id, role, status)
SELECT p.id, 'super_admin', 'active'
FROM public.profiles p
WHERE p.phone = '0971234567'   -- 👈 your phone number
ON CONFLICT (user_id) DO UPDATE SET
  role   = 'super_admin',
  status = 'active',
  updated_at = NOW();
*/
