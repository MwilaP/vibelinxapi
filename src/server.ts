import app from './app';
import { config } from './config';

const PORT = config.port;

app.listen(PORT, () => {
  console.log(`🚀 VibeLinx Payment API running on port ${PORT}`);
  console.log(`📍 Environment: ${config.nodeEnv}`);
  console.log(`💳 Lencopay integration: ${config.lencopay.baseUrl}`);
  console.log(`📱 African's Talking SMS: ${config.africastalking.senderId}`);
  console.log(`\n✅ Server is ready to accept requests`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT signal received: closing HTTP server');
  process.exit(0);
});
