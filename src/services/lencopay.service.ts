import axios, { AxiosInstance } from 'axios';
import crypto from 'crypto';
import { config } from '../config';
import { logger } from '../utils/logger';
import {
  PaymentInitiationRequest,
  PaymentInitiationResponse,
  PaymentVerificationResponse,
  PaymentCallbackData,
} from '../types';

class LencopayService {
  private client: AxiosInstance;
  private apiKey: string;
  private webhookHashKey: string;

  constructor() {
    this.apiKey = config.lencopay.apiKey;
    
    logger.info('Initializing Lenco Pay Service', {
      baseURL: config.lencopay.baseUrl,
      hasApiKey: !!this.apiKey,
      apiKeyLength: this.apiKey?.length || 0,
      apiKeyPrefix: this.apiKey?.substring(0, 10) + '...',
    });
    
    this.webhookHashKey = crypto
      .createHash('sha256')
      .update(this.apiKey)
      .digest('hex');

    this.client = axios.create({
      baseURL: config.lencopay.baseUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`,
        'accept': 'application/json',
      },
      timeout: 30000,
    });

    // Add request interceptor for logging
    this.client.interceptors.request.use(
      (config) => {
        logger.debug('Lenco API Request', {
          method: config.method,
          url: config.url,
          fullURL: `${config.baseURL}${config.url}`,
          headers: {
            'Authorization': config.headers?.['Authorization'] ? 'Bearer ***...' : 'MISSING',
            'Content-Type': config.headers?.['Content-Type'],
          },
          data: config.data,
        });
        return config;
      },
      (error) => {
        logger.error('Lenco API Request Error', { error: error.message });
        return Promise.reject(error);
      }
    );

    // Add response interceptor for logging
    this.client.interceptors.response.use(
      (response) => {
        logger.debug('Lenco API Response', {
          status: response.status,
          data: response.data,
        });
        return response;
      },
      (error) => {
        logger.error('Lenco API Request Failed', {
          status: error.response?.status,
          statusText: error.response?.statusText,
          data: error.response?.data,
          url: error.config?.url,
          method: error.config?.method,
          message: error.message,
        });
        return Promise.reject(error);
      }
    );
  }

  private generateWebhookSignature(payload: any): string {
    return crypto
      .createHmac('sha512', this.webhookHashKey)
      .update(JSON.stringify(payload))
      .digest('hex');
  }

  private generateTransactionId(): string {
    return `VBL-${Date.now()}-${Math.random().toString(36).substr(2, 9).toUpperCase()}`;
  }

  private formatPhoneNumber(phone: string, countryCode: string = '260'): string {
    // Remove any spaces, dashes, or special characters
    let cleaned = phone.replace(/[\s\-\(\)]/g, '');
    
    // Remove leading zeros
    cleaned = cleaned.replace(/^0+/, '');
    
    // Remove country code if already present
    if (cleaned.startsWith(countryCode)) {
      return cleaned;
    }
    
    // Add country code
    return `${countryCode}${cleaned}`;
  }

  private detectOperator(phone: string): string | null {
    // Remove country code and leading zeros for prefix detection
    const cleaned = phone.replace(/^(\+?260|0)/, '');
    const prefix = cleaned.substring(0, 3);
    
    // Zambian mobile operator prefixes (lowercase for Lenco API)
    if (prefix === '096' || prefix === '076') return 'mtn';
    if (prefix === '097' || prefix === '077') return 'airtel';
    if (prefix === '095' || prefix === '075') return 'zamtel';
    
    return null;
  }

  async initiatePayment(
    paymentData: PaymentInitiationRequest
  ): Promise<PaymentInitiationResponse> {
    try {
      // Use the reference passed from the controller (contains transaction ID)
      // If no reference provided, generate one (backward compatibility)
      const reference = paymentData.reference || 
        `${this.generateTransactionId()}-${paymentData.payment_type}-${paymentData.booking_id}`;
      
      const formattedPhone = this.formatPhoneNumber(paymentData.customer_phone);
      const operator = paymentData.payment_method; // Use the operator selected by the user
      
      logger.debug('Payment initiation details', {
        original: paymentData.customer_phone,
        formatted: formattedPhone,
        operator: operator,
        amount: paymentData.amount,
        reference: reference,
      });
      
      const payload = {
        amount: paymentData.amount.toString(),
        reference: reference,
        phone: formattedPhone,
        operator: operator,
        country: 'zm',
      };

      const response = await this.client.post('/collections/mobile-money', payload);

      logger.info('Lenco API Response', {
        reference,
        amount: paymentData.amount,
        responseStatus: response.data.status,
        responseData: response.data.data,
        fullResponse: JSON.stringify(response.data),
      });

      // Check if response has data (Lenco returns status: true/false)
      if (response.data.status === true || response.data.data) {
        const collectionData = response.data.data || {};
        
        return {
          success: true,
          transaction_id: reference,
          message: collectionData.status === 'pay-offline' 
            ? 'Payment initiated. Please authorize on your mobile phone.'
            : collectionData.status === 'otp-required'
            ? 'OTP sent to your phone. Please complete authorization.'
            : collectionData.status === 'pending'
            ? 'Payment initiated. Waiting for confirmation.'
            : 'Payment initiated successfully',
          data: {
            ...collectionData,
            lencoReference: collectionData.lencoReference,
            status: collectionData.status,
            operator: collectionData.mobileMoneyDetails?.operator,
          },
        };
      } else {
        logger.warn('Lenco payment initiation returned non-success status', {
          reference,
          responseStatus: response.data.status,
          message: response.data.message,
          fullResponse: JSON.stringify(response.data),
        });
        
        return {
          success: false,
          transaction_id: reference,
          message: response.data.message || 'Payment initiation failed',
          data: response.data,
        };
      }
    } catch (error: any) {
      logger.error('Failed to initiate mobile money payment', {
        error: error.message,
        reference: paymentData.booking_id,
        response: error.response?.data,
      });
      return {
        success: false,
        transaction_id: '',
        message: error.response?.data?.message || 'Payment initiation failed',
      };
    }
  }

  async verifyPayment(reference: string): Promise<PaymentVerificationResponse> {
    try {
      const response = await this.client.get(`/collections/${reference}`);

      logger.info('Payment verification completed', {
        reference,
        status: response.data.data?.status,
        amount: response.data.data?.amount,
      });

      if (response.data.status) {
        const collectionData = response.data.data;
        
        return {
          success: true,
          transaction_id: reference,
          status: collectionData.status,
          amount: parseFloat(collectionData.amount),
          currency: collectionData.currency,
          message: `Payment status: ${collectionData.status}`,
          data: {
            lencoReference: collectionData.lencoReference,
            completedAt: collectionData.completedAt,
            fee: collectionData.fee,
            operator: collectionData.mobileMoneyDetails?.operator,
            operatorTransactionId: collectionData.mobileMoneyDetails?.operatorTransactionId,
          },
        };
      } else {
        return {
          success: false,
          transaction_id: reference,
          status: 'failed',
          amount: 0,
          currency: 'ZMW',
          message: response.data.message || 'Payment verification failed',
        };
      }
    } catch (error: any) {
      logger.error('Failed to verify payment', {
        error: error.message,
        reference,
        response: error.response?.data,
      });
      return {
        success: false,
        transaction_id: reference,
        status: 'failed',
        amount: 0,
        currency: 'ZMW',
        message: error.response?.data?.message || 'Payment verification failed',
      };
    }
  }

  validateCallback(callbackData: any, signature: string): boolean {
    const generatedSignature = this.generateWebhookSignature(callbackData);
    return generatedSignature === signature;
  }

  async processCallback(webhookEvent: any): Promise<boolean> {
    try {
      logger.info('Processing Lenco webhook event', { event: webhookEvent.event });
      
      if (webhookEvent.event === 'collection.successful') {
        const collectionData = webhookEvent.data;
        logger.info('Collection successful', {
          reference: collectionData.reference,
          amount: collectionData.amount,
          operator: collectionData.mobileMoneyDetails?.operator,
        });
        return true;
      } else if (webhookEvent.event === 'collection.failed') {
        const collectionData = webhookEvent.data;
        logger.warn('Collection failed', {
          reference: collectionData.reference,
          reason: collectionData.reasonForFailure,
        });
        return false;
      }
      
      return false;
    } catch (error) {
      logger.error('Callback processing error', { error });
      return false;
    }
  }

  async getCollectionByReference(reference: string): Promise<any> {
    try {
      const response = await this.client.get(`/collections/${reference}`);
      
      if (response.data.status) {
        return {
          success: true,
          data: response.data.data,
          message: 'Collection retrieved successfully',
        };
      } else {
        return {
          success: false,
          message: response.data.message || 'Failed to retrieve collection',
        };
      }
    } catch (error: any) {
      logger.error('Get collection error', {
        error: error.message,
        reference,
        response: error.response?.data,
      });
      return {
        success: false,
        message: error.response?.data?.message || 'Failed to retrieve collection',
      };
    }
  }

  async initiateRefund(collectionId: string, amount: number, reason: string): Promise<any> {
    try {
      const payload = {
        amount: amount.toString(),
        reason: reason,
      };

      const response = await this.client.post(`/collections/${collectionId}/refund`, payload);

      return {
        success: response.data.status === true,
        message: response.data.message,
        data: response.data.data,
      };
    } catch (error: any) {
      logger.error('Lenco refund error', {
        error: error.message,
        collectionId,
        response: error.response?.data,
      });
      return {
        success: false,
        message: error.response?.data?.message || 'Refund failed',
      };
    }
  }

  async initiatePayout(payoutData: {
    amount: number;
    payment_method: string;
    payment_phone: string;
    reference: string;
    account_id?: string;
  }): Promise<any> {
    try {
      const formattedPhone = this.formatPhoneNumber(payoutData.payment_phone);
      const operator = payoutData.payment_method;

      logger.info('Initiating Lenco transfer', {
        amount: payoutData.amount,
        operator,
        phone: '***' + formattedPhone.slice(-4),
        reference: payoutData.reference,
      });

      // Get Lenco account ID from config or parameter
      const accountId = payoutData.account_id || config.lencopay.accountId;
      
      if (!accountId) {
        logger.error('Lenco account ID not configured', {
          reference: payoutData.reference,
        });
        return {
          success: false,
          message: 'Lenco account ID not configured. Please set LENCOPAY_ACCOUNT_ID environment variable.',
        };
      }

      // Build payload according to Lencopay API specification
      const payload: any = {
        accountId: accountId, // Required: 36-character account UUID
        amount: payoutData.amount.toString(),
        narration: 'VibeLinx provider withdrawal',
        reference: payoutData.reference,
        phone: formattedPhone,
        operator: operator,
        country: 'zm',
      };

      logger.info('Lenco transfer payload prepared', {
        endpoint: '/transfers/mobile-money',
        hasAccountId: !!payoutData.account_id,
        operator,
        country: 'zm',
      });

      // POST /transfers/mobile-money - Lencopay official endpoint
      const response = await this.client.post('/transfers/mobile-money', payload);

      logger.info('Lenco transfer response received', {
        reference: payoutData.reference,
        status: response.data.status,
        transferStatus: response.data.data?.status,
        lencoReference: response.data.data?.lencoReference,
      });

      // Lencopay returns: { status: boolean, message: string, data: {...} }
      if (response.data.status === true && response.data.data) {
        const transferData = response.data.data;
        
        return {
          success: true,
          message: response.data.message || 'Transfer initiated successfully',
          data: {
            id: transferData.id,
            lencoReference: transferData.lencoReference,
            reference: transferData.reference,
            status: transferData.status, // 'pending' | 'successful' | 'failed'
            amount: transferData.amount,
            fee: transferData.fee,
            currency: transferData.currency,
            initiatedAt: transferData.initiatedAt,
            completedAt: transferData.completedAt,
            creditAccount: transferData.creditAccount,
            reasonForFailure: transferData.reasonForFailure,
          },
        };
      } else {
        logger.warn('Lenco transfer initiation returned non-success', {
          status: response.data.status,
          message: response.data.message,
        });
        
        return {
          success: false,
          message: response.data.message || 'Transfer initiation failed',
          data: response.data,
        };
      }
    } catch (error: any) {
      logger.error('Failed to initiate transfer', {
        error: error.message,
        reference: payoutData.reference,
        statusCode: error.response?.status,
        statusText: error.response?.statusText,
        responseData: error.response?.data,
        url: error.config?.url,
        method: error.config?.method,
      });
      
      // Provide helpful error message based on Lencopay response
      let errorMessage = 'Transfer initiation failed';
      
      if (error.response?.status === 400) {
        // Bad request - validation error
        errorMessage = error.response.data?.message || 'Invalid transfer request. Please check phone number and operator.';
      } else if (error.response?.status === 401) {
        errorMessage = 'Lencopay authentication failed. Please check API credentials.';
      } else if (error.response?.status === 404) {
        errorMessage = 'Lencopay transfer endpoint not found. Please verify API configuration.';
      } else if (error.response?.status === 403) {
        errorMessage = 'Insufficient permissions or insufficient balance in Lenco account.';
      } else if (error.response?.data?.message) {
        errorMessage = error.response.data.message;
      }
      
      return {
        success: false,
        message: errorMessage,
        error: error.response?.data,
      };
    }
  }

  async verifyPayout(reference: string): Promise<any> {
    try {
      // GET /transfers/status/:reference - Lencopay official endpoint
      const response = await this.client.get(`/transfers/status/${reference}`);

      logger.info('Transfer verification completed', {
        reference,
        status: response.data.data?.status,
        amount: response.data.data?.amount,
        completedAt: response.data.data?.completedAt,
      });

      if (response.data.status && response.data.data) {
        const transferData = response.data.data;
        
        return {
          success: true,
          status: transferData.status, // 'pending' | 'successful' | 'failed'
          amount: parseFloat(transferData.amount),
          fee: parseFloat(transferData.fee || '0'),
          message: `Transfer status: ${transferData.status}`,
          data: {
            id: transferData.id,
            lencoReference: transferData.lencoReference,
            reference: transferData.reference,
            initiatedAt: transferData.initiatedAt,
            completedAt: transferData.completedAt,
            creditAccount: transferData.creditAccount,
            reasonForFailure: transferData.reasonForFailure,
            currency: transferData.currency,
          },
        };
      } else {
        return {
          success: false,
          status: 'unknown',
          message: response.data.message || 'Transfer verification failed',
        };
      }
    } catch (error: any) {
      logger.error('Failed to verify transfer', {
        error: error.message,
        reference,
        statusCode: error.response?.status,
        responseData: error.response?.data,
      });
      
      // Handle 404 - transfer not found
      if (error.response?.status === 404) {
        return {
          success: false,
          status: 'not_found',
          message: 'Transfer not found with the provided reference',
        };
      }
      
      return {
        success: false,
        status: 'error',
        message: error.response?.data?.message || 'Transfer verification failed',
      };
    }
  }
}

export const lencopayService = new LencopayService();
