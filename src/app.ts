import express, { Application } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from './config';
import paymentRoutes from './routes/payment.routes';
import bookingRoutes from './routes/booking.routes';
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

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
