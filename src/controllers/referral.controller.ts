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

// --- Marketing Manager Controllers ---

export const registerMarketingManager = async (req: Request, res: Response) => {
  try {
    const { fullName, phone, password } = req.body;

    if (!fullName || !phone || !password) {
      return res.status(400).json({ success: false, error: 'fullName, phone, and password are required' });
    }

    if (password.length < 6) {
      return res.status(400).json({ success: false, error: 'Password must be at least 6 characters' });
    }

    const result = await referralService.registerManager(fullName, phone, password);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    return res.status(201).json({
      success: true,
      message: 'Marketing manager registered successfully',
      data: { userId: result.userId, referralCode: result.referralCode },
    });
  } catch (error) {
    logger.error('Error in registerMarketingManager controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};

export const loginMarketingManager = async (req: Request, res: Response) => {
  try {
    const { phone, password } = req.body;

    if (!phone || !password) {
      return res.status(400).json({ success: false, error: 'phone and password are required' });
    }

    const result = await referralService.loginManager(phone, password);

    if (!result.success) {
      return res.status(401).json({ success: false, error: result.error });
    }

    return res.status(200).json({
      success: true,
      message: 'Login successful',
      data: { session: result.session },
    });
  } catch (error) {
    logger.error('Error in loginMarketingManager controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};

export const getWithdrawalHistory = async (req: Request, res: Response) => {
  try {
    const userId = req.query.userId as string;
    const limit = parseInt(req.query.limit as string) || 20;
    const offset = parseInt(req.query.offset as string) || 0;

    if (!userId) {
      return res.status(400).json({ success: false, error: 'userId is required' });
    }

    const result = await referralService.getWithdrawalHistory(userId, limit, offset);

    if (!result.success) {
      return res.status(500).json({ success: false, error: result.error });
    }

    return res.status(200).json({
      success: true,
      data: { payouts: result.payouts, total: result.total },
    });
  } catch (error) {
    logger.error('Error in getWithdrawalHistory controller:', error);
    return res.status(500).json({ success: false, error: 'Internal server error' });
  }
};
