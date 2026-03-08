# SMS Troubleshooting Guide

## Problem: SMS Not Being Sent

This guide will help you debug and fix SMS sending issues in the VibeLinx API.

## Quick Diagnosis

### Step 1: Check SMS Service Status

Run this command to check if the SMS service is properly initialized:

```bash
curl http://localhost:3001/api/test/sms/status
```

**Expected Response (Working):**
```json
{
  "success": true,
  "status": {
    "smsServiceInitialized": true,
    "clientInitialized": true,
    "credentials": {
      "hasUsername": true,
      "hasApiKey": true,
      "hasSenderId": true
    }
  },
  "ready": true
}
```

**If `ready: false`**, proceed to Step 2.

### Step 2: Verify Environment Variables

Check your `.env` file has the following variables set:

```bash
AT_USERNAME=your_africastalking_username
AT_API_KEY=your_africastalking_api_key
AT_SENDER_ID=VIBELINX
```

**Common Issues:**
- ❌ Variables not set at all
- ❌ Variables set but empty (e.g., `AT_USERNAME=`)
- ❌ Extra spaces around values
- ❌ Using placeholder values from `.env.example`

**Fix:**
1. Open your `.env` file
2. Set actual Africa's Talking credentials (get them from https://account.africastalking.com/)
3. Ensure no extra spaces: `AT_USERNAME=sandbox` NOT `AT_USERNAME = sandbox`
4. Restart your server after changing `.env`

### Step 3: Test SMS Sending

Send a test SMS to verify everything works:

```bash
curl -X POST http://localhost:3001/api/test/sms/test \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "+260XXXXXXXXX",
    "message": "Test SMS from VibeLinx"
  }'
```

Replace `+260XXXXXXXXX` with your actual Zambian phone number.

**Expected Response (Success):**
```json
{
  "success": true,
  "message": "Message sent successfully",
  "messageId": "ATXid_xxxxx"
}
```

## Common Error Messages and Solutions

### Error: "SMS service not initialized"

**Cause:** Africa's Talking credentials are missing or invalid.

**Solution:**
1. Check `.env` file has `AT_USERNAME` and `AT_API_KEY`
2. Verify credentials are correct (login to Africa's Talking dashboard)
3. Restart the server: `npm run dev` or `npm start`

### Error: "Invalid phone number format"

**Cause:** Phone number doesn't match expected Zambian format.

**Valid Formats:**
- `+260XXXXXXXXX` (international format)
- `0XXXXXXXXX` (local format with leading 0)
- `9XXXXXXXX` (9-digit number starting with 7 or 9)

**Solution:**
Ensure phone numbers in the database are stored in one of these formats.

### Error: "Failed to send SMS: InsufficientBalance"

**Cause:** Africa's Talking account has no airtime.

**Solution:**
1. Login to https://account.africastalking.com/
2. Add airtime to your account
3. For sandbox mode, you get free test credits

### Error: "Failed to send SMS: InvalidPhoneNumber"

**Cause:** Phone number is not valid according to Africa's Talking.

**Solution:**
1. Verify the phone number is a valid Zambian number
2. Check the number is registered in Africa's Talking sandbox (if using sandbox)
3. Ensure the number format is correct (+260...)

## Enhanced Logging

The notification service now includes detailed logging with emojis for easy identification:

- 🚀 Service initialization
- 📱 SMS sending started
- ✅ Success messages
- ❌ Error messages
- 📡 API calls
- 📨 API responses

**View logs in real-time:**
```bash
tail -f logs/combined.log
```

**View only errors:**
```bash
tail -f logs/error.log
```

## Testing Checklist

- [ ] Environment variables are set in `.env`
- [ ] Server restarted after changing `.env`
- [ ] `/api/test/sms/status` returns `ready: true`
- [ ] Africa's Talking account has airtime
- [ ] Phone numbers are in correct format
- [ ] Test SMS endpoint works
- [ ] Logs show successful initialization

## Debugging Flow

```
1. Start Server
   ↓
2. Check logs for "🚀 Initializing Notification Service"
   ↓
3. Should see "✅ Africa's Talking SMS service initialized successfully"
   ↓
4. If you see "❌" errors, check environment variables
   ↓
5. Test with /api/test/sms/test endpoint
   ↓
6. Check logs for detailed error messages
   ↓
7. Fix issues and restart server
```

## Phone Number Validation

The service validates phone numbers strictly. Here's what happens:

```javascript
// Valid inputs:
"+260977123456" → "+260977123456" ✅
"0977123456"    → "+260977123456" ✅
"977123456"     → "+260977123456" ✅
"260977123456"  → "+260977123456" ✅

// Invalid inputs:
"123456"        → null ❌ (too short)
"+1234567890"   → null ❌ (wrong country code)
"abc123"        → null ❌ (contains letters)
```

## Africa's Talking Sandbox Mode

If using sandbox mode for testing:

1. **Add test phone numbers** in the Africa's Talking dashboard
2. Only registered numbers will receive SMS in sandbox
3. Switch to production mode for real SMS sending

## Still Not Working?

Check the following in order:

1. **Server logs** - Look for initialization errors
2. **Environment variables** - Verify they're loaded correctly
3. **Africa's Talking dashboard** - Check account status and balance
4. **Network connectivity** - Ensure server can reach Africa's Talking API
5. **Phone number format** - Verify numbers in database are valid

## Support

If you've tried everything and SMS still doesn't work:

1. Check logs in `logs/combined.log` and `logs/error.log`
2. Run `/api/test/sms/status` and share the output
3. Try the test endpoint with a known working number
4. Verify Africa's Talking API status: https://status.africastalking.com/
