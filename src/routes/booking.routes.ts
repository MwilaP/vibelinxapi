import { Router } from 'express';
import { bookingController } from '../controllers/booking.controller';

const router = Router();

router.post('/notify', (req, res) => 
  bookingController.notifyProvider(req, res)
);

router.post('/status-update', (req, res) => 
  bookingController.sendStatusUpdate(req, res)
);

router.post('/custom-notification', (req, res) => 
  bookingController.sendCustomNotification(req, res)
);

router.get('/:booking_id', (req, res) => 
  bookingController.getBooking(req, res)
);

export default router;
