import { Router } from 'express';
import * as providerController from '../controllers/provider.controller';

const router = Router();

/**
 * @route POST /api/providers/pay-visibility
 * @desc Pay for provider profile visibility
 * @access Private
 */
router.post('/pay-visibility', providerController.payVisibilityFee);

export default router;
