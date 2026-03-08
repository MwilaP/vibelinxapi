import { Router, Request, Response } from 'express';
import { notificationService } from '../services/notification.service';
import { logger } from '../utils/logger';

const router = Router();

router.post('/sms/test', async (req: Request, res: Response) => {
  try {
    const { phoneNumber, message } = req.body;

    if (!phoneNumber) {
      return res.status(400).json({
        success: false,
        error: 'Phone number is required',
      });
    }

    logger.info('🧪 Test SMS endpoint called', {
      phoneNumber,
      hasMessage: !!message,
    });

    const testMessage = message || 'This is a test SMS from VibeLinx API. If you receive this, SMS is working correctly!';

    const result = await notificationService.sendCustomMessage(phoneNumber, testMessage);

    return res.json({
      success: result.success,
      message: result.message,
      messageId: result.messageId,
      details: result,
    });
  } catch (error: any) {
    logger.error('❌ Test SMS endpoint error', {
      error: error.message,
      stack: error.stack,
    });
    return res.status(500).json({
      success: false,
      error: error.message || 'Failed to send test SMS',
    });
  }
});

router.get('/sms/status', async (req: Request, res: Response) => {
  try {
    const config = await import('../config');
    
    const status = {
      smsServiceInitialized: !!(notificationService as any).sms,
      clientInitialized: !!(notificationService as any).client,
      credentials: {
        hasUsername: !!config.config.africastalking.username,
        hasApiKey: !!config.config.africastalking.apiKey,
        hasSenderId: !!config.config.africastalking.senderId,
        usernameLength: config.config.africastalking.username?.length || 0,
        apiKeyLength: config.config.africastalking.apiKey?.length || 0,
      },
      environment: {
        AT_USERNAME: process.env.AT_USERNAME ? 'SET' : 'NOT SET',
        AT_API_KEY: process.env.AT_API_KEY ? 'SET' : 'NOT SET',
        AT_SENDER_ID: process.env.AT_SENDER_ID || 'VIBELINX',
      }
    };

    logger.info('📊 SMS Status check', status);

    return res.json({
      success: true,
      status,
      ready: status.smsServiceInitialized && status.credentials.hasUsername && status.credentials.hasApiKey,
    });
  } catch (error: any) {
    logger.error('❌ Status check error', {
      error: error.message,
      stack: error.stack,
    });
    return res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

export default router;
