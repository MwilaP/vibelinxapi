import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';
import {
  ReferralEventType,
  ReferralEarningStatus,
  ReferralPayoutMethod,
  ReferralDashboardData
} from '../types/referral';
import { notificationService } from './notification.service';
import { pawapayService } from './pawapay.service';
import { encodeReferralCode, decodeReferralCode } from '../utils/referralCode';

class ReferralService {
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

  // --- Referral Code Logic ---

  async validateCode(code: string, requestingUserId?: string): Promise<{ referrerId: string | null; error: string | null }> {
    try {
      // Decode the code first (fallback is safe if it's already a raw code)
      const decodedCode = decodeReferralCode(code);

      const { data: profile, error } = await this.supabase
        .from('profiles')
        .select('id')
        .eq('referral_code', decodedCode.toUpperCase())
        .single();

      if (error || !profile) {
        return { referrerId: null, error: 'Invalid referral code' };
      }

      if (requestingUserId && profile.id === requestingUserId) {
        return { referrerId: null, error: 'Self-referral is not allowed' };
      }

      return { referrerId: profile.id, error: null };
    } catch (error) {
      logger.error('Error validating referral code:', error);
      return { referrerId: null, error: 'Internal server error' };
    }
  }

  // --- Earning Logic ---

  async processEvent(
    eventType: ReferralEventType,
    sourceId: string,
    referredUserId: string,
    grossAmount: number
  ): Promise<void> {
    try {
      logger.info('Processing referral event', { eventType, sourceId, referredUserId, grossAmount });

      // 1. Look up referred user to find their referrer
      const { data: referredUser, error: userError } = await this.supabase
        .from('profiles')
        .select('referred_by_user_id')
        .eq('id', referredUserId)
        .single();

      if (userError || !referredUser || !referredUser.referred_by_user_id) {
        logger.info('No referrer found for user', { referredUserId });
        return;
      }

      const referrerId = referredUser.referred_by_user_id;

      // 2. Check if referrer is active
      const { data: isActive, error: activeError } = await this.supabase
        .rpc('is_referrer_active', { p_user_id: referrerId });

      if (activeError) {
        logger.error('Error checking referrer active status:', activeError);
        return;
      }

      // 3. Get referrer role
      const { data: referrerProfile } = await this.supabase
        .from('profiles')
        .select('role')
        .eq('id', referrerId)
        .single();

      const referrerRole = referrerProfile?.role || 'client';

      // 4. Get reward rate (role-aware)
      const rewardRate = await this.getRewardRate(eventType, referrerRole);

      // If rate is 0 (e.g. MM on booking_platform_fee), skip earning
      if (rewardRate === 0) {
        logger.info('Reward rate is 0 for this event/role combination, skipping', { eventType, referrerRole });
        return;
      }

      const rewardAmount = grossAmount * rewardRate;

      // 5. Log the earning
      const status: ReferralEarningStatus = isActive ? 'confirmed' : 'missed';
      const missedReason = isActive ? null : 'referrer subscription not active at event time';

      const { error: logError } = await this.supabase
        .from('referral_earnings')
        .insert({
          referrer_user_id: referrerId,
          referred_user_id: referredUserId,
          event_type: eventType,
          source_id: sourceId,
          gross_amount: grossAmount,
          reward_rate: rewardRate,
          reward_amount: rewardAmount,
          status: status,
          referrer_was_active: isActive,
          missed_reason: missedReason
        });

      if (logError) {
        logger.error('Error logging referral earning:', logError);
        return;
      }

      // 6. If active, credit the wallet
      if (isActive) {
        await this.creditWallet(referrerId, rewardAmount);

        // 7. Send notification
        const { data: referrerNotifProfile } = await this.supabase
          .from('profiles')
          .select('phone, display_name')
          .eq('id', referrerId)
          .single();

        if (referrerNotifProfile && referrerNotifProfile.phone) {
          let message = '';
          if (eventType === 'booking_platform_fee') {
            message = `Vibeslinx: You earned K${rewardAmount.toFixed(2)} from a booking your referral generated!`;
          } else {
            message = `Vibeslinx: You earned K${rewardAmount.toFixed(2)}! A referral subscribed using your code.`;
          }
          await notificationService.sendCustomMessage(referrerNotifProfile.phone, message);
        }
      } else {
        // Notify about missed earning
        const { data: referrerProfile } = await this.supabase
          .from('profiles')
          .select('phone')
          .eq('id', referrerId)
          .single();

        if (referrerProfile && referrerProfile.phone) {
          await notificationService.sendCustomMessage(
            referrerProfile.phone,
            'Vibeslinx: Your referral earnings are paused because your subscription expired. Renew now to resume earning!'
          );
        }
      }

    } catch (error) {
      logger.error('Unexpected error in processEvent:', error);
    }
  }

  // --- Reward Rate Logic ---

  private async getRewardRate(
    eventType: ReferralEventType,
    referrerRole: string
  ): Promise<number> {
    // Marketing managers: 25% on subscriptions & visibility, skip booking fees
    if (referrerRole === 'marketing_manager') {
      if (eventType === 'client_subscription' || eventType === 'subscription_renewal') {
        const { data: rate } = await this.supabase
          .rpc('get_setting_decimal', { p_setting_key: 'marketing_manager_sub_rate' });
        return rate ?? 0.25;
      }
      if (eventType === 'provider_visibility') {
        const { data: rate } = await this.supabase
          .rpc('get_setting_decimal', { p_setting_key: 'marketing_manager_visibility_rate' });
        return rate ?? 0.25;
      }
      // MMs do NOT earn on booking_platform_fee
      return 0;
    }

    // Standard referral rates (existing users)
    let rateKey = '';
    switch (eventType) {
      case 'client_subscription':
      case 'subscription_renewal':
        rateKey = 'referral_client_sub_rate';
        break;
      case 'provider_visibility':
        rateKey = 'referral_visibility_rate';
        break;
      case 'booking_platform_fee':
        rateKey = 'referral_booking_fee_rate';
        break;
    }
    const { data: rateData, error: rateError } = await this.supabase
      .rpc('get_setting_decimal', { p_setting_key: rateKey });
    return rateError ? 0.15 : (rateData || 0.15);
  }

  // --- Wallet Logic ---

  async creditWallet(userId: string, amount: number): Promise<void> {
    try {
      // Use a RPC for transaction-safe update if available, or manual update
      // For now, let's do a select + update (not ideal for high concurrency, but okay for this MVP)
      // Ideally we'd have a 'credit_referral_wallet' RPC.

      const { data: wallet, error: walletError } = await this.supabase
        .from('referral_wallets')
        .select('*')
        .eq('user_id', userId)
        .single();

      if (walletError || !wallet) {
        logger.error('Referral wallet not found for user', { userId });
        return;
      }

      const { error: updateError } = await this.supabase
        .from('referral_wallets')
        .update({
          balance: parseFloat(wallet.balance) + amount,
          total_earned: parseFloat(wallet.total_earned) + amount,
          last_updated_at: new Date().toISOString()
        })
        .eq('id', wallet.id);

      if (updateError) {
        logger.error('Error crediting referral wallet:', updateError);
      }
    } catch (error) {
      logger.error('Unexpected error in creditWallet:', error);
    }
  }

  calculatePayoutFee(payoutAmount: number): { fee: number; netPayout: number; walletDebit: number } {
    // Mimic provider wallet's 3% fee structure
    // User requests payoutAmount (what they want to receive)
    // Fee is 3% on top
    const feePercentage = 0.03;
    const fee = Math.round(payoutAmount * feePercentage * 100) / 100;
    const walletDebit = payoutAmount + fee;
    const netPayout = payoutAmount;

    return {
      fee,
      netPayout,
      walletDebit
    };
  }

  async getDashboardData(userId: string): Promise<ReferralDashboardData | null> {
    try {
      let { data: profile, error: profileError } = await this.supabase
        .from('profiles')
        .select('referral_code, display_name')
        .eq('id', userId)
        .single();

      if (profileError || !profile) return null;

      // Ensure user has a referral code
      if (!profile.referral_code) {
        const newCode = (
          (profile.display_name?.substring(0, 3) || 'USR') +
          '-' +
          userId.substring(0, 4)
        ).toUpperCase();

        await this.supabase
          .from('profiles')
          .update({ referral_code: newCode })
          .eq('id', userId);

        profile.referral_code = newCode;
      }

      let { data: wallet, error: walletError } = await this.supabase
        .from('referral_wallets')
        .select('*')
        .eq('user_id', userId)
        .single();

      if (walletError || !wallet) {
        // Auto-create wallet for existing users
        const { data: newWallet, error: createError } = await this.supabase
          .from('referral_wallets')
          .insert({ user_id: userId })
          .select()
          .single();

        if (createError) {
          logger.error('Failed to auto-create referral wallet:', createError);
          return null;
        }
        wallet = newWallet;
      }

      const { data: earnings } = await this.supabase
        .from('referral_earnings')
        .select('*')
        .eq('referrer_user_id', userId)
        .order('created_at', { ascending: false })
        .limit(10);

      const { data: statsData } = await this.supabase
        .from('referral_earnings')
        .select('status, reward_amount')
        .eq('referrer_user_id', userId);

      const { count: totalReferrals } = await this.supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true })
        .eq('referred_by_user_id', userId);

      const { data: isActive } = await this.supabase
        .rpc('is_referrer_active', { p_user_id: userId });

      const stats = {
        totalReferrals: totalReferrals || 0,
        activeReferrals: 0, // Could be refined to count users with active subs
        pendingEarnings: (statsData || [])
          .filter(e => e.status === 'pending')
          .reduce((sum, e) => sum + parseFloat(e.reward_amount), 0),
        missedEarnings: (statsData || [])
          .filter(e => e.status === 'missed')
          .reduce((sum, e) => sum + parseFloat(e.reward_amount), 0)
      };

      return {
        referralCode: profile.referral_code,
        referralLink: `https://${config.domain}/ref/${encodeReferralCode(profile.referral_code)}`,
        wallet: {
          balance: parseFloat(wallet.balance),
          totalEarned: parseFloat(wallet.total_earned),
          totalPaidOut: parseFloat(wallet.total_paid_out)
        },
        stats,
        recentEarnings: earnings || [],
        isReferrerActive: !!isActive
      };
    } catch (error) {
      logger.error('Error getting dashboard data:', error);
      return null;
    }
  }

  async requestPayout(
    userId: string, 
    amount: number, 
    method: ReferralPayoutMethod,
    paymentPhone?: string,
    paymentProvider?: string
  ): Promise<{ success: boolean; error: string | null }> {
    try {
      // 1. Get min payout setting
      const { data: minPayout } = await this.supabase
        .rpc('get_setting_decimal', { p_setting_key: 'referral_min_payout' });

      if (amount < (minPayout || 20)) {
        return { success: false, error: `Minimum payout amount is K${minPayout || 20}` };
      }

      // 2. Calculate fees (3% model like provider wallet)
      const feeInfo = this.calculatePayoutFee(amount);
      const totalDeduction = feeInfo.walletDebit;

      // 3. Check balance
      const { data: wallet, error: walletError } = await this.supabase
        .from('referral_wallets')
        .select('*')
        .eq('user_id', userId)
        .single();

      if (walletError || !wallet) {
        return { success: false, error: 'Wallet not found' };
      }

      if (parseFloat(wallet.balance) < totalDeduction) {
        return { 
          success: false, 
          error: `Insufficient balance. You need K${totalDeduction.toFixed(2)} but have K${parseFloat(wallet.balance).toFixed(2)}` 
        };
      }

      // 4. Deduct from balance
      const { error: updateError } = await this.supabase
        .from('referral_wallets')
        .update({
          balance: parseFloat(wallet.balance) - totalDeduction,
          total_paid_out: parseFloat(wallet.total_paid_out) + totalDeduction,
          last_updated_at: new Date().toISOString()
        })
        .eq('id', wallet.id);

      if (updateError) {
        return { success: false, error: 'Failed to update wallet' };
      }

      // 5. Check if this is a marketing manager (auto PawaPay disbursement)
      const { data: userProfile } = await this.supabase
        .from('profiles')
        .select('role, display_name')
        .eq('id', userId)
        .single();

      const isMarketingManager = userProfile?.role === 'marketing_manager';
      let pawapayPayoutId: string | null = null;
      let payoutStatus: string = 'requested';

      if (isMarketingManager && method === 'mobile_money' && paymentPhone && paymentProvider) {
        // Auto-disburse via PawaPay
        const reference = `MM-PAYOUT-${userId.slice(0, 8)}-${Date.now()}`;
        const pawapayResult = await pawapayService.initiatePayout({
          amount: feeInfo.netPayout,
          payment_method: paymentProvider,
          payment_phone: paymentPhone,
          reference,
        });

        if (pawapayResult.success && pawapayResult.data?.payoutId) {
          pawapayPayoutId = pawapayResult.data.payoutId;
          payoutStatus = 'processing';
          logger.info('PawaPay payout initiated for marketing manager', { userId, payoutId: pawapayPayoutId });
        } else {
          // PawaPay failed — rollback wallet and return error
          await this.supabase.from('referral_wallets').update({
            balance: parseFloat(wallet.balance),
            total_paid_out: parseFloat(wallet.total_paid_out)
          }).eq('id', wallet.id);
          logger.error('PawaPay payout failed for MM, rolling back', { userId, error: pawapayResult.message });
          return { success: false, error: `Payment disbursement failed: ${pawapayResult.message}` };
        }
      }

      // 6. Create payout record
      const { error: payoutError } = await this.supabase
        .from('referral_payouts')
        .insert({
          user_id: userId,
          amount: amount,
          fee_amount: feeInfo.fee,
          net_amount: feeInfo.netPayout,
          method: method,
          payment_phone: paymentPhone,
          payment_provider: paymentProvider,
          status: payoutStatus,
          pawapay_payout_id: pawapayPayoutId,
          requested_at: new Date().toISOString(),
        });

      if (payoutError) {
        // Rollback wallet
        await this.supabase.from('referral_wallets').update({
          balance: parseFloat(wallet.balance),
          total_paid_out: parseFloat(wallet.total_paid_out)
        }).eq('id', wallet.id);
        return { success: false, error: 'Failed to create payout record' };
      }

      return { success: true, error: null };
    } catch (error) {
      logger.error('Error requesting payout:', error);
      return { success: false, error: 'Internal server error' };
    }
  }

  // --- Marketing Manager Registration & Auth ---

  async registerManager(
    fullName: string,
    phone: string,
    password: string
  ): Promise<{ success: boolean; userId?: string; referralCode?: string; error?: string }> {
    try {
      const email = `${phone.replace(/\s/g, '')}@vibeslinx.com`;

      // 1. Create Supabase Auth user
      const { data: authData, error: authError } = await this.supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          display_name: fullName,
          phone,
          role: 'marketing_manager',
        },
      });

      if (authError || !authData.user) {
        logger.error('Failed to create MM auth user:', authError);
        if (authError?.message?.includes('already registered')) {
          return { success: false, error: 'A user with this phone number already exists.' };
        }
        return { success: false, error: authError?.message || 'Registration failed' };
      }

      const userId = authData.user.id;

      // 2. Create profile via DB function (handles referral code + wallet init)
      const { data: referralCode, error: profileError } = await this.supabase
        .rpc('create_marketing_manager_profile', {
          p_user_id: userId,
          p_display_name: fullName,
          p_phone: phone,
        });

      if (profileError) {
        logger.error('Failed to create MM profile:', profileError);
        // Attempt cleanup
        await this.supabase.auth.admin.deleteUser(userId);
        return { success: false, error: 'Profile creation failed. Please try again.' };
      }

      logger.info('Marketing manager registered successfully', { userId, referralCode });
      return { success: true, userId, referralCode };
    } catch (error) {
      logger.error('Unexpected error in registerManager:', error);
      return { success: false, error: 'Internal server error' };
    }
  }

  async loginManager(
    phone: string,
    password: string
  ): Promise<{ success: boolean; session?: any; error?: string }> {
    try {
      const email = `${phone.replace(/\s/g, '')}@vibeslinx.com`;

      const { data, error } = await this.supabase.auth.signInWithPassword({ email, password });

      if (error || !data.user) {
        return { success: false, error: 'Invalid phone number or password' };
      }

      // Verify the user is actually a marketing manager
      const { data: profile } = await this.supabase
        .from('profiles')
        .select('role, display_name, referral_code')
        .eq('id', data.user.id)
        .single();

      if (!profile || profile.role !== 'marketing_manager') {
        return { success: false, error: 'Access denied. This portal is for marketing managers only.' };
      }

      return { success: true, session: data.session };
    } catch (error) {
      logger.error('Error in loginManager:', error);
      return { success: false, error: 'Internal server error' };
    }
  }

  async getWithdrawalHistory(
    userId: string,
    limit: number = 20,
    offset: number = 0
  ): Promise<{ success: boolean; payouts?: any[]; total?: number; error?: string }> {
    try {
      const { data: payouts, error, count } = await this.supabase
        .from('referral_payouts')
        .select('*', { count: 'exact' })
        .eq('user_id', userId)
        .order('requested_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (error) {
        return { success: false, error: 'Failed to fetch withdrawal history' };
      }

      return { success: true, payouts: payouts || [], total: count || 0 };
    } catch (error) {
      logger.error('Error in getWithdrawalHistory:', error);
      return { success: false, error: 'Internal server error' };
    }
  }
}

export const referralService = new ReferralService();
