import { Router, Request, Response } from 'express';
import { withdrawalController } from '../controllers/withdrawal.controller';

const router: Router = Router();

router.post('/request', (req: Request, res: Response) => 
  withdrawalController.requestWithdrawal(req, res)
);

router.get('/history/:user_id', (req: Request, res: Response) => 
  withdrawalController.getWithdrawalHistory(req, res)
);

router.get('/:withdrawal_id', (req: Request, res: Response) => 
  withdrawalController.getWithdrawalDetails(req, res)
);

router.get('/calculate-fee', (req: Request, res: Response) => 
  withdrawalController.calculateFees(req, res)
);

export default router;
