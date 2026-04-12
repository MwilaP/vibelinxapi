import { Request, Response } from 'express';
import { walletService } from '../services/wallet.service';
import { escrowService } from '../services/escrow.service';
import { transactionService } from '../services/transaction.service';
import { pawapayService } from '../services/pawapay.service';
import { logger } from '../utils/logger';

export class WalletController {
  async depositFunds(req: Request, res: Response): Promise<void> {
    try {
      const { user_id, amount, payment_method, customer_phone } = req.body;

      logger.info('Initiating wallet deposit', {
        userId: user_id,
        amount,
        paymentMethod: payment_method,
      });

      if (!user_id || !amount || !payment_method || !customer_phone) {
        res.status(400).json({
          success: false,
          message: 'Missing required fields: user_id, amount, payment_method, customer_phone',
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

      const { wallet, error: walletError } = await walletService.getWalletByUserId(user_id, 'client');

      if (walletError) {
        logger.error('Failed to get or create wallet', { error: walletError });
        res.status(500).json({
          success: false,
          message: 'Failed to access wallet',
        });
        return;
      }

      const { transaction, error: txError } = await transactionService.createTransaction({
        user_id,
        amount,
        transaction_type: 'wallet_topup',
        payment_type: 'full',
        payment_method,
        payment_phone: customer_phone,
        reference_number: 'PENDING',
        metadata: {
          wallet_id: wallet.id,
        },
        description: 'Wallet deposit',
      });

      if (txError || !transaction) {
        logger.error('Failed to create transaction for wallet deposit', { error: txError });
        res.status(500).json({
          success: false,
          message: 'Failed to initiate deposit transaction',
        });
        return;
      }

      const lencoReference = `VBL-${transaction.id}-wallet-deposit`;

      await transactionService.updateTransactionReference(transaction.id, lencoReference);

      const paymentResult = await pawapayService.initiateDeposit({
        amount,
        currency: 'ZMW',
        payment_method,
        payment_type: 'full',
        customer_phone,
        reference: lencoReference,
      });

      if (!paymentResult.success) {
        await transactionService.updateTransactionStatus(
          transaction.id,
          'failed',
          'payment_initiation_failed',
          paymentResult.message
        );

        res.status(400).json({
          success: false,
          message: paymentResult.message,
          transaction_id: transaction.id,
        });
        return;
      }

      // Update transaction with PawaPay deposit ID and status
      await transactionService.updateTransactionStatus(
        transaction.id,
        'pending',
        paymentResult.data?.status || 'pending',
        undefined, // errorMessage
        paymentResult.data?.depositId // pawapayDepositId
      );

      logger.info('Wallet deposit initiated successfully', {
        transactionId: transaction.id,
        walletId: wallet.id,
        amount,
        depositId: paymentResult.data?.depositId,
      });

      res.status(200).json({
        success: true,
        message: 'Wallet deposit initiated. Please complete payment on your phone.',
        transaction_id: transaction.id,
        wallet_id: wallet.id,
        data: {
          ...paymentResult.data,
          transaction_id: transaction.id,
          reference: lencoReference,
          amount,
          currency: 'ZMW',
        },
      });
    } catch (error: any) {
      logger.error('Wallet deposit error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getWalletBalance(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;
      const { user_type } = req.query;

      if (!user_id || !user_type) {
        res.status(400).json({
          success: false,
          message: 'user_id and user_type are required',
        });
        return;
      }

      if (user_type !== 'client' && user_type !== 'provider') {
        res.status(400).json({
          success: false,
          message: 'user_type must be either "client" or "provider"',
        });
        return;
      }

      const balanceData = await walletService.getWalletBalance(user_id, user_type as 'client' | 'provider');

      if (balanceData.error) {
        logger.error('Failed to get wallet balance', { error: balanceData.error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve wallet balance',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          available_balance: balanceData.available_balance,
          locked_balance: balanceData.locked_balance,
          total_balance: balanceData.total_balance,
          currency: 'ZMW',
        },
      });
    } catch (error: any) {
      logger.error('Get wallet balance error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getWalletTransactions(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;
      const { user_type, limit } = req.query;

      if (!user_id || !user_type) {
        res.status(400).json({
          success: false,
          message: 'user_id and user_type are required',
        });
        return;
      }

      if (user_type !== 'client' && user_type !== 'provider') {
        res.status(400).json({
          success: false,
          message: 'user_type must be either "client" or "provider"',
        });
        return;
      }

      const { wallet, error: walletError } = await walletService.getWalletByUserId(
        user_id,
        user_type as 'client' | 'provider'
      );

      if (walletError || !wallet) {
        res.status(404).json({
          success: false,
          message: 'Wallet not found',
        });
        return;
      }

      const transactionLimit = limit ? parseInt(limit as string) : 50;
      const { transactions, error } = await walletService.getWalletTransactions(wallet.id, transactionLimit);

      if (error) {
        logger.error('Failed to get wallet transactions', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve wallet transactions',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          transactions,
          count: transactions.length,
        },
      });
    } catch (error: any) {
      logger.error('Get wallet transactions error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getEscrowTransactions(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;
      const { user_type, status } = req.query;

      if (!user_id || !user_type) {
        res.status(400).json({
          success: false,
          message: 'user_id and user_type are required',
        });
        return;
      }

      if (user_type !== 'client' && user_type !== 'provider') {
        res.status(400).json({
          success: false,
          message: 'user_type must be either "client" or "provider"',
        });
        return;
      }

      const { wallet, error: walletError } = await walletService.getWalletByUserId(
        user_id,
        user_type as 'client' | 'provider'
      );

      if (walletError || !wallet) {
        res.status(404).json({
          success: false,
          message: 'Wallet not found',
        });
        return;
      }

      const { escrows, error } = await escrowService.getEscrowsByWallet(
        wallet.id,
        status as string | undefined
      );

      if (error) {
        logger.error('Failed to get escrow transactions', { error });
        res.status(500).json({
          success: false,
          message: 'Failed to retrieve escrow transactions',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: {
          escrows,
          count: escrows.length,
        },
      });
    } catch (error: any) {
      logger.error('Get escrow transactions error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getDashboardSummary(req: Request, res: Response): Promise<void> {
    try {
      const { user_id } = req.params;
      const { user_type } = req.query;

      if (!user_id || !user_type) {
        res.status(400).json({
          success: false,
          message: 'user_id and user_type are required',
        });
        return;
      }

      if (user_type !== 'client' && user_type !== 'provider') {
        res.status(400).json({
          success: false,
          message: 'user_type must be either "client" or "provider"',
        });
        return;
      }

      const { wallet, error: walletError } = await walletService.getWalletByUserId(
        user_id,
        user_type as 'client' | 'provider'
      );

      if (walletError || !wallet) {
        res.status(404).json({
          success: false,
          message: 'Wallet not found',
        });
        return;
      }

      const { escrows: lockedEscrows } = await escrowService.getEscrowsByWallet(wallet.id, 'locked');
      const { transactions: recentTransactions } = await walletService.getWalletTransactions(wallet.id, 10);

      res.status(200).json({
        success: true,
        data: {
          wallet: {
            available_balance: parseFloat(wallet.available_balance),
            locked_balance: parseFloat(wallet.locked_balance),
            total_balance: parseFloat(wallet.available_balance) + parseFloat(wallet.locked_balance),
            total_deposited: parseFloat(wallet.total_deposited),
            total_withdrawn: parseFloat(wallet.total_withdrawn),
            currency: wallet.currency,
            status: wallet.status,
          },
          escrow: {
            locked_count: lockedEscrows.length,
            locked_amount: lockedEscrows.reduce((sum, e) => sum + parseFloat(e.amount), 0),
          },
          recent_transactions: recentTransactions,
        },
      });
    } catch (error: any) {
      logger.error('Get dashboard summary error', { error: error.message });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const walletController = new WalletController();
