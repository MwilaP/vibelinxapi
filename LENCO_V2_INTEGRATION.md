# Lenco Pay v2 Mobile Money Integration Guide

This document explains how the VibeLinx Payment API integrates with Lenco Pay v2 for mobile money collections in Zambia.

## Overview

Lenco Pay v2 provides a robust API for collecting payments via mobile money (MTN, Airtel, Zamtel) in Zambia. The integration uses:

- **API Base URL**: `https://api.lenco.co/access/v2`
- **Authentication**: Bearer token (API Key)
- **Webhook Signature**: HMAC SHA512 using webhook hash key

## Key Features

### 1. Mobile Money Collections

The API initiates mobile money collections using the `/collections/mobile-money` endpoint.

**Request Format:**
```json
{
  "amount": "100.00",
  "currency": "ZMW",
  "phone": "260971234567",
  "country": "ZM",
  "reference": "VBL-1234567890-ABC-commitment-booking-uuid",
  "narration": "VibeLinx commitment payment for booking xyz"
}
```

**Response Statuses:**
- `pay-offline`: Customer needs to authorize on their phone (USSD push)
- `otp-required`: OTP sent to customer's phone
- `pending`: Payment is being processed
- `successful`: Payment completed
- `failed`: Payment failed

### 2. Authentication

All API requests use Bearer token authentication:

```typescript
headers: {
  'Authorization': `Bearer ${apiKey}`,
  'Content-Type': 'application/json'
}
```

### 3. Webhook Signature Validation

Lenco sends webhooks with `X-Lenco-Signature` header for security.

**Validation Process:**
1. Generate webhook hash key: `SHA256(API_KEY)`
2. Generate signature: `HMAC-SHA512(webhook_body, webhook_hash_key)`
3. Compare with `X-Lenco-Signature` header

**Implementation:**
```typescript
const webhookHashKey = crypto
  .createHash('sha256')
  .update(apiKey)
  .digest('hex');

const signature = crypto
  .createHmac('sha512', webhookHashKey)
  .update(JSON.stringify(webhookBody))
  .digest('hex');

const isValid = signature === req.headers['x-lenco-signature'];
```

## Payment Flow

### Step 1: Initiate Collection

```typescript
POST /collections/mobile-money
Authorization: Bearer {API_KEY}

{
  "amount": "50.00",
  "currency": "ZMW",
  "phone": "260971234567",
  "country": "ZM",
  "reference": "unique-reference",
  "narration": "Payment description"
}
```

**Response:**
```json
{
  "status": true,
  "message": "Collection initiated",
  "data": {
    "id": "collection-id",
    "reference": "unique-reference",
    "lencoReference": "LENCO-REF-123",
    "status": "pay-offline",
    "amount": "50.00",
    "currency": "ZMW",
    "mobileMoneyDetails": {
      "phone": "260971234567",
      "operator": "MTN",
      "country": "ZM"
    }
  }
}
```

### Step 2: Customer Authorization

- **pay-offline**: Customer receives USSD push notification on their phone
- **otp-required**: Customer receives OTP via SMS
- Customer completes authorization on their mobile device

### Step 3: Webhook Notification

Lenco sends webhook to your callback URL when payment status changes.

**Webhook Events:**
- `collection.successful`: Payment completed successfully
- `collection.failed`: Payment failed

**Webhook Payload:**
```json
{
  "event": "collection.successful",
  "data": {
    "id": "collection-id",
    "reference": "unique-reference",
    "lencoReference": "LENCO-REF-123",
    "amount": "50.00",
    "fee": "1.50",
    "currency": "ZMW",
    "status": "successful",
    "completedAt": "2024-03-02T10:30:00Z",
    "mobileMoneyDetails": {
      "phone": "260971234567",
      "operator": "MTN",
      "accountName": "John Doe",
      "operatorTransactionId": "MTN-TXN-123"
    }
  }
}
```

### Step 4: Verify Payment (Optional)

Query payment status manually if needed:

```typescript
GET /collections/{reference}
Authorization: Bearer {API_KEY}
```

**Response:**
```json
{
  "status": true,
  "data": {
    "id": "collection-id",
    "reference": "unique-reference",
    "status": "successful",
    "amount": "50.00",
    "completedAt": "2024-03-02T10:30:00Z"
  }
}
```

## Implementation Details

### Reference Generation

References include payment type and booking ID for easy tracking:

```typescript
const reference = `VBL-${timestamp}-${randomId}-${paymentType}-${bookingId}`;
// Example: VBL-1709376000000-ABC123-commitment-uuid-123
```

### Webhook Handler

```typescript
app.post('/api/payments/callback', async (req, res) => {
  const webhookEvent = req.body;
  const signature = req.headers['x-lenco-signature'];
  
  // Validate signature
  if (!validateSignature(webhookEvent, signature)) {
    return res.status(401).json({ success: false });
  }
  
  // Process event
  if (webhookEvent.event === 'collection.successful') {
    const { reference, amount } = webhookEvent.data;
    await processSuccessfulPayment(reference, amount);
  }
  
  // Always respond with 200
  res.status(200).json({ success: true });
});
```

### Error Handling

```typescript
try {
  const response = await lencoClient.post('/collections/mobile-money', payload);
  
  if (response.data.status) {
    // Success - handle based on collection status
    const status = response.data.data.status;
    
    if (status === 'pay-offline') {
      // Notify user to check their phone
    } else if (status === 'otp-required') {
      // Notify user to enter OTP
    }
  } else {
    // API returned error
    console.error('Collection failed:', response.data.message);
  }
} catch (error) {
  // Network or server error
  console.error('API error:', error.response?.data || error.message);
}
```

## Mobile Money Operators

Lenco supports the following operators in Zambia:

- **MTN Mobile Money**
- **Airtel Money**
- **Zamtel Kwacha**

The operator is automatically detected from the phone number.

## Phone Number Format

Phone numbers must be in international format:

- **Correct**: `260971234567` (with country code)
- **Incorrect**: `0971234567` (without country code)

The notification service automatically formats numbers:
```typescript
let cleaned = phone.replace(/\D/g, '');
if (cleaned.startsWith('0')) {
  cleaned = '260' + cleaned.substring(1);
}
return '+' + cleaned;
```

## Testing

### Sandbox Environment

Use sandbox URL for testing:
```
https://sandbox.lenco.co/access/v2
```

### Test Accounts

Refer to Lenco's documentation for test phone numbers and scenarios:
- Successful payment scenarios
- Failed payment scenarios
- OTP required scenarios

### Testing Webhooks

1. Use ngrok or similar tool to expose local server:
   ```bash
   ngrok http 3001
   ```

2. Configure webhook URL in Lenco dashboard:
   ```
   https://your-ngrok-url.ngrok.io/api/payments/callback
   ```

3. Test webhook signature validation locally

## Best Practices

### 1. Idempotency

Always use unique references to prevent duplicate charges:
```typescript
const reference = `${prefix}-${timestamp}-${uuid}-${context}`;
```

### 2. Webhook Reliability

- Always respond with 200 OK to acknowledge receipt
- Process webhooks asynchronously if needed
- Implement retry logic for failed webhook processing
- Log all webhook events for debugging

### 3. Status Polling

For critical payments, implement polling as backup:
```typescript
// Poll every 30 seconds for up to 5 minutes
const maxAttempts = 10;
for (let i = 0; i < maxAttempts; i++) {
  const status = await verifyPayment(reference);
  if (status === 'successful' || status === 'failed') {
    break;
  }
  await sleep(30000);
}
```

### 4. User Communication

- Notify users about payment status changes via SMS
- Provide clear instructions for authorization
- Handle timeout scenarios gracefully

## Troubleshooting

### Issue: Webhook not received

**Solutions:**
1. Verify webhook URL is publicly accessible
2. Check webhook URL configuration in Lenco dashboard
3. Verify SSL certificate is valid
4. Check server logs for incoming requests
5. Test webhook endpoint with curl

### Issue: Invalid signature

**Solutions:**
1. Verify API key is correct
2. Check webhook hash key generation
3. Ensure request body is not modified before validation
4. Log both signatures for comparison

### Issue: Payment stuck in pending

**Solutions:**
1. Check customer's phone for authorization prompt
2. Verify customer has sufficient balance
3. Implement status polling
4. Contact Lenco support with reference

### Issue: Phone number format error

**Solutions:**
1. Ensure phone number includes country code (260)
2. Remove any spaces or special characters
3. Validate format before sending to API

## API Endpoints Summary

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/collections/mobile-money` | POST | Initiate mobile money collection |
| `/collections/{reference}` | GET | Get collection status by reference |
| `/collections/{id}/refund` | POST | Initiate refund for a collection |

## Security Considerations

1. **Never expose API keys** in client-side code
2. **Always validate webhook signatures** before processing
3. **Use HTTPS** for all API communication
4. **Store API keys** in environment variables
5. **Implement rate limiting** on webhook endpoints
6. **Log security events** for audit trail

## Support

For Lenco API issues:
- Email: [email protected]
- Documentation: https://lenco-api.readme.io/v2.0/reference
- Dashboard: https://app.lenco.co

## Migration from v1

Key differences from Lenco v1:

1. **Authentication**: Changed from `X-API-Key` to `Bearer` token
2. **Endpoints**: New `/collections/mobile-money` endpoint
3. **Webhook signature**: Now uses HMAC SHA512 instead of SHA256
4. **Response format**: Standardized with `status`, `message`, `data` structure
5. **Status values**: New statuses like `pay-offline` and `otp-required`

## Example Integration

See `src/services/lencopay.service.ts` for complete implementation:
- Mobile money collection initiation
- Webhook signature validation
- Payment verification
- Error handling
- Refund processing
