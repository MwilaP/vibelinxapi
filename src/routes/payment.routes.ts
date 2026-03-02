import { Router, Request, Response } from 'express';
import { paymentController } from '../controllers/payment.controller';
import { validatePaymentInitiation, validatePaymentVerification } from '../middleware/validation';

const router = Router();

router.post('/initiate', validatePaymentInitiation, (req: Request, res: Response) => 
  paymentController.initiatePayment(req, res)
);

router.get('/verify/:transaction_id', validatePaymentVerification, (req: Request, res: Response) => 
  paymentController.verifyPayment(req, res)
);

router.get('/status/:transaction_id', (req: Request, res: Response) => 
  paymentController.getTransactionStatus(req, res)
);

router.post('/callback', (req: Request, res: Response) => 
  paymentController.handleCallback(req, res)
);

router.post('/refund', (req: Request, res: Response) => 
  paymentController.refundPayment(req, res)
);

router.post('/create-booking', (req: Request, res: Response) => 
  paymentController.createBookingWithPayment(req, res)
);

export default router;
