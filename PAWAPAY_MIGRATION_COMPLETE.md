# PawaPay Migration - Implementation Complete

## Migration Summary

The VibeLinx payment system has been successfully migrated from Lenco Pay to PawaPay.

## Changes Implemented

### 1. New PawaPay Service
- **Created**: `src/services/pawapay.service.ts`
- Implements deposit (collections) via `/v2/deposits`
- Implements payout (withdrawals) via `/v2/payouts`
- Provider mapping: mtn → MTN_MOMO_ZMB, airtel → AIRTEL_OAPI_ZMB, zamtel → ZAMTEL_ZMB
- Status mapping: ACCEPTED/SUBMITTED → pending, COMPLETED → completed, FAILED/REJECTED → failed

### 2. Configuration Updates
- **Updated**: `src/config/index.ts`
  - Removed `lencopay` configuration
  - Added `pawapay` configuration with apiToken, baseUrl, webhookUrl
- **Updated**: `.env.example`
  - Removed LENCOPAY_* variables
  - Added PAWAPAY_API_TOKEN, PAWAPAY_BASE_URL, PAWAPAY_WEBHOOK_URL

### 3. Controller Updates
- **Updated**: `src/controllers/payment.controller.ts`
  - Replaced all `lencopayService` calls with `pawapayService`
  - Updated `initiatePayment()` to use `initiateDeposit()`
  - Updated `verifyPayment()` to use `checkDepositStatus()`
  - Updated webhook handling for PawaPay events

- **Updated**: `src/controllers/wallet.controller.ts`
  - Replaced `lencopayService.initiatePayment()` with `pawapayService.initiateDeposit()`

### 4. Service Updates
- **Updated**: `src/services/withdrawal.service.ts`
  - Replaced `lencopayService.initiatePayout()` with `pawapayService.initiatePayout()`
  - Updated logging references from Lenco to PawaPay

### 5. Type Definitions
- **Updated**: `src/types/index.ts`
  - Updated `PaymentVerificationResponse` interface
  - Replaced Lenco-specific fields with PawaPay fields (depositId, payoutId, pawapayStatus)

### 6. Database Migration
- **Created**: `database/migrations/002_migrate_to_pawapay.sql`
  - Adds `pawapay_deposit_id` column to `transactions` table
  - Adds `pawapay_payout_id` column to `withdrawal_requests` table
  - Archives Lenco columns by renaming with `_archived` suffix
  - Preserves all historical data
  - Includes rollback script

## Files to Remove Manually

**IMPORTANT**: The following file should be deleted manually:
- `src/services/lencopay.service.ts` (551 lines) - No longer needed

To remove it, run:
```bash
rm src/services/lencopay.service.ts
```

Or delete it through your file explorer/IDE.

## Required Environment Variables

Update your `.env` file with the following PawaPay credentials:

```env
PAWAPAY_API_TOKEN=your_pawapay_bearer_token
PAWAPAY_BASE_URL=https://api.sandbox.pawapay.io  # Use production URL when ready
PAWAPAY_WEBHOOK_URL=https://your-domain.com/api/payments/webhook
```

## Database Migration Steps

1. **Backup your database** before running the migration
2. Run the migration script:
   ```bash
   # Connect to your database and run:
   psql -U your_user -d your_database -f database/migrations/002_migrate_to_pawapay.sql
   ```
3. Verify the migration:
   ```sql
   -- Check that archived columns exist
   SELECT column_name FROM information_schema.columns 
   WHERE table_name = 'transactions' AND column_name LIKE '%archived%';
   
   -- Check that new PawaPay columns exist
   SELECT column_name FROM information_schema.columns 
   WHERE table_name = 'transactions' AND column_name LIKE '%pawapay%';
   ```

## Testing Checklist

Before deploying to production:

- [ ] Install uuid package: `npm install uuid` and `npm install --save-dev @types/uuid`
- [ ] Update `.env` with PawaPay credentials
- [ ] Run database migration script
- [ ] Delete `src/services/lencopay.service.ts`
- [ ] Test deposit flow (booking payments)
- [ ] Test deposit flow (wallet top-ups)
- [ ] Test payout flow (provider withdrawals)
- [ ] Test webhook handling
- [ ] Verify all payment methods (MTN, Airtel, Zamtel)
- [ ] Monitor first transactions in production

## API Endpoint Changes

### Deposits (Collections)
- **Old**: Lenco Pay `/collections/mobile-money`
- **New**: PawaPay `/v2/deposits`

### Payouts (Withdrawals)
- **Old**: Lenco Pay `/transfers/mobile-money`
- **New**: PawaPay `/v2/payouts`

### Status Checking
- **Old**: Lenco Pay `/collections/{reference}` and `/transfers/status/{reference}`
- **New**: PawaPay `/v2/deposits/{depositId}` and `/v2/payouts/{payoutId}`

## Webhook Events

PawaPay webhook events to handle:
- `deposit.completed` - Deposit successful
- `deposit.failed` - Deposit failed
- `payout.completed` - Payout successful
- `payout.failed` - Payout failed

## Rollback Plan

If issues arise, you can rollback using the script in the migration file:

```sql
ALTER TABLE transactions RENAME COLUMN lenco_reference_archived TO lenco_reference;
ALTER TABLE transactions DROP COLUMN IF EXISTS pawapay_deposit_id;
DROP INDEX IF EXISTS idx_transactions_pawapay_deposit_id;

ALTER TABLE withdrawal_requests RENAME COLUMN lenco_reference_archived TO lenco_reference;
ALTER TABLE withdrawal_requests RENAME COLUMN lenco_payout_id_archived TO lenco_payout_id;
ALTER TABLE withdrawal_requests DROP COLUMN IF EXISTS pawapay_payout_id;
DROP INDEX IF EXISTS idx_withdrawal_requests_pawapay_payout_id;
```

Then revert the code changes via git.

## Support & Documentation

- PawaPay API Docs: https://docs.pawapay.io/v2/api-reference
- Deposits: https://docs.pawapay.io/v2/api-reference/deposits/initiate-deposit
- Payouts: https://docs.pawapay.io/v2/api-reference/payouts/initiate-payout

## Migration Status

✅ **COMPLETE** - All code changes implemented
⚠️ **ACTION REQUIRED**:
1. Install uuid package
2. Delete `src/services/lencopay.service.ts` manually
3. Update environment variables
4. Run database migration
5. Test thoroughly before production deployment

---

**Migration Date**: January 2025  
**Migrated By**: VibeLinx Development Team  
**Status**: Ready for Testing
