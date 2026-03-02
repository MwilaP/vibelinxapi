# VibeLinx Payment API

A comprehensive payment and notification API for the VibeLinx platform, integrating Lencopay for payments and African's Talking for SMS notifications.

## Features

- **Mobile Money Collections**: Lenco Pay v2 integration for MTN, Airtel, and Zamtel mobile money
- **SMS Notifications**: African's Talking integration for booking notifications
- **Booking Management**: Integration with Supabase for booking data
- **Payment Types**: Support for commitment, balance, and full payments
- **Webhook Support**: Lenco webhook handling with HMAC SHA512 signature validation
- **Real-time Status**: Pay-offline and OTP-required payment flows
- **Refund Support**: Automated refund processing

## Tech Stack

- **Runtime**: Node.js with TypeScript
- **Framework**: Express.js P v2 (Mobile Money Collections)
- **Payment Gateway**: Lencopay
- **SMS Service**: African's Talking
- **Database**: SupabaseS, HMAC HA512 Webhook Validation
- **Security**: Helmet, CORS

## Installation

1. Clone the repository and navigate to the API folder:
```bash
cd vibelinxapi
```

2. Install dependencies:
```bash
npm install
```

3. Create a `.env` file based on `.env.example`:
```bash
cp .env.example .env
```

4. Configure your environment variables in `.env`:
   - Lencopay API credentials
   - African's Talking credentials
   - Supabase credentials
   - Server configuration

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `PORT` | Server port (default: 3001) |
| `NODE_ENV` | Environment (development/production) |
| `LENCOPAY_API_KEY` | Lenco API token (Bearer token) |
| `LENCOPAY_BASE_URL` | Lenco API base URL (v2: https://api.lenco.co/access/v2) |
| `LENCOPAY_CALLBACK_URL` | Callback URL for payment webhooks |
| `AT_USERNAME` | African's Talking username |
| `AT_API_KEY` | African's Talking API key |
| `AT_SENDER_ID` | SMS sender ID (default: VIBELINX) |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `API_SECRET_KEY` | Secret key for API security |
| `ALLOWED_ORIGINS` | Comma-separated allowed CORS origins |

## Development

Start the development server with hot reload:
```bash
npm run dev
```

Build the TypeScript code:
```bash
npm run build
```

Start the production server:
```bash
npm start
```

## API Endpoints

### Payment Endpoints

#### Initiate Payment
```http
POST /api/payments/initiate
Content-Type: application/json

{
  "booking_id": "uuid",
  "amount": 100.00,
  "currency": "ZMW",
  "payment_type": "commitment",
  "customer_phone": "260971234567",
  "customer_email": "customer@example.com",
  "customer_name": "John Doe"
}
```

**Response:**
```json
{
  "success": true,
  "transaction_id": "VBL-1234567890-ABC123",
  "payment_url": "https://payment.lencopay.com/...",
  "message": "Payment initiated successfully"
}
```

#### Verify Payment
```http
GET /api/payments/verify/:transaction_id
```

**Response:**
```json
{
  "success": true,
  "transaction_id": "VBL-1234567890-ABC123",
  "status": "success",
  "amount": 100.00,
  "currency": "ZMW",
  "message": "Payment verification completed"
}
```

#### Payment Callback (Webhook)
```http
POST /api/payments/callback
X-Lencopay-Signature: signature_hash
Content-Type: application/json

{
  "transaction_id": "VBL-1234567890-ABC123",
  "status": "success",
  "amount": 100.00,
  "currency": "ZMW",
  "reference": "booking_id",
  "payment_method": "mobile_money",
  "timestamp": "2024-03-02T10:00:00Z"
}
```

#### Refund Payment
```http
POST /api/payments/refund
Content-Type: application/json

{
  "transaction_id": "VBL-1234567890-ABC123",
  "amount": 100.00,
  "reason": "Booking cancelled by provider"
}
```

### Booking Endpoints

#### Notify Provider
```http
POST /api/bookings/notify
Content-Type: application/json

{
  "booking_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Provider notified successfully"
}
```

#### Send Status Update
```http
POST /api/bookings/status-update
Content-Type: application/json

{
  "phone_number": "260971234567",
  "booking_id": "uuid",
  "status": "confirmed",
  "additional_info": "Your booking has been confirmed"
}
```

#### Send Custom Notification
```http
POST /api/bookings/custom-notification
Content-Type: application/json

{
  "phone_number": "260971234567",
  "message": "Your custom message here"
}
```

#### Get Booking
```http
GET /api/bookings/:booking_id
```

### Health Check
```http
GET /health
```

**Response:**
```json
{
  "success": true,
  "message": "VibeLinx Payment API is running",
  "timestamp": "2024-03-02T10:00:00Z"
}
```

## Payment Flow

1. **Client initiates payment** → POST `/api/payments/initiate`
2. **Client redirected to Lencopay** → Uses `payment_url` from response
3. **Client completes payment** → On Lencopay platform
4. **Lencopay sends callback** → POST `/api/payments/callback`
5. **System updates booking** → Payment status updated in Supabase
6. **System sends notifications** → SMS to client and provider

## Notification Flow

1. **Payment confirmed** → Commitment fee paid
2. **Provider notified** → SMS sent via African's Talking
3. **Provider responds** → Confirms or declines booking
4. **Client notified** → Status update sent via SMS

## Error Handling

All endpoints return consistent error responses:

```json
{
  "success": false,
  "message": "Error description",
  "errors": [
    {
      "field": "amount",
      "message": "Amount must be a number"
    }
  ]
}
```

## Security

- **CORS**: Configured with allowed origins
- **Helmet**: Security headers enabled
- **Signature Validation**: Lencopay callbacks validated with HMAC
- **Environment Variables**: Sensitive data stored in `.env`
- **Input Validation**: Express-validator for request validation

## Integration with VibeLinx Frontend

The frontend should call this API for:

1. **Payment initiation** when a booking is created
2. **Payment verification** to check payment status
3. **Booking notifications** after successful payment

Example frontend integration:

```typescript
// Initiate payment
const response = await fetch('http://localhost:3001/api/payments/initiate', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    booking_id: bookingId,
    amount: commitmentFee,
    currency: 'ZMW',
    payment_type: 'commitment',
    customer_phone: userPhone,
    customer_email: userEmail,
    customer_name: userName
  })
});

const { payment_url } = await response.json();
// Redirect user to payment_url
window.location.href = payment_url;
```

## Testing

Test the API endpoints using tools like Postman or curl:

```bash
# Health check
curl http://localhost:3001/health

# Initiate payment
curl -X POST http://localhost:3001/api/payments/initiate \
  -H "Content-Type: application/json" \
  -d '{
    "booking_id": "test-booking-id",
    "amount": 50.00,
    "currency": "ZMW",
    "payment_type": "commitment",
    "customer_phone": "260971234567"
  }'
```

## Production Deployment

1. Set `NODE_ENV=production` in `.env`
2. Configure production Lencopay credentials
3. Set up proper CORS origins
4. Configure callback URL to production domain
5. Enable HTTPS
6. Set up process manager (PM2 recommended)

```bash
# Using PM2
npm install -g pm2
npm run build
pm2 start dist/server.js --name vibelinx-api
```

## Logging and Monitoring

The API uses **Winston** for comprehensive logging:

### Log Files

- **`logs/error.log`** - All errors and exceptions
- **`logs/combined.log`** - Complete audit trail of all operations
- **Console** - Real-time colored output during development

### Log Levels

- **debug** - API requests/responses, detailed debugging
- **info** - Successful operations, general information
- **warn** - Invalid data, missing configurations
- **error** - Failures, exceptions with stack traces

### Viewing Logs

```bash
# Watch logs in real-time
tail -f logs/combined.log

# Search for specific booking
grep "booking-uuid-123" logs/combined.log

# View all errors
cat logs/error.log

# Find payment failures
grep "Failed to initiate" logs/error.log
```

### Production Monitoring

For production, integrate with:
- **Datadog** - Real-time monitoring and alerts
- **Sentry** - Error tracking and reporting
- **CloudWatch** - AWS log aggregation
- **ELK Stack** - Log analysis and visualization

## Troubleshooting

### Payment Issues
- **Check logs**: `grep "Payment" logs/error.log`
- Verify Lencopay credentials are correct
- Check callback URL is accessible from Lencopay servers
- Validate signature generation matches Lencopay's requirements
- Review API request/response logs in debug mode

### SMS Issues
- **Check logs**: `grep "SMS" logs/error.log`
- Verify African's Talking credentials
- Check phone number format (must include country code)
- Ensure sender ID is approved by African's Talking
- Review notification service initialization logs

### Database Issues
- **Check logs**: `grep "Supabase" logs/error.log`
- Verify Supabase credentials
- Check RLS policies allow service role access
- Ensure booking table schema matches expected structure

### Webhook Issues
- **Check logs**: `grep "webhook" logs/combined.log`
- Verify webhook URL is publicly accessible
- Check signature validation logs
- Ensure Lenco webhook secret is configured correctly

## Support

For issues or questions:
- Check the logs: `npm run dev` shows detailed error messages
- Review Lencopay documentation
- Review African's Talking documentation
- Check Supabase logs for database issues

## License

MIT
