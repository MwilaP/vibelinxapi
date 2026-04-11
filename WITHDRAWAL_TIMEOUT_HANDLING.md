# Withdrawal Timeout Handling

## Problem Identified

When a withdrawal request times out (30-60 seconds), the system was:
1. ❌ Marking withdrawal as "failed"
2. ❌ Refunding money to wallet
3. ✅ Transfer actually succeeds on Lencopay side
4. ✅ Webhook arrives later confirming success
5. **Result:** User receives money + refund = **DOUBLE PAYMENT**

## Example Timeline

```
15:58:04 - Transfer initiated to Lencopay
15:58:35 - HTTP timeout (30 seconds)
15:58:35 - System marks as "failed" and refunds K20
16:01:57 - Webhook arrives: transfer.successful
16:02:02 - System updates to "completed"
Result: User got K20 payout + K20 refund = K40 total ❌
```

## Solution Implemented

### 1. Increased Timeout
**Changed:** 30 seconds → **60 seconds**

Lencopay transfers can take 30-60 seconds to process, especially for mobile money transactions.

```typescript
// lencopay.service.ts
timeout: 60000, // 60 seconds - transfers can take time
```

### 2. Smart Timeout Handling

**Don't refund on timeout** - wait for webhook confirmation instead.

```typescript
if (!payoutResult.success) {
  const isTimeout = payoutResult.message?.includes('timeout') || 
                    payoutResult.error?.code === 'ECONNABORTED';
  
  if (isTimeout) {
    // Keep status as 'processing' - webhook will update it
    // NO REFUND - wait for webhook
    return { success: true, timeout: true };
  } else {
    // Actual failure - refund wallet
    await refundWallet();
    return { success: false };
  }
}
```

### 3. Status Flow

#### Timeout Scenario (New Behavior)
```
pending → processing (timeout) → [wait for webhook] → completed/failed
```

#### Actual Failure Scenario
```
pending → processing → failed (immediate refund)
```

## Timeout vs Failure Detection

### Timeout Indicators
- Error message contains "timeout"
- Error code is `ECONNABORTED`
- HTTP request exceeds 60 seconds

### Actual Failure Indicators
- 400: Validation error (invalid phone, operator)
- 401: Authentication failed
- 403: Insufficient balance
- 404: Endpoint not found
- Any Lencopay error message

## Withdrawal Statuses

### 1. `pending`
- Withdrawal request created
- Wallet not yet deducted

### 2. `processing`
- Wallet deducted
- Transfer initiated to Lencopay
- Awaiting completion

### 3. `processing` (with timeout metadata)
- Transfer initiated but response timed out
- **No refund issued**
- Awaiting webhook confirmation
- Metadata includes:
  ```json
  {
    "timeout": true,
    "timeout_at": "2026-04-11T15:58:35Z",
    "message": "Transfer initiated but response timed out. Awaiting webhook confirmation."
  }
  ```

### 4. `completed`
- Transfer successful
- User received money
- Webhook confirmed

### 5. `failed`
- Transfer actually failed
- Wallet refunded
- User notified

## Webhook Handling

Webhooks are the **source of truth** for transfer status.

### Transfer Successful Webhook
```json
{
  "event": "transfer.successful",
  "data": {
    "reference": "VBL-WD-...",
    "status": "successful",
    "amount": "9.75"
  }
}
```

**Actions:**
1. Find withdrawal by reference
2. Update status to `completed`
3. Update `total_withdrawn` in wallet
4. Send SMS notification
5. **No refund** (money already sent)

### Transfer Failed Webhook
```json
{
  "event": "transfer.failed",
  "data": {
    "reference": "VBL-WD-...",
    "status": "failed",
    "reasonForFailure": "Invalid phone number"
  }
}
```

**Actions:**
1. Find withdrawal by reference
2. Check if already refunded
3. If not refunded: Credit wallet
4. Update status to `failed`
5. Send SMS notification

## Preventing Double Payments

### Check Before Refund
```typescript
// In webhook handler
if (status === 'failed') {
  // Check if wallet was already refunded
  const withdrawal = await getWithdrawal(reference);
  
  if (withdrawal.status === 'failed') {
    // Already refunded, skip
    return;
  }
  
  // Refund wallet
  await creditWallet(withdrawal.amount);
}
```

### Idempotency
- Use withdrawal reference as idempotency key
- Check withdrawal status before any wallet operation
- Log all wallet transactions for audit

## Monitoring

### Key Metrics
- **Timeout rate:** % of withdrawals that timeout
- **Timeout → Success rate:** % of timeouts that eventually succeed
- **Timeout → Failure rate:** % of timeouts that eventually fail
- **Double payment incidents:** Should be 0

### Alerts
Set up alerts for:
- Timeout rate > 10%
- Any double payment detected
- Withdrawal stuck in 'processing' > 10 minutes
- Webhook not received within 5 minutes

### Log Messages

#### Timeout Detected
```
⚠️ "Lencopay transfer timeout - waiting for webhook confirmation"
```

#### Webhook Resolves Timeout
```
✅ "Withdrawal completed successfully" (after timeout)
❌ "Withdrawal failed, refunded to wallet" (after timeout)
```

## Testing

### Test Timeout Scenario

1. **Simulate timeout:**
   ```typescript
   // Temporarily reduce timeout for testing
   timeout: 5000, // 5 seconds
   ```

2. **Make withdrawal request**

3. **Verify behavior:**
   - Status should be 'processing'
   - Wallet should be deducted
   - No refund issued
   - Metadata shows timeout

4. **Wait for webhook:**
   - Should update to 'completed' or 'failed'
   - If failed, refund should occur

### Test Actual Failure

1. **Use invalid phone number**
2. **Verify immediate failure:**
   - Status: 'failed'
   - Wallet refunded immediately
   - No waiting for webhook

## Rollback Plan

If issues persist:

1. **Increase timeout further:**
   ```typescript
   timeout: 120000, // 2 minutes
   ```

2. **Manual reconciliation:**
   - Query all 'processing' withdrawals > 10 minutes old
   - Check Lenco dashboard for actual status
   - Manually update status and refund if needed

3. **Disable auto-processing:**
   - Mark all withdrawals as 'pending_manual'
   - Admin processes manually
   - Ensures no double payments

## Best Practices

### 1. Always Wait for Webhook
Never trust HTTP response alone for financial transactions.

### 2. Idempotent Operations
All wallet operations should be idempotent using reference IDs.

### 3. Audit Trail
Log every wallet transaction with:
- Withdrawal reference
- Amount
- Timestamp
- Reason

### 4. Reconciliation
Daily reconciliation:
- Compare Lenco dashboard with database
- Check for stuck withdrawals
- Verify no double payments

### 5. User Communication
For timeouts, show user:
> "Your withdrawal is being processed. You'll receive a notification when complete. This may take a few minutes."

## Summary

✅ **Increased timeout:** 30s → 60s
✅ **Smart timeout handling:** Don't refund on timeout
✅ **Webhook-based confirmation:** Wait for actual status
✅ **Prevents double payments:** Only refund on actual failure
✅ **Better user experience:** Clear status messages

---

**Status:** ✅ IMPLEMENTED
**Date:** April 11, 2026
**Priority:** CRITICAL - Prevents double payments
