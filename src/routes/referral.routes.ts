import { Router } from 'express';
import { 
  getReferralDashboard, 
  validateReferralCode, 
  requestReferralPayout,
  registerMarketingManager,
  loginMarketingManager,
  getWithdrawalHistory,
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
 * @desc Request a referral payout (MMs get auto PawaPay disbursement)
 * @access Private
 */
router.post('/payout', requestReferralPayout);

// --- Marketing Manager Routes ---

/**
 * @route POST /api/referral/mm/register
 * @desc Register a new marketing manager
 * @access Public
 */
router.post('/mm/register', registerMarketingManager);

/**
 * @route POST /api/referral/mm/login
 * @desc Login as a marketing manager
 * @access Public
 */
router.post('/mm/login', loginMarketingManager);

/**
 * @route GET /api/referral/mm/withdrawal-history
 * @desc Get withdrawal history for a marketing manager
 * @access Private
 */
router.get('/mm/withdrawal-history', getWithdrawalHistory);

export default router;
