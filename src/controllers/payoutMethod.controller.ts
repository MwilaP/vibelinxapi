import { Request, Response } from 'express';
import { payoutMethodService } from '../services/payoutMethod.service';
import { logger } from '../utils/logger';

export class PayoutMethodController {
  async saveMethod(req: Request, res: Response): Promise<void> {
    try {
      const { user_id, payment_method, payment_phone, account_name, is_default } = req.body;

      logger.info('Save payout method request', {
        userId: user_id,
        paymentMethod: payment_method,
      });

      if (!user_id || !payment_method || !payment_phone) {
        res.status(400).json({
          success: false,
          message: 'Missing required fields: user_id, payment_method, payment_phone',
        });
        return;
      }

      if (!['mtn', 'airtel', 'zamtel'].includes(payment_method)) {
        res.status(400).json({
          success: false,
          message: 'Invalid payment method. Must be mtn, airtel, or zamtel',
        });
        return;
      }

      const { method, error } = await payoutMethodService.savePayoutMethod({
        user_id,
        payment_method,
        payment_phone,
        account_name,
        is_default,
      });

      if (error) {
        logger.error('Failed to save payout method', { error });
        res.status(400).json({
          success: false,
          message: error.message || 'Failed to save payout method',
          error: error.code || 'SAVE_METHOD_ERROR',
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Payout method saved successfully',
        data: {
          method,
        },
      });
    } catch (error: any) {
      logger.error('Save payout method error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getMethods(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;

      if (!user_id) {
        res.status(400).json({
          success: false,
          message: 'user_id is required',
        });
        return;
      }

      const { methods, error } = await payoutMethodService.getPayoutMethods(user_id);

      if (error) {
        logger.error('Failed to get payout methods', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve payout methods',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          methods,
          count: methods.length,
        },
      });
    } catch (error: any) {
      logger.error('Get payout methods error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async deleteMethod(req: Request, res: Response): Promise<void> {
    try {
      const { method_id } = req.params;
      const { user_id } = req.body;

      if (!method_id || !user_id) {
        res.status(400).json({
          success: false,
          message: 'method_id and user_id are required',
        });
        return;
      }

      const { success, error } = await payoutMethodService.deletePayoutMethod(user_id, method_id);

      if (error || !success) {
        logger.error('Failed to delete payout method', { error });
        res.status(400).json({
          success: false,
          message: error?.message || 'Failed to delete payout method',
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Payout method deleted successfully',
      });
    } catch (error: any) {
      logger.error('Delete payout method error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async setDefault(req: Request, res: Response): Promise<void> {
    try {
      const { method_id } = req.params;
      const { user_id } = req.body;

      if (!method_id || !user_id) {
        res.status(400).json({
          success: false,
          message: 'method_id and user_id are required',
        });
        return;
      }

      const { success, error } = await payoutMethodService.setDefaultPayoutMethod(user_id, method_id);

      if (error || !success) {
        logger.error('Failed to set default payout method', { error });
        res.status(400).json({
          success: false,
          message: error?.message || 'Failed to set default payout method',
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Default payout method set successfully',
      });
    } catch (error: any) {
      logger.error('Set default payout method error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const payoutMethodController = new PayoutMethodController();
