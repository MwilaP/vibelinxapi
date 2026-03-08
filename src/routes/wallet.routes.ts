import { Router, Request, Response } from 'express';
import { walletController } from '../controllers/wallet.controller';

const router: Router = Router();

router.post('/deposit', (req: Request, res: Response) => 
  walletController.depositFunds(req, res)
);

router.get('/balance/:user_id', (req: Request, res: Response) => 
  walletController.getWalletBalance(req, res)
);

router.get('/transactions/:user_id', (req: Request, res: Response) => 
  walletController.getWalletTransactions(req, res)
);

router.get('/escrow/:user_id', (req: Request, res: Response) => 
  walletController.getEscrowTransactions(req, res)
);

router.get('/dashboard/:user_id', (req: Request, res: Response) => 
  walletController.getDashboardSummary(req, res)
);

export default router;
