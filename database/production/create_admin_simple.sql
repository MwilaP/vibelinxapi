-- ============================================
-- SIMPLE ADMIN USER CREATOR
-- ============================================
-- Quick script to create your first admin user
-- Copy this to Supabase SQL Editor and run it
-- ============================================

-- ⚠️ UPDATE THESE THREE LINES WITH YOUR INFO:
DO $$
DECLARE
  admin_phone TEXT := '0971234567';        -- 👈 CHANGE THIS to your phone number
  admin_name TEXT := 'Super Admin';        -- 👈 CHANGE THIS to your name
  admin_password TEXT := 'Admin@123';      -- 👈 CHANGE THIS to a secure password
  
  -- Internal variables (don't change these)
  v_user_id UUID;
  v_email TEXT;
BEGIN
  -- Convert phone to email
  v_email := admin_phone || '@vibeslinx.com';
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Creating admin user...';
  RAISE NOTICE 'Phone: %', admin_phone;
  RAISE NOTICE 'Email: %', v_email;
  RAISE NOTICE '========================================';
  
  -- Check if user exists
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;
  
  IF v_user_id IS NULL THEN
    -- User doesn't exist, create everything
    RAISE NOTICE 'User not found. Creating new user...';
    
    -- Create auth user
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
      NOW(),
      NOW(),
      '', '', '', ''
    ) RETURNING id INTO v_user_id;
    
    -- Create profile
    INSERT INTO public.profiles (id, display_name, phone, role, onboarding_completed)
    VALUES (v_user_id, admin_name, admin_phone, 'client', true);
    
    RAISE NOTICE '✓ Created auth user and profile';
  ELSE
    RAISE NOTICE 'User already exists with ID: %', v_user_id;
  END IF;
  
  -- Create or update admin user
  INSERT INTO public.admin_users (user_id, role, status)
  VALUES (v_user_id, 'super_admin', 'active')
  ON CONFLICT (user_id) 
  DO UPDATE SET 
    role = 'super_admin',
    status = 'active',
    updated_at = NOW();
  
  RAISE NOTICE '✓ Created/updated admin user';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ SUCCESS! Admin user is ready';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Login Details:';
  RAISE NOTICE '  Phone: %', admin_phone;
  RAISE NOTICE '  Password: %', admin_password;
  RAISE NOTICE '  Email: %', v_email;
  RAISE NOTICE '  User ID: %', v_user_id;
  RAISE NOTICE '';
  RAISE NOTICE 'Next Steps:';
  RAISE NOTICE '1. Go to admin panel: http://localhost:3001';
  RAISE NOTICE '2. Enter phone: %', admin_phone;
  RAISE NOTICE '3. Enter password: %', admin_password;
  RAISE NOTICE '4. Click Sign In';
  RAISE NOTICE '5. Start managing your platform!';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  IMPORTANT: Change your password after first login!';
  RAISE NOTICE '========================================';
END $$;

-- Verify the admin was created
SELECT 
  'VERIFICATION' as check_type,
  au.role as admin_role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  'Admin user created successfully!' as message
FROM public.admin_users au
JOIN public.profiles p ON au.user_id = p.id
JOIN auth.users u ON au.user_id = u.id
WHERE au.role = 'super_admin'
ORDER BY au.created_at DESC
LIMIT 1;
