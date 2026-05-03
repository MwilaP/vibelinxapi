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
 * Pay for provider profile visibility
 */
export const payVisibilityFee = async (req: Request, res: Response) => {
  try {
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'user_id is required',
      });
    }

    // 1. Get visibility fee from settings
    const { data: feeData, error: feeError } = await supabase
      .rpc('get_setting_decimal', { p_setting_key: 'provider_visibility_fee' });

    if (feeError) {
      console.error('[PROVIDER] Error fetching visibility fee:', feeError);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch visibility fee setting',
      });
    }

    const visibilityFee = feeData || 100.00; // Fallback to 100 if not found

    // 2. Check if provider already has active visibility
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('visibility_status, role')
      .eq('id', user_id)
      .single();

    if (profileError || !profile) {
      return res.status(404).json({
        success: false,
        error: 'Provider profile not found',
      });
    }

    if (profile.role !== 'provider') {
      return res.status(400).json({
        success: false,
        error: 'Only providers can pay for visibility',
      });
    }

    if (profile.visibility_status === 'active') {
      return res.status(400).json({
        success: false,
        error: 'Provider visibility is already active',
      });
    }

    // 3. Get provider wallet
    let { data: wallet, error: walletError } = await supabase
      .from('wallets')
      .select('id, available_balance')
      .eq('user_id', user_id)
      .eq('user_type', 'provider')
      .single();

    if (walletError || !wallet) {
      return res.status(404).json({
        success: false,
        error: 'Provider wallet not found',
      });
    }

    // 4. Check balance
    if (wallet.available_balance < visibilityFee) {
      return res.status(400).json({
        success: false,
        error: 'Insufficient wallet balance',
        data: {
          required: visibilityFee,
          available: wallet.available_balance,
        },
      });
    }

    // 5. Process payment (Transaction)
    
    // Deduct from wallet
    const { error: walletUpdateError } = await supabase
      .from('wallets')
      .update({
        available_balance: wallet.available_balance - visibilityFee,
        updated_at: new Date().toISOString(),
      })
      .eq('id', wallet.id);

    if (walletUpdateError) {
      return res.status(500).json({
        success: false,
        error: 'Failed to update wallet balance',
      });
    }

    // Create public transaction record
    const { data: transaction, error: txError } = await supabase
      .from('transactions')
      .insert({
        user_id,
        amount: -visibilityFee,
        type: 'payment',
        status: 'completed',
        description: 'Provider Visibility Fee',
        metadata: {
          fee_type: 'visibility_fee',
          amount: visibilityFee,
        },
      })
      .select()
      .single();

    if (txError) {
      // Rollback wallet (best effort)
      await supabase.from('wallets').update({
        available_balance: wallet.available_balance,
      }).eq('id', wallet.id);

      return res.status(500).json({
        success: false,
        error: 'Failed to create transaction record',
      });
    }

    // Create wallet transaction record
    await supabase.from('wallet_transactions').insert({
      wallet_id: wallet.id,
      transaction_type: 'service_payment',
      amount: -visibilityFee,
      balance_before: wallet.available_balance,
      balance_after: wallet.available_balance - visibilityFee,
      description: 'Provider Visibility Fee',
      reference_id: transaction.id,
      reference_type: 'payment',
    });

    // 6. Update profile visibility status
    const { error: profileUpdateError } = await supabase
      .from('profiles')
      .update({
        visibility_status: 'active',
        updated_at: new Date().toISOString(),
      })
      .eq('id', user_id);

    if (profileUpdateError) {
      return res.status(500).json({
        success: false,
        error: 'Failed to update profile visibility status',
      });
    }

    // Process Referral Earnings
    try {
      const { referralService } = require('../services/referral.service');
      await referralService.processEvent(
        'provider_visibility',
        transaction.id,
        user_id,
        visibilityFee
      );
    } catch (refError) {
      console.error('[PROVIDER] Error processing referral earnings:', refError);
    }

    return res.status(200).json({
      success: true,
      message: 'Visibility fee paid successfully',
      data: {
        transaction_id: transaction.id,
        amount_paid: visibilityFee,
        visibility_status: 'active',
      },
    });

  } catch (error: any) {
    console.error('[PROVIDER] Unexpected error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message,
    });
  }
};
