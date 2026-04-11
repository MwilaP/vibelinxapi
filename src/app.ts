import express, { Application } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from './config';
import paymentRoutes from './routes/payment.routes';
import bookingRoutes from './routes/booking.routes';
import walletRoutes from './routes/wallet.routes';
import adminRoutes from './routes/admin.routes';
import testRoutes from './routes/test.routes';
import subscriptionRoutes from './routes/subscription.routes';
import withdrawalRoutes from './routes/withdrawal.routes';
import payoutMethodRoutes from './routes/payoutMethod.routes';
import settingsRoutes from './routes/settings.routes';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';

const app: Application = express();

app.use(helmet());
app.use(cors({
  origin: config.security.allowedOrigins,
  credentials: true,
}));
app.use(morgan('combined'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/health', (req, res) => {
  res.status(200).json({
    success: true,
    message: 'VibeLinx Payment API is running',
    timestamp: new Date().toISOString(),
  });
});

app.use('/api/payments', paymentRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/admin/settings', settingsRoutes);
app.use('/api/test', testRoutes);
app.use('/api/subscriptions', subscriptionRoutes);
app.use('/api/withdrawal', withdrawalRoutes);
app.use('/api/payout-methods', payoutMethodRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
