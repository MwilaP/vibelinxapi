-- ============================================
-- ADMIN REVENUE STATS ENHANCEMENT
-- ============================================

-- 1. Add RLS policies for admin access to revenue-related tables
-- This ensures the view can be queried by admin users

-- Subscriptions
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Admins can view all subscriptions') THEN
    CREATE POLICY "Admins can view all subscriptions"
    ON public.subscriptions FOR SELECT
    TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid() AND status = 'active'
      )
    );
  END IF;
END $$;

-- Escrow Payments
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'escrow_payments' AND policyname = 'Admins can view all escrow payments') THEN
    CREATE POLICY "Admins can view all escrow payments"
    ON public.escrow_payments FOR SELECT
    TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid() AND status = 'active'
      )
    );
  END IF;
END $$;

-- Transactions (Extend existing policy or add new one)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'transactions' AND policyname = 'Admins can view all transactions') THEN
    CREATE POLICY "Admins can view all transactions"
    ON public.transactions FOR SELECT
    TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.admin_users
        WHERE user_id = auth.uid() AND status = 'active'
      )
    );
  END IF;
END $$;

-- 2. Update admin_dashboard_stats view with revenue metrics
CREATE OR REPLACE VIEW public.admin_dashboard_stats AS
SELECT
  (SELECT COUNT(*) FROM public.profiles) as total_users,
  (SELECT COUNT(*) FROM public.profiles WHERE role = 'client') as total_clients,
  (SELECT COUNT(*) FROM public.profiles WHERE role = 'provider') as total_providers,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'pending') as pending_bookings,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'confirmed') as confirmed_bookings,
  (SELECT COUNT(*) FROM public.bookings WHERE status = 'completed') as completed_bookings,
  (SELECT COALESCE(SUM(available_balance + locked_balance), 0) FROM public.wallets) as total_wallet_balance,
  (SELECT COALESCE(SUM(amount), 0) FROM public.escrow_transactions WHERE status = 'locked') as total_locked_escrow,
  (SELECT COUNT(*) FROM public.withdrawal_requests WHERE status = 'pending') as pending_withdrawals,
  (SELECT COUNT(*) FROM public.user_flags WHERE status IN ('pending', 'under_review')) as active_flags,
  (SELECT COUNT(*) FROM public.booking_disputes WHERE status IN ('pending', 'under_review')) as active_disputes,
  -- All-time Revenue Stats
  (SELECT COALESCE(SUM(amount_paid), 0) FROM public.subscriptions) as total_subscription_revenue,
  (SELECT COALESCE(SUM(platform_fee), 0) FROM public.bookings WHERE status = 'completed') as total_platform_fees,
  (SELECT COALESCE(SUM(ABS(amount)), 0) FROM public.transactions 
   WHERE metadata->>'fee_type' = 'visibility_fee' 
   AND status = 'completed') as total_visibility_fees;

-- 3. Grant permissions
GRANT SELECT ON public.admin_dashboard_stats TO authenticated;
