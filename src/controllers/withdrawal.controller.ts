import { Request, Response } from 'express';
import { withdrawalService } from '../services/withdrawal.service';
import { walletService } from '../services/wallet.service';
import { payoutMethodService } from '../services/payoutMethod.service';
import { settingsService } from '../services/settings.service';
import { logger } from '../utils/logger';

export class WithdrawalController {
  async requestWithdrawal(req: Request, res: Response): Promise<void> {
    try {
      const { user_id, amount, payment_method, payment_phone, save_payout_method } = req.body;

      logger.info('Withdrawal request received', {
        userId: user_id,
        amount,
        paymentMethod: payment_method,
      });

      if (!user_id || !amount || !payment_method || !payment_phone) {
        res.status(400).json({
          success: false,
          message: 'Missing required fields: user_id, amount, payment_method, payment_phone',
        });
        return;
      }

      if (amount <= 0) {
        res.status(400).json({
          success: false,
          message: 'Amount must be greater than 0',
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

      // Get provider wallet
      const { wallet, error: walletError } = await walletService.getWalletByUserId(user_id, 'provider');

      if (walletError || !wallet) {
        logger.error('Failed to get provider wallet', { error: walletError });
        res.status(404).json({
          success: false,
          message: 'Provider wallet not found',
        });
        return;
      }

      // Save payout method if requested
      if (save_payout_method) {
        await payoutMethodService.savePayoutMethod({
          user_id,
          payment_method,
          payment_phone,
          is_default: false,
        });
      }

      // Create withdrawal request
      const { withdrawal, error } = await withdrawalService.createWithdrawalRequest({
        user_id,
        wallet_id: wallet.id,
        amount,
        payment_method,
        payment_phone,
        save_payout_method,
      });

      if (error) {
        logger.error('Failed to create withdrawal request', { error });
        res.status(400).json({
          success: false,
          message: error.message || 'Failed to create withdrawal request',
          error: error.code || 'WITHDRAWAL_ERROR',
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Withdrawal request created successfully',
        data: {
          withdrawal,
        },
      });
    } catch (error: any) {
      logger.error('Withdrawal request error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getWithdrawalHistory(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;
      const { limit } = req.query;

      if (!user_id) {
        res.status(400).json({
          success: false,
          message: 'user_id is required',
        });
        return;
      }

      const { withdrawals, error } = await withdrawalService.getWithdrawalsByUserId(
        user_id,
        limit ? parseInt(limit as string) : 50
      );

      if (error) {
        logger.error('Failed to get withdrawal history', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve withdrawal history',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          withdrawals,
          count: withdrawals.length,
        },
      });
    } catch (error: any) {
      logger.error('Get withdrawal history error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getWithdrawalDetails(req: Request, res: Response): Promise<void> {
    try {
      const { withdrawal_id } = req.params;

      if (!withdrawal_id) {
        res.status(400).json({
          success: false,
          message: 'withdrawal_id is required',
        });
        return;
      }

      const { withdrawal, error } = await withdrawalService.getWithdrawalById(withdrawal_id);

      if (error || !withdrawal) {
        logger.error('Failed to get withdrawal details', { error });
        res.status(404).json({
          success: false,
          message: 'Withdrawal not found',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          withdrawal,
        },
      });
    } catch (error: any) {
      logger.error('Get withdrawal details error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async calculateFees(req: Request, res: Response): Promise<void> {
    try {
      const { amount } = req.query;

      if (!amount) {
        res.status(400).json({
          success: false,
          message: 'amount is required',
        });
        return;
      }

      const amountNum = parseFloat(amount as string);

      if (isNaN(amountNum) || amountNum <= 0) {
        res.status(400).json({
          success: false,
          message: 'Invalid amount',
        });
        return;
      }

      const minWithdrawalAmount = await settingsService.getMinWithdrawalAmount();
      if (amountNum < minWithdrawalAmount) {
        res.status(400).json({
          success: false,
          message: `Minimum withdrawal amount is K${minWithdrawalAmount}`,
        });
        return;
      }

      const feeInfo = withdrawalService.calculateWithdrawalFee(amountNum);

      res.status(200).json({
        success: true,
        data: {
          payout_amount: amountNum, // What user wants to receive
          fee: feeInfo.fee, // 3% fee
          fee_percentage: feeInfo.fee_percentage, // 3
          wallet_debit: feeInfo.wallet_debit, // payout_amount + fee
          net_payout: feeInfo.net_payout, // Same as payout_amount
        },
      });
    } catch (error: any) {
      logger.error('Calculate fees error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const withdrawalController = new WithdrawalController();
