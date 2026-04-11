import { Request, Response } from 'express';
import { lencopayService } from '../services/lencopay.service';
import { bookingService } from '../services/booking.service';
import { transactionService } from '../services/transaction.service';
import { walletService } from '../services/wallet.service';
import { withdrawalService } from '../services/withdrawal.service';
import { PaymentInitiationRequest, PaymentCallbackData } from '../types';
import { logger } from '../utils/logger';

export class PaymentController {
  async initiatePayment(req: Request, res: Response): Promise<void> {
    try {
      const { booking_data, user_id, ...paymentData } = req.body;

      logger.info('Initiating payment with transaction creation', {
        userId: user_id,
        amount: paymentData.amount,
        paymentType: paymentData.payment_type,
        hasBookingData: !!booking_data,
      });

      if (!user_id) {
        res.status(400).json({
          success: false,
          message: 'User ID is required',
        });
        return;
      }

      // Determine transaction type
      let transactionType: 'booking_commitment' | 'booking_balance' | 'booking_full' | 'subscription';
      if (booking_data) {
        if (paymentData.payment_type === 'commitment') {
          transactionType = 'booking_commitment';
        } else if (paymentData.payment_type === 'balance') {
          transactionType = 'booking_balance';
        } else {
          transactionType = 'booking_full';
        }
      } else {
        transactionType = 'subscription';
      }

      // Create transaction record BEFORE initiating payment (with placeholder reference)
      const { transaction, error: txError } = await transactionService.createTransaction({
        user_id,
        amount: paymentData.amount,
        transaction_type: transactionType,
        payment_type: paymentData.payment_type,
        payment_method: paymentData.payment_method,
        payment_phone: paymentData.customer_phone,
        reference_number: 'PENDING', // Will be updated with transaction ID
        external_transaction_id: null,
        metadata: {
          booking_data: booking_data || null,
          payment_info: {
            payment_method: paymentData.payment_method,
            payment_phone: paymentData.customer_phone,
            customer_name: paymentData.customer_name,
            customer_email: paymentData.customer_email,
          },
        },
        description: booking_data 
          ? `${paymentData.payment_type} payment for ${booking_data.service_name}`
          : `${paymentData.payment_type} payment`,
      });

      if (txError || !transaction) {
        logger.error('Failed to create transaction record', {
          error: txError,
        });
        res.status(500).json({
          success: false,
          message: 'Failed to create transaction record',
        });
        return;
      }

      // Use transaction ID as the Lenco reference
      const lencoReference = `VBL-${transaction.id}-${paymentData.payment_type}`;

      // Update transaction with its own ID as reference
      await transactionService.updateTransactionReference(
        transaction.id,
        lencoReference
      );

      logger.info('Transaction created, now initiating Lenco payment', {
        transactionId: transaction.id,
        lencoReference,
      });

      // Now initiate payment with Lenco using transaction ID as reference
      const result = await lencopayService.initiatePayment({
        ...paymentData,
        reference: lencoReference, // Use transaction-based reference
      });

      if (!result.success) {
        // Payment initiation failed, mark transaction as failed
        await transactionService.updateTransactionStatus(
          transaction.id,
          'failed',
          'payment_initiation_failed',
          result.message
        );
        
        logger.error('Lenco payment initiation failed', {
          transactionId: transaction.id,
          lencoReference,
          error: result.message,
          resultData: result.data,
        });
        
        // Still return transaction ID so frontend can poll for status
        res.status(400).json({
          ...result,
          transaction_id: transaction.id,
          data: {
            ...result.data,
            transaction_id: transaction.id,
          }
        });
        return;
      }

      // Update transaction with Lenco's internal ID
      if (result.data?.lencoReference || result.data?.id) {
        await transactionService.updateTransactionStatus(
          transaction.id,
          'pending',
          result.data?.status || 'pending'
        );
      }

      logger.info('Payment initiated successfully', {
        transactionId: transaction.id,
        lencoReference,
        lencoInternalId: result.data?.lencoReference,
        lencoStatus: result.data?.status,
      });

      res.status(200).json({
        success: true,
        message: result.message,
        transaction_id: transaction.id,
        data: {
          ...result.data,
          transaction_id: transaction.id,
          reference: lencoReference,
          amount: paymentData.amount,
          currency: paymentData.currency,
          status: result.data?.status || 'pending',
        }
      });
    } catch (error: any) {
      logger.error('Payment initiation error', {
        error: error.message,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async verifyPayment(req: Request, res: Response): Promise<void> {
    try {
      const { transaction_id } = req.params;

      logger.info('Verifying payment', { transactionId: transaction_id });

      if (!transaction_id) {
        res.status(400).json({
          success: false,
          message: 'Transaction ID is required',
        });
        return;
      }

      // Get transaction from database to get the reference
      const { transaction, error: txError } = await transactionService.getTransactionById(transaction_id);

      if (txError || !transaction) {
        logger.error('Transaction not found for verification', {
          transactionId: transaction_id,
          error: txError,
        });
        res.status(404).json({
          success: false,
          message: 'Transaction not found',
        });
        return;
      }

      // Verify payment using the Lenco reference
      const result = await lencopayService.verifyPayment(transaction.reference_number);

      res.status(result.success ? 200 : 400).json(result);
    } catch (error: any) {
      logger.error('Payment verification error', {
        error: error.message,
        transactionId: req.params.transaction_id,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getTransactionStatus(req: Request, res: Response): Promise<void> {
    try {
      const { transaction_id } = req.params;

      logger.info('Getting transaction status', { transactionId: transaction_id });

      if (!transaction_id) {
        res.status(400).json({
          success: false,
          message: 'Transaction ID is required',
        });
        return;
      }

      // Get transaction from database
      const { transaction, error: txError } = await transactionService.getTransactionById(transaction_id);

      if (txError || !transaction) {
        logger.error('Transaction not found', {
          transactionId: transaction_id,
          error: txError,
        });
        res.status(404).json({
          success: false,
          message: 'Transaction not found',
        });
        return;
      }

      // Verify payment status with Lenco
      const paymentVerification = await lencopayService.verifyPayment(transaction.reference_number);

      // Build response with transaction and booking info
      const response: any = {
        success: true,
        message: 'Transaction status retrieved',
        data: {
          transaction_id: transaction.id,
          reference: transaction.reference_number,
          status: transaction.status,
          payment_status: paymentVerification.status,
          amount: transaction.amount,
          currency: 'ZMW',
          transaction_type: transaction.transaction_type,
          payment_type: transaction.payment_type,
          booking_id: transaction.booking_id,
          has_booking: !!transaction.booking_id,
          created_at: transaction.created_at,
          updated_at: transaction.updated_at,
        },
      };

      res.status(200).json(response);
    } catch (error: any) {
      logger.error('Get transaction status error', {
        error: error.message,
        transactionId: req.params.transaction_id,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async handleCallback(req: Request, res: Response): Promise<void> {
    try {
      const webhookEvent = req.body;
      const signature = req.headers['x-lenco-signature'] as string;

      logger.info('Received Lenco webhook', { event: webhookEvent.event });

      if (!signature || !lencopayService.validateCallback(webhookEvent, signature)) {
        logger.warn('Invalid webhook signature', {
          hasSignature: !!signature,
          event: webhookEvent.event,
        });
        res.status(401).json({
          success: false,
          message: 'Invalid signature',
        });
        return;
      }

      if (webhookEvent.event === 'collection.successful') {
        const collectionData = webhookEvent.data;
        
        logger.info('Processing successful collection', {
          event: webhookEvent.event,
          reference: collectionData.reference,
          amount: collectionData.amount,
        });

        // Find transaction by reference
        const { transaction, error: txError } = await transactionService.getTransactionByReference(
          collectionData.reference
        );

        if (txError || !transaction) {
          logger.error('Transaction not found for webhook', {
            reference: collectionData.reference,
            error: txError,
          });
          res.status(200).json({ success: true });
          return;
        }

        // Update transaction status to completed
        await transactionService.updateTransactionStatus(
          transaction.id,
          'completed',
          collectionData.status
        );

        logger.info('Transaction status updated to completed', {
          transactionId: transaction.id,
          event: webhookEvent.event,
        });

        // Check if this is a wallet deposit transaction
        if (transaction.transaction_type === 'wallet_topup' && transaction.metadata?.wallet_id) {
          logger.info('Processing wallet deposit', {
            transactionId: transaction.id,
            walletId: transaction.metadata.wallet_id,
            amount: collectionData.amount,
          });

          const creditResult = await walletService.creditWallet({
            wallet_id: transaction.metadata.wallet_id,
            amount: parseFloat(collectionData.amount),
            transaction_id: transaction.id,
            description: 'Wallet deposit via mobile money',
            metadata: {
              payment_method: transaction.payment_method,
              external_transaction_id: collectionData.lencoReference,
            },
          });

          if (creditResult.error) {
            logger.error('Failed to credit wallet', {
              transactionId: transaction.id,
              walletId: transaction.metadata.wallet_id,
              error: creditResult.error,
            });
          } else {
            logger.info('Wallet credited successfully', {
              transactionId: transaction.id,
              walletId: transaction.metadata.wallet_id,
              amount: collectionData.amount,
            });
          }
        }
        // Check if this is a booking transaction
        else if (transaction.metadata?.booking_data && 
            ['booking_commitment', 'booking_balance', 'booking_full'].includes(transaction.transaction_type)) {
          
          const bookingData = transaction.metadata.booking_data;

          // Create booking from transaction metadata
          const { booking, error: bookingError } = await bookingService.createBookingWithPayment({
            ...bookingData,
            transaction_id: transaction.id,
            payment_type: transaction.payment_type,
          });

          if (bookingError) {
            logger.error('Failed to create booking from transaction', {
              transactionId: transaction.id,
              error: bookingError,
            });
          } else {
            logger.info('Booking created from transaction metadata', {
              bookingId: booking.id,
              transactionId: transaction.id,
            });

            // Update transaction with booking_id
            await transactionService.updateTransactionBookingId(
              transaction.id,
              booking.id
            );

            // Notify provider of new booking
            if (transaction.payment_type === 'commitment' || transaction.payment_type === 'full') {
              await bookingService.notifyProviderOfNewBooking(booking.id);
            }

            // Notify client of payment confirmation
            await bookingService.notifyPaymentConfirmation(
              booking.id,
              transaction.payment_type,
              parseFloat(collectionData.amount)
            );
          }
        }

        logger.info('Webhook processed successfully', {
          event: webhookEvent.event,
          transactionId: transaction.id,
          transactionType: transaction.transaction_type,
        });
      } else if (webhookEvent.event === 'payout.successful' || webhookEvent.event === 'payout.completed') {
        const payoutData = webhookEvent.data;
        
        logger.info('Processing successful payout', {
          event: webhookEvent.event,
          reference: payoutData.reference,
          amount: payoutData.amount,
        });

        // Handle payout webhook
        await withdrawalService.handlePayoutWebhook({
          reference: payoutData.reference,
          status: 'successful',
          externalTransactionId: payoutData.mobileMoneyDetails?.operatorTransactionId,
        });

        logger.info('Payout webhook processed successfully', {
          reference: payoutData.reference,
        });
      } else if (webhookEvent.event === 'payout.failed') {
        const payoutData = webhookEvent.data;
        
        logger.warn('Payout failed webhook received', {
          reference: payoutData.reference,
          reason: payoutData.reasonForFailure,
        });

        // Handle payout failure
        await withdrawalService.handlePayoutWebhook({
          reference: payoutData.reference,
          status: 'failed',
          failureReason: payoutData.reasonForFailure,
        });
      } else if (webhookEvent.event === 'collection.settled' || 
                 webhookEvent.event === 'transaction.credit') {
        // Log but don't process these events - only collection.successful creates bookings
        logger.info('Received webhook event (not processing)', {
          event: webhookEvent.event,
          reference: webhookEvent.data?.reference,
        });
      } else if (webhookEvent.event === 'collection.failed') {
        const collectionData = webhookEvent.data;
        
        logger.warn('Collection failed webhook received', {
          reference: collectionData.reference,
          reason: collectionData.reasonForFailure,
        });

        // Find and update transaction
        const { transaction } = await transactionService.getTransactionByReference(
          collectionData.reference
        );

        if (transaction) {
          await transactionService.updateTransactionStatus(
            transaction.id,
            'failed',
            collectionData.status,
            collectionData.reasonForFailure
          );
        }
      }

      res.status(200).json({
        success: true,
        message: 'Webhook processed',
      });
    } catch (error: any) {
      logger.error('Webhook processing error', {
        error: error.message,
        event: req.body.event,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  private extractBookingIdFromReference(reference: string): string | null {
    const parts = reference.split('-');
    if (parts.length >= 4) {
      return parts.slice(3).join('-');
    }
    return null;
  }

  private determinePaymentType(reference: string): 'commitment' | 'balance' | 'full' {
    if (reference.includes('commitment')) return 'commitment';
    if (reference.includes('balance')) return 'balance';
    if (reference.includes('full')) return 'full';
    return 'commitment';
  }

  async refundPayment(req: Request, res: Response): Promise<void> {
    try {
      const { transaction_id, amount, reason } = req.body;

      logger.info('Initiating refund', {
        transactionId: transaction_id,
        amount,
        reason,
      });

      if (!transaction_id || !amount || !reason) {
        res.status(400).json({
          success: false,
          message: 'Transaction ID, amount, and reason are required',
        });
        return;
      }

      const result = await lencopayService.initiateRefund(transaction_id, amount, reason);

      res.status(result.success ? 200 : 400).json(result);
    } catch (error: any) {
      logger.error('Refund error', {
        error: error.message,
        transactionId: req.body.transaction_id,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async createBookingWithPayment(req: Request, res: Response): Promise<void> {
    try {
      const { booking_data, transaction_id } = req.body;

      logger.info('Creating booking with payment', {
        transactionId: transaction_id,
        providerId: booking_data.provider_id,
      });

      if (!booking_data || !transaction_id) {
        res.status(400).json({
          success: false,
          message: 'Booking data and transaction ID are required',
        });
        return;
      }

      const verification = await lencopayService.verifyPayment(transaction_id);
      
      if (!verification.success || verification.status !== 'successful') {
        logger.warn('Payment verification failed for booking creation', {
          transactionId: transaction_id,
          status: verification.status,
        });
        res.status(400).json({
          success: false,
          message: 'Payment verification failed. Please ensure payment is completed.',
          verification,
        });
        return;
      }

      const { booking, error } = await bookingService.createBookingWithPayment({
        ...booking_data,
        transaction_id,
      });

      if (error) {
        logger.error('Booking creation failed', {
          error: error.message,
          transactionId: transaction_id,
        });
        res.status(400).json({
          success: false,
          message: 'Failed to create booking',
          error: error.message,
        });
        return;
      }

      await bookingService.notifyProviderOfNewBooking(booking.id);

      logger.info('Booking created successfully with payment', {
        bookingId: booking.id,
        transactionId: transaction_id,
      });

      res.status(201).json({
        success: true,
        message: 'Booking created successfully',
        booking,
      });
    } catch (error: any) {
      logger.error('Create booking with payment error', {
        error: error.message,
      });
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const paymentController = new PaymentController();
