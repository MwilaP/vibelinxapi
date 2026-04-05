# Vibeslinx Production Database Migrations

This directory contains consolidated, production-ready database migration files for the Vibeslinx platform. These migrations have been consolidated from 42 scattered migration files across both `vibeslinx/supabase` and `vibelinxapi/database` repositories.

## Overview

**Total Migrations**: 10 consolidated files  
**Source Files**: 35 from vibeslinx + 7 from vibelinxapi = 42 original files  
**Target Database**: Supabase (PostgreSQL)  
**Purpose**: Fresh production database setup

## Migration Files

Execute these files **in order** for a fresh Supabase project:

### 001_core_schema.sql
**Core User Profiles & Authentication**
- Profiles table with full-text search
- Authentication triggers (handle_new_user)
- Storage bucket for profile photos
- RLS policies for profiles and storage
- Search functions (case-insensitive city search)
- **Includes fixes from**: 013_fix_city_case_insensitive.sql

### 002_bookings_system.sql
**Booking Management**
- Bookings table with payment tracking
- Status management triggers
- Commitment percentage support
- RLS policies for clients and providers
- **Includes fixes from**: 014_add_commitment_percentage.sql, 018_fix_booking_profile_access.sql, 019_add_payment_tracking.sql, 026_remove_booking_date_constraint.sql, 030_add_wallet_payment_type.sql

### 003_transactions_payments.sql
**Transaction & Escrow Management**
- Transactions table for all payments
- Escrow payments table
- Automated escrow release/refund triggers
- Auto-create escrow on booking
- **Includes fixes from**: 020_transaction_metadata_redesign.sql, 023_fix_transaction_type_case.sql, 025_auto_create_escrow_on_booking.sql, 027_fix_escrow_release_transaction_type.sql

### 004_wallet_escrow_system.sql
**Comprehensive Wallet System**
- Wallets table (new system)
- Wallet transactions tracking
- Escrow transactions for bookings
- Withdrawal requests
- Wallet balances (legacy support)
- Automated balance updates
- **Merged from both repositories**
- **Includes fixes from**: 012_fix_wallet_trigger_permissions.sql, 024_fix_wallet_notification_triggers.sql, 026_fix_transaction_id_columns_type.sql, 031_fix_wallet_rls_policies.sql, 034_fix_wallet_trigger_permissions.sql

### 005_reviews_ratings.sql
**Reviews & Rating System**
- Reviews table with moderation
- Provider ratings cache
- Automated rating recalculation
- Review eligibility validation
- 7-day edit window for reviews

### 006_notifications.sql
**Notification System**
- Notifications table
- Automated triggers for booking events
- Payment event notifications
- Review notifications
- **Includes fixes from**: 021_fix_trigger_and_notifications.sql

### 007_provider_stats.sql
**Provider Analytics**
- Provider stats table
- Automated booking stats tracking
- Performance metrics calculation
- Profile view counter
- Provider leaderboard view
- **Includes fixes from**: 015_fix_provider_stats_permissions.sql, 016_fix_trigger_security.sql, 017_fix_provider_stats_trigger_final.sql, 028_add_increment_profile_views_function.sql

### 008_subscriptions.sql
**Client Subscriptions**
- Subscriptions table (monthly/annual)
- Automated status updates
- Wallet-integrated purchase function
- Subscription expiration handling
- **Includes fixes from**: 033_fix_subscription_wallet_permissions.sql, 035_secure_subscription_purchase.sql

### 009_indexes_optimization.sql
**Performance Optimization**
- Materialized view for top providers
- Composite indexes for common queries
- Partial indexes for filtered queries
- Covering indexes for performance
- Expression indexes

### 010_realtime_setup.sql
**Supabase Realtime**
- Enable replica identity for live updates
- Configuration for realtime subscriptions
- **Includes fixes from**: 022_enable_realtime_transactions.sql

## Deployment Instructions

### Prerequisites
- Supabase project created
- Database access via SQL Editor or psql
- Supabase CLI (optional, for local development)

### Step 1: Run Migrations in Order

**Option A: Supabase SQL Editor (Recommended)**
1. Log into your Supabase Dashboard
2. Navigate to SQL Editor
3. Copy and paste each migration file **in order** (001 → 010)
4. Execute each migration
5. Verify success before proceeding to the next

**Option B: Command Line (psql)**
```bash
# Set your database connection string
export DATABASE_URL="postgresql://postgres:[PASSWORD]@[PROJECT_REF].supabase.co:5432/postgres"

# Run migrations in order
psql $DATABASE_URL -f 001_core_schema.sql
psql $DATABASE_URL -f 002_bookings_system.sql
psql $DATABASE_URL -f 003_transactions_payments.sql
psql $DATABASE_URL -f 004_wallet_escrow_system.sql
psql $DATABASE_URL -f 005_reviews_ratings.sql
psql $DATABASE_URL -f 006_notifications.sql
psql $DATABASE_URL -f 007_provider_stats.sql
psql $DATABASE_URL -f 008_subscriptions.sql
psql $DATABASE_URL -f 009_indexes_optimization.sql
psql $DATABASE_URL -f 010_realtime_setup.sql
```

**Option C: Supabase CLI**
```bash
# Link to your project
supabase link --project-ref [YOUR_PROJECT_REF]

# Apply migrations
supabase db push
```

### Step 2: Enable Realtime (Supabase Dashboard)

After running all migrations:

1. Go to **Database** → **Replication** in Supabase Dashboard
2. Enable replication for these tables:
   - `transactions`
   - `bookings`
   - `notifications`
   - `wallet_balances`
   - `wallet_transactions`
   - `escrow_payments`
   - `reviews`
   - `provider_stats`

### Step 3: Verify Installation

Run this verification query in SQL Editor:

```sql
-- Check all tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Expected tables:
-- bookings, escrow_payments, escrow_transactions, notifications,
-- profiles, provider_ratings, provider_stats, reviews, subscriptions,
-- transactions, wallet_balances, wallet_transactions, wallets,
-- withdrawal_requests

-- Check RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND rowsecurity = true;

-- Check triggers exist
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;
```

### Step 4: Configure Environment Variables

Update your application's environment variables:

```env
# Supabase
VITE_SUPABASE_URL=https://[PROJECT_REF].supabase.co
VITE_SUPABASE_ANON_KEY=[YOUR_ANON_KEY]
SUPABASE_SERVICE_ROLE_KEY=[YOUR_SERVICE_ROLE_KEY]

# Database (for backend API)
DATABASE_URL=postgresql://postgres:[PASSWORD]@[PROJECT_REF].supabase.co:5432/postgres
```

## Database Schema Overview

### Core Tables
- **profiles**: User profiles (clients & providers)
- **bookings**: Booking management
- **transactions**: All payment transactions
- **escrow_payments**: Escrow for bookings

### Wallet System
- **wallets**: User wallet balances (new)
- **wallet_balances**: Legacy wallet support
- **wallet_transactions**: Wallet operation history
- **escrow_transactions**: Booking-related escrow
- **withdrawal_requests**: Provider payout requests

### Social Features
- **reviews**: User reviews
- **provider_ratings**: Cached rating calculations
- **notifications**: User notifications

### Analytics
- **provider_stats**: Provider performance metrics
- **subscriptions**: Client subscription management

### Storage
- **profile-photos**: Storage bucket for user photos

## Key Features

### Security
- ✅ Row Level Security (RLS) enabled on all tables
- ✅ SECURITY DEFINER on sensitive triggers
- ✅ Service role policies for backend operations
- ✅ Proper foreign key constraints

### Performance
- ✅ Comprehensive indexing strategy
- ✅ Materialized views for common queries
- ✅ Full-text search on profiles
- ✅ Partial indexes for filtered queries

### Automation
- ✅ Auto-create profiles on signup
- ✅ Auto-create wallets on signup
- ✅ Auto-create escrow on booking
- ✅ Auto-release/refund escrow on completion/cancellation
- ✅ Auto-calculate provider ratings
- ✅ Auto-update provider stats
- ✅ Auto-send notifications

### Realtime
- ✅ Live booking updates
- ✅ Live transaction updates
- ✅ Live notification updates
- ✅ Live wallet balance updates

## Maintenance

### Regular Tasks

**Daily** (via cron job):
```sql
-- Expire old subscriptions
SELECT public.expire_subscriptions();
```

**Weekly**:
```sql
-- Refresh top providers materialized view
SELECT public.refresh_top_providers();
```

### Monitoring Queries

**Check wallet balances**:
```sql
SELECT * FROM public.wallet_summary ORDER BY total_balance DESC LIMIT 10;
```

**Check pending bookings**:
```sql
SELECT COUNT(*) FROM public.bookings WHERE status = 'pending';
```

**Check provider performance**:
```sql
SELECT * FROM public.provider_leaderboard LIMIT 10;
```

## Troubleshooting

### Issue: Triggers not firing
**Solution**: Check trigger security and search_path settings. All triggers use `SECURITY DEFINER` and `SET search_path = public`.

### Issue: RLS blocking operations
**Solution**: Verify you're using the correct role (authenticated vs service_role). Backend operations should use service_role key.

### Issue: Realtime not working
**Solution**: 
1. Verify replica identity is set: `ALTER TABLE [table] REPLICA IDENTITY FULL;`
2. Check replication is enabled in Supabase Dashboard
3. Verify RLS policies allow the user to SELECT the row

### Issue: Search not working
**Solution**: Update search vectors:
```sql
UPDATE public.profiles SET updated_at = updated_at;
```

## Support

For issues or questions:
- Check migration comments for specific feature documentation
- Review RLS policies if access issues occur
- Verify all migrations ran successfully
- Check Supabase logs for detailed error messages

## Migration History

**Consolidated**: April 2026  
**Original Files**: 42 migrations  
**Consolidated Files**: 10 migrations  
**Status**: Production Ready ✅

---

**Note**: This is a complete fresh setup. For existing databases with data, a different migration strategy would be required.
