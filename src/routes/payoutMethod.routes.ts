import { Router, Request, Response } from 'express';
import { payoutMethodController } from '../controllers/payoutMethod.controller';

const router: Router = Router();

router.post('/', (req: Request, res: Response) => 
  payoutMethodController.saveMethod(req, res)
);

router.get('/:user_id', (req: Request, res: Response) => 
  payoutMethodController.getMethods(req, res)
);

router.delete('/:method_id', (req: Request, res: Response) => 
  payoutMethodController.deleteMethod(req, res)
);

router.put('/:method_id/default', (req: Request, res: Response) => 
  payoutMethodController.setDefault(req, res)
);

export default router;
