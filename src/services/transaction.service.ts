import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';

interface CreateTransactionData {
  user_id: string;
  amount: number;
  transaction_type: 'booking_commitment' | 'booking_balance' | 'booking_full' | 'subscription' | 'wallet_topup';
  payment_type: 'commitment' | 'balance' | 'full' | 'subscription';
  payment_method: 'mtn' | 'airtel' | 'zamtel';
  payment_phone: string;
  reference_number: string;
  external_transaction_id: string;
  metadata: {
    booking_data?: any;
    subscription_data?: any;
    payment_info?: any;
  };
  description?: string;
}

class TransactionService {
  private supabase;

  constructor() {
    this.supabase = createClient(
      config.supabase.url,
      config.supabase.serviceKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    );
  }

  async createTransaction(data: CreateTransactionData): Promise<{ transaction: any | null; error: any }> {
    try {
      const { data: transaction, error } = await this.supabase
        .from('transactions')
        .insert({
          user_id: data.user_id,
          amount: data.amount,
          type: 'payment',
          transaction_type: data.transaction_type,
          payment_type: data.payment_type,
          status: 'pending',
          payment_method: data.payment_method,
          payment_phone: data.payment_phone,
          reference_number: data.reference_number,
          external_transaction_id: data.external_transaction_id,
          metadata: data.metadata,
          description: data.description || `${data.transaction_type} payment`,
        })
        .select()
        .single();

      if (error) {
        logger.error('Error creating transaction:', error);
        return { transaction: null, error };
      }

      logger.info('Transaction created successfully', {
        transactionId: transaction.id,
        type: data.transaction_type,
        amount: data.amount,
      });

      return { transaction, error: null };
    } catch (error) {
      logger.error('Unexpected error creating transaction:', error);
      return { transaction: null, error };
    }
  }

  async updateTransactionStatus(
    transactionId: string,
    status: 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled',
    externalStatus?: string,
    errorMessage?: string
  ): Promise<{ error: any }> {
    try {
      const updates: any = {
        status,
        external_status: externalStatus,
        updated_at: new Date().toISOString(),
      };

      if (errorMessage) {
        updates.error_message = errorMessage;
      }

      const { error } = await this.supabase
        .from('transactions')
        .update(updates)
        .eq('id', transactionId);

      if (error) {
        logger.error('Error updating transaction status:', error);
        return { error };
      }

      logger.info('Transaction status updated', {
        transactionId,
        status,
      });

      return { error: null };
    } catch (error) {
      logger.error('Unexpected error updating transaction:', error);
      return { error };
    }
  }

  async getTransactionByReference(reference: string): Promise<{ transaction: any | null; error: any }> {
    try {
      const { data: transaction, error } = await this.supabase
        .from('transactions')
        .select('*')
        .eq('reference_number', reference)
        .single();

      if (error) {
        logger.error('Error fetching transaction by reference:', error);
        return { transaction: null, error };
      }

      return { transaction, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching transaction:', error);
      return { transaction: null, error };
    }
  }

  async getTransactionByExternalId(externalId: string): Promise<{ transaction: any | null; error: any }> {
    try {
      const { data: transaction, error } = await this.supabase
        .from('transactions')
        .select('*')
        .eq('external_transaction_id', externalId)
        .single();

      if (error) {
        logger.error('Error fetching transaction by external ID:', error);
        return { transaction: null, error };
      }

      return { transaction, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching transaction:', error);
      return { transaction: null, error };
    }
  }

  async getTransactionById(transactionId: string): Promise<{ transaction: any | null; error: any }> {
    try {
      const { data: transaction, error } = await this.supabase
        .from('transactions')
        .select('*')
        .eq('id', transactionId)
        .single();

      if (error) {
        logger.error('Error fetching transaction:', error);
        return { transaction: null, error };
      }

      return { transaction, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching transaction:', error);
      return { transaction: null, error };
    }
  }
}

export const transactionService = new TransactionService();
