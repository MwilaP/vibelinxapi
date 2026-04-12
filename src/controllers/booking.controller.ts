import { Request, Response } from 'express';
import { bookingService } from '../services/booking.service';
import { notificationService } from '../services/notification.service';

export class BookingController {
  async notifyProvider(req: Request, res: Response): Promise<void> {
    try {
      const { booking_id } = req.body;

      if (!booking_id) {
        res.status(400).json({
          success: false,
          message: 'Booking ID is required',
        });
        return;
      }

      const result = await bookingService.notifyProviderOfNewBooking(booking_id);

      res.status(result ? 200 : 400).json({
        success: result,
        message: result 
          ? 'Provider notified successfully' 
          : 'Failed to notify provider',
      });
    } catch (error: any) {
      console.error('Notification error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async sendStatusUpdate(req: Request, res: Response): Promise<void> {
    try {
      const { phone_number, booking_id, status, additional_info } = req.body;

      if (!phone_number || !booking_id || !status) {
        res.status(400).json({
          success: false,
          message: 'Phone number, booking ID, and status are required',
        });
        return;
      }

      const result = await notificationService.sendBookingStatusUpdate(
        phone_number,
        booking_id,
        status,
        additional_info
      );

      res.status(result.success ? 200 : 400).json(result);
    } catch (error: any) {
      console.error('Status update error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async sendCustomNotification(req: Request, res: Response): Promise<void> {
    try {
      const { phone_number, message } = req.body;

      if (!phone_number || !message) {
        res.status(400).json({
          success: false,
          message: 'Phone number and message are required',
        });
        return;
      }

      const result = await notificationService.sendCustomMessage(phone_number, message);

      res.status(result.success ? 200 : 400).json(result);
    } catch (error: any) {
      console.error('Custom notification error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async getBooking(req: Request, res: Response): Promise<void> {
    try {
      const { booking_id } = req.params;

      if (!booking_id) {
        res.status(400).json({
          success: false,
          message: 'Booking ID is required',
        });
        return;
      }

      const booking = await bookingService.getBookingById(booking_id);

      if (!booking) {
        res.status(404).json({
          success: false,
          message: 'Booking not found',
        });
        return;
      }

      res.status(200).json({
        success: true,
        data: booking,
      });
    } catch (error: any) {
      console.error('Get booking error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async acceptBooking(req: Request, res: Response): Promise<void> {
    try {
      console.log('\n=== ACCEPT BOOKING REQUEST ===');
      console.log('Request body:', JSON.stringify(req.body, null, 2));
      
      const { booking_id, provider_id } = req.body;

      if (!booking_id || !provider_id) {
        console.log('❌ Missing required fields');
        res.status(400).json({
          success: false,
          message: 'Booking ID and Provider ID are required',
        });
        return;
      }

      console.log('📞 Calling bookingService.acceptBooking...');
      const result = await bookingService.acceptBooking(booking_id, provider_id);
      console.log('Result:', JSON.stringify(result, null, 2));

      if (!result.success) {
        console.log('❌ Accept booking failed:', result.error?.message);
        res.status(400).json({
          success: false,
          message: result.error?.message || 'Failed to accept booking',
        });
        return;
      }

      console.log('✅ Booking accepted successfully');
      res.status(200).json({
        success: true,
        message: 'Booking accepted successfully. Client has been notified.',
      });
    } catch (error: any) {
      console.error('❌ Accept booking error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async completeBooking(req: Request, res: Response): Promise<void> {
    try {
      console.log('\n=== COMPLETE BOOKING REQUEST ===');
      console.log('Request body:', JSON.stringify(req.body, null, 2));
      
      const { booking_id, provider_id } = req.body;

      if (!booking_id || !provider_id) {
        console.log('❌ Missing required fields');
        res.status(400).json({
          success: false,
          message: 'Booking ID and Provider ID are required',
        });
        return;
      }

      console.log('📞 Calling bookingService.completeBooking...');
      const result = await bookingService.completeBooking(booking_id, provider_id);
      console.log('Result:', JSON.stringify(result, null, 2));

      if (!result.success) {
        console.log('❌ Complete booking failed:', result.error?.message);
        res.status(400).json({
          success: false,
          message: result.error?.message || 'Failed to complete booking',
        });
        return;
      }

      console.log('✅ Booking completed successfully');
      res.status(200).json({
        success: true,
        message: 'Booking completed successfully. Escrow will be released to your wallet.',
      });
    } catch (error: any) {
      console.error('❌ Complete booking error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async declineBooking(req: Request, res: Response): Promise<void> {
    try {
      console.log('\n=== DECLINE BOOKING REQUEST ===');
      console.log('Request body:', JSON.stringify(req.body, null, 2));
      
      const { booking_id, provider_id, reason } = req.body;

      if (!booking_id || !provider_id) {
        console.log('❌ Missing required fields');
        res.status(400).json({
          success: false,
          message: 'Booking ID and Provider ID are required',
        });
        return;
      }

      console.log('📞 Calling bookingService.declineBooking...');
      const result = await bookingService.declineBooking(booking_id, provider_id, reason);
      console.log('Result:', JSON.stringify(result, null, 2));

      if (!result.success) {
        console.log('❌ Decline booking failed:', result.error?.message);
        res.status(400).json({
          success: false,
          message: result.error?.message || 'Failed to decline booking',
        });
        return;
      }

      console.log('✅ Booking declined successfully');
      res.status(200).json({
        success: true,
        message: 'Booking declined. Client has been notified and will be refunded.',
      });
    } catch (error: any) {
      console.error('❌ Decline booking error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async cancelBookingByProvider(req: Request, res: Response): Promise<void> {
    try {
      console.log('\n=== CANCEL BOOKING BY PROVIDER REQUEST ===');
      console.log('Request body:', JSON.stringify(req.body, null, 2));
      
      const { booking_id, provider_id, reason } = req.body;

      if (!booking_id || !provider_id) {
        console.log('❌ Missing required fields');
        res.status(400).json({
          success: false,
          message: 'Booking ID and Provider ID are required',
        });
        return;
      }

      console.log('📞 Calling bookingService.cancelBookingByProvider...');
      const result = await bookingService.cancelBookingByProvider(booking_id, provider_id, reason);
      console.log('Result:', JSON.stringify(result, null, 2));

      if (!result.success) {
        console.log('❌ Cancel booking failed:', result.error?.message);
        res.status(400).json({
          success: false,
          message: result.error?.message || 'Failed to cancel booking',
        });
        return;
      }

      console.log('✅ Booking cancelled successfully by provider');
      res.status(200).json({
        success: true,
        message: 'Booking cancelled. Client has been notified and will be refunded.',
      });
    } catch (error: any) {
      console.error('❌ Cancel booking by provider error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }

  async createBookingWithWallet(req: Request, res: Response): Promise<void> {
    try {
      console.log('\n=== CREATE BOOKING WITH WALLET ===');
      console.log('Request body:', JSON.stringify(req.body, null, 2));

      const bookingData = req.body;

      if (!bookingData.client_id || !bookingData.provider_id || !bookingData.commitment_fee) {
        res.status(400).json({
          success: false,
          message: 'Missing required fields: client_id, provider_id, commitment_fee',
        });
        return;
      }

      const { booking, error } = await bookingService.createBookingWithWallet(bookingData);

      if (error) {
        if (error.code === 'INSUFFICIENT_BALANCE') {
          res.status(400).json({
            success: false,
            message: 'Insufficient wallet balance',
            error: {
              code: 'INSUFFICIENT_BALANCE',
              required: error.required,
              available: error.available,
            },
          });
          return;
        }

        console.error('❌ Create booking with wallet failed:', error);
        res.status(400).json({
          success: false,
          message: 'Failed to create booking',
          error: error.message || error,
        });
        return;
      }

      await bookingService.notifyProviderOfNewBooking(booking.id);

      console.log('✅ Booking created with wallet successfully');
      res.status(200).json({
        success: true,
        message: 'Booking created successfully. Commitment fee deducted from wallet and held in escrow.',
        data: {
          booking_id: booking.id,
          status: booking.status,
          commitment_fee: booking.commitment_fee,
        },
      });
    } catch (error: any) {
      console.error('❌ Create booking with wallet error:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
      });
    }
  }
}

export const bookingController = new BookingController();
