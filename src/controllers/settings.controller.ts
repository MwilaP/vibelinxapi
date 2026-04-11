import { Request, Response } from 'express';
import { settingsService } from '../services/settings.service';
import { logger } from '../utils/logger';

export class SettingsController {
  async getAllSettings(req: Request, res: Response): Promise<void> {
    try {
      const { settings, error } = await settingsService.getSettings();

      if (error) {
        logger.error('Failed to get settings', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve settings',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: settings,
      });
    } catch (error: any) {
      logger.error('Get settings error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getSetting(req: Request, res: Response): Promise<void> {
    try {
      const { key } = req.params;

      if (!key) {
        res.status(400).json({
          success: false,
          message: 'Setting key is required',
        });
        return;
      }

      const { setting, error } = await settingsService.getSetting(key);

      if (error || !setting) {
        logger.error('Failed to get setting', { key, error });
        res.status(404).json({
          success: false,
          message: 'Setting not found',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: setting,
      });
    } catch (error: any) {
      logger.error('Get setting error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async updateSetting(req: Request, res: Response): Promise<void> {
    try {
      const { key } = req.params;
      const { value, admin_id } = req.body;

      if (!key || value === undefined || value === null) {
        res.status(400).json({
          success: false,
          message: 'Setting key and value are required',
        });
        return;
      }

      if (!admin_id) {
        res.status(400).json({
          success: false,
          message: 'Admin ID is required',
        });
        return;
      }

      // Validate value for currency types
      if (['min_withdrawal_amount', 'monthly_subscription_fee', 'annual_subscription_fee'].includes(key)) {
        const numValue = parseFloat(value);
        if (isNaN(numValue) || numValue <= 0) {
          res.status(400).json({
            success: false,
            message: 'Value must be a positive number',
          });
          return;
        }

        // Additional validation for specific settings
        if (key === 'min_withdrawal_amount' && numValue > 1000) {
          res.status(400).json({
            success: false,
            message: 'Minimum withdrawal amount cannot exceed K1000',
          });
          return;
        }

        if (key === 'monthly_subscription_fee' && numValue > 500) {
          res.status(400).json({
            success: false,
            message: 'Monthly subscription fee cannot exceed K500',
          });
          return;
        }

        if (key === 'annual_subscription_fee' && numValue > 10000) {
          res.status(400).json({
            success: false,
            message: 'Annual subscription fee cannot exceed K10,000',
          });
          return;
        }
      }

      logger.info('Updating setting', {
        key,
        value,
        adminId: admin_id,
      });

      const { success, error } = await settingsService.updateSetting({
        setting_key: key,
        setting_value: value,
        admin_id,
      });

      if (!success) {
        logger.error('Failed to update setting', { error });
        res.status(400).json({
          success: false,
          message: error?.message || 'Failed to update setting',
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Setting updated successfully',
      });
    } catch (error: any) {
      logger.error('Update setting error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const settingsController = new SettingsController();
