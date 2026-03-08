-- Wallet and Escrow System Migration
-- This migration creates the necessary tables for the wallet-based escrow system

-- 1. Wallets Table - Stores wallet balances for clients and providers
CREATE TABLE IF NOT EXISTS wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('client', 'provider')),
  available_balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  locked_balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  total_deposited DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  total_withdrawn DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  currency VARCHAR(3) NOT NULL DEFAULT 'ZMW',
  status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'frozen')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, user_type)
);

-- 2. Wallet Transactions Table - Records all wallet operations
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
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
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Escrow Table - Manages funds held in escrow for bookings
CREATE TABLE IF NOT EXISTS escrow_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  client_wallet_id UUID NOT NULL REFERENCES wallets(id),
  provider_wallet_id UUID NOT NULL REFERENCES wallets(id),
  amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'locked' CHECK (status IN (
    'locked', 'released', 'refunded', 'disputed', 'cancelled'
  )),
  locked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  released_at TIMESTAMP WITH TIME ZONE,
  refunded_at TIMESTAMP WITH TIME ZONE,
  released_to_provider_at TIMESTAMP WITH TIME ZONE,
  reason TEXT,
  resolved_by UUID REFERENCES auth.users(id),
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Withdrawal Requests Table - Manages provider withdrawal requests
CREATE TABLE IF NOT EXISTS withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount DECIMAL(10, 2) NOT NULL,
  payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('mtn', 'airtel', 'zamtel', 'bank_transfer')),
  payment_phone VARCHAR(20),
  bank_details JSONB,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'processing', 'completed', 'failed', 'cancelled'
  )),
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  transaction_id UUID,
  failure_reason TEXT,
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Update transactions table to support wallet deposits
ALTER TABLE transactions 
  ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_user_type ON wallets(user_type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type ON wallet_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at ON wallet_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_escrow_booking_id ON escrow_transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_escrow_status ON escrow_transactions(status);
CREATE INDEX IF NOT EXISTS idx_escrow_client_wallet ON escrow_transactions(client_wallet_id);
CREATE INDEX IF NOT EXISTS idx_escrow_provider_wallet ON escrow_transactions(provider_wallet_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_wallet_id ON withdrawal_requests(wallet_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status ON withdrawal_requests(status);

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add triggers for updated_at columns
DROP TRIGGER IF EXISTS update_wallets_updated_at ON wallets;
CREATE TRIGGER update_wallets_updated_at
  BEFORE UPDATE ON wallets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_escrow_updated_at ON escrow_transactions;
CREATE TRIGGER update_escrow_updated_at
  BEFORE UPDATE ON escrow_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_withdrawal_updated_at ON withdrawal_requests;
CREATE TRIGGER update_withdrawal_updated_at
  BEFORE UPDATE ON withdrawal_requests
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Row Level Security (RLS) Policies
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawal_requests ENABLE ROW LEVEL SECURITY;

-- Wallets policies
CREATE POLICY "Users can view their own wallet"
  ON wallets FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage all wallets"
  ON wallets FOR ALL
  USING (auth.role() = 'service_role');

-- Wallet transactions policies
CREATE POLICY "Users can view their wallet transactions"
  ON wallet_transactions FOR SELECT
  USING (
    wallet_id IN (
      SELECT id FROM wallets WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage all wallet transactions"
  ON wallet_transactions FOR ALL
  USING (auth.role() = 'service_role');

-- Escrow transactions policies
CREATE POLICY "Users can view their escrow transactions"
  ON escrow_transactions FOR SELECT
  USING (
    client_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
    OR provider_wallet_id IN (SELECT id FROM wallets WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role can manage all escrow transactions"
  ON escrow_transactions FOR ALL
  USING (auth.role() = 'service_role');

-- Withdrawal requests policies
CREATE POLICY "Users can view their withdrawal requests"
  ON withdrawal_requests FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can create withdrawal requests"
  ON withdrawal_requests FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role can manage all withdrawal requests"
  ON withdrawal_requests FOR ALL
  USING (auth.role() = 'service_role');
