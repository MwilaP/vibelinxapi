import AfricasTalking from 'africastalking';
import { config } from '../config';
import { BookingNotification, SMSResponse } from '../types';
import { logger } from '../utils/logger';

class NotificationService {
  private client: any;
  private sms: any;

  constructor() {
    logger.info('🚀 Initializing Notification Service', {
      hasUsername: !!config.africastalking.username,
      hasApiKey: !!config.africastalking.apiKey,
      hasSenderId: !!config.africastalking.senderId,
      usernameLength: config.africastalking.username?.length || 0,
      apiKeyLength: config.africastalking.apiKey?.length || 0,
      username: config.africastalking.username ? `${config.africastalking.username.substring(0, 3)}***` : 'MISSING',
      apiKey: config.africastalking.apiKey ? `${config.africastalking.apiKey.substring(0, 8)}***` : 'MISSING',
    });

    if (!config.africastalking.username || config.africastalking.username.trim() === '') {
      logger.error('❌ AT_USERNAME is missing or empty in environment variables!');
      logger.error('Please set AT_USERNAME in your .env file');
    }

    if (!config.africastalking.apiKey || config.africastalking.apiKey.trim() === '') {
      logger.error('❌ AT_API_KEY is missing or empty in environment variables!');
      logger.error('Please set AT_API_KEY in your .env file');
    }

    if (config.africastalking.username && config.africastalking.apiKey) {
      try {
        logger.info('🔧 Attempting to initialize Africa\'s Talking client...');
        this.client = AfricasTalking({
          apiKey: config.africastalking.apiKey,
          username: config.africastalking.username,
        });
        this.sms = this.client.SMS;
        logger.info('✅ Africa\'s Talking SMS service initialized successfully', {
          username: config.africastalking.username,
          senderId: config.africastalking.senderId || 'default',
          smsServiceAvailable: !!this.sms,
        });
      } catch (error) {
        logger.error('❌ CRITICAL: Failed to initialize Africa\'s Talking client', {
          error: error instanceof Error ? error.message : error,
          errorType: error instanceof Error ? error.name : typeof error,
          stack: error instanceof Error ? error.stack : undefined,
        });
        logger.error('SMS notifications will NOT work until this is resolved!');
      }
    } else {
      logger.warn('⚠️  Africa\'s Talking credentials not configured - SMS notifications DISABLED', {
        missingUsername: !config.africastalking.username,
        missingApiKey: !config.africastalking.apiKey,
        envCheck: {
          AT_USERNAME: process.env.AT_USERNAME ? 'SET' : 'NOT SET',
          AT_API_KEY: process.env.AT_API_KEY ? 'SET' : 'NOT SET',
        }
      });
    }
  }

  private formatPhoneNumber(phone: string): string | null {
    if (!phone) {
      logger.debug('formatPhoneNumber: No phone number provided');
      return null;
    }

    logger.debug('formatPhoneNumber: Input', { originalPhone: phone });

    let cleaned = phone.replace(/\s+/g, '').replace(/[^0-9+]/g, '');
    logger.debug('formatPhoneNumber: After cleaning', { cleaned });

    let formatted: string | null = null;

    if (cleaned.startsWith('+260')) {
      formatted = cleaned;
      logger.debug('formatPhoneNumber: Already in international format', { formatted });
      return formatted;
    }

    if (cleaned.startsWith('260')) {
      formatted = '+' + cleaned;
      logger.debug('formatPhoneNumber: Added + prefix', { formatted });
      return formatted;
    }

    if (cleaned.startsWith('0')) {
      formatted = '+260' + cleaned.substring(1);
      logger.debug('formatPhoneNumber: Converted from local format', { formatted });
      return formatted;
    }

    if (cleaned.length === 9 && /^[79]/.test(cleaned)) {
      formatted = '+260' + cleaned;
      logger.debug('formatPhoneNumber: Added country code to 9-digit number', { formatted });
      return formatted;
    }

    logger.warn('formatPhoneNumber: Unable to format phone number', { 
      originalPhone: phone, 
      cleaned,
      cleanedLength: cleaned.length 
    });
    return null;
  }

  private generateProviderBookingMessage(notification: BookingNotification): string {
    const formattedDate = new Date(notification.booking_date).toLocaleDateString('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric'
    });
    return `Booking Update\n\nYou have a new booking request for ${notification.service_name}. Date: ${formattedDate}. Please confirm or reject this booking in your dashboard.\n\nVibeLinx`;
  }

  private generateClientConfirmationMessage(notification: BookingNotification): string {
    const formattedDate = new Date(notification.booking_date).toLocaleDateString('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric'
    });
    const providerName = notification.provider_name || 'Provider';
    return `Booking Update\n\n${providerName} has confirmed your booking for ${notification.service_name}. Date: ${formattedDate}. Please contact ${providerName}: ${notification.provider_phone} for more info.\n\nVibeLinx`;
  }

  async sendBookingNotification(notification: BookingNotification): Promise<SMSResponse> {
    logger.info('📱 sendBookingNotification: Starting', {
      bookingId: notification.booking_id,
      providerPhone: notification.provider_phone,
      hasClient: !!this.client,
      hasSMS: !!this.sms,
    });

    if (!this.sms) {
      logger.error('❌ sendBookingNotification: SMS service NOT initialized - cannot send notification', { 
        bookingId: notification.booking_id,
        hasClient: !!this.client,
        hasSMS: !!this.sms,
        troubleshooting: 'Check AT_USERNAME and AT_API_KEY in .env file',
      });
      return {
        success: false,
        message: 'SMS service not initialized - check AT_USERNAME and AT_API_KEY environment variables',
      };
    }

    try {
      const phoneNumber = this.formatPhoneNumber(notification.provider_phone);
      if (!phoneNumber) {
        logger.error('❌ sendBookingNotification: Invalid phone number format', {
          bookingId: notification.booking_id,
          rawPhone: notification.provider_phone,
          expectedFormat: '+260XXXXXXXXX or 0XXXXXXXXX or 9XXXXXXXX',
        });
        return {
          success: false,
          message: `Invalid phone number format: ${notification.provider_phone}`,
        };
      }
      logger.info('✅ Phone number formatted successfully', { formatted: phoneNumber });

      const message = this.generateProviderBookingMessage(notification);

      const options: any = {
        to: [phoneNumber],
        message: message,
      };

      logger.info('📡 sendBookingNotification: Calling Africa\'s Talking API', {
        to: options.to,
        messageLength: options.message.length,
        from: 'default (no custom sender ID)',
        messagePreview: options.message.substring(0, 50) + '...',
      });

      let response;
      try {
        response = await this.sms.send(options);
        logger.info('📨 Africa\'s Talking API Response received', {
          bookingId: notification.booking_id,
          fullResponse: JSON.stringify(response, null, 2),
          hasMessageData: !!response.SMSMessageData,
          hasRecipients: !!(response.SMSMessageData?.Recipients),
          recipientCount: response.SMSMessageData?.Recipients?.length || 0,
        });
      } catch (apiError: any) {
        logger.error('❌ Africa\'s Talking API call failed', {
          bookingId: notification.booking_id,
          error: apiError.message,
          errorType: apiError.name,
          statusCode: apiError.statusCode,
          stack: apiError.stack,
        });
        throw apiError;
      }

      if (response.SMSMessageData?.Recipients && response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        logger.info('📋 Recipient status', {
          status: recipient.status,
          statusCode: recipient.statusCode,
          messageId: recipient.messageId,
          cost: recipient.cost,
        });
        
        if (recipient.status === 'Success') {
          logger.info('✅ SMS sent successfully!', {
            bookingId: notification.booking_id,
            messageId: recipient.messageId,
          });
          return {
            success: true,
            message: 'Booking notification sent successfully',
            messageId: recipient.messageId,
            recipients: response.SMSMessageData.Recipients.length,
          };
        } else {
          logger.error('❌ SMS failed at provider level', {
            status: recipient.status,
            statusCode: recipient.statusCode,
            number: recipient.number,
          });
          return {
            success: false,
            message: `Failed to send SMS: ${recipient.status} (Code: ${recipient.statusCode})`,
          };
        }
      } else {
        logger.error('❌ No recipients in response', {
          response: JSON.stringify(response),
        });
        return {
          success: false,
          message: 'No recipients processed by Africa\'s Talking',
        };
      }
    } catch (error: any) {
      logger.error('❌ EXCEPTION in sendBookingNotification', {
        bookingId: notification.booking_id,
        error: error instanceof Error ? error.message : String(error),
        errorName: error instanceof Error ? error.name : 'Unknown',
        errorType: typeof error,
        statusCode: error.statusCode,
        stack: error instanceof Error ? error.stack : undefined,
        fullError: JSON.stringify(error, null, 2),
      });
      return {
        success: false,
        message: `SMS Error: ${error.message || 'Failed to send booking notification'}`,
      };
    }
  }

  async sendClientConfirmation(notification: BookingNotification): Promise<SMSResponse> {
    logger.info('📱 sendClientConfirmation: Starting', {
      bookingId: notification.booking_id,
      clientPhone: notification.client_phone,
    });

    if (!this.sms) {
      logger.error('❌ sendClientConfirmation: SMS service not initialized');
      return { success: false, message: 'SMS service not initialized' };
    }

    if (!notification.client_phone) {
      logger.warn('⚠️ sendClientConfirmation: No client phone number provided');
      return { success: false, message: 'No client phone number provided' };
    }

    try {
      const phoneNumber = this.formatPhoneNumber(notification.client_phone);
      if (!phoneNumber) {
        logger.error('❌ sendClientConfirmation: Invalid phone number format', {
          bookingId: notification.booking_id,
          rawPhone: notification.client_phone,
        });
        return {
          success: false,
          message: `Invalid phone number format: ${notification.client_phone}`,
        };
      }

      const message = this.generateClientConfirmationMessage(notification);

      const options: any = {
        to: [phoneNumber],
        message: message,
      };

      logger.info('📡 sendClientConfirmation: Calling Africa\'s Talking API', {
        to: options.to,
        messageLength: options.message.length,
      });

      const response = await this.sms.send(options);

      if (response.SMSMessageData?.Recipients && response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        if (recipient.status === 'Success') {
          logger.info('✅ Client confirmation SMS sent successfully!', {
            bookingId: notification.booking_id,
            messageId: recipient.messageId,
          });
          return {
            success: true,
            message: 'Client confirmation sent successfully',
            messageId: recipient.messageId,
          };
        } else {
          logger.error('❌ SMS failed at provider level', {
            status: recipient.status,
            statusCode: recipient.statusCode,
          });
          return {
            success: false,
            message: `Failed to send SMS: ${recipient.status}`,
          };
        }
      }

      return {
        success: false,
        message: 'No recipients processed',
      };
    } catch (error: any) {
      logger.error('❌ EXCEPTION in sendClientConfirmation', {
        bookingId: notification.booking_id,
        error: error instanceof Error ? error.message : String(error),
      });
      return {
        success: false,
        message: error.message || 'Failed to send client confirmation',
      };
    }
  }

  async sendPaymentConfirmation(
    phoneNumber: string,
    bookingId: string,
    amount: number,
    paymentType: string
  ): Promise<SMSResponse> {
    logger.info('sendPaymentConfirmation: Starting', {
      bookingId,
      phoneNumber,
      amount,
      paymentType,
    });

    if (!this.sms) {
      logger.warn('sendPaymentConfirmation: SMS service not initialized');
      return { success: false, message: 'SMS service not initialized' };
    }

    try {
      const formattedPhone = this.formatPhoneNumber(phoneNumber);
      if (!formattedPhone) {
        logger.warn('sendPaymentConfirmation: Invalid phone number', { phoneNumber });
        return { success: false, message: 'Invalid phone number' };
      }
      const message = `Your payment of ZMW ${amount.toFixed(2)} has been received. Thank you for using VibeLinx!`;

      const options: any = {
        to: [formattedPhone],
        message: message,
      };

      const response = await this.sms.send(options);

      if (response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        return {
          success: recipient.status === 'Success',
          message: recipient.status === 'Success' 
            ? 'Payment confirmation sent' 
            : `Failed: ${recipient.status}`,
          messageId: recipient.messageId,
        };
      }

      return {
        success: false,
        message: 'No recipients processed',
      };
    } catch (error: any) {
      logger.error('sendPaymentConfirmation: Failed', {
        bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      return {
        success: false,
        message: error.message || 'Failed to send payment confirmation',
      };
    }
  }

  async sendBookingStatusUpdate(
    phoneNumber: string,
    bookingId: string,
    status: string,
    additionalInfo?: string
  ): Promise<SMSResponse> {
    logger.info('sendBookingStatusUpdate: Starting', {
      bookingId,
      status,
    });

    if (!this.sms) {
      logger.warn('sendBookingStatusUpdate: SMS service not initialized');
      return { success: false, message: 'SMS service not initialized' };
    }

    try {
      const formattedPhone = this.formatPhoneNumber(phoneNumber);
      if (!formattedPhone) {
        logger.warn('sendBookingStatusUpdate: Invalid phone number', { phoneNumber });
        return { success: false, message: 'Invalid phone number' };
      }
      let message = `Booking Update\n\nYour booking status: ${status.toUpperCase()}.`;
      
      if (additionalInfo) {
        message += ` ${additionalInfo}`;
      }
      
      message += '\n\nVibeLinx';

      const options: any = {
        to: [formattedPhone],
        message: message,
      };

      const response = await this.sms.send(options);

      if (response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        return {
          success: recipient.status === 'Success',
          message: recipient.status === 'Success' 
            ? 'Status update sent' 
            : `Failed: ${recipient.status}`,
          messageId: recipient.messageId,
        };
      }

      return {
        success: false,
        message: 'No recipients processed',
      };
    } catch (error: any) {
      logger.error('sendBookingStatusUpdate: Failed', {
        bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      return {
        success: false,
        message: error.message || 'Failed to send status update',
      };
    }
  }

  async sendCustomMessage(phoneNumber: string, message: string): Promise<SMSResponse> {
    logger.info('🔍 sendCustomMessage: Starting', { 
      phoneNumber,
      messageLength: message.length,
      hasSMSService: !!this.sms,
    });

    if (!this.sms) {
      logger.error('❌ sendCustomMessage: SMS service not initialized');
      return { success: false, message: 'SMS service not initialized' };
    }

    try {
      const formattedPhone = this.formatPhoneNumber(phoneNumber);
      logger.info('📞 Phone formatting result', { 
        original: phoneNumber, 
        formatted: formattedPhone 
      });
      
      if (!formattedPhone) {
        logger.error('❌ sendCustomMessage: Invalid phone number', { phoneNumber });
        return { success: false, message: 'Invalid phone number' };
      }

      const options: any = {
        to: [formattedPhone],
        message: message,
      };

      logger.info('📡 Sending SMS with options', {
        to: options.to,
        messageLength: options.message.length,
        from: 'default (no custom sender ID)',
        messagePreview: options.message.substring(0, 100),
      });

      const response = await this.sms.send(options);

      logger.info('📨 Full Africa\'s Talking API Response', {
        fullResponse: JSON.stringify(response, null, 2),
        hasMessageData: !!response.SMSMessageData,
        hasRecipients: !!(response.SMSMessageData?.Recipients),
        recipientCount: response.SMSMessageData?.Recipients?.length || 0,
        responseKeys: Object.keys(response),
        messageDataKeys: response.SMSMessageData ? Object.keys(response.SMSMessageData) : [],
      });

      if (response.SMSMessageData?.Recipients && response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        logger.info('✅ Recipient details', {
          status: recipient.status,
          statusCode: recipient.statusCode,
          messageId: recipient.messageId,
          number: recipient.number,
          cost: recipient.cost,
        });
        
        return {
          success: recipient.status === 'Success',
          message: recipient.status === 'Success' 
            ? 'Message sent successfully' 
            : `Failed: ${recipient.status}`,
          messageId: recipient.messageId,
        };
      }

      logger.error('❌ No recipients in response', {
        response: JSON.stringify(response),
        recipientCount: response.SMSMessageData?.Recipients?.length || 0,
      });

      return {
        success: false,
        message: 'No recipients processed',
      };
    } catch (error: any) {
      logger.error('❌ sendCustomMessage: Exception caught', {
        error: error instanceof Error ? error.message : String(error),
        errorType: error instanceof Error ? error.name : typeof error,
        statusCode: error.statusCode,
        stack: error instanceof Error ? error.stack : undefined,
        fullError: JSON.stringify(error, null, 2),
      });
      return {
        success: false,
        message: error.message || 'Failed to send message',
      };
    }
  }
}

export const notificationService = new NotificationService();
