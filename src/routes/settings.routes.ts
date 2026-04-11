import { Router, Request, Response } from 'express';
import { settingsController } from '../controllers/settings.controller';

const router: Router = Router();

router.get('/', (req: Request, res: Response) => 
  settingsController.getAllSettings(req, res)
);

router.get('/:key', (req: Request, res: Response) => 
  settingsController.getSetting(req, res)
);

router.put('/:key', (req: Request, res: Response) => 
  settingsController.updateSetting(req, res)
);

export default router;
