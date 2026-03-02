import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: process.env.PORT || 3001,
  nodeEnv: process.env.NODE_ENV || 'development',
  
  lencopay: {
    apiKey: process.env.LENCOPAY_API_KEY || '',
    baseUrl: process.env.LENCOPAY_BASE_URL || 'https://api.lenco.co/access/v2',
    callbackUrl: process.env.LENCOPAY_CALLBACK_URL || '',
  },
  
  africastalking: {
    username: process.env.AT_USERNAME || '',
    apiKey: process.env.AT_API_KEY || '',
    senderId: process.env.AT_SENDER_ID || 'VIBELINX',
  },
  
  supabase: {
    url: process.env.SUPABASE_URL || '',
    serviceKey: process.env.SUPABASE_SERVICE_KEY || '',
  },
  
  security: {
    apiSecretKey: process.env.API_SECRET_KEY || '',
    allowedOrigins: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:5173'],
  },
};
