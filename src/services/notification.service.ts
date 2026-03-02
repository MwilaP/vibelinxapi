import AfricasTalking from 'africastalking';
import { config } from '../config';
import { BookingNotification, SMSResponse } from '../types';
import { logger } from '../utils/logger';

class NotificationService {
  private client: any;
  private sms: any;

  constructor() {
    logger.info('Initializing Notification Service', {
      hasUsername: !!config.africastalking.username,
      hasApiKey: !!config.africastalking.apiKey,
      hasSenderId: !!config.africastalking.senderId,
      usernameLength: config.africastalking.username?.length || 0,
      apiKeyLength: config.africastalking.apiKey?.length || 0,
    });

    if (config.africastalking.username && config.africastalking.apiKey) {
      try {
        this.client = AfricasTalking({
          apiKey: config.africastalking.apiKey,
          username: config.africastalking.username,
        });
        this.sms = this.client.SMS;
        logger.info('Africa\'s Talking SMS service initialized successfully', {
          username: config.africastalking.username,
          senderId: config.africastalking.senderId || 'none',
        });
      } catch (error) {
        logger.error('Failed to initialize Africa\'s Talking client', {
          error: error instanceof Error ? error.message : error,
          stack: error instanceof Error ? error.stack : undefined,
        });
      }
    } else {
      logger.warn('Africa\'s Talking credentials not configured - SMS notifications disabled', {
        missingUsername: !config.africastalking.username,
        missingApiKey: !config.africastalking.apiKey,
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

  private generateBookingMessage(notification: BookingNotification): string {
    return `New Booking Alert!\n\nClient: ${notification.client_name}\nService: ${notification.service_name}\nDate: ${notification.booking_date}\nTime: ${notification.booking_time}\nLocation: ${notification.location_type}\nAmount: ZMW ${notification.total_amount.toFixed(2)}\n\nBooking ID: ${notification.booking_id}\n\nPlease confirm or decline this booking in the VibeLinx app.`;
  }

  async sendBookingNotification(notification: BookingNotification): Promise<SMSResponse> {
    logger.info('sendBookingNotification: Starting', {
      bookingId: notification.booking_id,
      providerPhone: notification.provider_phone,
    });

    if (!this.sms) {
      logger.warn('sendBookingNotification: SMS service not initialized - skipping notification', { 
        bookingId: notification.booking_id,
      });
      return {
        success: false,
        message: 'SMS service not initialized',
      };
    }

    try {
      const phoneNumber = this.formatPhoneNumber(notification.provider_phone);
      if (!phoneNumber) {
        logger.warn('sendBookingNotification: Invalid phone number', {
          bookingId: notification.booking_id,
          rawPhone: notification.provider_phone,
        });
        return {
          success: false,
          message: 'Invalid phone number',
        };
      }

      const message = this.generateBookingMessage(notification);

      const options = {
        to: [phoneNumber],
        message: message,
        from: config.africastalking.senderId || undefined,
      };

      logger.info('sendBookingNotification: Calling Africa\'s Talking API', {
        to: options.to,
        messageLength: options.message.length,
        from: options.from || 'default',
      });

      const response = await this.sms.send(options);

      logger.info('sendBookingNotification: SMS sent successfully', {
        bookingId: notification.booking_id,
        response: JSON.stringify(response),
        recipients: response.SMSMessageData?.Recipients || [],
      });

      if (response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        if (recipient.status === 'Success') {
          return {
            success: true,
            message: 'Booking notification sent successfully',
            messageId: recipient.messageId,
            recipients: response.SMSMessageData.Recipients.length,
          };
        } else {
          return {
            success: false,
            message: `Failed to send SMS: ${recipient.status}`,
          };
        }
      } else {
        return {
          success: false,
          message: 'No recipients processed',
        };
      }
    } catch (error: any) {
      logger.error('sendBookingNotification: Failed to send SMS', {
        bookingId: notification.booking_id,
        error: error instanceof Error ? error.message : String(error),
        errorName: error instanceof Error ? error.name : 'Unknown',
        stack: error instanceof Error ? error.stack : undefined,
      });
      return {
        success: false,
        message: error.message || 'Failed to send booking notification',
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
      const message = `Payment Confirmed!\n\nYour ${paymentType} payment of ZMW ${amount.toFixed(2)} for booking ${bookingId} has been received.\n\nThank you for using VibeLinx!`;

      const options = {
        to: [formattedPhone],
        message: message,
        from: config.africastalking.senderId,
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
      let message = `Booking Update!\n\nYour booking ${bookingId} status: ${status.toUpperCase()}`;
      
      if (additionalInfo) {
        message += `\n\n${additionalInfo}`;
      }
      
      message += '\n\nVibeLinx';

      const options = {
        to: [formattedPhone],
        message: message,
        from: config.africastalking.senderId,
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
    logger.info('sendCustomMessage: Starting', { phoneNumber });

    if (!this.sms) {
      logger.warn('sendCustomMessage: SMS service not initialized');
      return { success: false, message: 'SMS service not initialized' };
    }

    try {
      const formattedPhone = this.formatPhoneNumber(phoneNumber);
      if (!formattedPhone) {
        logger.warn('sendCustomMessage: Invalid phone number', { phoneNumber });
        return { success: false, message: 'Invalid phone number' };
      }

      const options = {
        to: [formattedPhone],
        message: message,
        from: config.africastalking.senderId,
      };

      const response = await this.sms.send(options);

      if (response.SMSMessageData.Recipients.length > 0) {
        const recipient = response.SMSMessageData.Recipients[0];
        
        return {
          success: recipient.status === 'Success',
          message: recipient.status === 'Success' 
            ? 'Message sent successfully' 
            : `Failed: ${recipient.status}`,
          messageId: recipient.messageId,
        };
      }

      return {
        success: false,
        message: 'No recipients processed',
      };
    } catch (error: any) {
      logger.error('sendCustomMessage: Failed', {
        error: error instanceof Error ? error.message : String(error),
      });
      return {
        success: false,
        message: error.message || 'Failed to send message',
      };
    }
  }
}

export const notificationService = new NotificationService();
