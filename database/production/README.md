# Vibeslinx Production Database Setup

Fresh Supabase database? Run **two files**. That's it.

---

## ⚡ Quick Start (2 Steps)

### Step 1 — Run All Migrations

Run each numbered file **in order** in the Supabase SQL Editor:

| # | File | What it does |
|---|------|-------------|
| 1 | `001_core_schema.sql` | Profiles, auth triggers, storage bucket, RLS |
| 2 | `002_bookings_system.sql` | Bookings table, status triggers, RLS |
| 3 | `003_transactions_payments.sql` | Transactions, escrow payments, auto-escrow triggers |
| 4 | `004_wallet_escrow_system.sql` | Wallets, wallet transactions, withdrawal requests |
| 5 | `005_reviews_ratings.sql` | Reviews, provider & client rating caches, rating triggers |
| 6 | `006_notifications.sql` | Notifications table, booking/payment event triggers |
| 7 | `007_provider_stats.sql` | Provider stats, leaderboard view, profile view counter |
| 8 | `008_subscriptions.sql` | Subscriptions, expiry handling, wallet purchase function |
| 9 | `009_indexes_optimization.sql` | Composite indexes, partial indexes, materialized views |
| 10 | `010_realtime_setup.sql` | Replica identity for Supabase Realtime |
| 11 | `011_admin_system.sql` | Admin tables, roles, permissions (35+), audit log |
| 12 | `012_admin_functions.sql` | Admin stored procedures (adjust wallets, escrow, disputes) |
| 13 | `013_admin_views_policies.sql` | Admin dashboard views, RLS policies |
| 14 | `014_fix_admin_rls.sql` | Disables RLS on admin_users to prevent infinite recursion |
| 15 | `015_withdrawal_payout_system.sql` | Payout methods, Lencopay integration columns |
| 16 | `016_system_settings.sql` | Platform settings table with defaults |
| 17 | `017_referral_system.sql` | Referral codes, earnings, wallets, payouts, fraud flags |
| 18 | `036_add_province_to_profiles.sql` | Province column on profiles |
| 19 | `037_provider_visibility_fee.sql` | Visibility status/fee, updates search functions |
| 20 | `038_admin_grant_functions.sql` | Admin grant/revoke subscription & visibility functions |
| 21 | `039_admin_revenue_stats.sql` | Revenue metrics in admin dashboard view |
| 22 | `040_referral_payout_details.sql` | Payout phone, provider, fee columns on referral_payouts |

> **Tip (psql):** You can run all migrations at once from the command line:
> ```bash
> export DB="postgresql://postgres:[PASSWORD]@[PROJECT_REF].supabase.co:5432/postgres"
> for f in 001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 036 037 038 039 040; do
>   psql $DB -f ${f}_*.sql
> done
> ```

---

### Step 2 — Create Your First Admin

Open **`STEP_2_create_admin.sql`** in Supabase SQL Editor.

1. Update the three variables at the top: `admin_phone`, `admin_name`, `admin_password`
2. Click **Run**
3. Note your login credentials from the output

Login at your admin panel and **change your password immediately**.

---

## Post-Setup Checklist

### Enable Realtime (Supabase Dashboard)

Go to **Database → Replication** and enable these tables:

- `transactions`
- `bookings`
- `notifications`
- `wallet_balances`
- `wallet_transactions`
- `escrow_payments`
- `reviews`
- `provider_stats`

### Environment Variables

```env
VITE_SUPABASE_URL=https://[PROJECT_REF].supabase.co
VITE_SUPABASE_ANON_KEY=[YOUR_ANON_KEY]
SUPABASE_SERVICE_ROLE_KEY=[YOUR_SERVICE_ROLE_KEY]
DATABASE_URL=postgresql://postgres:[PASSWORD]@[PROJECT_REF].supabase.co:5432/postgres
```

### Verify Installation

```sql
-- All tables should be present
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- RLS should be enabled on most tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = true;
```

---

## Database Schema Reference

### Core Tables
| Table | Purpose |
|-------|---------|
| `profiles` | All users (clients & providers) |
| `bookings` | Booking lifecycle & payment tracking |
| `transactions` | All payment transactions |
| `escrow_payments` | Escrow records per booking |

### Wallet System
| Table | Purpose |
|-------|---------|
| `wallets` | User wallet balances |
| `wallet_transactions` | Wallet operation history |
| `escrow_transactions` | Booking escrow (new wallet system) |
| `withdrawal_requests` | Provider payout requests |
| `payout_methods` | Saved payout methods (MTN, Airtel, Zamtel) |

### Social
| Table | Purpose |
|-------|---------|
| `reviews` | Mutual client↔provider reviews |
| `provider_ratings` | Cached provider rating stats |
| `client_ratings` | Cached client rating stats |
| `notifications` | In-app notifications |

### Analytics
| Table | Purpose |
|-------|---------|
| `provider_stats` | Booking counts, performance metrics |
| `subscriptions` | Client subscription records |
| `system_settings` | Admin-configurable platform settings |

### Referral System
| Table | Purpose |
|-------|---------|
| `referral_earnings` | Per-event referral reward records |
| `referral_wallets` | Referral balance per user |
| `referral_payouts` | Referral payout requests |
| `referral_fraud_flags` | Fraud detection flags |

### Admin System
| Table | Purpose |
|-------|---------|
| `admin_users` | Admin accounts & roles |
| `admin_permissions` | 35+ granular permissions |
| `admin_role_permissions` | Role → permission mapping |
| `admin_activity_log` | Full audit trail |
| `user_flags` | User moderation flags |
| `booking_disputes` | Dispute resolution |
| `wallet_adjustments` | Manual balance adjustments (with approval) |
| `escrow_admin_actions` | Admin escrow interventions |
| `platform_revenue` | Revenue tracking |

---

## Admin Roles

| Role | Access |
|------|--------|
| `super_admin` | Full access, can bypass approval workflows |
| `finance_admin` | Wallets, escrow, financial reports |
| `support_admin` | Users, disputes, booking management |
| `operations_admin` | Day-to-day ops, withdrawals, basic reports |

---

## Maintenance

**Daily** (via cron):
```sql
SELECT public.expire_subscriptions();
```

**Weekly**:
```sql
SELECT public.refresh_top_providers();
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Triggers not firing | All triggers use `SECURITY DEFINER` — check function exists |
| RLS blocking admin operations | Use `service_role` key for backend API calls |
| Realtime not working | Check replica identity: `ALTER TABLE t REPLICA IDENTITY FULL;` |
| `admin_users` recursion error | Run `014_fix_admin_rls.sql` |
| Dashboard showing zeros | Re-run `039_admin_revenue_stats.sql` to refresh view |
| Search not working | `UPDATE public.profiles SET updated_at = updated_at;` |

---

## File Structure

```
production/
├── README.md                      ← You are here
├── STEP_2_create_admin.sql        ← Run after migrations to create first admin
│
├── 001_core_schema.sql            ┐
├── 002_bookings_system.sql        │
├── 003_transactions_payments.sql  │
├── 004_wallet_escrow_system.sql   │
├── 005_reviews_ratings.sql        │
├── 006_notifications.sql          │ Run in order
├── 007_provider_stats.sql         │
├── 008_subscriptions.sql          │
├── 009_indexes_optimization.sql   │
├── 010_realtime_setup.sql         │
├── 011_admin_system.sql           │
├── 012_admin_functions.sql        │
├── 013_admin_views_policies.sql   │
├── 014_fix_admin_rls.sql          │
├── 015_withdrawal_payout_system.sql│
├── 016_system_settings.sql        │
├── 017_referral_system.sql        │
├── 036_add_province_to_profiles.sql│
├── 037_provider_visibility_fee.sql│
├── 038_admin_grant_functions.sql  │
├── 039_admin_revenue_stats.sql    │
└── 040_referral_payout_details.sql┘
│
└── _archive/                      ← Old one-off fix scripts (keep for reference)
```

---

**Status**: Production Ready ✅ | **Last Updated**: May 2026
