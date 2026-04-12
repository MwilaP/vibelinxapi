-- Migration: Migrate from Lenco Pay to PawaPay
-- Description: Add PawaPay fields to transactions and withdrawal_requests tables
-- Date: 2025-01-XX
-- Author: VibeLinx Team

-- ============================================================================
-- TRANSACTIONS TABLE UPDATES
-- ============================================================================

-- Add PawaPay deposit ID column
ALTER TABLE transactions 
ADD COLUMN IF NOT EXISTS pawapay_deposit_id UUID;

-- Add index on PawaPay deposit ID for faster lookups
CREATE INDEX IF NOT EXISTS idx_transactions_pawapay_deposit_id 
ON transactions(pawapay_deposit_id);

-- Add comment to new column
COMMENT ON COLUMN transactions.pawapay_deposit_id IS 
'PawaPay deposit ID (UUID) for tracking payment status';

-- ============================================================================
-- WITHDRAWAL_REQUESTS TABLE UPDATES
-- ============================================================================

-- Add PawaPay payout ID column
ALTER TABLE withdrawal_requests 
ADD COLUMN IF NOT EXISTS pawapay_payout_id UUID;

-- Add index on PawaPay payout ID for faster lookups
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_pawapay_payout_id 
ON withdrawal_requests(pawapay_payout_id);

-- Add comment to new column
COMMENT ON COLUMN withdrawal_requests.pawapay_payout_id IS 
'PawaPay payout ID (UUID) for tracking payout status';

-- ============================================================================
-- DATA MIGRATION NOTES
-- ============================================================================

-- Note: This migration only adds new PawaPay columns
-- Existing reference_number fields in transactions will continue to work
-- New transactions will store PawaPay deposit/payout IDs in the new columns

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify new columns were created
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_name = 'transactions' AND column_name = 'pawapay_deposit_id';

-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_name = 'withdrawal_requests' AND column_name = 'pawapay_payout_id';

-- ============================================================================
-- ROLLBACK SCRIPT (if needed)
-- ============================================================================

-- To rollback this migration:
-- ALTER TABLE transactions DROP COLUMN IF EXISTS pawapay_deposit_id;
-- DROP INDEX IF EXISTS idx_transactions_pawapay_deposit_id;
--
-- ALTER TABLE withdrawal_requests DROP COLUMN IF EXISTS pawapay_payout_id;
-- DROP INDEX IF EXISTS idx_withdrawal_requests_pawapay_payout_id;
