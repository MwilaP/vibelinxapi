# Wallet and Escrow System Documentation

## Overview

The VibeLinx platform has been upgraded from a pay-per-booking mobile money system to a wallet-based escrow system. This change eliminates payment friction by allowing clients to deposit funds once and use their wallet balance for multiple bookings.

## Key Features

### 1. **Wallet System**
- Clients and providers each have their own wallet
- Supports deposits via mobile money (MTN, Airtel, Zamtel)
- Real-time balance tracking (available + locked funds)
- Complete transaction history

### 2. **Escrow Protection**
- Commitment fees are locked in escrow when booking is created
- Funds are released to provider only when service is completed
- Automatic refund to client if booking is cancelled or declined
- Admin controls for dispute resolution

### 3. **Seamless Booking Flow**
- No payment required at booking time (uses wallet balance)
- Instant booking confirmation
- Automatic escrow management
- Transparent fund tracking

## Database Schema

### Tables Created

#### `wallets`
Stores wallet information for clients and providers.

```sql
- id: UUID (Primary Key)
- user_id: UUID (Foreign Key to auth.users)
- user_type: VARCHAR ('client' or 'provider')
- available_balance: DECIMAL(10,2)
- locked_balance: DECIMAL(10,2)
- total_deposited: DECIMAL(10,2)
- total_withdrawn: DECIMAL(10,2)
- currency: VARCHAR(3) - Default 'ZMW'
- status: VARCHAR(20) - 'active', 'suspended', 'frozen'
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### `wallet_transactions`
Records all wallet operations.

```sql
- id: UUID (Primary Key)
- wallet_id: UUID (Foreign Key to wallets)
- transaction_type: VARCHAR(30) - 'deposit', 'withdrawal', 'escrow_lock', 'escrow_release', etc.
- amount: DECIMAL(10,2)
- balance_before: DECIMAL(10,2)
- balance_after: DECIMAL(10,2)
- reference_id: UUID
- reference_type: VARCHAR(30) - 'booking', 'escrow', 'payment', 'withdrawal'
- description: TEXT
- metadata: JSONB
- created_at: TIMESTAMP
```

#### `escrow_transactions`
Manages funds held in escrow for bookings.

```sql
- id: UUID (Primary Key)
- booking_id: UUID (Foreign Key to bookings)
- client_wallet_id: UUID (Foreign Key to wallets)
- provider_wallet_id: UUID (Foreign Key to wallets)
- amount: DECIMAL(10,2)
- status: VARCHAR(20) - 'locked', 'released', 'refunded', 'disputed', 'cancelled'
- locked_at: TIMESTAMP
- released_at: TIMESTAMP
- refunded_at: TIMESTAMP
- released_to_provider_at: TIMESTAMP
- reason: TEXT
- resolved_by: UUID (Admin user ID)
- metadata: JSONB
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### `withdrawal_requests`
Manages provider withdrawal requests.

```sql
- id: UUID (Primary Key)
- wallet_id: UUID (Foreign Key to wallets)
- user_id: UUID (Foreign Key to auth.users)
- amount: DECIMAL(10,2)
- payment_method: VARCHAR(20) - 'mtn', 'airtel', 'zamtel', 'bank_transfer'
- payment_phone: VARCHAR(20)
- bank_details: JSONB
- status: VARCHAR(20) - 'pending', 'processing', 'completed', 'failed', 'cancelled'
- processed_by: UUID (Admin user ID)
- processed_at: TIMESTAMP
- transaction_id: UUID
- failure_reason: TEXT
- metadata: JSONB
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

## API Endpoints

### Wallet Endpoints

#### **POST /api/wallet/deposit**
Initiate a wallet deposit via mobile money.

**Request Body:**
```json
{
  "user_id": "uuid",
  "amount": 100.00,
  "payment_method": "mtn",
  "customer_phone": "+260961234567"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Wallet deposit initiated. Please complete payment on your phone.",
  "transaction_id": "uuid",
  "wallet_id": "uuid",
  "data": {
    "transaction_id": "uuid",
    "reference": "VBL-xxx-wallet-deposit",
    "amount": 100.00,
    "currency": "ZMW",
    "status": "pending"
  }
}
```

#### **GET /api/wallet/balance/:user_id?user_type=client**
Get wallet balance for a user.

**Response:**
```json
{
  "success": true,
  "data": {
    "available_balance": 150.00,
    "locked_balance": 50.00,
    "total_balance": 200.00,
    "currency": "ZMW"
  }
}
```

#### **GET /api/wallet/transactions/:user_id?user_type=client&limit=50**
Get wallet transaction history.

**Response:**
```json
{
  "success": true,
  "data": {
    "transactions": [
      {
        "id": "uuid",
        "transaction_type": "deposit",
        "amount": 100.00,
        "balance_before": 50.00,
        "balance_after": 150.00,
        "description": "Wallet deposit via mobile money",
        "created_at": "2024-01-01T10:00:00Z"
      }
    ],
    "count": 1
  }
}
```

#### **GET /api/wallet/escrow/:user_id?user_type=client&status=locked**
Get escrow transactions for a user.

**Response:**
```json
{
  "success": true,
  "data": {
    "escrows": [
      {
        "id": "uuid",
        "booking_id": "uuid",
        "amount": 50.00,
        "status": "locked",
        "locked_at": "2024-01-01T10:00:00Z"
      }
    ],
    "count": 1
  }
}
```

#### **GET /api/wallet/dashboard/:user_id?user_type=client**
Get comprehensive wallet dashboard summary.

**Response:**
```json
{
  "success": true,
  "data": {
    "wallet": {
      "available_balance": 150.00,
      "locked_balance": 50.00,
      "total_balance": 200.00,
      "total_deposited": 500.00,
      "total_withdrawn": 300.00,
      "currency": "ZMW",
      "status": "active"
    },
    "escrow": {
      "locked_count": 2,
      "locked_amount": 50.00
    },
    "recent_transactions": []
  }
}
```

### Booking Endpoints

#### **POST /api/bookings/create-with-wallet**
Create a booking using wallet balance (no payment required).

**Request Body:**
```json
{
  "client_id": "uuid",
  "provider_id": "uuid",
  "service_name": "Massage Therapy",
  "service_duration": "2 hours",
  "service_price": 500.00,
  "booking_date": "2024-01-15",
  "booking_time": "14:00",
  "duration_minutes": 120,
  "location_type": "my",
  "location_details": "123 Main Street",
  "client_notes": "Please bring massage table",
  "platform_fee": 0,
  "commitment_fee": 50.00,
  "balance_due": 450.00,
  "total_amount": 500.00
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Booking created successfully. Commitment fee deducted from wallet and held in escrow.",
  "data": {
    "booking_id": "uuid",
    "status": "pending",
    "commitment_fee": 50.00
  }
}
```

**Response (Insufficient Balance):**
```json
{
  "success": false,
  "message": "Insufficient wallet balance",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "required": 50.00,
    "available": 30.00
  }
}
```

### Admin Endpoints

#### **GET /api/admin/escrows?status=locked&limit=50&offset=0**
Get all escrow transactions (admin only).

#### **POST /api/admin/escrow/release**
Manually release escrow to provider.

**Request Body:**
```json
{
  "escrow_id": "uuid",
  "reason": "Manual release by admin",
  "admin_id": "uuid"
}
```

#### **POST /api/admin/escrow/refund**
Manually refund escrow to client.

**Request Body:**
```json
{
  "escrow_id": "uuid",
  "reason": "Dispute resolved in favor of client",
  "admin_id": "uuid"
}
```

#### **POST /api/admin/escrow/dispute**
Mark escrow as disputed.

**Request Body:**
```json
{
  "escrow_id": "uuid",
  "reason": "Client reported service not completed"
}
```

#### **POST /api/admin/wallet/adjust**
Adjust wallet balance (admin only).

**Request Body:**
```json
{
  "wallet_id": "uuid",
  "amount": 100.00,
  "reason": "Promotional credit",
  "admin_id": "uuid"
}
```

## User Flows

### Client Deposit Flow

1. Client opens dashboard and clicks "Deposit Funds"
2. Client enters amount and selects payment method
3. System initiates mobile money payment
4. Client authorizes payment on their phone
5. Payment provider sends webhook to system
6. System credits wallet balance
7. Client sees updated balance on dashboard

### Wallet-Based Booking Flow

1. Client selects provider and service
2. System calculates 10% commitment fee
3. System checks client wallet balance
4. If sufficient:
   - Deduct commitment fee from available balance
   - Lock funds in escrow
   - Create booking with status "pending"
   - Notify provider
5. If insufficient:
   - Show error message
   - Prompt client to deposit funds

### Service Completion Flow

1. Provider marks booking as "completed"
2. System automatically:
   - Releases escrow funds
   - Transfers funds to provider wallet
   - Updates escrow status to "released"
   - Notifies both parties

### Booking Cancellation Flow

1. Provider declines booking OR client cancels
2. System automatically:
   - Refunds escrow to client wallet
   - Updates escrow status to "refunded"
   - Notifies both parties

## Migration Guide

### Database Migration

Run the migration SQL file to create all necessary tables:

```bash
psql -U your_user -d your_database -f database/migrations/001_wallet_escrow_system.sql
```

### Existing Bookings

Existing bookings using the old payment system will continue to work. The new wallet system is additive and doesn't break existing functionality.

### Frontend Integration

Update your frontend to:

1. **Display wallet balance** on client dashboard
2. **Show deposit button** for clients to add funds
3. **Check wallet balance** before allowing booking
4. **Display escrow status** for active bookings
5. **Show transaction history** for transparency

### Example Frontend Flow

```javascript
// Check wallet balance before booking
const checkBalance = async (userId) => {
  const response = await fetch(`/api/wallet/balance/${userId}?user_type=client`);
  const data = await response.json();
  return data.data.available_balance;
};

// Create booking with wallet
const createBooking = async (bookingData) => {
  const balance = await checkBalance(bookingData.client_id);
  
  if (balance < bookingData.commitment_fee) {
    // Show insufficient balance message
    // Redirect to deposit page
    return;
  }
  
  const response = await fetch('/api/bookings/create-with-wallet', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(bookingData)
  });
  
  return response.json();
};
```

## Security Considerations

1. **Row Level Security (RLS)** is enabled on all wallet and escrow tables
2. **Users can only view their own wallet** data
3. **Service role** has full access for backend operations
4. **Admin endpoints** should be protected with authentication middleware
5. **Webhook signatures** are validated for payment callbacks

## Testing

### Test Wallet Deposit

```bash
curl -X POST http://localhost:3001/api/wallet/deposit \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "your-user-id",
    "amount": 100,
    "payment_method": "mtn",
    "customer_phone": "+260961234567"
  }'
```

### Test Wallet Balance

```bash
curl http://localhost:3001/api/wallet/balance/your-user-id?user_type=client
```

### Test Wallet Booking

```bash
curl -X POST http://localhost:3001/api/bookings/create-with-wallet \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "your-client-id",
    "provider_id": "provider-id",
    "service_name": "Test Service",
    "service_price": 100,
    "commitment_fee": 10,
    "balance_due": 90,
    "total_amount": 100,
    ...
  }'
```

## Monitoring and Maintenance

### Key Metrics to Monitor

1. **Wallet Balance Discrepancies** - Ensure available + locked = total
2. **Stuck Escrow Transactions** - Escrows locked for > 7 days
3. **Failed Deposits** - Track deposit failure rates
4. **Refund Processing Time** - Monitor escrow refund speed

### Database Queries for Monitoring

```sql
-- Check for balance discrepancies
SELECT id, user_id, available_balance, locked_balance, 
       (available_balance + locked_balance) as calculated_total
FROM wallets
WHERE status = 'active';

-- Find stuck escrows
SELECT * FROM escrow_transactions
WHERE status = 'locked'
  AND locked_at < NOW() - INTERVAL '7 days';

-- Get deposit success rate
SELECT 
  COUNT(*) FILTER (WHERE status = 'completed') as successful,
  COUNT(*) FILTER (WHERE status = 'failed') as failed,
  COUNT(*) as total
FROM transactions
WHERE transaction_type = 'wallet_topup'
  AND created_at > NOW() - INTERVAL '30 days';
```

## Support and Troubleshooting

### Common Issues

**Issue: Wallet balance not updating after deposit**
- Check transaction status in `transactions` table
- Verify webhook was received and processed
- Check wallet_transactions for the deposit record

**Issue: Insufficient balance error despite having funds**
- Verify funds are in `available_balance`, not `locked_balance`
- Check for pending escrow transactions

**Issue: Escrow not releasing after booking completion**
- Verify booking status is "completed"
- Check escrow_transactions table for status
- Review logs for any errors in escrow release process

## Future Enhancements

1. **Provider Withdrawals** - Allow providers to withdraw funds to mobile money
2. **Wallet Top-up Bonuses** - Incentivize larger deposits
3. **Recurring Payments** - Auto-deduct for subscription services
4. **Multi-currency Support** - Support USD, EUR, etc.
5. **Wallet Limits** - Set maximum wallet balances for security
6. **Automated Escrow Release** - Release after X days if no disputes

## Conclusion

The wallet and escrow system provides a seamless, secure, and transparent payment experience for both clients and providers. It reduces friction, builds trust, and improves the overall user experience on the VibeLinx platform.
