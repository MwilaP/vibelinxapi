# PawaPay Migration - Deployment Checklist

## Pre-Deployment Steps

### 1. Clean Up Old Files
```bash
# Delete the old Lenco Pay service file
rm src/services/lencopay.service.ts
```

### 2. Update Environment Variables
Create or update your `.env` file with PawaPay credentials:

```env
# PawaPay Configuration
PAWAPAY_API_TOKEN=your_actual_pawapay_bearer_token
PAWAPAY_BASE_URL=https://api.sandbox.pawapay.io  # Use https://api.pawapay.io for production
PAWAPAY_WEBHOOK_URL=https://your-domain.com/api/payments/webhook

# Keep existing variables
PORT=3001
NODE_ENV=development
AT_USERNAME=your_africastalking_username
AT_API_KEY=your_africastalking_api_key
AT_SENDER_ID=VIBELINX
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_supabase_service_key
API_SECRET_KEY=your_secret_key
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
```

### 3. Database Migration
**IMPORTANT: Backup your database first!**

```bash
# Connect to your Supabase/PostgreSQL database
psql -U your_user -d your_database -f database/migrations/002_migrate_to_pawapay.sql

# Or use Supabase dashboard SQL editor and paste the migration script
```

### 4. Verify Dependencies
All required packages are already installed:
- ✅ uuid (v9.0.1)
- ✅ @types/uuid (v9.0.7)
- ✅ axios (v1.6.2)

### 5. Build and Test
```bash
# Install dependencies (if needed)
npm install

# Build the project
npm run build

# Run in development mode
npm run dev

# Test the endpoints
curl -X POST http://localhost:3001/api/payments/initiate \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "test-user-id",
    "amount": 100,
    "currency": "ZMW",
    "payment_method": "mtn",
    "payment_type": "full",
    "customer_phone": "0976123456"
  }'
```

## Testing Checklist

### Sandbox Testing (Before Production)

- [ ] **Deposit Flow - Booking Payment**
  - [ ] Test MTN payment
  - [ ] Test Airtel payment
  - [ ] Test Zamtel payment
  - [ ] Verify transaction created in database
  - [ ] Verify webhook received and processed

- [ ] **Deposit Flow - Wallet Top-up**
  - [ ] Initiate wallet deposit
  - [ ] Complete payment on mobile
  - [ ] Verify wallet credited after webhook
  - [ ] Check transaction history

- [ ] **Payout Flow - Provider Withdrawal**
  - [ ] Request withdrawal
  - [ ] Verify wallet deducted
  - [ ] Verify payout initiated
  - [ ] Check payout status
  - [ ] Verify webhook updates status

- [ ] **Error Handling**
  - [ ] Test insufficient balance
  - [ ] Test invalid phone number
  - [ ] Test timeout scenarios
  - [ ] Test failed payments

## Production Deployment

### 1. Configure PawaPay Production
- [ ] Update `PAWAPAY_BASE_URL` to `https://api.pawapay.io`
- [ ] Use production API token
- [ ] Configure production webhook URL in PawaPay dashboard

### 2. Database Migration
- [ ] Backup production database
- [ ] Run migration script on production
- [ ] Verify migration success

### 3. Deploy Code
```bash
# Build production bundle
npm run build

# Deploy to your hosting platform
# (Specific commands depend on your hosting provider)
```

### 4. Post-Deployment Verification
- [ ] Monitor first 10 transactions closely
- [ ] Check webhook delivery logs
- [ ] Verify database updates
- [ ] Monitor error logs
- [ ] Test all payment methods in production

## Monitoring

### Key Metrics to Watch
1. **Transaction Success Rate**: Should be >95%
2. **Webhook Delivery**: Should be 100%
3. **Average Processing Time**: <30 seconds
4. **Failed Transactions**: Investigate any failures immediately

### Log Locations
- Application logs: Check your logging service (Winston logs)
- PawaPay API logs: Available in PawaPay dashboard
- Database logs: Check Supabase logs

## Rollback Procedure

If critical issues occur:

1. **Revert Code**
   ```bash
   git revert HEAD
   npm run build
   # Redeploy
   ```

2. **Rollback Database**
   ```sql
   -- Run the rollback script from migration file
   ALTER TABLE transactions RENAME COLUMN lenco_reference_archived TO lenco_reference;
   ALTER TABLE transactions DROP COLUMN IF EXISTS pawapay_deposit_id;
   -- (see full rollback script in migration file)
   ```

3. **Restore Environment Variables**
   - Switch back to Lenco Pay credentials
   - Restart application

## Support Contacts

- **PawaPay Support**: support@pawapay.io
- **PawaPay Documentation**: https://docs.pawapay.io
- **Internal Team**: [Your team contact]

## Success Criteria

✅ All deposits process successfully  
✅ All payouts process successfully  
✅ Webhooks received and processed  
✅ No data loss or corruption  
✅ Historical data accessible  
✅ Performance meets SLAs  

---

**Last Updated**: January 2025  
**Migration Status**: Ready for Deployment
