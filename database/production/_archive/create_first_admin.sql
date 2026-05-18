-- ============================================
-- CREATE FIRST ADMIN USER FOR VIBESLINX
-- ============================================
-- This script creates a complete admin user setup
-- Run this in Supabase SQL Editor after all migrations
-- ============================================

-- INSTRUCTIONS:
-- 1. Replace the placeholders below with your actual values
-- 2. Run this script in Supabase SQL Editor
-- 3. Use the phone number to login to the admin panel

-- ============================================
-- CONFIGURATION - UPDATE THESE VALUES
-- ============================================

-- Your phone number (e.g., '0971234567')
\set admin_phone '0971234567'

-- Your display name
\set admin_name 'Admin User'

-- ============================================
-- STEP 1: Create Auth User (if not exists)
-- ============================================

DO $$
DECLARE
  v_user_id UUID;
  v_email TEXT;
  v_phone TEXT := '0971234567'; -- UPDATE THIS
  v_display_name TEXT := 'Admin User'; -- UPDATE THIS
BEGIN
  -- Convert phone to email format
  v_email := v_phone || '@vibeslinx.com';
  
  -- Check if user already exists
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = v_email;
  
  IF v_user_id IS NULL THEN
    -- Create new auth user
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
      crypt('temporary_password_change_me', gen_salt('bf')),
      NOW(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object(
        'phone', v_phone,
        'display_name', v_display_name,
        'role', 'client'
      ),
      NOW(),
      NOW(),
      '',
      '',
      '',
      ''
    ) RETURNING id INTO v_user_id;
    
    RAISE NOTICE 'Created auth user with ID: %', v_user_id;
  ELSE
    RAISE NOTICE 'Auth user already exists with ID: %', v_user_id;
  END IF;
  
  -- ============================================
  -- STEP 2: Create Profile (if not exists)
  -- ============================================
  
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
    INSERT INTO public.profiles (
      id,
      display_name,
      phone,
      role,
      onboarding_completed
    ) VALUES (
      v_user_id,
      v_display_name,
      v_phone,
      'client',
      true
    );
    
    RAISE NOTICE 'Created profile for user: %', v_user_id;
  ELSE
    RAISE NOTICE 'Profile already exists for user: %', v_user_id;
  END IF;
  
  -- ============================================
  -- STEP 3: Create Admin User (if not exists)
  -- ============================================
  
  IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = v_user_id) THEN
    INSERT INTO public.admin_users (
      user_id,
      role,
      status,
      assigned_by,
      assigned_at
    ) VALUES (
      v_user_id,
      'super_admin',
      'active',
      NULL, -- First admin has no assigner
      NOW()
    );
    
    RAISE NOTICE 'Created super admin for user: %', v_user_id;
  ELSE
    RAISE NOTICE 'Admin user already exists for: %', v_user_id;
  END IF;
  
  -- ============================================
  -- STEP 4: Display Summary
  -- ============================================
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'ADMIN USER CREATED SUCCESSFULLY!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'User ID: %', v_user_id;
  RAISE NOTICE 'Email: %', v_email;
  RAISE NOTICE 'Phone: %', v_phone;
  RAISE NOTICE 'Display Name: %', v_display_name;
  RAISE NOTICE 'Role: super_admin';
  RAISE NOTICE 'Status: active';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'NEXT STEPS:';
  RAISE NOTICE '1. Go to Supabase Auth > Users';
  RAISE NOTICE '2. Find user: %', v_email;
  RAISE NOTICE '3. Send password reset email OR use magic link';
  RAISE NOTICE '4. Login to admin panel at http://localhost:3001';
  RAISE NOTICE '5. Use phone number: %', v_phone;
  RAISE NOTICE '========================================';
  
END $$;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Verify the admin user was created
SELECT 
  au.id as admin_id,
  au.user_id,
  au.role,
  au.status,
  p.display_name,
  p.phone,
  u.email,
  au.created_at
FROM public.admin_users au
JOIN public.profiles p ON au.user_id = p.id
JOIN auth.users u ON au.user_id = u.id
WHERE au.role = 'super_admin'
ORDER BY au.created_at DESC
LIMIT 1;
