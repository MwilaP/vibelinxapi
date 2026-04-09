# Admin User Setup Guide

This guide will help you create your first admin user for the Vibeslinx Admin Panel.

## 📋 Prerequisites

- ✅ All database migrations applied (001-013)
- ✅ Supabase project set up
- ✅ Access to Supabase SQL Editor

## 🚀 Quick Start - Choose Your Method

### Method 1: Create New Admin User (Recommended)

**Use this if you don't have an existing user account.**

1. Open Supabase Dashboard → SQL Editor
2. Open the file: `create_admin_simple.sql`
3. Update these three lines at the top:
   ```sql
   admin_phone TEXT := '0971234567';    -- Your phone number
   admin_name TEXT := 'Super Admin';     -- Your name
   admin_password TEXT := 'Admin@123';   -- Your secure password
   ```
4. Click "Run" or press `Ctrl+Enter`
5. Check the output for success message

### Method 2: Promote Existing User

**Use this if you already have a user account in the system.**

1. Open Supabase Dashboard → SQL Editor
2. Open the file: `promote_to_admin.sql`
3. Update the phone number in the WHERE clause:
   ```sql
   WHERE p.phone = '0971234567'  -- Your phone number
   ```
4. Click "Run"
5. Verify the result shows your admin user

## 📝 Detailed Instructions

### Step-by-Step: Create New Admin User

1. **Navigate to Supabase**
   - Go to https://supabase.com
   - Select your project
   - Click "SQL Editor" in the left sidebar

2. **Copy the SQL Script**
   - Open `create_admin_simple.sql`
   - Copy the entire contents

3. **Customize the Script**
   ```sql
   admin_phone TEXT := '0971234567';        -- Change to your phone
   admin_name TEXT := 'Your Name Here';     -- Change to your name
   admin_password TEXT := 'SecurePass123';  -- Change to a strong password
   ```

4. **Run the Script**
   - Paste into SQL Editor
   - Click "Run" button
   - Wait for completion

5. **Verify Success**
   - You should see messages like:
     ```
     ✓ Created auth user and profile
     ✓ Created/updated admin user
     ✅ SUCCESS! Admin user is ready
     ```
   - A verification table will show your admin details

### What Gets Created

The script creates three things:

1. **Auth User** (`auth.users`)
   - Email: `{phone}@vibeslinx.com`
   - Confirmed and ready to use

2. **Profile** (`public.profiles`)
   - Display name
   - Phone number
   - Role: client
   - Onboarding completed

3. **Admin User** (`public.admin_users`)
   - Role: super_admin
   - Status: active
   - Full permissions

## 🔐 Login to Admin Panel

After creating the admin user:

1. **Start the Admin Panel**
   ```bash
   cd d:\personal\vibeslinx-admin
   npm run dev
   ```

2. **Open in Browser**
   - Navigate to: http://localhost:3001

3. **Login**
   - Enter your phone number (e.g., `0971234567`)
   - Enter your password
   - Click "Sign In"

4. **You're In!**
   - You'll be redirected to the admin dashboard
   - Your role badge will show "Super Admin"

## 📱 Default Login Flow

1. **Phone Number & Password Entry** → Enter credentials
2. **Authentication** → System verifies via Supabase Auth
3. **Admin Check** → System verifies you're an active admin
4. **Dashboard** → You're redirected to the admin dashboard

## 🔍 Troubleshooting

### Problem: "User not found" or "Access denied"

**Solution:**
```sql
-- Check if admin user exists
SELECT * FROM public.admin_users 
WHERE user_id IN (
  SELECT id FROM public.profiles WHERE phone = '0971234567'
);
```

If no results, run the creation script again.

### Problem: "Invalid phone number or password"

**Solutions:**
1. Verify the phone number matches exactly (no spaces)
2. Check that the password is correct (case-sensitive)
3. Reset password if needed:
   ```sql
   UPDATE auth.users 
   SET encrypted_password = crypt('NewPassword123', gen_salt('bf'))
   WHERE email = '0971234567@vibeslinx.com';
   ```

### Problem: Forgot password

**Solution - Reset via SQL:**
```sql
-- Update password for admin user
UPDATE auth.users 
SET encrypted_password = crypt('YourNewPassword', gen_salt('bf'))
WHERE email = 'YOUR_PHONE@vibeslinx.com';
```

### Problem: Can't find user ID

**Run this query:**
```sql
SELECT 
  p.id as user_id,
  p.display_name,
  p.phone,
  u.email
FROM public.profiles p
JOIN auth.users u ON p.id = u.id
WHERE p.phone = '0971234567'  -- Your phone number
LIMIT 1;
```

## 📊 Verify Admin Setup

Run this query to see all admin users:

```sql
SELECT 
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
```

Expected output:
```
admin_role   | status | display_name | phone      | email
-------------|--------|--------------|------------|------------------------
super_admin  | active | Your Name    | 0971234567 | 0971234567@vibeslinx.com
```

## 👥 Creating Additional Admins

To create more admin users with different roles:

```sql
-- Finance Admin
INSERT INTO public.admin_users (user_id, role, status, assigned_by)
SELECT 
  p.id,
  'finance_admin',
  'active',
  (SELECT id FROM public.admin_users WHERE role = 'super_admin' LIMIT 1)
FROM public.profiles p
WHERE p.phone = 'PHONE_NUMBER_HERE';

-- Support Admin
INSERT INTO public.admin_users (user_id, role, status, assigned_by)
SELECT 
  p.id,
  'support_admin',
  'active',
  (SELECT id FROM public.admin_users WHERE role = 'super_admin' LIMIT 1)
FROM public.profiles p
WHERE p.phone = 'PHONE_NUMBER_HERE';

-- Operations Admin
INSERT INTO public.admin_users (user_id, role, status, assigned_by)
SELECT 
  p.id,
  'operations_admin',
  'active',
  (SELECT id FROM public.admin_users WHERE role = 'super_admin' LIMIT 1)
FROM public.profiles p
WHERE p.phone = 'PHONE_NUMBER_HERE';
```

## 🎯 Admin Roles & Permissions

| Role | Permissions |
|------|-------------|
| **super_admin** | Full access to everything, can bypass approvals |
| **finance_admin** | Wallets, escrow, withdrawals, financial reports |
| **support_admin** | Users, bookings, disputes, flags |
| **operations_admin** | Daily operations, basic reports |

## 📚 Next Steps

After creating your admin user:

1. ✅ Login to admin panel
2. ✅ Explore the dashboard
3. ✅ Test user management features
4. ✅ Review pending approvals
5. ✅ Check financial reports

## 🆘 Need Help?

- Check the main README: `../vibeslinx-admin/README.md`
- Review implementation status: `../vibeslinx-admin/IMPLEMENTATION_STATUS.md`
- Check Supabase logs for errors
- Verify all migrations ran successfully

## 📝 Files Reference

- `create_admin_simple.sql` - Quick admin creation (recommended)
- `create_first_admin.sql` - Detailed admin creation with comments
- `promote_to_admin.sql` - Promote existing user to admin
- `ADMIN_SETUP_GUIDE.md` - This guide

---

**Ready to go?** Run one of the SQL scripts and start managing your platform! 🚀
