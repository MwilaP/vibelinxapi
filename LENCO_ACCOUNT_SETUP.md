# Lenco Account Setup Guide

## Issue: Invalid accountId Error

When initiating transfers, Lencopay requires a valid **accountId** (36-character UUID) to identify which Lenco account to debit funds from.

### Error Message
```
{
  "success": true,
  "message": "Invalid accountId",
  "status": false,
  "errorCode": "01",
  "data": null
}
```

## Solution: Configure Lenco Account ID

### Step 1: Get Your Lenco Account ID

#### Option A: From Lenco Dashboard
1. Log in to https://app.lenco.co
2. Navigate to **Settings** → **API & Webhooks**
3. Find your **Account ID** (36-character UUID)
4. Copy the Account ID

#### Option B: From Lenco API
You can retrieve your account ID using the Lenco API:

```bash
curl -X GET "https://api.lenco.co/access/v2/accounts" \
  -H "Authorization: Bearer YOUR_API_KEY"
```

Response:
```json
{
  "status": true,
  "data": [
    {
      "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "name": "Main Account",
      "currency": "ZMW",
      "balance": "10000.00"
    }
  ]
}
```

Copy the `id` field from your desired account.

### Step 2: Add to Environment Variables

Add the account ID to your `.env` file:

```env
# Lencopay Configuration
LENCOPAY_API_KEY=your_api_key_here
LENCOPAY_BASE_URL=https://api.lenco.co/access/v2
LENCOPAY_ACCOUNT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
LENCOPAY_CALLBACK_URL=https://your-domain.com/api/payments/callback
```

### Step 3: Restart Your Server

```bash
# Stop the server
# Update .env file
# Restart the server
npm run dev
```

### Step 4: Verify Configuration

Check the logs when making a withdrawal. You should see:

```
✅ Lenco transfer payload prepared {
  "endpoint": "/transfers/mobile-money",
  "hasAccountId": true,  // Should be true now
  "operator": "airtel",
  "country": "zm"
}
```

## Account ID Format

- **Length:** 36 characters
- **Format:** UUID v4 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
- **Example:** `a1b2c3d4-e5f6-7890-abcd-ef1234567890`

## Multiple Accounts

If you have multiple Lenco accounts (e.g., different currencies or business units):

### Option 1: Use Default Account
Set `LENCOPAY_ACCOUNT_ID` to your main account ID. All transfers will debit from this account.

### Option 2: Dynamic Account Selection
Pass `account_id` parameter when initiating transfers:

```typescript
await lencopayService.initiatePayout({
  amount: 100,
  payment_method: 'mtn',
  payment_phone: '0961234567',
  reference: 'VBL-WD-123',
  account_id: 'specific-account-uuid-here', // Override default
});
```

## Troubleshooting

### Error: "Lenco account ID not configured"
**Cause:** `LENCOPAY_ACCOUNT_ID` environment variable is not set.

**Solution:**
1. Add `LENCOPAY_ACCOUNT_ID` to `.env` file
2. Restart server
3. Verify with `console.log(config.lencopay.accountId)`

### Error: "Invalid accountId"
**Cause:** Account ID is incorrect or doesn't exist.

**Solutions:**
1. Verify the account ID is exactly 36 characters
2. Check for extra spaces or quotes
3. Confirm account exists in Lenco dashboard
4. Ensure account is active and has sufficient balance
5. Verify API key has access to this account

### Error: "Insufficient balance"
**Cause:** Lenco account doesn't have enough funds.

**Solutions:**
1. Check account balance in Lenco dashboard
2. Top up the account
3. Ensure balance covers transfer amount + Lenco fees

## Security Best Practices

### 1. Never Hardcode Account ID
❌ **Wrong:**
```typescript
const accountId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
```

✅ **Correct:**
```typescript
const accountId = config.lencopay.accountId;
```

### 2. Use Environment Variables
Store sensitive data in `.env` file:
```env
LENCOPAY_ACCOUNT_ID=your-account-id
```

### 3. Different Accounts for Environments
Use different accounts for development and production:

```env
# .env.development
LENCOPAY_ACCOUNT_ID=dev-account-uuid

# .env.production
LENCOPAY_ACCOUNT_ID=prod-account-uuid
```

## Testing

### Test Transfer with Account ID

```bash
# Make a test withdrawal
curl -X POST "http://localhost:3001/api/withdrawal/request" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "user_id": "user-uuid",
    "amount": 50,
    "payment_method": "mtn",
    "payment_phone": "0961234567"
  }'
```

### Expected Log Output

```
✅ Initiating Lenco transfer
✅ Lenco transfer payload prepared { hasAccountId: true }
✅ Lenco transfer response received { status: true }
```

## API Reference

### Get Accounts Endpoint
```
GET /accounts
Authorization: Bearer {api_key}
```

**Response:**
```json
{
  "status": true,
  "message": "Accounts retrieved successfully",
  "data": [
    {
      "id": "account-uuid",
      "name": "Main Account",
      "currency": "ZMW",
      "balance": "10000.00",
      "availableBalance": "9500.00",
      "status": "active"
    }
  ]
}
```

## Summary

1. ✅ Get your Lenco Account ID from dashboard or API
2. ✅ Add `LENCOPAY_ACCOUNT_ID` to `.env` file
3. ✅ Restart server
4. ✅ Test withdrawal
5. ✅ Verify logs show `hasAccountId: true`

---

**Status:** Configuration Required
**Priority:** HIGH - Withdrawals won't work without this
**Documentation:** https://lenco-api.readme.io/v2.0/reference
