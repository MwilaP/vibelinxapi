import { Router } from 'express';
import { bookingController } from '../controllers/booking.controller';

const router: Router = Router();

router.post('/notify', (req, res) => 
  bookingController.notifyProvider(req, res)
);

router.post('/status-update', (req, res) => 
  bookingController.sendStatusUpdate(req, res)
);

router.post('/custom-notification', (req, res) => 
  bookingController.sendCustomNotification(req, res)
);

router.post('/accept', (req, res) => 
  bookingController.acceptBooking(req, res)
);

router.post('/complete', (req, res) => 
  bookingController.completeBooking(req, res)
);

router.post('/decline', (req, res) => 
  bookingController.declineBooking(req, res)
);

router.post('/cancel-by-provider', (req, res) => 
  bookingController.cancelBookingByProvider(req, res)
);

router.post('/cancel-by-client', (req, res) => 
  bookingController.cancelBookingByClient(req, res)
);

router.get('/:booking_id', (req, res) => 
  bookingController.getBooking(req, res)
);

router.post('/create-with-wallet', (req, res) => 
  bookingController.createBookingWithWallet(req, res)
);

export default router;
