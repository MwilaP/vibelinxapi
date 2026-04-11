# Lencopay Transfers - Official Implementation

## Overview
Proper implementation of Lencopay transfers API based on official documentation at https://lenco-api.readme.io/v2.0/reference

## API Endpoints

### 1. Initiate Transfer
**Endpoint:** `POST /transfers/mobile-money`

**Purpose:** Initiate transfer to a mobile money account (Zambia & Malawi)

**Request Payload:**
```typescript
{
  accountId?: string,        // Optional: 36-char account UUID to debit
  amount: string,            // Transfer amount
  narration: string,         // Transfer description
  reference?: string,        // Optional: Unique client reference (-, ., _ and alphanumeric only)
  phone: string,             // Mobile money phone number
  operator: string,          // 'mtn' | 'airtel' | 'zamtel' (Zambia)
  country: string            // 'zm' (Zambia) | 'mw' (Malawi)
}
```

**Response Schema:**
```typescript
{
  status: boolean,
  message: string,
  data: {
    id: string,                    // Transfer ID
    amount: string,
    fee: string,                   // Lencopay fee
    currency: string,
    narration: string,
    initiatedAt: string,           // ISO date-time
    completedAt: string | null,    // ISO date-time or null if pending
    accountId: string,
    creditAccount: {
      type: 'mobile-money',
      accountName: string,
      phone: string,
      operator: string,
      country: string
    },
    status: 'pending' | 'successful' | 'failed',
    reasonForFailure: string | null,
    reference: string | null,
    lencoReference: string,        // Lenco's internal reference
    extraData: {
      nipSessionId: string | null
    },
    source: string
  }
}
```

### 2. Get Transfer by Reference
**Endpoint:** `GET /transfers/status/:reference`

**Purpose:** Retrieve transfer information using your reference

**Response Schema:** Same as initiate transfer response

**Status Codes:**
- `200` - Transfer found
- `404` - Transfer not found

## Implementation Details

### Transfer Initiation

```typescript
async initiatePayout(payoutData: {
  amount: number;
  payment_method: string;  // 'mtn' | 'airtel' | 'zamtel'
  payment_phone: string;
  reference: string;
  account_id?: string;     // Optional Lenco account ID
}): Promise<any>
```

**Key Features:**
- ✅ Proper phone number formatting (260XXXXXXXXX)
- ✅ Operator validation (mtn, airtel, zamtel)
- ✅ Country set to 'zm' for Zambia
- ✅ Unique reference generation
- ✅ Optional account ID for multi-account setups
- ✅ Comprehensive error handling
- ✅ Detailed logging

**Response Handling:**
```typescript
{
  success: boolean,
  message: string,
  data: {
    id: string,
    lencoReference: string,
    reference: string,
    status: 'pending' | 'successful' | 'failed',
    amount: string,
    fee: string,
    currency: string,
    initiatedAt: string,
    completedAt: string | null,
    creditAccount: {...},
    reasonForFailure: string | null
  }
}
```

### Transfer Verification

```typescript
async verifyPayout(reference: string): Promise<any>
```

**Endpoint:** `GET /transfers/status/{reference}`

**Response:**
```typescript
{
  success: boolean,
  status: 'pending' | 'successful' | 'failed' | 'not_found' | 'error',
  amount: number,
  fee: number,
  message: string,
  data: {
    id: string,
    lencoReference: string,
    reference: string,
    initiatedAt: string,
    completedAt: string | null,
    creditAccount: {...},
    reasonForFailure: string | null,
    currency: string
  }
}
```

## Transfer Statuses

### Lencopay Transfer Statuses
1. **`pending`** - Transfer initiated, awaiting processing
2. **`successful`** - Transfer completed successfully
3. **`failed`** - Transfer failed (see reasonForFailure)

### Internal Status Mapping
- `pending` → Keep withdrawal as 'processing'
- `successful` → Update withdrawal to 'completed'
- `failed` → Update withdrawal to 'failed' + refund wallet

## Webhook Events

Expected webhook events from Lencopay:

### Transfer Successful
```json
{
  "event": "transfer.successful",
  "data": {
    "id": "transfer-id",
    "reference": "VBL-WD-123...",
    "lencoReference": "LENCO-REF-123",
    "amount": "100.00",
    "fee": "10.00",
    "status": "successful",
    "completedAt": "2026-04-11T12:00:00Z",
    "creditAccount": {
      "type": "mobile-money",
      "phone": "260961234567",
      "operator": "MTN"
    }
  }
}
```

### Transfer Failed
```json
{
  "event": "transfer.failed",
  "data": {
    "id": "transfer-id",
    "reference": "VBL-WD-123...",
    "status": "failed",
    "reasonForFailure": "Insufficient balance in account"
  }
}
```

## Error Handling

### HTTP Status Codes
- **400** - Bad Request (validation error, invalid phone/operator)
- **401** - Unauthorized (invalid API key)
- **403** - Forbidden (insufficient permissions or balance)
- **404** - Not Found (endpoint or transfer not found)
- **500** - Internal Server Error

### Error Messages
```typescript
{
  success: false,
  message: string,  // Human-readable error message
  error: any        // Original error data from Lencopay
}
```

### Specific Error Handling
1. **400 - Validation Error**
   - Check phone number format
   - Verify operator matches phone prefix
   - Ensure reference format is correct

2. **403 - Insufficient Balance**
   - Verify Lenco account has sufficient funds
   - Check account permissions

3. **404 - Not Found**
   - Verify API endpoint configuration
   - Check if transfer reference exists

## Integration Flow

### 1. Provider Requests Withdrawal
```
Provider → Frontend → Backend API
```

### 2. Backend Processes Request
```typescript
1. Validate withdrawal amount (min K50)
2. Calculate fees (Lencopay tiered pricing)
3. Check provider wallet balance
4. Create withdrawal_request record (status: 'pending')
5. Deduct amount from wallet
6. Call Lencopay initiatePayout()
7. Update withdrawal_request with Lenco details
8. Set status to 'processing'
```

### 3. Lencopay Processes Transfer
```
Lencopay → Mobile Money Operator → Provider's Phone
```

### 4. Webhook Updates Status
```typescript
1. Receive webhook (transfer.successful or transfer.failed)
2. Validate webhook signature
3. Find withdrawal by reference
4. Update withdrawal status
5. If failed: refund wallet
6. If successful: mark completed
7. Send SMS notification to provider
```

## Configuration

### Environment Variables
```env
LENCO_API_KEY=your_api_key_here
LENCO_BASE_URL=https://api.lenco.co/access/v2
LENCO_ACCOUNT_ID=your_account_uuid  # Optional
```

### Webhook Configuration
Configure in Lencopay dashboard:
```
Webhook URL: https://your-domain.com/api/payments/callback
Events: transfer.successful, transfer.failed
```

## Testing

### Test Scenarios

#### 1. Successful Transfer
```typescript
// Request
{
  amount: 100,
  payment_method: 'mtn',
  payment_phone: '0961234567',
  reference: 'VBL-WD-TEST-001'
}

// Expected Response
{
  success: true,
  data: {
    status: 'pending',
    lencoReference: 'LENCO-XXX',
    fee: '10.00'
  }
}

// Expected Webhook
{
  event: 'transfer.successful',
  data: { status: 'successful' }
}
```

#### 2. Invalid Phone Number
```typescript
// Request
{
  phone: '0771234567',  // Airtel number
  operator: 'mtn'        // Wrong operator
}

// Expected Response
{
  success: false,
  message: 'Invalid transfer request...'
}
```

#### 3. Insufficient Balance
```typescript
// Expected Response
{
  success: false,
  message: 'Insufficient permissions or insufficient balance in Lenco account.'
}
```

### Testing Checklist
- [ ] Test MTN transfer (096...)
- [ ] Test Airtel transfer (097...)
- [ ] Test Zamtel transfer (095...)
- [ ] Test invalid phone number
- [ ] Test mismatched operator
- [ ] Test insufficient balance
- [ ] Test webhook processing (successful)
- [ ] Test webhook processing (failed)
- [ ] Test wallet refund on failure
- [ ] Test duplicate reference handling

## Monitoring

### Key Metrics
- Transfer success rate (target: >95%)
- Average processing time (target: <5 minutes)
- Webhook delivery rate (target: 100%)
- Failed transfer reasons (categorize)

### Log Messages
```
✅ "Initiating Lenco transfer" - Transfer request started
✅ "Lenco transfer response received" - Lencopay accepted
✅ "Processing successful transfer/payout" - Webhook received
✅ "Withdrawal completed successfully" - Process complete
❌ "Failed to initiate transfer" - API error
❌ "Transfer/payout failed webhook received" - Transfer failed
```

## Best Practices

### 1. Reference Generation
```typescript
// Use unique, traceable references
const reference = `VBL-WD-${Date.now()}-${randomString}`;
// Only -, ., _ and alphanumeric allowed
```

### 2. Phone Number Validation
```typescript
// Always format to international format
const formatted = formatPhoneNumber(phone); // 260XXXXXXXXX
// Validate operator matches phone prefix
validateOperator(phone, operator);
```

### 3. Idempotency
```typescript
// Use unique references to prevent duplicate transfers
// Check if reference already exists before initiating
```

### 4. Error Recovery
```typescript
// Always refund wallet on transfer failure
// Log all errors with full context
// Retry logic for network failures (not validation errors)
```

### 5. Webhook Security
```typescript
// Always validate webhook signatures
// Respond with 200 OK immediately
// Process asynchronously if needed
```

## Troubleshooting

### Issue: Transfer stuck in 'pending'
**Solutions:**
1. Check Lenco account balance
2. Verify phone number is active
3. Check mobile money operator status
4. Use verifyPayout() to check status
5. Contact Lencopay support with lencoReference

### Issue: Webhook not received
**Solutions:**
1. Verify webhook URL is publicly accessible
2. Check webhook configuration in Lenco dashboard
3. Verify SSL certificate
4. Check server logs for incoming requests
5. Test webhook endpoint manually

### Issue: Transfer fails immediately
**Solutions:**
1. Verify phone number format (260XXXXXXXXX)
2. Check operator matches phone prefix
3. Verify Lenco account has sufficient balance
4. Check API credentials
5. Review Lencopay error message

## Support

### Lencopay Support
- **Email:** [email protected]
- **Documentation:** https://lenco-api.readme.io/v2.0/reference
- **Dashboard:** https://app.lenco.co

### Questions for Support
1. What are the exact webhook event names for transfers?
2. How long do transfers typically take to complete?
3. What are the retry policies for failed transfers?
4. Are there rate limits on the transfer API?
5. How to handle duplicate references?

---

**Implementation Status:** ✅ COMPLETE (Based on Official API Docs)
**API Version:** Lencopay v2.0
**Last Updated:** April 11, 2026
**Documentation:** https://lenco-api.readme.io/v2.0/reference/initiate-transfer-to-mobile-money
