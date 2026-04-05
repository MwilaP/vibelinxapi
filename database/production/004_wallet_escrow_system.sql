-- ============================================
-- VIBESLINX WALLET & ESCROW SYSTEM - PRODUCTION v1.0
-- Comprehensive Wallet Management & Escrow Transactions
-- ============================================
-- This migration creates the complete wallet system including:
-- - Wallets table for user balances
-- - Wallet transactions for all wallet operations
-- - Escrow transactions for booking-related holds
-- - Withdrawal requests for provider payouts
-- Merged from both vibeslinx and vibelinxapi repositories
-- Includes all fixes from: 012_fix_wallet_trigger_permissions.sql,
-- 024_fix_wallet_notification_triggers.sql, 026_fix_transaction_id_columns_type.sql,
-- 031_fix_wallet_rls_policies.sql, 034_fix_wallet_trigger_permissions.sql
-- ============================================

-- ============================================
-- 1. CREATE WALLETS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('client', 'provider')),
  available_balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  locked_balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  total_deposited DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  total_withdrawn DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  currency VARCHAR(3) NOT NULL DEFAULT 'ZMW',
  status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'frozen')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, user_type)
);

-- ============================================
-- 2. CREATE WALLET TRANSACTIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
  transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN (
    'deposit', 'withdrawal', 'escrow_lock', 'escrow_release', 
    'escrow_refund', 'booking_deduction', 'service_payment', 'admin_adjustment'
  )),
  amount DECIMAL(10, 2) NOT NULL,
  balance_before DECIMAL(10, 2) NOT NULL,
  balance_after DECIMAL(10, 2) NOT NULL,
  reference_id UUID,
  reference_type VARCHAR(30) CHECK (reference_type IN ('booking', 'escrow', 'payment', 'withdrawal')),
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 3. CREATE ESCROW TRANSACTIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.escrow_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  client_wallet_id UUID NOT NULL REFERENCES public.wallets(id),
  provider_wallet_id UUID NOT NULL REFERENCES public.wallets(id),
  amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'locked' CHECK (status IN (
    'locked', 'released', 'refunded', 'disputed', 'cancelled'
  )),
  locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  released_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  released_to_provider_at TIMESTAMPTZ,
  reason TEXT,
  resolved_by UUID REFERENCES auth.users(id),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(booking_id)
);

-- ============================================
-- 4. CREATE WITHDRAWAL REQUESTS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount DECIMAL(10, 2) NOT NULL,
  payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('mtn', 'airtel', 'zamtel', 'bank_transfer')),
  payment_phone VARCHAR(20),
  bank_details JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'processing', 'completed', 'failed', 'cancelled'
  )),
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  transaction_id UUID,
  failure_reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 5. CREATE WALLET BALANCES TABLE (Legacy Support)
-- ============================================

CREATE TABLE IF NOT EXISTS public.wallet_balances (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  available_balance DECIMAL(10, 2) NOT NULL DEFAULT 0,
  escrow_balance DECIMAL(10, 2) NOT NULL DEFAULT 0,
  total_earned DECIMAL(10, 2) NOT NULL DEFAULT 0,
  total_spent DECIMAL(10, 2) NOT NULL DEFAULT 0,
  total_withdrawn DECIMAL(10, 2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT valid_balances CHECK (
    available_balance >= 0 AND 
    escrow_balance >= 0 AND
    total_earned >= 0 AND
    total_spent >= 0 AND
    total_withdrawn >= 0
  )
);

-- ============================================
-- 6. CREATE INDEXES
-- ============================================

-- Wallets indexes
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_user_type ON public.wallets(user_type);
CREATE INDEX IF NOT EXISTS idx_wallets_status ON public.wallets(status);

-- Wallet transactions indexes
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_id ON public.wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type ON public.wallet_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON public.wallet_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_reference ON public.wallet_transactions(reference_id, reference_type);

-- Escrow transactions indexes
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_booking_id ON public.escrow_transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_status ON public.escrow_transactions(status);
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_client_wallet ON public.escrow_transactions(client_wallet_id);
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_provider_wallet ON public.escrow_transactions(provider_wallet_id);

-- Withdrawal requests indexes
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_wallet_id ON public.withdrawal_requests(wallet_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_user_id ON public.withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status ON public.withdrawal_requests(status);

-- Wallet balances indexes
CREATE INDEX IF NOT EXISTS idx_wallet_balances_available ON public.wallet_balances(available_balance DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_balances_updated ON public.wallet_balances(updated_at DESC);

-- ============================================
-- 7. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Function to create wallet on user creation
CREATE OR REPLACE FUNCTION public.create_wallet_on_signup()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create wallet_balances entry
  INSERT INTO public.wallet_balances (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  
  -- Create wallets entry based on role
  INSERT INTO public.wallets (user_id, user_type)
  SELECT NEW.id, NEW.raw_user_meta_data->>'role'
  WHERE NEW.raw_user_meta_data->>'role' IN ('client', 'provider')
  ON CONFLICT (user_id, user_type) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update wallet balance based on transactions
CREATE OR REPLACE FUNCTION public.update_wallet_balance()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  wallet_record RECORD;
BEGIN
  -- Only process completed transactions
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    
    -- Ensure wallet exists
    INSERT INTO public.wallet_balances (user_id)
    VALUES (NEW.user_id)
    ON CONFLICT (user_id) DO NOTHING;
    
    -- Update balance based on transaction type
    CASE NEW.type
      -- Incoming funds (escrow releases)
      WHEN 'escrow_release' THEN
        UPDATE public.wallet_balances
        SET 
          available_balance = available_balance + NEW.amount,
          total_earned = total_earned + NEW.amount,
          updated_at = NOW()
        WHERE user_id = NEW.user_id;
        
      -- Outgoing funds (payments)
      WHEN 'payment' THEN
        UPDATE public.wallet_balances
        SET 
          total_spent = total_spent + ABS(NEW.amount),
          updated_at = NOW()
        WHERE user_id = NEW.user_id;
        
      -- Withdrawals
      WHEN 'withdrawal' THEN
        UPDATE public.wallet_balances
        SET 
          available_balance = available_balance - ABS(NEW.amount),
          total_withdrawn = total_withdrawn + ABS(NEW.amount),
          updated_at = NOW()
        WHERE user_id = NEW.user_id;
        
      -- Refunds
      WHEN 'refund' THEN
        UPDATE public.wallet_balances
        SET 
          available_balance = available_balance + NEW.amount,
          updated_at = NOW()
        WHERE user_id = NEW.user_id;
        
      -- Deposits
      WHEN 'deposit' THEN
        UPDATE public.wallet_balances
        SET 
          available_balance = available_balance + NEW.amount,
          updated_at = NOW()
        WHERE user_id = NEW.user_id;
        
      ELSE
        NULL;
    END CASE;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update escrow balance
CREATE OR REPLACE FUNCTION public.update_escrow_balance()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ensure wallets exist for both parties
  INSERT INTO public.wallet_balances (user_id)
  VALUES (NEW.payer_id), (NEW.payee_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  -- Handle escrow status changes
  IF NEW.status = 'held' AND (OLD.status IS NULL OR OLD.status != 'held') THEN
    -- Add to payee's escrow balance when funds are held
    UPDATE public.wallet_balances
    SET 
      escrow_balance = escrow_balance + NEW.amount,
      updated_at = NOW()
    WHERE user_id = NEW.payee_id;
    
  ELSIF NEW.status = 'released' AND OLD.status = 'held' THEN
    -- Remove from escrow when released
    UPDATE public.wallet_balances
    SET 
      escrow_balance = escrow_balance - NEW.amount,
      updated_at = NOW()
    WHERE user_id = NEW.payee_id;
    
  ELSIF NEW.status = 'refunded' AND OLD.status = 'held' THEN
    -- Remove from escrow when refunded
    UPDATE public.wallet_balances
    SET 
      escrow_balance = escrow_balance - NEW.amount,
      updated_at = NOW()
    WHERE user_id = NEW.payee_id;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update updated_at column
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 8. CREATE TRIGGERS
-- ============================================

-- Create wallet when user signs up
DROP TRIGGER IF EXISTS on_user_created_wallet ON auth.users;
CREATE TRIGGER on_user_created_wallet
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_wallet_on_signup();

-- Update wallet on transaction completion
DROP TRIGGER IF EXISTS on_transaction_completed_update_wallet ON public.transactions;
CREATE TRIGGER on_transaction_completed_update_wallet
  AFTER INSERT OR UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_wallet_balance();

-- Update escrow balance on escrow changes
DROP TRIGGER IF EXISTS on_escrow_changed_update_wallet ON public.escrow_payments;
CREATE TRIGGER on_escrow_changed_update_wallet
  AFTER INSERT OR UPDATE ON public.escrow_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.update_escrow_balance();

-- Update updated_at triggers
DROP TRIGGER IF EXISTS update_wallets_updated_at ON public.wallets;
CREATE TRIGGER update_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_escrow_transactions_updated_at ON public.escrow_transactions;
CREATE TRIGGER update_escrow_transactions_updated_at
  BEFORE UPDATE ON public.escrow_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_withdrawal_requests_updated_at ON public.withdrawal_requests;
CREATE TRIGGER update_withdrawal_requests_updated_at
  BEFORE UPDATE ON public.withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================
-- 9. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_balances ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 10. CREATE RLS POLICIES
-- ============================================

-- Wallets policies
DROP POLICY IF EXISTS "Users can view their own wallets" ON public.wallets;
DROP POLICY IF EXISTS "Service role can manage all wallets" ON public.wallets;

CREATE POLICY "Users can view their own wallets"
  ON public.wallets FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Service role can manage all wallets"
  ON public.wallets FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Wallet transactions policies
DROP POLICY IF EXISTS "Users can view their wallet transactions" ON public.wallet_transactions;
DROP POLICY IF EXISTS "Service role can manage all wallet transactions" ON public.wallet_transactions;

CREATE POLICY "Users can view their wallet transactions"
  ON public.wallet_transactions FOR SELECT
  TO authenticated
  USING (
    wallet_id IN (
      SELECT id FROM public.wallets WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage all wallet transactions"
  ON public.wallet_transactions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Escrow transactions policies
DROP POLICY IF EXISTS "Users can view their escrow transactions" ON public.escrow_transactions;
DROP POLICY IF EXISTS "Service role can manage all escrow transactions" ON public.escrow_transactions;

CREATE POLICY "Users can view their escrow transactions"
  ON public.escrow_transactions FOR SELECT
  TO authenticated
  USING (
    client_wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid())
    OR provider_wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role can manage all escrow transactions"
  ON public.escrow_transactions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Withdrawal requests policies
DROP POLICY IF EXISTS "Users can view their withdrawal requests" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Users can create withdrawal requests" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Service role can manage all withdrawal requests" ON public.withdrawal_requests;

CREATE POLICY "Users can view their withdrawal requests"
  ON public.withdrawal_requests FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users can create withdrawal requests"
  ON public.withdrawal_requests FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role can manage all withdrawal requests"
  ON public.withdrawal_requests FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Wallet balances policies
DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallet_balances;
DROP POLICY IF EXISTS "Service role can manage wallets" ON public.wallet_balances;

CREATE POLICY "Users can view own wallet"
ON public.wallet_balances FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage wallets"
ON public.wallet_balances
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 11. CREATE WALLET VIEWS
-- ============================================

-- Wallet summary view
CREATE OR REPLACE VIEW public.wallet_summary AS
SELECT 
  wb.user_id,
  wb.available_balance,
  wb.escrow_balance,
  wb.available_balance + wb.escrow_balance as total_balance,
  wb.total_earned,
  wb.total_spent,
  wb.total_withdrawn,
  wb.updated_at,
  p.display_name,
  p.role
FROM public.wallet_balances wb
JOIN public.profiles p ON p.id = wb.user_id;

GRANT SELECT ON public.wallet_summary TO authenticated;

-- ============================================
-- 12. GRANT PERMISSIONS
-- ============================================

GRANT SELECT ON public.wallets TO authenticated;
GRANT ALL ON public.wallets TO service_role;

GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT ALL ON public.wallet_transactions TO service_role;

GRANT SELECT ON public.escrow_transactions TO authenticated;
GRANT ALL ON public.escrow_transactions TO service_role;

GRANT SELECT, INSERT ON public.withdrawal_requests TO authenticated;
GRANT ALL ON public.withdrawal_requests TO service_role;

GRANT SELECT ON public.wallet_balances TO authenticated;
GRANT ALL ON public.wallet_balances TO service_role;

-- ============================================
-- WALLET & ESCROW SYSTEM COMPLETE
-- ============================================
