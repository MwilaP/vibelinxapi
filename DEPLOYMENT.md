# Deployment Guide

## Quick Start

1. **Install dependencies:**
```bash
cd vibelinxapi
npm install
```

2. **Configure environment:**
```bash
# Copy example env file
cp .env.example .env

# Edit .env with your credentials
nano .env
```

3. **Run in development:**
```bash
npm run dev
```

4. **Build for production:**
```bash
npm run build
npm start
```

## Environment Setup

### Required Credentials

#### Lencopay
- Sign up at Lencopay merchant portal
- Get API Key, API Secret, and Merchant ID
- Configure callback URL in Lencopay dashboard

#### African's Talking
- Create account at https://africastalking.com
- Get API Key and Username
- Register sender ID (VIBELINX)

#### Supabase
- Get Supabase URL and Service Key from project settings
- Ensure RLS policies allow service role access

### Environment Variables

Edit `.env` file with your credentials:

```env
# Server
PORT=3001
NODE_ENV=production

# Lencopay
LENCOPAY_API_KEY=your_actual_api_key
LENCOPAY_API_SECRET=your_actual_secret
LENCOPAY_MERCHANT_ID=your_merchant_id
LENCOPAY_BASE_URL=https://api.lencopay.com/v1
LENCOPAY_CALLBACK_URL=https://yourdomain.com/api/payments/callback

# African's Talking
AT_USERNAME=your_username
AT_API_KEY=your_api_key
AT_SENDER_ID=VIBELINX

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_key

# Security
API_SECRET_KEY=generate_random_secure_key
ALLOWED_ORIGINS=https://yourdomain.com,https://www.yourdomain.com
```

## Production Deployment

### Option 1: VPS/Cloud Server (Recommended)

1. **Install Node.js:**
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

2. **Install PM2:**
```bash
npm install -g pm2
```

3. **Deploy application:**
```bash
# Clone/upload your code
cd vibelinxapi

# Install dependencies
npm install

# Build TypeScript
npm run build

# Start with PM2
pm2 start dist/server.js --name vibelinx-api

# Save PM2 configuration
pm2 save

# Setup PM2 to start on boot
pm2 startup
```

4. **Configure Nginx reverse proxy:**
```nginx
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

5. **Setup SSL with Let's Encrypt:**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.yourdomain.com
```

### Option 2: Heroku

1. **Create Heroku app:**
```bash
heroku create vibelinx-api
```

2. **Set environment variables:**
```bash
heroku config:set NODE_ENV=production
heroku config:set LENCOPAY_API_KEY=your_key
# ... set all other env vars
```

3. **Deploy:**
```bash
git push heroku main
```

### Option 3: Railway/Render

1. Connect your GitHub repository
2. Set environment variables in dashboard
3. Deploy automatically on push

## Database Setup

Ensure your Supabase database has the required schema:

```sql
-- Add payment tracking columns to bookings table
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS commitment_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS balance_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS commitment_transaction_id TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS balance_transaction_id TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS full_payment_transaction_id TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS commitment_paid_at TIMESTAMPTZ;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS balance_paid_at TIMESTAMPTZ;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS full_payment_at TIMESTAMPTZ;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notification_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notification_sent_at TIMESTAMPTZ;
```

## Monitoring

### PM2 Monitoring

```bash
# View logs
pm2 logs vibelinx-api

# Monitor resources
pm2 monit

# Restart app
pm2 restart vibelinx-api

# Stop app
pm2 stop vibelinx-api
```

### Health Check

```bash
# Check API health
curl https://api.yourdomain.com/health
```

## Troubleshooting

### API not starting
- Check logs: `pm2 logs vibelinx-api`
- Verify environment variables are set
- Check port is not in use: `lsof -i :3001`

### Payment failures
- Verify Lencopay credentials
- Check callback URL is accessible
- Review Lencopay dashboard for errors

### SMS not sending
- Verify African's Talking credentials
- Check phone number format (+260...)
- Ensure sender ID is approved

## Security Checklist

- [ ] Use HTTPS in production
- [ ] Set strong `API_SECRET_KEY`
- [ ] Configure CORS with specific origins
- [ ] Keep dependencies updated
- [ ] Enable rate limiting (add middleware)
- [ ] Monitor logs for suspicious activity
- [ ] Use environment variables for secrets
- [ ] Validate all webhook signatures

## Backup and Recovery

```bash
# Backup environment variables
pm2 save

# Backup application
tar -czf vibelinx-api-backup.tar.gz vibelinxapi/

# Restore
tar -xzf vibelinx-api-backup.tar.gz
cd vibelinxapi
npm install
pm2 start dist/server.js --name vibelinx-api
```
