import { Request, Response } from 'express';
import { createClient } from '@supabase/supabase-js';
import { config } from '../config';

const supabase = createClient(
  config.supabase.url,
  config.supabase.serviceKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);

/**
 * Purchase a subscription plan
 * Uses the wallets table (same as booking system)
 */
export const purchaseSubscription = async (req: Request, res: Response) => {
  try {
    console.log('[SUBSCRIPTION] Purchase request received:', { user_id: req.body.user_id, plan_type: req.body.plan_type });
    const { user_id, plan_type } = req.body;

    // Validate input
    if (!user_id || !plan_type) {
      return res.status(400).json({
        success: false,
        error: 'user_id and plan_type are required',
      });
    }

    if (!['monthly', 'annual'].includes(plan_type)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid plan_type. Must be monthly or annual',
      });
    }

    // Get plan details
    const planPrice = plan_type === 'monthly' ? 50.00 : 500.00;
    const planDurationDays = plan_type === 'monthly' ? 30 : 365;

    // Check if user already has an active subscription
    const { data: existingSubscription } = await supabase
      .from('subscriptions')
      .select('id')
      .eq('user_id', user_id)
      .eq('status', 'active')
      .gt('end_date', new Date().toISOString())
      .single();

    if (existingSubscription) {
      return res.status(400).json({
        success: false,
        error: 'User already has an active subscription',
      });
    }

    // Get wallet balance from wallets table (Backend API system)
    console.log('[SUBSCRIPTION] Fetching wallet for user:', user_id);
    let { data: wallet, error: walletError } = await supabase
      .from('wallets')
      .select('id, available_balance, locked_balance, total_deposited, total_withdrawn')
      .eq('user_id', user_id)
      .eq('user_type', 'client')
      .single();
    
    console.log('[SUBSCRIPTION] Wallet query result:', { wallet, error: walletError });

    // If wallet doesn't exist, create it
    if (walletError && walletError.code === 'PGRST116') {
      console.log('[SUBSCRIPTION] Wallet not found, creating new wallet');
      const { data: newWallet, error: createError } = await supabase
        .from('wallets')
        .insert({
          user_id,
          user_type: 'client',
          available_balance: 0,
          locked_balance: 0,
          total_deposited: 0,
          total_withdrawn: 0,
          currency: 'ZMW',
          status: 'active',
        })
        .select('id, available_balance, locked_balance, total_deposited, total_withdrawn')
        .single();
      
      console.log('[SUBSCRIPTION] Wallet creation result:', { newWallet, error: createError });

      if (createError || !newWallet) {
        return res.status(500).json({
          success: false,
          error: 'Failed to create wallet',
          details: createError?.message,
        });
      }

      wallet = newWallet;
    } else if (walletError || !wallet) {
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch wallet',
        details: walletError?.message,
      });
    }

    // Check sufficient balance
    console.log('[SUBSCRIPTION] Checking balance:', { available: wallet.available_balance, required: planPrice });
    if (wallet.available_balance < planPrice) {
      console.log('[SUBSCRIPTION] Insufficient balance');
      return res.status(400).json({
        success: false,
        error: 'Insufficient wallet balance',
        data: {
          required: planPrice,
          available: wallet.available_balance,
          shortfall: planPrice - wallet.available_balance,
        },
      });
    }

    // Calculate end date
    const startDate = new Date();
    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + planDurationDays);

    // Start transaction: Deduct from wallet
    console.log('[SUBSCRIPTION] Deducting from wallet:', { amount: planPrice, new_balance: wallet.available_balance - planPrice });
    const { error: walletUpdateError } = await supabase
      .from('wallets')
      .update({
        available_balance: wallet.available_balance - planPrice,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', user_id)
      .eq('user_type', 'client');

    if (walletUpdateError) {
      console.error('[SUBSCRIPTION] Wallet update error:', walletUpdateError);
      return res.status(500).json({
        success: false,
        error: 'Failed to deduct from wallet',
        details: walletUpdateError.message,
      });
    }
    console.log('[SUBSCRIPTION] Wallet updated successfully');

    // Create transaction record in public.transactions table (for subscription foreign key)
    console.log('[SUBSCRIPTION] Creating transaction record in public.transactions');
    const { data: publicTransaction, error: publicTxError } = await supabase
      .from('transactions')
      .insert({
        user_id,
        amount: -planPrice,
        type: 'payment',
        status: 'completed',
        description: `Subscription - ${plan_type === 'monthly' ? 'Monthly Plan' : 'Annual Plan'}`,
        metadata: {
          plan_type,
          plan_price: planPrice,
          duration_days: planDurationDays,
          source: 'subscription_purchase',
          subscription_type: plan_type,
          processed_by_rpc: 'true',
        },
      })
      .select()
      .single();

    if (publicTxError) {
      console.error('[SUBSCRIPTION] Public transaction creation error:', publicTxError);
      // Rollback wallet update
      await supabase
        .from('wallets')
        .update({
          available_balance: wallet.available_balance,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', user_id)
        .eq('user_type', 'client');

      return res.status(500).json({
        success: false,
        error: 'Failed to create transaction record',
        details: publicTxError.message,
      });
    }
    console.log('[SUBSCRIPTION] Public transaction created:', publicTransaction.id);

    // Create wallet transaction record (for wallet system tracking)
    console.log('[SUBSCRIPTION] Creating wallet transaction record');
    const { data: walletTransaction, error: walletTxError } = await supabase
      .from('wallet_transactions')
      .insert({
        wallet_id: wallet.id,
        transaction_type: 'service_payment',
        amount: -planPrice,
        balance_before: wallet.available_balance,
        balance_after: wallet.available_balance - planPrice,
        description: `Subscription - ${plan_type === 'monthly' ? 'Monthly Plan' : 'Annual Plan'}`,
        reference_id: publicTransaction.id,
        reference_type: 'payment',
        metadata: {
          plan_type,
          plan_price: planPrice,
          duration_days: planDurationDays,
          public_transaction_id: publicTransaction.id,
        },
      })
      .select()
      .single();

    if (walletTxError) {
      console.error('[SUBSCRIPTION] Wallet transaction creation error:', walletTxError);
      // Rollback public transaction and wallet update
      await supabase.from('transactions').delete().eq('id', publicTransaction.id);
      await supabase
        .from('wallets')
        .update({
          available_balance: wallet.available_balance,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', user_id)
        .eq('user_type', 'client');

      return res.status(500).json({
        success: false,
        error: 'Failed to create wallet transaction record',
        details: walletTxError.message,
      });
    }
    console.log('[SUBSCRIPTION] Wallet transaction created:', walletTransaction.id);

    // Create subscription in Supabase
    console.log('[SUBSCRIPTION] Creating subscription record');
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .insert({
        user_id,
        plan_type,
        status: 'active',
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString(),
        amount_paid: planPrice,
        transaction_id: publicTransaction.id,
        auto_renew: true,
      })
      .select()
      .single();

    if (subError) {
      console.error('[SUBSCRIPTION] Subscription creation error:', subError);
      // Rollback wallet and transaction
      await supabase.from('wallets').update({
        available_balance: wallet.available_balance,
        updated_at: new Date().toISOString(),
      }).eq('user_id', user_id).eq('user_type', 'client');

      await supabase.from('wallet_transactions').delete().eq('id', walletTransaction.id);
      await supabase.from('transactions').delete().eq('id', publicTransaction.id);

      return res.status(500).json({
        success: false,
        error: 'Failed to create subscription',
        details: subError.message,
      });
    }
    console.log('[SUBSCRIPTION] Subscription created:', subscription.id);

    // Update profile subscription status
    await supabase
      .from('profiles')
      .update({
        subscription_status: 'active',
        updated_at: new Date().toISOString(),
      })
      .eq('id', user_id);

    // Process Referral Earnings
    try {
      const { referralService } = require('../services/referral.service');
      await referralService.processEvent(
        'client_subscription',
        subscription.id,
        user_id,
        planPrice
      );
    } catch (refError) {
      console.error('[SUBSCRIPTION] Error processing referral earnings:', refError);
    }

    // Return success
    console.log('[SUBSCRIPTION] Purchase completed successfully');
    return res.status(200).json({
      success: true,
      message: 'Subscription purchased successfully',
      data: {
        subscription_id: subscription.id,
        transaction_id: publicTransaction.id,
        plan_type,
        amount_paid: planPrice,
        start_date: startDate.toISOString(),
        end_date: endDate.toISOString(),
        status: 'active',
      },
    });
  } catch (error: any) {
    console.error('[SUBSCRIPTION] Unexpected error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message,
    });
  }
};

/**
 * Cancel active subscription
 */
export const cancelSubscription = async (req: Request, res: Response) => {
  try {
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'user_id is required',
      });
    }

    // Get active subscription
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .select('*')
      .eq('user_id', user_id)
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (subError || !subscription) {
      return res.status(404).json({
        success: false,
        error: 'No active subscription found',
      });
    }

    // Update subscription status
    const { error: updateError } = await supabase
      .from('subscriptions')
      .update({
        status: 'cancelled',
        auto_renew: false,
        updated_at: new Date().toISOString(),
      })
      .eq('id', subscription.id);

    if (updateError) {
      return res.status(500).json({
        success: false,
        error: 'Failed to cancel subscription',
        details: updateError.message,
      });
    }

    return res.status(200).json({
      success: true,
      message: 'Subscription cancelled successfully. Access will continue until end date.',
      data: {
        subscription_id: subscription.id,
        end_date: subscription.end_date,
      },
    });
  } catch (error: any) {
    console.error('Cancel subscription error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message,
    });
  }
};

/**
 * Get subscription status
 */
export const getSubscriptionStatus = async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    if (!userId) {
      return res.status(400).json({
        success: false,
        error: 'userId is required',
      });
    }

    // Get subscription from view
    const { data, error } = await supabase
      .from('user_subscription_status')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(200).json({
          success: true,
          data: {
            isSubscribed: false,
            subscription: null,
            daysRemaining: 0,
          },
        });
      }
      return res.status(500).json({
        success: false,
        error: 'Failed to get subscription status',
        details: error.message,
      });
    }

    const isSubscribed = data.status === 'active' && data.days_remaining > 0;

    return res.status(200).json({
      success: true,
      data: {
        isSubscribed,
        subscription: data.subscription_id ? {
          id: data.subscription_id,
          plan_type: data.plan_type,
          status: data.status,
          start_date: data.start_date,
          end_date: data.end_date,
          amount_paid: data.amount_paid,
          auto_renew: data.auto_renew,
        } : null,
        daysRemaining: data.days_remaining || 0,
        planType: data.plan_type,
      },
    });
  } catch (error: any) {
    console.error('Get subscription status error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message,
    });
  }
};
