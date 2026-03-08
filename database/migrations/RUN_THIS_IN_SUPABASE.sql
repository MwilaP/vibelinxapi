-- ============================================
-- WALLET AND ESCROW SYSTEM MIGRATION
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Create wallets table
CREATE TABLE IF NOT EXISTS wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('client', 'provider')),
  available_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  locked_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  total_deposited DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  total_withdrawn DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  currency VARCHAR(3) NOT NULL DEFAULT 'ZMW',
  status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'frozen')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, user_type)
);

-- 2. Create wallet_transactions table
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  transaction_type VARCHAR(30) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  balance_before DECIMAL(10,2) NOT NULL,
  balance_after DECIMAL(10,2) NOT NULL,
  reference_id UUID,
  reference_type VARCHAR(30),
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Create escrow_transactions table
CREATE TABLE IF NOT EXISTS escrow_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  client_wallet_id UUID NOT NULL REFERENCES wallets(id),
  provider_wallet_id UUID NOT NULL REFERENCES wallets(id),
  amount DECIMAL(10,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'locked' CHECK (status IN ('locked', 'released', 'refunded', 'disputed', 'cancelled')),
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

-- 4. Create withdrawal_requests table
CREATE TABLE IF NOT EXISTS withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  payment_method VARCHAR(20) NOT NULL,
  payment_phone VARCHAR(20),
  bank_details JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  transaction_id UUID,
  failure_reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Create indexes
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_user_type ON wallets(user_type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON wallet_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_booking_id ON escrow_transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_escrow_transactions_status ON escrow_transactions(status);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_user_id ON withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status ON withdrawal_requests(status);

-- 6. Create updated_at triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_wallets_updated_at ON wallets;
CREATE TRIGGER update_wallets_updated_at
  BEFORE UPDATE ON wallets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_escrow_transactions_updated_at ON escrow_transactions;
CREATE TRIGGER update_escrow_transactions_updated_at
  BEFORE UPDATE ON escrow_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_withdrawal_requests_updated_at ON withdrawal_requests;
CREATE TRIGGER update_withdrawal_requests_updated_at
  BEFORE UPDATE ON withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 7. Enable Row Level Security
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawal_requests ENABLE ROW LEVEL SECURITY;

-- 8. Create RLS Policies for wallets
DROP POLICY IF EXISTS "Users can view their own wallets" ON wallets;
CREATE POLICY "Users can view their own wallets"
  ON wallets FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Service role can manage all wallets" ON wallets;
CREATE POLICY "Service role can manage all wallets"
  ON wallets FOR ALL
  USING (auth.role() = 'service_role');

-- 9. Create RLS Policies for wallet_transactions
DROP POLICY IF EXISTS "Users can view their wallet transactions" ON wallet_transactions;
CREATE POLICY "Users can view their wallet transactions"
  ON wallet_transactions FOR SELECT
  USING (
    wallet_id IN (
      SELECT id FROM wallets WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Service role can manage all wallet transactions" ON wallet_transactions;
CREATE POLICY "Service role can manage all wallet transactions"
  ON wallet_transactions FOR ALL
  USING (auth.role() = 'service_role');

-- 10. Create RLS Policies for escrow_transactions
DROP POLICY IF EXISTS "Users can view their escrow transactions" ON escrow_transactions;
CREATE POLICY "Users can view their escrow transactions"
  ON escrow_transactions FOR SELECT
  USING (
    client_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
    OR provider_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Service role can manage all escrow transactions" ON escrow_transactions;
CREATE POLICY "Service role can manage all escrow transactions"
  ON escrow_transactions FOR ALL
  USING (auth.role() = 'service_role');

-- 11. Create RLS Policies for withdrawal_requests
DROP POLICY IF EXISTS "Users can view their withdrawal requests" ON withdrawal_requests;
CREATE POLICY "Users can view their withdrawal requests"
  ON withdrawal_requests FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can create withdrawal requests" ON withdrawal_requests;
CREATE POLICY "Users can create withdrawal requests"
  ON withdrawal_requests FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Service role can manage all withdrawal requests" ON withdrawal_requests;
CREATE POLICY "Service role can manage all withdrawal requests"
  ON withdrawal_requests FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================
-- MIGRATION COMPLETE!
-- ============================================
-- You should see a success message.
-- Now restart your backend server and try again.
-- ============================================
