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
}

export const bookingController = new BookingController();
