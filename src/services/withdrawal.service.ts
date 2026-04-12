import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';
import { walletService } from './wallet.service';
import { pawapayService } from './pawapay.service';
import { settingsService } from './settings.service';

interface CreateWithdrawalRequest {
  user_id: string;
  wallet_id: string;
  amount: number;
  payment_method: 'mtn' | 'airtel' | 'zamtel';
  payment_phone: string;
  save_payout_method?: boolean;
}

interface WithdrawalFee {
  min: number;
  max: number;
  tier: string;
  averageFee: number;
}

class WithdrawalService {
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

  calculateWithdrawalFee(amount: number): WithdrawalFee {
    if (amount < 0) {
      throw new Error('Invalid withdrawal amount');
    }

    if (amount >= 0 && amount <= 1000) {
      return { 
        min: 8.50, 
        max: 12, 
        tier: 'tier_1',
        averageFee: 10.25 // Use average for calculation
      };
    } else if (amount > 1000 && amount <= 50000) {
      return { 
        min: 15, 
        max: 25, 
        tier: 'tier_2',
        averageFee: 20 // Use average for calculation
      };
    } else if (amount > 50000 && amount <= 100000000) {
      return { 
        min: 35, 
        max: 35, 
        tier: 'tier_3',
        averageFee: 35
      };
    }
    
    throw new Error('Withdrawal amount exceeds maximum limit');
  }

  async createWithdrawalRequest(data: CreateWithdrawalRequest): Promise<{ withdrawal: any | null; error: any }> {
    try {
      logger.info('Creating withdrawal request', {
        userId: data.user_id,
        amount: data.amount,
        paymentMethod: data.payment_method,
      });

      // Validate minimum withdrawal amount (dynamic from settings)
      const minWithdrawalAmount = await settingsService.getMinWithdrawalAmount();
      if (data.amount < minWithdrawalAmount) {
        return { 
          withdrawal: null, 
          error: { message: `Minimum withdrawal amount is K${minWithdrawalAmount}`, code: 'MIN_AMOUNT_ERROR' }
        };
      }

      // Get wallet and verify ownership
      const { wallet, error: walletError } = await walletService.getWalletById(data.wallet_id);
      
      if (walletError || !wallet) {
        return { withdrawal: null, error: walletError || new Error('Wallet not found') };
      }

      if (wallet.user_id !== data.user_id) {
        return { withdrawal: null, error: new Error('Unauthorized wallet access') };
      }

      // Calculate fees
      const feeInfo = this.calculateWithdrawalFee(data.amount);
      const feeAmount = feeInfo.averageFee;
      const netAmount = data.amount - feeAmount;
      const totalDeduction = data.amount; // Total to deduct from wallet

      // Check if sufficient balance
      const availableBalance = parseFloat(wallet.available_balance);
      if (availableBalance < totalDeduction) {
        return { 
          withdrawal: null, 
          error: { 
            message: 'Insufficient balance',
            code: 'INSUFFICIENT_BALANCE',
            required: totalDeduction,
            available: availableBalance
          }
        };
      }

      // Generate unique reference
      const reference = `VBL-WD-${Date.now()}-${Math.random().toString(36).substr(2, 9).toUpperCase()}`;

      // Create withdrawal request
      const { data: withdrawal, error: insertError } = await this.supabase
        .from('withdrawal_requests')
        .insert({
          wallet_id: data.wallet_id,
          user_id: data.user_id,
          amount: data.amount,
          fee_amount: feeAmount,
          net_amount: netAmount,
          fee_tier: feeInfo.tier,
          payment_method: data.payment_method,
          payment_phone: data.payment_phone,
          lenco_reference: reference,
          status: 'pending',
          metadata: {
            fee_min: feeInfo.min,
            fee_max: feeInfo.max,
            fee_tier: feeInfo.tier,
          }
        })
        .select()
        .single();

      if (insertError) {
        logger.error('Error creating withdrawal request:', insertError);
        return { withdrawal: null, error: insertError };
      }

      logger.info('Withdrawal request created', {
        withdrawalId: withdrawal.id,
        reference,
        amount: data.amount,
        feeAmount,
        netAmount,
      });

      // Process withdrawal immediately (auto-process)
      const processResult = await this.processWithdrawal(withdrawal.id);
      
      if (!processResult.success) {
        logger.error('Failed to process withdrawal', { error: processResult.error });
        // Update status to failed
        await this.updateWithdrawalStatus(withdrawal.id, 'failed', processResult.error?.message);
        return { withdrawal: null, error: processResult.error };
      }

      return { withdrawal, error: null };
    } catch (error) {
      logger.error('Unexpected error creating withdrawal request:', error);
      return { withdrawal: null, error };
    }
  }

  async processWithdrawal(withdrawalId: string): Promise<{ success: boolean; error: any; timeout?: boolean }> {
    try {
      logger.info('Processing withdrawal', { withdrawalId });

      // Get withdrawal request
      const { data: withdrawal, error: fetchError } = await this.supabase
        .from('withdrawal_requests')
        .select('*')
        .eq('id', withdrawalId)
        .single();

      if (fetchError || !withdrawal) {
        return { success: false, error: fetchError || new Error('Withdrawal not found') };
      }

      if (withdrawal.status !== 'pending') {
        return { success: false, error: new Error('Withdrawal already processed') };
      }

      // Update status to processing
      await this.updateWithdrawalStatus(withdrawalId, 'processing');

      // Deduct from wallet first (total amount including fee)
      const deductResult = await walletService.deductFromWallet({
        wallet_id: withdrawal.wallet_id,
        amount: withdrawal.amount, // Deduct full requested amount
        reference_id: withdrawalId,
        reference_type: 'withdrawal',
        description: `Withdrawal request - K${withdrawal.net_amount.toFixed(2)} (Fee: K${withdrawal.fee_amount.toFixed(2)})`,
      });

      if (!deductResult.success) {
        logger.error('Failed to deduct from wallet', { error: deductResult.error });
        await this.updateWithdrawalStatus(withdrawalId, 'failed', 'Failed to deduct from wallet');
        return { success: false, error: deductResult.error };
      }

      // Record withdrawal fee transaction
      await walletService.recordWalletTransaction({
        wallet_id: withdrawal.wallet_id,
        transaction_type: 'withdrawal',
        amount: withdrawal.fee_amount,
        balance_before: 0, // Already deducted in main transaction
        balance_after: 0,
        reference_id: withdrawalId,
        reference_type: 'withdrawal',
        description: `Withdrawal fee (${withdrawal.fee_tier})`,
      });

      // Initiate PawaPay payout
      const payoutResult = await pawapayService.initiatePayout({
        amount: withdrawal.net_amount,
        payment_method: withdrawal.payment_method,
        payment_phone: withdrawal.payment_phone,
        reference: withdrawal.lenco_reference,
      });

      if (!payoutResult.success) {
        const isTimeout = payoutResult.message?.includes('timeout') || payoutResult.error?.code === 'ECONNABORTED';
        
        if (isTimeout) {
          // Timeout - transfer may still succeed, wait for webhook
          logger.warn('PawaPay transfer timeout - waiting for webhook confirmation', {
            withdrawalId,
            reference: withdrawal.lenco_reference,
          });
          
          // Keep status as 'processing' - webhook will update it
          await this.supabase
            .from('withdrawal_requests')
            .update({
              status: 'processing',
              metadata: {
                timeout: true,
                timeout_at: new Date().toISOString(),
                message: 'Transfer initiated but response timed out. Awaiting webhook confirmation.',
              },
              updated_at: new Date().toISOString(),
            })
            .eq('id', withdrawalId);
          
          // Return success - webhook will handle final status
          return { success: true, error: null, timeout: true };
        } else {
          // Actual failure (validation error, insufficient balance, etc.)
          logger.error('PawaPay payout failed', { error: payoutResult.message });
          
          // Refund to wallet only for actual failures
          await walletService.creditWallet({
            wallet_id: withdrawal.wallet_id,
            amount: withdrawal.amount,
            transaction_id: withdrawalId,
            description: 'Withdrawal failed - refunded',
          });

          await this.updateWithdrawalStatus(withdrawalId, 'failed', payoutResult.message);
          return { success: false, error: new Error(payoutResult.message) };
        }
      }

      // Update withdrawal with PawaPay details
      await this.supabase
        .from('withdrawal_requests')
        .update({
          lenco_payout_id: payoutResult.data?.payoutId || payoutResult.data?.id,
          status: 'processing',
          updated_at: new Date().toISOString(),
        })
        .eq('id', withdrawalId);

      logger.info('Withdrawal processing initiated', {
        withdrawalId,
        pawapayPayoutId: payoutResult.data?.payoutId,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error processing withdrawal:', error);
      return { success: false, error };
    }
  }

  async updateWithdrawalStatus(
    withdrawalId: string, 
    status: string, 
    failureReason?: string,
    externalTransactionId?: string
  ): Promise<{ success: boolean; error: any }> {
    try {
      const updates: any = {
        status,
        updated_at: new Date().toISOString(),
      };

      if (status === 'completed') {
        updates.processed_at = new Date().toISOString();
      }

      if (failureReason) {
        updates.failure_reason = failureReason;
      }

      if (externalTransactionId) {
        updates.external_transaction_id = externalTransactionId;
      }

      const { error } = await this.supabase
        .from('withdrawal_requests')
        .update(updates)
        .eq('id', withdrawalId);

      if (error) {
        logger.error('Error updating withdrawal status:', error);
        return { success: false, error };
      }

      logger.info('Withdrawal status updated', { withdrawalId, status });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error updating withdrawal status:', error);
      return { success: false, error };
    }
  }

  async getWithdrawalsByUserId(userId: string, limit: number = 50): Promise<{ withdrawals: any[]; error: any }> {
    try {
      const { data: withdrawals, error } = await this.supabase
        .from('withdrawal_requests')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) {
        logger.error('Error fetching withdrawals:', error);
        return { withdrawals: [], error };
      }

      return { withdrawals: withdrawals || [], error: null };
    } catch (error) {
      logger.error('Unexpected error fetching withdrawals:', error);
      return { withdrawals: [], error };
    }
  }

  async getWithdrawalById(withdrawalId: string): Promise<{ withdrawal: any | null; error: any }> {
    try {
      const { data: withdrawal, error } = await this.supabase
        .from('withdrawal_requests')
        .select('*')
        .eq('id', withdrawalId)
        .single();

      if (error) {
        logger.error('Error fetching withdrawal:', error);
        return { withdrawal: null, error };
      }

      return { withdrawal, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching withdrawal:', error);
      return { withdrawal: null, error };
    }
  }

  async handlePayoutWebhook(webhookData: any): Promise<{ success: boolean; error: any }> {
    try {
      const { reference, status, externalTransactionId } = webhookData;

      logger.info('Processing payout webhook', { reference, status });

      // Find withdrawal by reference
      const { data: withdrawal, error: fetchError } = await this.supabase
        .from('withdrawal_requests')
        .select('*')
        .eq('lenco_reference', reference)
        .single();

      if (fetchError || !withdrawal) {
        logger.error('Withdrawal not found for webhook', { reference });
        return { success: false, error: fetchError || new Error('Withdrawal not found') };
      }

      if (status === 'successful' || status === 'completed') {
        await this.updateWithdrawalStatus(
          withdrawal.id, 
          'completed',
          undefined,
          externalTransactionId
        );
        
        // Update wallet total_withdrawn
        await this.supabase.rpc('increment_total_withdrawn', {
          p_wallet_id: withdrawal.wallet_id,
          p_amount: withdrawal.net_amount
        });

        logger.info('Withdrawal completed successfully', { withdrawalId: withdrawal.id });
      } else if (status === 'failed') {
        // Refund to wallet
        await walletService.creditWallet({
          wallet_id: withdrawal.wallet_id,
          amount: withdrawal.amount,
          transaction_id: withdrawal.id,
          description: 'Withdrawal failed - refunded',
        });

        await this.updateWithdrawalStatus(
          withdrawal.id, 
          'failed',
          webhookData.failureReason || 'Payout failed'
        );

        logger.warn('Withdrawal failed, refunded to wallet', { withdrawalId: withdrawal.id });
      }

      return { success: true, error: null };
    } catch (error) {
      logger.error('Error handling payout webhook:', error);
      return { success: false, error };
    }
  }
}

export const withdrawalService = new WithdrawalService();
