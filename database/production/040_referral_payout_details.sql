-- Add detailed payout columns to referral_payouts
ALTER TABLE public.referral_payouts ADD COLUMN IF NOT EXISTS payment_phone VARCHAR(20);
ALTER TABLE public.referral_payouts ADD COLUMN IF NOT EXISTS payment_provider VARCHAR(50);
ALTER TABLE public.referral_payouts ADD COLUMN IF NOT EXISTS fee_amount DECIMAL(10,2) DEFAULT 0.00;
ALTER TABLE public.referral_payouts ADD COLUMN IF NOT EXISTS net_amount DECIMAL(10,2) DEFAULT 0.00;

-- Comment on columns
COMMENT ON COLUMN public.referral_payouts.payment_phone IS 'The phone number for mobile money payout';
COMMENT ON COLUMN public.referral_payouts.payment_provider IS 'The mobile money provider (mtn, airtel, zamtel)';
COMMENT ON COLUMN public.referral_payouts.fee_amount IS 'The fee charged for the withdrawal (usually 3%)';
COMMENT ON COLUMN public.referral_payouts.net_amount IS 'The actual amount the user receives after fees';
