export type ReferralEventType = 
  | 'client_subscription' 
  | 'provider_visibility' 
  | 'booking_platform_fee' 
  | 'subscription_renewal';

export type ReferralEarningStatus = 
  | 'pending' 
  | 'confirmed' 
  | 'missed' 
  | 'paid_out';

export type ReferralPayoutMethod = 
  | 'mobile_money' 
  | 'bank_transfer' 
  | 'platform_credit';

export type ReferralPayoutStatus = 
  | 'requested' 
  | 'processing' 
  | 'completed' 
  | 'rejected'
  | 'failed';

export interface ReferralEarning {
  id: string;
  referrer_user_id: string;
  referred_user_id: string;
  event_type: ReferralEventType;
  source_id: string;
  gross_amount: number;
  reward_rate: number;
  reward_amount: number;
  status: ReferralEarningStatus;
  referrer_was_active: boolean;
  missed_reason?: string;
  created_at: string;
}

export interface ReferralWallet {
  id: string;
  user_id: string;
  balance: number;
  total_earned: number;
  total_paid_out: number;
  last_updated_at: string;
}

export interface ReferralPayout {
  id: string;
  user_id: string;
  amount: number;
  method: ReferralPayoutMethod;
  status: ReferralPayoutStatus;
  reference?: string;
  requested_at: string;
  completed_at?: string;
}

export interface ReferralDashboardData {
  referralCode: string;
  referralLink: string;
  wallet: {
    balance: number;
    totalEarned: number;
    totalPaidOut: number;
  };
  stats: {
    totalReferrals: number;
    activeReferrals: number;
    pendingEarnings: number;
    missedEarnings: number;
  };
  recentEarnings: ReferralEarning[];
  isReferrerActive: boolean;
}
