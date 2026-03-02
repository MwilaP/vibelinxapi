export interface PaymentInitiationRequest {
  booking_id?: string;
  amount: number;
  currency: string;
  payment_method: 'mtn' | 'airtel' | 'zamtel';
  payment_type: 'commitment' | 'balance' | 'full';
  customer_phone: string;
  customer_email?: string;
  customer_name?: string;
  reference?: string;
}

export interface PaymentInitiationResponse {
  success: boolean;
  transaction_id: string;
  payment_url?: string;
  message: string;
  data?: any;
}

export interface PaymentCallbackData {
  transaction_id: string;
  status: 'success' | 'failed' | 'pending';
  amount: number;
  currency: string;
  reference: string;
  payment_method?: string;
  timestamp: string;
}

export interface PaymentVerificationResponse {
  success: boolean;
  transaction_id: string;
  status: string;
  amount: number;
  currency: string;
  message: string;
  data?: {
    lencoReference?: string;
    completedAt?: string;
    fee?: string;
    operator?: string;
    operatorTransactionId?: string;
  };
}

export interface BookingNotification {
  booking_id: string;
  provider_phone: string;
  client_name: string;
  service_name: string;
  booking_date: string;
  booking_time: string;
  location_type: string;
  total_amount: number;
}

export interface SMSResponse {
  success: boolean;
  message: string;
  messageId?: string;
  recipients?: number;
}

export interface Booking {
  id: string;
  client_id: string;
  provider_id: string;
  service_name: string;
  service_price: number;
  booking_date: string;
  booking_time: string;
  location_type: string;
  total_amount: number;
  commitment_fee: number;
  balance_due: number;
  status: string;
}

export interface Provider {
  id: string;
  phone: string;
  name: string;
  email?: string;
}

export interface CreateBookingWithPaymentRequest {
  client_id: string;
  provider_id: string;
  service_name: string;
  service_duration: string;
  service_price: number;
  booking_date: string;
  booking_time: string;
  duration_minutes: number;
  location_type: 'my' | 'provider' | 'hotel';
  location_details?: string;
  client_notes?: string;
  platform_fee: number;
  commitment_fee: number;
  commitment_percentage: number;
  balance_due: number;
  total_amount: number;
  transaction_id: string;
  payment_type: 'commitment' | 'balance' | 'full';
}
