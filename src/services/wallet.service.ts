import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';

interface CreateWalletData {
  user_id: string;
  user_type: 'client' | 'provider';
  currency?: string;
}

interface WalletDepositData {
  wallet_id: string;
  amount: number;
  transaction_id: string;
  description?: string;
  metadata?: any;
}

interface WalletDeductionData {
  wallet_id: string;
  amount: number;
  reference_id: string;
  reference_type: 'booking' | 'escrow' | 'withdrawal';
  description: string;
  metadata?: any;
}

class WalletService {
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

  async createWallet(data: CreateWalletData): Promise<{ wallet: any | null; error: any }> {
    try {
      const { data: existingWallet } = await this.supabase
        .from('wallets')
        .select('*')
        .eq('user_id', data.user_id)
        .eq('user_type', data.user_type)
        .single();

      if (existingWallet) {
        logger.info('Wallet already exists', {
          userId: data.user_id,
          userType: data.user_type,
          walletId: existingWallet.id,
        });
        return { wallet: existingWallet, error: null };
      }

      const { data: wallet, error } = await this.supabase
        .from('wallets')
        .insert({
          user_id: data.user_id,
          user_type: data.user_type,
          available_balance: 0,
          locked_balance: 0,
          total_deposited: 0,
          total_withdrawn: 0,
          currency: data.currency || 'ZMW',
          status: 'active',
        })
        .select()
        .single();

      if (error) {
        logger.error('Error creating wallet:', error);
        return { wallet: null, error };
      }

      logger.info('Wallet created successfully', {
        walletId: wallet.id,
        userId: data.user_id,
        userType: data.user_type,
      });

      return { wallet, error: null };
    } catch (error) {
      logger.error('Unexpected error creating wallet:', error);
      return { wallet: null, error };
    }
  }

  async getWalletByUserId(userId: string, userType: 'client' | 'provider'): Promise<{ wallet: any | null; error: any }> {
    try {
      const { data: wallet, error } = await this.supabase
        .from('wallets')
        .select('*')
        .eq('user_id', userId)
        .eq('user_type', userType)
        .single();

      if (error && error.code !== 'PGRST116') {
        logger.error('Error fetching wallet:', error);
        return { wallet: null, error };
      }

      if (!wallet) {
        const createResult = await this.createWallet({ user_id: userId, user_type: userType });
        return createResult;
      }

      return { wallet, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching wallet:', error);
      return { wallet: null, error };
    }
  }

  async getWalletById(walletId: string): Promise<{ wallet: any | null; error: any }> {
    try {
      const { data: wallet, error } = await this.supabase
        .from('wallets')
        .select('*')
        .eq('id', walletId)
        .single();

      if (error) {
        logger.error('Error fetching wallet by ID:', error);
        return { wallet: null, error };
      }

      return { wallet, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching wallet:', error);
      return { wallet: null, error };
    }
  }

  async creditWallet(data: WalletDepositData): Promise<{ success: boolean; error: any }> {
    try {
      const { wallet, error: walletError } = await this.getWalletById(data.wallet_id);
      
      if (walletError || !wallet) {
        logger.error('Wallet not found for credit', { walletId: data.wallet_id });
        return { success: false, error: walletError || new Error('Wallet not found') };
      }

      const balanceBefore = parseFloat(wallet.available_balance);
      const balanceAfter = balanceBefore + data.amount;
      const totalDeposited = parseFloat(wallet.total_deposited) + data.amount;

      const { error: updateError } = await this.supabase
        .from('wallets')
        .update({
          available_balance: balanceAfter,
          total_deposited: totalDeposited,
          updated_at: new Date().toISOString(),
        })
        .eq('id', data.wallet_id);

      if (updateError) {
        logger.error('Error updating wallet balance:', updateError);
        return { success: false, error: updateError };
      }

      await this.recordWalletTransaction({
        wallet_id: data.wallet_id,
        transaction_type: 'deposit',
        amount: data.amount,
        balance_before: balanceBefore,
        balance_after: balanceAfter,
        reference_id: data.transaction_id,
        reference_type: 'payment',
        description: data.description || 'Wallet deposit',
        metadata: data.metadata,
      });

      logger.info('Wallet credited successfully', {
        walletId: data.wallet_id,
        amount: data.amount,
        newBalance: balanceAfter,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error crediting wallet:', error);
      return { success: false, error };
    }
  }

  async deductFromWallet(data: WalletDeductionData): Promise<{ success: boolean; error: any }> {
    try {
      const { wallet, error: walletError } = await this.getWalletById(data.wallet_id);
      
      if (walletError || !wallet) {
        logger.error('Wallet not found for deduction', { walletId: data.wallet_id });
        return { success: false, error: walletError || new Error('Wallet not found') };
      }

      const balanceBefore = parseFloat(wallet.available_balance);
      
      if (balanceBefore < data.amount) {
        logger.warn('Insufficient wallet balance', {
          walletId: data.wallet_id,
          required: data.amount,
          available: balanceBefore,
        });
        return { success: false, error: new Error('Insufficient wallet balance') };
      }

      const balanceAfter = balanceBefore - data.amount;

      const { error: updateError } = await this.supabase
        .from('wallets')
        .update({
          available_balance: balanceAfter,
          updated_at: new Date().toISOString(),
        })
        .eq('id', data.wallet_id);

      if (updateError) {
        logger.error('Error deducting from wallet:', updateError);
        return { success: false, error: updateError };
      }

      await this.recordWalletTransaction({
        wallet_id: data.wallet_id,
        transaction_type: 'booking_deduction',
        amount: data.amount,
        balance_before: balanceBefore,
        balance_after: balanceAfter,
        reference_id: data.reference_id,
        reference_type: data.reference_type,
        description: data.description,
        metadata: data.metadata,
      });

      logger.info('Wallet deducted successfully', {
        walletId: data.wallet_id,
        amount: data.amount,
        newBalance: balanceAfter,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error deducting from wallet:', error);
      return { success: false, error };
    }
  }

  async lockFunds(walletId: string, amount: number, referenceId: string): Promise<{ success: boolean; error: any }> {
    try {
      const { wallet, error: walletError } = await this.getWalletById(walletId);
      
      if (walletError || !wallet) {
        return { success: false, error: walletError || new Error('Wallet not found') };
      }

      const availableBalance = parseFloat(wallet.available_balance);
      const lockedBalance = parseFloat(wallet.locked_balance);

      if (availableBalance < amount) {
        return { success: false, error: new Error('Insufficient available balance') };
      }

      const { error: updateError } = await this.supabase
        .from('wallets')
        .update({
          available_balance: availableBalance - amount,
          locked_balance: lockedBalance + amount,
          updated_at: new Date().toISOString(),
        })
        .eq('id', walletId);

      if (updateError) {
        logger.error('Error locking funds:', updateError);
        return { success: false, error: updateError };
      }

      await this.recordWalletTransaction({
        wallet_id: walletId,
        transaction_type: 'escrow_lock',
        amount: amount,
        balance_before: availableBalance,
        balance_after: availableBalance - amount,
        reference_id: referenceId,
        reference_type: 'escrow',
        description: 'Funds locked in escrow',
      });

      logger.info('Funds locked successfully', {
        walletId,
        amount,
        referenceId,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error locking funds:', error);
      return { success: false, error };
    }
  }

  async unlockFunds(walletId: string, amount: number, referenceId: string, releaseToBalance: boolean = false): Promise<{ success: boolean; error: any }> {
    try {
      const { wallet, error: walletError } = await this.getWalletById(walletId);
      
      if (walletError || !wallet) {
        return { success: false, error: walletError || new Error('Wallet not found') };
      }

      const availableBalance = parseFloat(wallet.available_balance);
      const lockedBalance = parseFloat(wallet.locked_balance);

      if (lockedBalance < amount) {
        return { success: false, error: new Error('Insufficient locked balance') };
      }

      const updates: any = {
        locked_balance: lockedBalance - amount,
        updated_at: new Date().toISOString(),
      };

      if (releaseToBalance) {
        updates.available_balance = availableBalance + amount;
      }

      const { error: updateError } = await this.supabase
        .from('wallets')
        .update(updates)
        .eq('id', walletId);

      if (updateError) {
        logger.error('Error unlocking funds:', updateError);
        return { success: false, error: updateError };
      }

      await this.recordWalletTransaction({
        wallet_id: walletId,
        transaction_type: releaseToBalance ? 'escrow_refund' : 'escrow_release',
        amount: amount,
        balance_before: availableBalance,
        balance_after: releaseToBalance ? availableBalance + amount : availableBalance,
        reference_id: referenceId,
        reference_type: 'escrow',
        description: releaseToBalance ? 'Escrow funds refunded' : 'Escrow funds released',
      });

      logger.info('Funds unlocked successfully', {
        walletId,
        amount,
        releaseToBalance,
        referenceId,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error unlocking funds:', error);
      return { success: false, error };
    }
  }

  async transferLockedFunds(fromWalletId: string, toWalletId: string, amount: number, referenceId: string): Promise<{ success: boolean; error: any }> {
    try {
      const unlockResult = await this.unlockFunds(fromWalletId, amount, referenceId, false);
      
      if (!unlockResult.success) {
        return unlockResult;
      }

      const { wallet: toWallet, error: toWalletError } = await this.getWalletById(toWalletId);
      
      if (toWalletError || !toWallet) {
        await this.lockFunds(fromWalletId, amount, referenceId);
        return { success: false, error: toWalletError || new Error('Recipient wallet not found') };
      }

      const toBalanceBefore = parseFloat(toWallet.available_balance);
      const toBalanceAfter = toBalanceBefore + amount;

      const { error: creditError } = await this.supabase
        .from('wallets')
        .update({
          available_balance: toBalanceAfter,
          updated_at: new Date().toISOString(),
        })
        .eq('id', toWalletId);

      if (creditError) {
        logger.error('Error crediting recipient wallet:', creditError);
        await this.lockFunds(fromWalletId, amount, referenceId);
        return { success: false, error: creditError };
      }

      await this.recordWalletTransaction({
        wallet_id: toWalletId,
        transaction_type: 'service_payment',
        amount: amount,
        balance_before: toBalanceBefore,
        balance_after: toBalanceAfter,
        reference_id: referenceId,
        reference_type: 'escrow',
        description: 'Payment received from escrow',
      });

      logger.info('Locked funds transferred successfully', {
        fromWalletId,
        toWalletId,
        amount,
        referenceId,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error transferring locked funds:', error);
      return { success: false, error };
    }
  }

  private async recordWalletTransaction(data: {
    wallet_id: string;
    transaction_type: string;
    amount: number;
    balance_before: number;
    balance_after: number;
    reference_id?: string;
    reference_type?: string;
    description?: string;
    metadata?: any;
  }): Promise<void> {
    try {
      await this.supabase
        .from('wallet_transactions')
        .insert({
          wallet_id: data.wallet_id,
          transaction_type: data.transaction_type,
          amount: data.amount,
          balance_before: data.balance_before,
          balance_after: data.balance_after,
          reference_id: data.reference_id,
          reference_type: data.reference_type,
          description: data.description,
          metadata: data.metadata,
        });
    } catch (error) {
      logger.error('Error recording wallet transaction:', error);
    }
  }

  async getWalletTransactions(walletId: string, limit: number = 50): Promise<{ transactions: any[]; error: any }> {
    try {
      const { data: transactions, error } = await this.supabase
        .from('wallet_transactions')
        .select('*')
        .eq('wallet_id', walletId)
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) {
        logger.error('Error fetching wallet transactions:', error);
        return { transactions: [], error };
      }

      return { transactions: transactions || [], error: null };
    } catch (error) {
      logger.error('Unexpected error fetching wallet transactions:', error);
      return { transactions: [], error };
    }
  }

  async getWalletBalance(userId: string, userType: 'client' | 'provider'): Promise<{ 
    available_balance: number; 
    locked_balance: number; 
    total_balance: number;
    error: any 
  }> {
    try {
      const { wallet, error } = await this.getWalletByUserId(userId, userType);
      
      if (error || !wallet) {
        return { 
          available_balance: 0, 
          locked_balance: 0, 
          total_balance: 0,
          error: error || new Error('Wallet not found') 
        };
      }

      const available = parseFloat(wallet.available_balance);
      const locked = parseFloat(wallet.locked_balance);

      return {
        available_balance: available,
        locked_balance: locked,
        total_balance: available + locked,
        error: null,
      };
    } catch (error) {
      logger.error('Unexpected error fetching wallet balance:', error);
      return { 
        available_balance: 0, 
        locked_balance: 0, 
        total_balance: 0,
        error 
      };
    }
  }
}

export const walletService = new WalletService();
