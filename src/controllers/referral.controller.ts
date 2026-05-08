import { Request, Response } from 'express';
import { referralService } from '../services/referral.service';
import { logger } from '../utils/logger';

export const getReferralDashboard = async (req: Request, res: Response) => {
  try {
    const userId = req.query.userId as string;
    if (!userId) {
      return res.status(400).json({ success: false, error: 'userId is required' });
    }

    const dashboard = await referralService.getDashboardData(userId);
    if (!dashboard) {
      return res.status(404).json({ success: false, error: 'Dashboard data not found' });
    }

    return res.status(200).json({ success: true, data: dashboard });
  } catch (error) {
    logger.error('Error in getReferralDashboard controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};

export const validateReferralCode = async (req: Request, res: Response) => {
  try {
    const { code, userId } = req.params;
    const result = await referralService.validateCode(code, userId);

    if (result.error) {
      return res.status(400).json({ success: false, error: result.error });
    }

    return res.status(200).json({ success: true, data: { referrerId: result.referrerId } });
  } catch (error) {
    logger.error('Error in validateReferralCode controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};

export const requestReferralPayout = async (req: Request, res: Response) => {
  try {
    const { userId, amount, method, paymentPhone, paymentProvider } = req.body;

    if (!userId || !amount || !method) {
      return res.status(400).json({ success: false, error: 'userId, amount, and method are required' });
    }

    const result = await referralService.requestPayout(userId, amount, method, paymentPhone, paymentProvider);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    return res.status(200).json({ success: true, message: 'Payout requested successfully' });
  } catch (error) {
    logger.error('Error in requestReferralPayout controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};
