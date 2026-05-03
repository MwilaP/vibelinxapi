import { Router } from 'express';
import { 
  getReferralDashboard, 
  validateReferralCode, 
  requestReferralPayout 
} from '../controllers/referral.controller';

const router = Router();

/**
 * @route GET /api/referral/dashboard
 * @desc Get referral dashboard data for a user
 * @access Private
 */
router.get('/dashboard', getReferralDashboard);

/**
 * @route GET /api/referral/validate/:code/:userId?
 * @desc Validate a referral code
 * @access Public
 */
router.get('/validate/:code/:userId?', validateReferralCode);

/**
 * @route POST /api/referral/payout
 * @desc Request a referral payout
 * @access Private
 */
router.post('/payout', requestReferralPayout);

export default router;
