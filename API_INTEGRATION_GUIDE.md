# VibeLinx API Integration Guide

This guide explains how to integrate the VibeLinx Payment API with your frontend application.

## Overview

The payment flow consists of three main steps:
1. **Initiate Payment** - Create a payment transaction
2. **Process Payment** - User completes payment on Lencopay
3. **Verify Payment** - Confirm payment status and update booking

## Frontend Integration

### 1. Payment Initiation

When a user creates a booking and needs to pay the commitment fee:

```typescript
// In your booking creation flow
async function initiateBookingPayment(bookingData: any) {
  try {
    // First, create the booking in your system
    const booking = await createBooking(bookingData);
    
    // Then initiate payment
    const paymentResponse = await fetch('http://localhost:3001/api/payments/initiate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        booking_id: booking.id,
        amount: booking.commitment_fee,
        currency: 'ZMW',
        payment_type: 'commitment',
        customer_phone: user.phone,
        customer_email: user.email,
        customer_name: user.full_name,
      }),
    });

    const result = await paymentResponse.json();

    if (result.success) {
      // Store transaction ID for later verification
      localStorage.setItem('pending_transaction', result.transaction_id);
      
      // Redirect to payment page
      window.location.href = result.payment_url;
    } else {
      // Handle error
      alert('Payment initiation failed: ' + result.message);
    }
  } catch (error) {
    console.error('Payment error:', error);
  }
}
```

### 2. Payment Callback Handling

After payment, Lencopay will redirect the user back to your app. Set up a callback page:

```typescript
// pages/payment-callback.tsx or similar
import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';

export default function PaymentCallback() {
  const router = useRouter();
  const [status, setStatus] = useState<'verifying' | 'success' | 'failed'>('verifying');

  useEffect(() => {
    verifyPayment();
  }, []);

  async function verifyPayment() {
    const transactionId = localStorage.getItem('pending_transaction');
    
    if (!transactionId) {
      setStatus('failed');
      return;
    }

    try {
      const response = await fetch(
        `http://localhost:3001/api/payments/verify/${transactionId}`
      );
      const result = await response.json();

      if (result.success && result.status === 'success') {
        setStatus('success');
        localStorage.removeItem('pending_transaction');
        
        // Redirect to booking confirmation
        setTimeout(() => {
          router.push('/bookings');
        }, 2000);
      } else {
        setStatus('failed');
      }
    } catch (error) {
      console.error('Verification error:', error);
      setStatus('failed');
    }
  }

  return (
    <div className="payment-callback">
      {status === 'verifying' && <p>Verifying your payment...</p>}
      {status === 'success' && <p>Payment successful! Redirecting...</p>}
      {status === 'failed' && <p>Payment verification failed. Please contact support.</p>}
    </div>
  );
}
```

### 3. Balance Payment

When the booking is confirmed and the client needs to pay the balance:

```typescript
async function payBalance(bookingId: string, balanceAmount: number) {
  try {
    const response = await fetch('http://localhost:3001/api/payments/initiate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        booking_id: bookingId,
        amount: balanceAmount,
        currency: 'ZMW',
        payment_type: 'balance',
        customer_phone: user.phone,
        customer_email: user.email,
        customer_name: user.full_name,
      }),
    });

    const result = await response.json();

    if (result.success) {
      localStorage.setItem('pending_transaction', result.transaction_id);
      window.location.href = result.payment_url;
    }
  } catch (error) {
    console.error('Balance payment error:', error);
  }
}
```

## Backend Integration (Existing Booking Service)

Update your existing booking service to integrate with the payment API:

### Update Booking Creation

```typescript
// In your existing booking.service.ts
import { bookingService as paymentBookingService } from './payment-api-client';

async createBooking(data: CreateBookingData): Promise<{ booking: Booking | null; error: Error | null }> {
  try {
    // ... existing booking creation logic ...
    
    const { data: booking, error } = await supabase
      .from('bookings')
      .insert(bookingData)
      .select()
      .single();

    if (error) {
      return { booking: null, error };
    }

    // After successful booking creation, you can optionally trigger notification
    // Note: The payment API will automatically send notification after payment confirmation
    
    return { booking, error: null };
  } catch (error) {
    return { booking: null, error: error as Error };
  }
}
```

### Payment API Client Helper

Create a helper file to interact with the payment API:

```typescript
// src/services/payment-api-client.ts

const PAYMENT_API_BASE_URL = process.env.NEXT_PUBLIC_PAYMENT_API_URL || 'http://localhost:3001';

export class PaymentAPIClient {
  async initiatePayment(paymentData: {
    booking_id: string;
    amount: number;
    currency: string;
    payment_type: 'commitment' | 'balance' | 'full';
    customer_phone: string;
    customer_email?: string;
    customer_name?: string;
  }) {
    const response = await fetch(`${PAYMENT_API_BASE_URL}/api/payments/initiate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(paymentData),
    });

    return response.json();
  }

  async verifyPayment(transactionId: string) {
    const response = await fetch(
      `${PAYMENT_API_BASE_URL}/api/payments/verify/${transactionId}`
    );
    return response.json();
  }

  async notifyProvider(bookingId: string) {
    const response = await fetch(`${PAYMENT_API_BASE_URL}/api/bookings/notify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ booking_id: bookingId }),
    });
    return response.json();
  }

  async sendStatusUpdate(
    phoneNumber: string,
    bookingId: string,
    status: string,
    additionalInfo?: string
  ) {
    const response = await fetch(`${PAYMENT_API_BASE_URL}/api/bookings/status-update`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone_number: phoneNumber,
        booking_id: bookingId,
        status,
        additional_info: additionalInfo,
      }),
    });
    return response.json();
  }
}

export const paymentAPIClient = new PaymentAPIClient();
```

## Environment Variables

Add to your frontend `.env` file:

```env
NEXT_PUBLIC_PAYMENT_API_URL=http://localhost:3001
```

For production:
```env
NEXT_PUBLIC_PAYMENT_API_URL=https://api.vibelinx.com
```

## Complete Booking Flow Example

```typescript
// Complete flow from booking creation to payment
async function completeBookingFlow(bookingData: CreateBookingData) {
  try {
    // Step 1: Create booking
    const { booking, error } = await bookingService.createBooking(bookingData);
    
    if (error || !booking) {
      throw new Error('Failed to create booking');
    }

    // Step 2: Initiate payment
    const paymentResult = await paymentAPIClient.initiatePayment({
      booking_id: booking.id,
      amount: booking.commitment_fee,
      currency: 'ZMW',
      payment_type: 'commitment',
      customer_phone: user.phone,
      customer_email: user.email,
      customer_name: user.full_name,
    });

    if (!paymentResult.success) {
      throw new Error('Failed to initiate payment');
    }

    // Step 3: Store transaction and redirect
    localStorage.setItem('pending_transaction', paymentResult.transaction_id);
    localStorage.setItem('pending_booking', booking.id);
    
    // Redirect to payment
    window.location.href = paymentResult.payment_url;
    
  } catch (error) {
    console.error('Booking flow error:', error);
    // Handle error appropriately
  }
}
```

## Provider Notification Flow

The payment API automatically handles provider notifications:

1. **Payment Confirmed** → Commitment fee paid
2. **Booking Updated** → Status updated in database
3. **Provider Notified** → SMS sent automatically
4. **Client Notified** → Payment confirmation SMS sent

You can also manually trigger notifications:

```typescript
// Manually notify provider (if needed)
async function manuallyNotifyProvider(bookingId: string) {
  const result = await paymentAPIClient.notifyProvider(bookingId);
  
  if (result.success) {
    console.log('Provider notified successfully');
  }
}

// Send custom status update
async function notifyBookingStatusChange(
  booking: Booking,
  newStatus: string
) {
  // Notify client
  await paymentAPIClient.sendStatusUpdate(
    booking.client_phone,
    booking.id,
    newStatus,
    `Your booking status has been updated to ${newStatus}`
  );
  
  // Notify provider
  await paymentAPIClient.sendStatusUpdate(
    booking.provider_phone,
    booking.id,
    newStatus,
    `Booking ${booking.id} status: ${newStatus}`
  );
}
```

## Error Handling

Always implement proper error handling:

```typescript
async function handlePayment(bookingId: string, amount: number) {
  try {
    const result = await paymentAPIClient.initiatePayment({
      booking_id: bookingId,
      amount,
      currency: 'ZMW',
      payment_type: 'commitment',
      customer_phone: user.phone,
    });

    if (!result.success) {
      // Show user-friendly error
      showError(result.message);
      return;
    }

    // Success - redirect to payment
    window.location.href = result.payment_url;
    
  } catch (error) {
    // Network or unexpected error
    console.error('Payment error:', error);
    showError('Unable to process payment. Please try again.');
  }
}
```

## Testing

Test the integration in development:

1. Start the payment API: `cd vibelinxapi && npm run dev`
2. Start your frontend: `npm run dev`
3. Create a test booking
4. Monitor the payment flow

## Production Checklist

- [ ] Update `NEXT_PUBLIC_PAYMENT_API_URL` to production URL
- [ ] Ensure CORS is configured correctly in payment API
- [ ] Test payment callback URL is accessible
- [ ] Verify Lencopay production credentials
- [ ] Test SMS notifications with real phone numbers
- [ ] Set up error monitoring (Sentry, etc.)
- [ ] Configure proper logging
- [ ] Test refund flow
- [ ] Verify webhook signature validation

## Support

For integration issues:
- Check browser console for errors
- Verify API is running: `curl http://localhost:3001/health`
- Check network tab for failed requests
- Review payment API logs
