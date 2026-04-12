import axios, { AxiosInstance } from 'axios';
import { v4 as uuidv4 } from 'uuid';
import { config } from '../config';
import { logger } from '../utils/logger';
import {
  PaymentInitiationRequest,
  PaymentInitiationResponse,
  PaymentVerificationResponse,
} from '../types';

interface PawapayDepositRequest {
  depositId: string;
  payer: {
    type: 'MMO';
    accountDetails: {
      phoneNumber: string;
      provider: string;
    };
  };
  amount: string;
  currency: string;
  clientReferenceId: string;
  customerMessage?: string;
  metadata?: Array<Record<string, any>>;
}

interface PawapayPayoutRequest {
  payoutId: string;
  recipient: {
    type: 'MMO';
    accountDetails: {
      phoneNumber: string;
      provider: string;
    };
  };
  amount: string;
  currency: string;
  clientReferenceId: string;
  customerMessage?: string;
  metadata?: Array<Record<string, any>>;
}

interface PawapayDepositResponse {
  depositId: string;
  status: 'ACCEPTED' | 'SUBMITTED' | 'COMPLETED' | 'FAILED' | 'REJECTED';
  created: string;
  amount?: string;
  currency?: string;
  payer?: any;
  failureReason?: {
    failureMessage: string;
    failureCode: string;
  };
}

interface PawapayPayoutResponse {
  payoutId: string;
  status: 'ACCEPTED' | 'SUBMITTED' | 'COMPLETED' | 'FAILED' | 'REJECTED';
  created: string;
  amount?: string;
  currency?: string;
  recipient?: any;
  failureReason?: {
    failureMessage: string;
    failureCode: string;
  };
}

class PawapayService {
  private client: AxiosInstance;
  private apiToken: string;

  constructor() {
    this.apiToken = config.pawapay.apiToken;

    logger.info('Initializing PawaPay Service', {
      baseURL: config.pawapay.baseUrl,
      hasApiToken: !!this.apiToken,
      apiTokenLength: this.apiToken?.length || 0,
    });

    this.client = axios.create({
      baseURL: config.pawapay.baseUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiToken}`,
      },
      timeout: 60000,
    });

    this.client.interceptors.request.use(
      (config) => {
        logger.debug('PawaPay API Request', {
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
        logger.error('PawaPay API Request Error', { error: error.message });
        return Promise.reject(error);
      }
    );

    this.client.interceptors.response.use(
      (response) => {
        logger.debug('PawaPay API Response', {
          status: response.status,
          data: response.data,
        });
        return response;
      },
      (error) => {
        logger.error('PawaPay API Request Failed', {
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

  private formatPhoneNumber(phone: string, countryCode: string = '260'): string {
    let cleaned = phone.replace(/[\s\-\(\)]/g, '');
    cleaned = cleaned.replace(/^0+/, '');
    
    if (cleaned.startsWith(countryCode)) {
      return cleaned;
    }
    
    return `${countryCode}${cleaned}`;
  }

  private mapOperatorToProvider(operator: string): string {
    const operatorMap: Record<string, string> = {
      'mtn': 'MTN_MOMO_ZMB',
      'airtel': 'AIRTEL_OAPI_ZMB',
      'zamtel': 'ZAMTEL_ZMB',
    };

    const provider = operatorMap[operator.toLowerCase()];
    if (!provider) {
      logger.warn('Unknown operator, defaulting to MTN', { operator });
      return 'MTN_MOMO_ZMB';
    }

    return provider;
  }

  private mapPawapayStatusToInternal(status: string): string {
    const statusMap: Record<string, string> = {
      'ACCEPTED': 'pending',
      'SUBMITTED': 'processing',
      'COMPLETED': 'completed',
      'FAILED': 'failed',
      'REJECTED': 'failed',
    };

    return statusMap[status] || 'pending';
  }

  async initiateDeposit(paymentData: PaymentInitiationRequest): Promise<PaymentInitiationResponse> {
    try {
      const depositId = uuidv4();
      const reference = paymentData.reference || `VBL-${Date.now()}`;
      const formattedPhone = this.formatPhoneNumber(paymentData.customer_phone);
      const provider = this.mapOperatorToProvider(paymentData.payment_method);

      logger.debug('Deposit initiation details', {
        depositId,
        original: paymentData.customer_phone,
        formatted: formattedPhone,
        provider,
        amount: paymentData.amount,
        reference,
      });

      const payload: PawapayDepositRequest = {
        depositId,
        payer: {
          type: 'MMO',
          accountDetails: {
            phoneNumber: formattedPhone,
            provider,
          },
        },
        amount: paymentData.amount.toString(),
        currency: paymentData.currency || 'ZMW',
        clientReferenceId: reference,
        customerMessage: 'VibeLinx Payment',
        metadata: [
          {
            paymentType: paymentData.payment_type,
            bookingId: paymentData.booking_id,
          },
        ],
      };

      const response = await this.client.post<PawapayDepositResponse>('/v2/deposits', payload);

      logger.info('PawaPay Deposit Response', {
        depositId,
        status: response.data.status,
        created: response.data.created,
      });

      const internalStatus = this.mapPawapayStatusToInternal(response.data.status);

      return {
        success: response.data.status === 'ACCEPTED' || response.data.status === 'SUBMITTED',
        transaction_id: reference,
        message: response.data.status === 'ACCEPTED'
          ? 'Payment initiated. Please authorize on your mobile phone.'
          : response.data.status === 'SUBMITTED'
          ? 'Payment submitted. Processing...'
          : response.data.status === 'COMPLETED'
          ? 'Payment completed successfully.'
          : response.data.failureReason?.failureMessage || 'Payment failed',
        data: {
          depositId,
          pawapayStatus: response.data.status,
          status: internalStatus,
          created: response.data.created,
          provider,
          failureReason: response.data.failureReason,
        },
      };
    } catch (error: any) {
      logger.error('Failed to initiate deposit', {
        error: error.message,
        response: error.response?.data,
      });
      return {
        success: false,
        transaction_id: '',
        message: error.response?.data?.message || 'Deposit initiation failed',
      };
    }
  }

  async checkDepositStatus(depositId: string): Promise<PaymentVerificationResponse> {
    try {
      const response = await this.client.get<PawapayDepositResponse>(`/v2/deposits/${depositId}`);

      logger.info('Deposit status check completed', {
        depositId,
        status: response.data.status,
        amount: response.data.amount,
      });

      const internalStatus = this.mapPawapayStatusToInternal(response.data.status);

      return {
        success: true,
        transaction_id: depositId,
        status: internalStatus,
        amount: parseFloat(response.data.amount || '0'),
        currency: response.data.currency || 'ZMW',
        message: `Deposit status: ${response.data.status}`,
        data: {
          depositId,
          pawapayStatus: response.data.status,
          created: response.data.created,
          failureReason: response.data.failureReason,
        },
      };
    } catch (error: any) {
      logger.error('Failed to check deposit status', {
        error: error.message,
        depositId,
        response: error.response?.data,
      });
      return {
        success: false,
        transaction_id: depositId,
        status: 'failed',
        amount: 0,
        currency: 'ZMW',
        message: error.response?.data?.message || 'Deposit status check failed',
      };
    }
  }

  async initiatePayout(payoutData: {
    amount: number;
    payment_method: string;
    payment_phone: string;
    reference: string;
  }): Promise<any> {
    try {
      const payoutId = uuidv4();
      const formattedPhone = this.formatPhoneNumber(payoutData.payment_phone);
      const provider = this.mapOperatorToProvider(payoutData.payment_method);

      logger.info('Initiating PawaPay payout', {
        payoutId,
        amount: payoutData.amount,
        provider,
        phone: '***' + formattedPhone.slice(-4),
        reference: payoutData.reference,
      });

      const payload: PawapayPayoutRequest = {
        payoutId,
        recipient: {
          type: 'MMO',
          accountDetails: {
            phoneNumber: formattedPhone,
            provider,
          },
        },
        amount: payoutData.amount.toString(),
        currency: 'ZMW',
        clientReferenceId: payoutData.reference,
        customerMessage: 'VibeLinx Withdrawal',
        metadata: [
          {
            type: 'provider_withdrawal',
          },
        ],
      };

      const response = await this.client.post<PawapayPayoutResponse>('/v2/payouts', payload);

      logger.info('PawaPay Payout Response', {
        payoutId,
        status: response.data.status,
        created: response.data.created,
      });

      const internalStatus = this.mapPawapayStatusToInternal(response.data.status);

      if (response.data.status === 'ACCEPTED' || response.data.status === 'SUBMITTED') {
        return {
          success: true,
          message: 'Payout initiated successfully',
          data: {
            id: payoutId,
            payoutId,
            reference: payoutData.reference,
            status: internalStatus,
            pawapayStatus: response.data.status,
            amount: payoutData.amount.toString(),
            currency: 'ZMW',
            created: response.data.created,
          },
        };
      } else {
        return {
          success: false,
          message: response.data.failureReason?.failureMessage || 'Payout initiation failed',
          data: {
            payoutId,
            status: internalStatus,
            failureReason: response.data.failureReason,
          },
        };
      }
    } catch (error: any) {
      logger.error('Failed to initiate payout', {
        error: error.message,
        reference: payoutData.reference,
        statusCode: error.response?.status,
        responseData: error.response?.data,
      });

      let errorMessage = 'Payout initiation failed';

      if (error.response?.status === 400) {
        errorMessage = error.response.data?.message || 'Invalid payout request. Please check phone number and provider.';
      } else if (error.response?.status === 401) {
        errorMessage = 'PawaPay authentication failed. Please check API credentials.';
      } else if (error.response?.status === 403) {
        errorMessage = 'Insufficient permissions or insufficient balance.';
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

  async checkPayoutStatus(payoutId: string): Promise<any> {
    try {
      const response = await this.client.get<PawapayPayoutResponse>(`/v2/payouts/${payoutId}`);

      logger.info('Payout status check completed', {
        payoutId,
        status: response.data.status,
        amount: response.data.amount,
      });

      const internalStatus = this.mapPawapayStatusToInternal(response.data.status);

      return {
        success: true,
        status: internalStatus,
        pawapayStatus: response.data.status,
        amount: parseFloat(response.data.amount || '0'),
        message: `Payout status: ${response.data.status}`,
        data: {
          payoutId,
          created: response.data.created,
          failureReason: response.data.failureReason,
          currency: response.data.currency,
        },
      };
    } catch (error: any) {
      logger.error('Failed to check payout status', {
        error: error.message,
        payoutId,
        statusCode: error.response?.status,
        responseData: error.response?.data,
      });

      if (error.response?.status === 404) {
        return {
          success: false,
          status: 'not_found',
          message: 'Payout not found with the provided ID',
        };
      }

      return {
        success: false,
        status: 'error',
        message: error.response?.data?.message || 'Payout status check failed',
      };
    }
  }

  async handleWebhook(webhookEvent: any): Promise<boolean> {
    try {
      logger.info('Processing PawaPay webhook event', { event: webhookEvent });

      return true;
    } catch (error) {
      logger.error('Webhook processing error', { error });
      return false;
    }
  }

  async getActiveConfiguration(country?: string, operationType?: 'DEPOSIT' | 'PAYOUT'): Promise<any> {
    try {
      const params = new URLSearchParams();
      if (country) params.append('country', country);
      if (operationType) params.append('operationType', operationType);

      const url = `/v2/active-conf${params.toString() ? `?${params.toString()}` : ''}`;
      
      logger.info('Fetching active configuration', { country, operationType, url });

      const response = await this.client.get(url);

      logger.info('Active configuration fetched successfully', {
        country,
        operationType,
        countriesCount: response.data.countries?.length,
      });

      return {
        success: true,
        data: response.data,
      };
    } catch (error: any) {
      logger.error('Failed to fetch active configuration', {
        error: error.message,
        country,
        operationType,
        statusCode: error.response?.status,
        responseData: error.response?.data,
      });

      return {
        success: false,
        message: error.response?.data?.message || 'Failed to fetch active configuration',
        error: error.response?.data,
      };
    }
  }

  async predictProvider(phoneNumber: string): Promise<any> {
    try {
      logger.info('Predicting provider for phone number', {
        phoneNumber: phoneNumber?.substring(0, 6) + '***',
      });

      const response = await this.client.post('/v2/predict-provider', {
        phoneNumber,
      });

      logger.info('Provider prediction successful', {
        country: response.data.country,
        provider: response.data.provider,
      });

      return {
        success: true,
        data: response.data,
      };
    } catch (error: any) {
      logger.error('Failed to predict provider', {
        error: error.message,
        statusCode: error.response?.status,
        responseData: error.response?.data,
      });

      return {
        success: false,
        message: error.response?.data?.message || 'Failed to predict provider',
        error: error.response?.data,
      };
    }
  }
}

export const pawapayService = new PawapayService();
