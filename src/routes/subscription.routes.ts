import { Router } from 'express';
import { purchaseSubscription, cancelSubscription, getSubscriptionStatus } from '../controllers/subscription.controller';

const router = Router();

/**
 * @route POST /api/subscriptions/purchase
 * @desc Purchase a subscription plan
 * @access Private
 */
router.post('/purchase', purchaseSubscription);

/**
 * @route POST /api/subscriptions/cancel
 * @desc Cancel active subscription
 * @access Private
 */
router.post('/cancel', cancelSubscription);

/**
 * @route GET /api/subscriptions/status/:userId
 * @desc Get subscription status
 * @access Private
 */
router.get('/status/:userId', getSubscriptionStatus);

export default router;
