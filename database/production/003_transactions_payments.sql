-- ============================================
-- VIBESLINX TRANSACTIONS & PAYMENTS - PRODUCTION v1.0
-- Transaction Records, Escrow Payments & Automated Triggers
-- ============================================
-- This migration creates the transactions and escrow_payments tables
-- with automated triggers for escrow release/refund on booking completion/cancellation.
-- Includes all fixes from: 020_transaction_metadata_redesign.sql,
-- 023_fix_transaction_type_case.sql, 025_auto_create_escrow_on_booking.sql,
-- 027_fix_escrow_release_transaction_type.sql
-- ============================================

-- ============================================
-- 1. CREATE TRANSACTIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  booking_id UUID REFERENCES public.bookings(id) ON DELETE SET NULL,
  
  -- Transaction Details
  amount DECIMAL(10, 2) NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('payment', 'withdrawal', 'refund', 'escrow_release', 'platform_fee', 'deposit', 'wallet_payment')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  
  -- Payment Method
  payment_method TEXT CHECK (payment_method IN ('mtn', 'airtel', 'zamtel', 'wallet')),
  payment_phone TEXT,
  reference_number TEXT,
  
  -- External Payment Reference
  external_transaction_id TEXT,
  external_status TEXT,
  
  -- Metadata
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  
  -- Error tracking
  error_message TEXT,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT valid_amount CHECK (amount != 0)
);

-- ============================================
-- 2. CREATE ESCROW PAYMENTS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.escrow_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  
  -- Parties
  payer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Amount Details
  amount DECIMAL(10, 2) NOT NULL,
  platform_fee DECIMAL(10, 2) NOT NULL DEFAULT 0,
  net_amount DECIMAL(10, 2) NOT NULL,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'released', 'refunded')),
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  held_at TIMESTAMPTZ DEFAULT NOW(),
  released_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  
  -- Constraints
  CONSTRAINT valid_escrow_amount CHECK (amount > 0 AND net_amount >= 0),
  CONSTRAINT unique_booking_escrow UNIQUE (booking_id),
  CONSTRAINT different_parties CHECK (payer_id != payee_id)
);

-- ============================================
-- 3. CREATE INDEXES
-- ============================================

-- Transactions indexes
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_booking_id ON public.transactions(booking_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON public.transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON public.transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_reference ON public.transactions(reference_number) WHERE reference_number IS NOT NULL;

-- Escrow indexes
CREATE INDEX IF NOT EXISTS idx_escrow_booking_id ON public.escrow_payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_escrow_payer_id ON public.escrow_payments(payer_id);
CREATE INDEX IF NOT EXISTS idx_escrow_payee_id ON public.escrow_payments(payee_id);
CREATE INDEX IF NOT EXISTS idx_escrow_status ON public.escrow_payments(status);

-- ============================================
-- 4. CREATE TRIGGER FUNCTIONS
-- ============================================

-- Function to update transaction timestamps
CREATE OR REPLACE FUNCTION public.handle_transaction_updated()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at = NOW();
  END IF;
  
  IF NEW.status = 'failed' AND OLD.status != 'failed' THEN
    NEW.failed_at = NOW();
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to create escrow payment when booking is created with payment
CREATE OR REPLACE FUNCTION public.create_escrow_on_booking()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  transaction_record RECORD;
  platform_fee_amount DECIMAL(10, 2);
  net_amount DECIMAL(10, 2);
  escrow_amount DECIMAL(10, 2);
BEGIN
  -- Only create escrow if booking has a commitment transaction
  IF NEW.commitment_paid = true AND NEW.commitment_transaction_id IS NOT NULL THEN
    
    -- Get the transaction details
    SELECT * INTO transaction_record
    FROM public.transactions
    WHERE id = NEW.commitment_transaction_id::uuid;
    
    IF FOUND THEN
      -- Calculate platform fee (10% of total amount)
      platform_fee_amount := NEW.total_amount * 0.10;
      
      -- Determine escrow amount based on payment type
      IF NEW.balance_paid = true THEN
        -- Full payment - escrow the entire amount minus platform fee
        escrow_amount := NEW.total_amount;
        net_amount := NEW.total_amount - platform_fee_amount;
      ELSE
        -- Commitment only - escrow the commitment fee
        escrow_amount := NEW.commitment_fee;
        net_amount := NEW.commitment_fee - (platform_fee_amount * (NEW.commitment_fee / NEW.total_amount));
      END IF;
      
      -- Create escrow payment record
      INSERT INTO public.escrow_payments (
        booking_id,
        transaction_id,
        payer_id,
        payee_id,
        amount,
        platform_fee,
        net_amount,
        status,
        held_at
      ) VALUES (
        NEW.id,
        NEW.commitment_transaction_id::uuid,
        NEW.client_id,
        NEW.provider_id,
        escrow_amount,
        platform_fee_amount * (escrow_amount / NEW.total_amount),
        net_amount,
        'held',
        NOW()
      )
      ON CONFLICT (booking_id) DO NOTHING;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update escrow on balance payment
CREATE OR REPLACE FUNCTION public.update_escrow_on_balance_payment()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_escrow RECORD;
  platform_fee_amount DECIMAL(10, 2);
BEGIN
  -- Check if balance was just paid
  IF NEW.balance_paid = true AND OLD.balance_paid = false AND NEW.balance_transaction_id IS NOT NULL THEN
    
    -- Get existing escrow record
    SELECT * INTO existing_escrow
    FROM public.escrow_payments
    WHERE booking_id = NEW.id
    LIMIT 1;
    
    IF FOUND THEN
      -- Calculate platform fee for the full amount
      platform_fee_amount := NEW.total_amount * 0.10;
      
      -- Update existing escrow to include balance payment
      UPDATE public.escrow_payments
      SET 
        amount = NEW.total_amount,
        platform_fee = platform_fee_amount,
        net_amount = NEW.total_amount - platform_fee_amount,
        transaction_id = NEW.balance_transaction_id::uuid
      WHERE booking_id = NEW.id;
    ELSE
      -- No existing escrow, create one for the full amount
      platform_fee_amount := NEW.total_amount * 0.10;
      
      INSERT INTO public.escrow_payments (
        booking_id,
        transaction_id,
        payer_id,
        payee_id,
        amount,
        platform_fee,
        net_amount,
        status,
        held_at
      ) VALUES (
        NEW.id,
        NEW.balance_transaction_id::uuid,
        NEW.client_id,
        NEW.provider_id,
        NEW.total_amount,
        platform_fee_amount,
        NEW.total_amount - platform_fee_amount,
        'held',
        NOW()
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle escrow release on booking completion
CREATE OR REPLACE FUNCTION public.release_escrow_on_completion()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  escrow_record RECORD;
BEGIN
  -- Only proceed if booking is completed
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    -- Find the escrow payment for this booking
    SELECT * INTO escrow_record
    FROM public.escrow_payments
    WHERE booking_id = NEW.id AND status = 'held'
    LIMIT 1;
    
    IF FOUND THEN
      -- Update escrow status to released
      UPDATE public.escrow_payments
      SET status = 'released', released_at = NOW()
      WHERE id = escrow_record.id;
      
      -- Create a transaction record for the escrow release
      INSERT INTO public.transactions (
        user_id,
        booking_id,
        amount,
        type,
        status,
        description,
        completed_at
      ) VALUES (
        escrow_record.payee_id,
        NEW.id,
        escrow_record.net_amount,
        'escrow_release',
        'completed',
        'Escrow released for booking #' || NEW.id,
        NOW()
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle escrow refund on cancellation
CREATE OR REPLACE FUNCTION public.refund_escrow_on_cancellation()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  escrow_record RECORD;
BEGIN
  -- Only proceed if booking is cancelled and wasn't already completed
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' AND OLD.status != 'completed' THEN
    -- Find the escrow payment for this booking
    SELECT * INTO escrow_record
    FROM public.escrow_payments
    WHERE booking_id = NEW.id AND status = 'held'
    LIMIT 1;
    
    IF FOUND THEN
      -- Update escrow status to refunded
      UPDATE public.escrow_payments
      SET status = 'refunded', refunded_at = NOW()
      WHERE id = escrow_record.id;
      
      -- Create a refund transaction
      INSERT INTO public.transactions (
        user_id,
        booking_id,
        amount,
        type,
        status,
        description,
        completed_at
      ) VALUES (
        escrow_record.payer_id,
        NEW.id,
        escrow_record.amount,
        'refund',
        'completed',
        'Escrow refunded for cancelled booking #' || NEW.id,
        NOW()
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS on_transaction_updated ON public.transactions;
CREATE TRIGGER on_transaction_updated
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_transaction_updated();

DROP TRIGGER IF EXISTS on_booking_created_create_escrow ON public.bookings;
CREATE TRIGGER on_booking_created_create_escrow
  AFTER INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.create_escrow_on_booking();

DROP TRIGGER IF EXISTS on_booking_balance_paid_update_escrow ON public.bookings;
CREATE TRIGGER on_booking_balance_paid_update_escrow
  AFTER UPDATE ON public.bookings
  FOR EACH ROW
  WHEN (NEW.balance_paid = true AND OLD.balance_paid = false)
  EXECUTE FUNCTION public.update_escrow_on_balance_payment();

DROP TRIGGER IF EXISTS on_booking_completed_release_escrow ON public.bookings;
CREATE TRIGGER on_booking_completed_release_escrow
  AFTER UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.release_escrow_on_completion();

DROP TRIGGER IF EXISTS on_booking_cancelled_refund_escrow ON public.bookings;
CREATE TRIGGER on_booking_cancelled_refund_escrow
  AFTER UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.refund_escrow_on_cancellation();

-- ============================================
-- 6. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escrow_payments ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 7. CREATE RLS POLICIES
-- ============================================

-- Transactions policies
DROP POLICY IF EXISTS "Users can view own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can create own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Service role can manage transactions" ON public.transactions;

CREATE POLICY "Users can view own transactions"
ON public.transactions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can create own transactions"
ON public.transactions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role can manage transactions"
ON public.transactions
TO service_role
USING (true)
WITH CHECK (true);

-- Escrow policies
DROP POLICY IF EXISTS "Payers can view their escrow payments" ON public.escrow_payments;
DROP POLICY IF EXISTS "Payees can view their escrow payments" ON public.escrow_payments;
DROP POLICY IF EXISTS "Service role can manage escrow" ON public.escrow_payments;

CREATE POLICY "Payers can view their escrow payments"
ON public.escrow_payments FOR SELECT
TO authenticated
USING (auth.uid() = payer_id);

CREATE POLICY "Payees can view their escrow payments"
ON public.escrow_payments FOR SELECT
TO authenticated
USING (auth.uid() = payee_id);

CREATE POLICY "Service role can manage escrow"
ON public.escrow_payments
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 8. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, INSERT, UPDATE ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO service_role;

GRANT SELECT ON public.escrow_payments TO authenticated;
GRANT ALL ON public.escrow_payments TO service_role;

-- ============================================
-- TRANSACTIONS & PAYMENTS SYSTEM COMPLETE
-- ============================================
