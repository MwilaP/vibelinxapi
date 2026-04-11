# Lencopay Transfers Endpoint - Fix Applied

## ✅ Issue Resolved

### Problem
Withdrawal system was failing with **404 Not Found** error when attempting to initiate payouts.

### Root Cause
Using incorrect endpoint `/disbursements/mobile-money` instead of Lencopay's actual endpoint.

### Solution
Updated to use correct Lencopay endpoint: **`/transfers/mobile-money`**

## Changes Made

### 1. Lencopay Service (`src/services/lencopay.service.ts`)

#### Initiate Transfer/Payout
```typescript
// BEFORE (WRONG)
const response = await this.client.post('/disbursements/mobile-money', payload);

// AFTER (CORRECT)
const response = await this.client.post('/transfers/mobile-money', payload);
```

#### Verify Transfer Status
```typescript
// BEFORE (WRONG)
const response = await this.client.get(`/payouts/${reference}`);

// AFTER (CORRECT)
const response = await this.client.get(`/transfers/${reference}`);
```

### 2. Webhook Handler (`src/controllers/payment.controller.ts`)

Updated to handle both `transfer.*` and `payout.*` events:

```typescript
// Support both event types
if (webhookEvent.event === 'transfer.successful' || 
    webhookEvent.event === 'transfer.completed' ||
    webhookEvent.event === 'payout.successful' || 
    webhookEvent.event === 'payout.completed') {
  // Process successful transfer
}

if (webhookEvent.event === 'transfer.failed' || 
    webhookEvent.event === 'payout.failed') {
  // Process failed transfer
}
```

### 3. Documentation Updates

#### Updated `LENCO_V2_INTEGRATION.md`
Added transfer endpoints to API documentation:
- `POST /transfers/mobile-money` - Initiate mobile money transfer/disbursement
- `GET /transfers/{reference}` - Get transfer status

#### Updated `LENCOPAY_PAYOUT_ISSUE.md`
Marked issue as resolved with correct endpoint information.

## Lencopay Transfers API

### Endpoint
```
POST https://api.lenco.co/access/v2/transfers/mobile-money
```

### Request Payload
```json
{
  "amount": "100.00",
  "reference": "VBL-WD-1234567890-ABC123",
  "phone": "260961234567",
  "operator": "mtn",
  "country": "zm",
  "narration": "VibeLinx provider withdrawal"
}
```

### Expected Response
```json
{
  "status": true,
  "message": "Transfer initiated",
  "data": {
    "id": "transfer-id",
    "reference": "VBL-WD-1234567890-ABC123",
    "lencoReference": "LENCO-REF-123",
    "status": "pending",
    "amount": "100.00",
    "mobileMoneyDetails": {
      "phone": "260961234567",
      "operator": "MTN"
    }
  }
}
```

### Webhook Events
Expected webhook events for transfers:
- `transfer.successful` - Transfer completed successfully
- `transfer.completed` - Alternative success event
- `transfer.failed` - Transfer failed

## Testing Checklist

### Before Production
- [ ] Test transfer initiation in sandbox
- [ ] Verify transfer status checking works
- [ ] Test webhook events (successful)
- [ ] Test webhook events (failed)
- [ ] Verify wallet balance updates correctly
- [ ] Test refund on failure
- [ ] Verify SMS notifications
- [ ] Test all three operators (MTN, Airtel, Zamtel)

### Test Scenarios
1. **Successful Withdrawal**
   - Request K100 withdrawal
   - Verify fee calculation (K10.25)
   - Confirm transfer initiated
   - Verify wallet deducted K100
   - Wait for webhook
   - Verify status updated to completed
   - Verify provider receives K89.75

2. **Failed Withdrawal**
   - Request withdrawal with invalid phone
   - Verify transfer fails
   - Verify wallet refunded K100
   - Verify status updated to failed
   - Verify provider notified

3. **Insufficient Balance**
   - Request withdrawal > available balance
   - Verify rejection before API call
   - Verify no wallet deduction

## Deployment Steps

### 1. Update Environment
Ensure Lencopay credentials are configured:
```env
LENCO_API_KEY=your_api_key
LENCO_BASE_URL=https://api.lenco.co/access/v2
```

### 2. Configure Webhook
Update Lencopay webhook URL to handle transfer events:
```
https://your-domain.com/api/payments/callback
```

### 3. Deploy Backend
```bash
cd d:\personal\vibelinxapi
git add .
git commit -m "Fix: Update to Lencopay transfers endpoint"
git push
# Deploy to production
```

### 4. Test in Production
1. Make small test withdrawal (K50)
2. Monitor logs for transfer initiation
3. Verify webhook received
4. Confirm wallet updated
5. Verify provider receives funds

## Monitoring

### Key Metrics to Watch
- Transfer success rate (target: >95%)
- Average processing time (target: <5 minutes)
- Webhook delivery rate (target: 100%)
- Refund accuracy (target: 100%)

### Log Messages to Monitor
```
✅ "Initiating Lenco payout" - Transfer request sent
✅ "Lenco payout response" - Transfer accepted
✅ "Processing successful transfer/payout" - Webhook received
✅ "Withdrawal completed successfully" - Process complete
❌ "Lencopay payout failed" - Transfer rejected
❌ "Transfer/payout failed webhook received" - Transfer failed
```

## Rollback Plan

If issues occur in production:

1. **Immediate**: Set minimum withdrawal to K10000 (effectively disable)
2. **Update settings**: Via admin panel or database
3. **Notify providers**: Via SMS/email about temporary maintenance
4. **Investigate**: Check logs for error patterns
5. **Fix**: Apply hotfix if needed
6. **Re-enable**: Lower minimum withdrawal back to K50

## Support Information

### Lencopay Support
- Email: [email protected]
- Documentation: https://lenco-api.readme.io/v2.0/reference
- Dashboard: https://app.lenco.co

### Questions to Ask if Issues Persist
1. Are there any account-level permissions needed for transfers?
2. What are the possible transfer statuses?
3. What is the expected webhook event format?
4. Are there rate limits on transfer API?
5. What are the transfer fees/pricing?

---

**Status:** ✅ FIXED
**Date:** April 11, 2026
**Ready for Testing:** YES
**Ready for Production:** After sandbox testing
