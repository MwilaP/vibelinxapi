import { Router, Request, Response } from 'express';
import { adminController } from '../controllers/admin.controller';

const router: Router = Router();

router.get('/escrows', (req: Request, res: Response) => 
  adminController.getAllEscrows(req, res)
);

router.get('/escrow/:escrow_id', (req: Request, res: Response) => 
  adminController.getEscrowDetails(req, res)
);

router.post('/escrow/release', (req: Request, res: Response) => 
  adminController.releaseEscrow(req, res)
);

router.post('/escrow/refund', (req: Request, res: Response) => 
  adminController.refundEscrow(req, res)
);

router.post('/escrow/dispute', (req: Request, res: Response) => 
  adminController.disputeEscrow(req, res)
);

router.get('/wallet/:wallet_id', (req: Request, res: Response) => 
  adminController.getWalletDetails(req, res)
);

router.post('/wallet/adjust', (req: Request, res: Response) => 
  adminController.adjustWalletBalance(req, res)
);

export default router;
