import { Request, Response, NextFunction } from 'express';
import { body, param, validationResult } from 'express-validator';

export const validatePaymentInitiation = [
  body('booking_id').optional(),
  body('amount').isNumeric().withMessage('Amount must be a number'),
  body('currency').notEmpty().withMessage('Currency is required'),
  body('payment_type')
    .isIn(['commitment', 'balance', 'full'])
    .withMessage('Payment type must be commitment, balance, or full'),
  body('customer_phone').notEmpty().withMessage('Customer phone is required'),
  (req: Request, res: Response, next: NextFunction) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        success: false, 
        errors: errors.array() 
      });
    }
    next();
  },
];

export const validatePaymentVerification = [
  param('transaction_id').notEmpty().withMessage('Transaction ID is required'),
  (req: Request, res: Response, next: NextFunction) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ 
        success: false, 
        errors: errors.array() 
      });
    }
    next();
  },
];
