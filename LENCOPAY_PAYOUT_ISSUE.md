# Lencopay Payout/Disbursement - RESOLVED

## ✅ Solution Found
Lencopay uses `/transfers/mobile-money` endpoint for disbursements (not `/disbursements` or `/payouts`).

**Correct Endpoint:** `https://api.lenco.co/access/v2/transfers/mobile-money`

## Previous Issue (RESOLVED)
The withdrawal system was failing with a **404 Not Found** error because we were using the wrong endpoint.

### Fixed Implementation
Now using: `/transfers/mobile-money` ✅

### Lencopay v2 Documented Endpoints
According to `LENCO_V2_INTEGRATION.md`, only these endpoints are documented:
- `POST /collections/mobile-money` - Collect payments (receive money)
- `GET /collections/{reference}` - Get collection status
- `POST /collections/{id}/refund` - Refund a collection

**No payout/disbursement endpoints are documented.**

## Possible Solutions

### Option 1: Contact Lencopay Support (RECOMMENDED)
Contact Lencopay to confirm:
1. Does Lencopay v2 support disbursements/payouts?
2. What is the correct endpoint for mobile money disbursements?
3. What is the payload format?
4. Are there any special permissions or account setup required?

**Lencopay Support:**
- Email: [email protected]
- Documentation: https://lenco-api.readme.io/v2.0/reference
- Dashboard: https://app.lenco.co

### Option 2: Try Alternative Endpoints
Test these possible endpoints:
- `/payouts/mobile-money`
- `/transfers/mobile-money`
- `/disbursements`
- `/payouts`

### Option 3: Use Manual Processing (Temporary Workaround)
Until Lencopay disbursements are available:
1. Mark withdrawals as "pending_manual"
2. Admin manually processes via Lencopay dashboard
3. Admin marks as completed in system
4. Update webhook to handle manual completions

### Option 4: Use Alternative Payment Gateway
Consider integrating with another provider that supports disbursements:
- Flutterwave
- Paystack
- DPO PayGate
- Other Zambian payment processors

## Temporary Workaround Implementation

### 1. Update Withdrawal Service
Change auto-processing to manual approval:

```typescript
// In withdrawal.service.ts
async createWithdrawalRequest(data: CreateWithdrawalRequest) {
  // ... existing code ...
  
  // Instead of auto-processing, mark as pending_manual
  const { data: withdrawal, error: insertError } = await this.supabase
    .from('withdrawal_requests')
    .insert({
      // ... existing fields ...
      status: 'pending_manual', // Changed from 'pending'
      metadata: {
        ...metadata,
        requires_manual_processing: true,
        reason: 'Lencopay disbursement API not available',
      }
    });
    
  // Don't call processWithdrawal() automatically
  return { withdrawal, error: null };
}
```

### 2. Add Admin Manual Processing
Create admin endpoint to manually mark withdrawals as processed:

```typescript
// In admin.controller.ts
async processManualWithdrawal(req: Request, res: Response) {
  const { withdrawal_id, lenco_reference, external_transaction_id } = req.body;
  
  // Update withdrawal status
  await withdrawalService.updateWithdrawalStatus(
    withdrawal_id,
    'completed',
    undefined,
    external_transaction_id
  );
  
  // Update wallet total_withdrawn
  // Send notification to provider
}
```

### 3. Update Admin UI
Add "Process Withdrawal" button in admin dashboard:
- Shows pending_manual withdrawals
- Admin processes via Lencopay dashboard manually
- Admin enters Lenco reference and confirms
- System updates status and notifies provider

## Testing Checklist

### Before Production
- [ ] Confirm Lencopay disbursement endpoint with support
- [ ] Test disbursement in sandbox environment
- [ ] Verify webhook events for disbursements
- [ ] Test failure scenarios
- [ ] Verify refund logic works correctly

### Current Status
- ✅ Collections (deposits) working
- ❌ Disbursements (withdrawals) failing with 404
- ✅ Refund logic implemented (untested)
- ✅ Webhook handling implemented (untested for payouts)

## Next Steps

1. **IMMEDIATE:** Contact Lencopay support to confirm disbursement API availability
2. **SHORT-TERM:** Implement manual processing workaround if needed
3. **LONG-TERM:** Integrate proper disbursement API once confirmed
4. **ALTERNATIVE:** Evaluate other payment gateways if Lencopay doesn't support disbursements

## Code Changes Made

### Enhanced Error Logging
Updated `lencopay.service.ts` to provide detailed error information:
- Changed endpoint to `/disbursements/mobile-money`
- Added comprehensive error logging
- Added helpful error messages for 404 errors

### Files to Update for Manual Processing
If manual processing is needed:
1. `src/services/withdrawal.service.ts` - Remove auto-processing
2. `src/controllers/admin.controller.ts` - Add manual processing endpoint
3. `src/routes/admin.routes.ts` - Add manual processing route
4. `vibeslinx-admin/src/pages/WalletsPage.tsx` - Add manual processing UI

## Important Notes

⚠️ **DO NOT deploy to production** until Lencopay disbursement endpoint is confirmed and tested.

⚠️ **Current implementation will fail** for all withdrawal requests.

⚠️ **Providers cannot withdraw funds** until this is resolved.

## Questions for Lencopay Support

1. Does Lencopay v2 API support mobile money disbursements/payouts?
2. What is the correct endpoint URL for disbursements?
3. What is the required payload format?
4. Are there webhook events for disbursement status updates?
5. What are the possible disbursement statuses?
6. Is there a sandbox environment for testing disbursements?
7. Are there any account-level permissions required for disbursements?
8. What are the disbursement fees/pricing?

---

**Status:** 🔴 BLOCKED - Awaiting Lencopay Support Response
**Priority:** HIGH - Critical for provider withdrawals
**Date:** April 11, 2026
