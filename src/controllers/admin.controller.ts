import { Request, Response } from 'express';
import { escrowService } from '../services/escrow.service';
import { walletService } from '../services/wallet.service';
import { logger } from '../utils/logger';

export class AdminController {
  async getAllEscrows(req: Request, res: Response): Promise<void> {
    try {
      const { status, limit, offset } = req.query;

      const filters = {
        status: status as string | undefined,
        limit: limit ? parseInt(limit as string) : 50,
        offset: offset ? parseInt(offset as string) : 0,
      };

      const { escrows, total, error } = await escrowService.getAllEscrows(filters);

      if (error) {
        logger.error('Failed to get all escrows', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve escrows',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          escrows,
          total,
          limit: filters.limit,
          offset: filters.offset,
        },
      });
    } catch (error: any) {
      logger.error('Get all escrows error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async releaseEscrow(req: Request, res: Response): Promise<void> {
    try {
      const { escrow_id, reason, admin_id } = req.body;

      if (!escrow_id) {
        res.status(400).json({
          success: false,
          message: 'escrow_id is required',
        });
        return;
      }

      logger.info('Admin releasing escrow', {
        escrowId: escrow_id,
        adminId: admin_id,
        reason,
      });

      const result = await escrowService.releaseEscrow({
        escrow_id,
        reason: reason || 'Released by admin',
        resolved_by: admin_id,
      });

      if (!result.success) {
        res.status(400).json({
          success: false,
          message: 'Failed to release escrow',
          error: result.error,
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Escrow released successfully',
      });
    } catch (error: any) {
      logger.error('Release escrow error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async refundEscrow(req: Request, res: Response): Promise<void> {
    try {
      const { escrow_id, reason, admin_id } = req.body;

      if (!escrow_id || !reason) {
        res.status(400).json({
          success: false,
          message: 'escrow_id and reason are required',
        });
        return;
      }

      logger.info('Admin refunding escrow', {
        escrowId: escrow_id,
        adminId: admin_id,
        reason,
      });

      const result = await escrowService.refundEscrow({
        escrow_id,
        reason,
        resolved_by: admin_id,
      });

      if (!result.success) {
        res.status(400).json({
          success: false,
          message: 'Failed to refund escrow',
          error: result.error,
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Escrow refunded successfully',
      });
    } catch (error: any) {
      logger.error('Refund escrow error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async disputeEscrow(req: Request, res: Response): Promise<void> {
    try {
      const { escrow_id, reason } = req.body;

      if (!escrow_id || !reason) {
        res.status(400).json({
          success: false,
          message: 'escrow_id and reason are required',
        });
        return;
      }

      const result = await escrowService.disputeEscrow(escrow_id, reason);

      if (!result.success) {
        res.status(400).json({
          success: false,
          message: 'Failed to mark escrow as disputed',
          error: result.error,
        });
        return;
      }

      res.status(200).json({
        success: true,
        message: 'Escrow marked as disputed',
      });
    } catch (error: any) {
      logger.error('Dispute escrow error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getEscrowDetails(req: Request, res: Response): Promise<void> {
    try {
      const { escrow_id } = req.params;

      const { escrow, error } = await escrowService.getEscrowById(escrow_id);

      if (error || !escrow) {
        res.status(404).json({
          success: false,
          message: 'Escrow not found',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: escrow,
      });
    } catch (error: any) {
      logger.error('Get escrow details error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getWalletDetails(req: Request, res: Response): Promise<void> {
    try {
      const { wallet_id } = req.params;

      const { wallet, error } = await walletService.getWalletById(wallet_id);

      if (error || !wallet) {
        res.status(404).json({
          success: false,
          message: 'Wallet not found',
        });
        return;
      }

      const { transactions } = await walletService.getWalletTransactions(wallet_id, 100);

      res.status(200).json({
        success: true,
        data: {
          wallet,
          recent_transactions: transactions,
        },
      });
    } catch (error: any) {
      logger.error('Get wallet details error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async adjustWalletBalance(req: Request, res: Response): Promise<void> {
    try {
      const { wallet_id, amount, reason, admin_id } = req.body;

      if (!wallet_id || !amount || !reason) {
        res.status(400).json({
          success: false,
          message: 'wallet_id, amount, and reason are required',
        });
        return;
      }

      logger.info('Admin adjusting wallet balance', {
        walletId: wallet_id,
        amount,
        reason,
        adminId: admin_id,
      });

      if (amount > 0) {
        const result = await walletService.creditWallet({
          wallet_id,
          amount,
          transaction_id: `admin-adjustment-${Date.now()}`,
          description: `Admin adjustment: ${reason}`,
          metadata: {
            admin_id,
            adjustment_type: 'credit',
          },
        });

        if (result.error) {
          res.status(400).json({
            success: false,
            message: 'Failed to credit wallet',
            error: result.error,
          });
          return;
        }
      } else if (amount < 0) {
        const result = await walletService.deductFromWallet({
          wallet_id,
          amount: Math.abs(amount),
          reference_id: `admin-adjustment-${Date.now()}`,
          reference_type: 'booking',
          description: `Admin adjustment: ${reason}`,
          metadata: {
            admin_id,
            adjustment_type: 'debit',
          },
        });

        if (result.error) {
          res.status(400).json({
            success: false,
            message: 'Failed to deduct from wallet',
            error: result.error,
          });
          return;
        }
      }

      res.status(200).json({
        success: true,
        message: 'Wallet balance adjusted successfully',
      });
    } catch (error: any) {
      logger.error('Adjust wallet balance error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const adminController = new AdminController();
