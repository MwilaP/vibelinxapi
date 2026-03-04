import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { Booking, Provider, BookingNotification } from '../types';
import { notificationService } from './notification.service';

class BookingService {
  private supabase;

  constructor() {
    this.supabase = createClient(
      config.supabase.url,
      config.supabase.serviceKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    );
  }

  async getBookingById(bookingId: string): Promise<Booking | null> {
    try {
      const { data, error } = await this.supabase
        .from('bookings')
        .select('*')
        .eq('id', bookingId)
        .single();

      if (error) {
        console.error('Error fetching booking:', error);
        return null;
      }

      return data as Booking;
    } catch (error) {
      console.error('Unexpected error fetching booking:', error);
      return null;
    }
  }

  async getBookingByTransactionId(transactionId: string): Promise<{ data: Booking | null; error: any }> {
    try {
      const { data, error } = await this.supabase
        .from('bookings')
        .select('*')
        .eq('commitment_transaction_id', transactionId)
        .single();

      if (error && error.code !== 'PGRST116') {
        console.error('Error fetching booking by transaction ID:', error);
        return { data: null, error };
      }

      return { data: data as Booking, error: null };
    } catch (error) {
      console.error('Unexpected error fetching booking by transaction ID:', error);
      return { data: null, error };
    }
  }

  private async getProviderDetails(providerId: string): Promise<Provider | null> {
    try {
      const { data, error } = await this.supabase
        .from('profiles')
        .select('id, phone, display_name')
        .eq('id', providerId)
        .single();

      if (error || !data) {
        console.error('Error fetching provider:', error);
        return null;
      }

      return {
        id: data.id,
        phone: data.phone,
        name: data.display_name,
      } as Provider;
    } catch (error) {
      console.error('Error in getProviderDetails:', error);
      return null;
    }
  }

  private async getClientDetails(clientId: string): Promise<any> {
    try {
      const { data, error } = await this.supabase
        .from('profiles')
        .select('id, phone, display_name')
        .eq('id', clientId)
        .single();

      if (error || !data) {
        console.error('Error fetching client:', error);
        return null;
      }

      return {
        id: data.id,
        phone: data.phone,
        name: data.display_name,
      };
    } catch (error) {
      console.error('Error in getClientDetails:', error);
      return null;
    }
  }

  async notifyProviderOfNewBooking(bookingId: string): Promise<boolean> {
    try {
      const booking = await this.getBookingById(bookingId);
      if (!booking) {
        console.error('Booking not found:', bookingId);
        return false;
      }

      const provider = await this.getProviderDetails(booking.provider_id);
      if (!provider || !provider.phone) {
        console.error('Provider not found or has no phone:', booking.provider_id);
        return false;
      }

      const client = await this.getClientDetails(booking.client_id);
      if (!client) {
        console.error('Client not found:', booking.client_id);
        return false;
      }

      const notification: BookingNotification = {
        booking_id: booking.id,
        provider_phone: provider.phone,
        client_name: client.name || 'Client',
        service_name: booking.service_name,
        booking_date: booking.booking_date,
        booking_time: booking.booking_time,
        location_type: booking.location_type,
        total_amount: booking.total_amount,
      };

      const result = await notificationService.sendBookingNotification(notification);
      
      if (result.success) {
        await this.supabase
          .from('bookings')
          .update({ 
            notification_sent: true,
            notification_sent_at: new Date().toISOString() 
          })
          .eq('id', bookingId);
      }

      return result.success;
    } catch (error) {
      console.error('Error notifying provider:', error);
      return false;
    }
  }

  async updateBookingPaymentStatus(
    bookingId: string,
    paymentType: 'commitment' | 'balance' | 'full',
    transactionId: string,
    amount: number
  ): Promise<boolean> {
    try {
      const updates: any = {
        updated_at: new Date().toISOString(),
      };

      if (paymentType === 'commitment') {
        updates.commitment_paid = true;
        updates.commitment_transaction_id = transactionId;
        updates.commitment_paid_at = new Date().toISOString();
      } else if (paymentType === 'balance') {
        updates.balance_paid = true;
        updates.balance_transaction_id = transactionId;
        updates.balance_paid_at = new Date().toISOString();
        updates.status = 'confirmed';
      } else if (paymentType === 'full') {
        updates.commitment_paid = true;
        updates.balance_paid = true;
        updates.full_payment_transaction_id = transactionId;
        updates.full_payment_at = new Date().toISOString();
        updates.status = 'confirmed';
      }

      const { error } = await this.supabase
        .from('bookings')
        .update(updates)
        .eq('id', bookingId);

      if (error) {
        console.error('Error updating booking payment status:', error);
        return false;
      }

      return true;
    } catch (error) {
      console.error('Unexpected error updating payment status:', error);
      return false;
    }
  }

  async notifyPaymentConfirmation(
    bookingId: string,
    paymentType: string,
    amount: number
  ): Promise<void> {
    try {
      const booking = await this.getBookingById(bookingId);
      if (!booking) return;

      const client = await this.getClientDetails(booking.client_id);
      if (!client || !client.phone) return;

      await notificationService.sendPaymentConfirmation(
        client.phone,
        bookingId,
        amount,
        paymentType
      );
    } catch (error) {
      console.error('Error sending payment confirmation:', error);
    }
  }

  async createBookingWithPayment(bookingData: any): Promise<{ booking: any | null; error: any }> {
    try {
      const paymentType = bookingData.payment_type;
      const isCommitmentOrFull = paymentType === 'commitment' || paymentType === 'full';
      const isFull = paymentType === 'full';

      // Ensure transaction_id is a valid UUID string
      const transactionId = bookingData.transaction_id;

      const { data: booking, error } = await this.supabase
        .from('bookings')
        .insert({
          client_id: bookingData.client_id,
          provider_id: bookingData.provider_id,
          service_name: bookingData.service_name,
          service_duration: bookingData.service_duration,
          service_price: bookingData.service_price,
          booking_date: bookingData.booking_date,
          booking_time: bookingData.booking_time,
          duration_minutes: bookingData.duration_minutes || 120,
          location_type: bookingData.location_type,
          location_details: bookingData.location_details || null,
          client_notes: bookingData.client_notes || null,
          platform_fee: bookingData.platform_fee,
          commitment_fee: bookingData.commitment_fee,
          balance_due: bookingData.balance_due,
          total_amount: bookingData.total_amount,
          payment_type: paymentType,
          commitment_paid: isCommitmentOrFull,
          commitment_transaction_id: isCommitmentOrFull ? transactionId : null,
          commitment_paid_at: isCommitmentOrFull ? new Date().toISOString() : null,
          balance_paid: isFull,
          balance_transaction_id: isFull ? transactionId : null,
          balance_paid_at: isFull ? new Date().toISOString() : null,
          full_payment_transaction_id: isFull ? transactionId : null,
          full_payment_at: isFull ? new Date().toISOString() : null,
          status: isFull ? 'confirmed' : 'pending'
        })
        .select()
        .single();

      if (error) {
        console.error('Error creating booking with payment:', error);
        return { booking: null, error };
      }

      return { booking, error: null };
    } catch (error) {
      console.error('Unexpected error creating booking with payment:', error);
      return { booking: null, error };
    }
  }

  async acceptBooking(bookingId: string, providerId: string): Promise<{ success: boolean; error: any }> {
    try {
      console.log('\n🔵 BookingService.acceptBooking called');
      console.log('  bookingId:', bookingId);
      console.log('  providerId:', providerId);

      const booking = await this.getBookingById(bookingId);
      if (!booking) {
        console.log('  ❌ Booking not found');
        return { success: false, error: new Error('Booking not found') };
      }
      console.log('  ✅ Booking found:', booking.id, 'status:', booking.status);

      if (booking.provider_id !== providerId) {
        console.log('  ❌ Unauthorized - provider mismatch');
        return { success: false, error: new Error('Unauthorized') };
      }

      if (booking.status !== 'pending') {
        console.log('  ❌ Invalid status:', booking.status);
        return { success: false, error: new Error('Booking cannot be accepted in current status') };
      }

      console.log('  📝 Updating booking status to confirmed...');
      const { error } = await this.supabase
        .from('bookings')
        .update({ status: 'confirmed', confirmed_at: new Date().toISOString() })
        .eq('id', bookingId);

      if (error) {
        console.error('  ❌ Error updating booking:', error);
        return { success: false, error };
      }
      console.log('  ✅ Booking status updated');

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending SMS to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'confirmed',
          `${provider?.name || 'Your provider'} has accepted your booking for ${booking.service_name} on ${booking.booking_date} at ${booking.booking_time}.`
        );
      }

      if (provider && provider.phone) {
        console.log('  📱 Sending SMS to provider...');
        await notificationService.sendCustomMessage(
          provider.phone,
          `You have confirmed booking ${bookingId} for ${booking.service_name} on ${booking.booking_date} at ${booking.booking_time}. Client: ${client?.name || 'Client'}`
        );
      }

      console.log('  ✅ Accept booking completed successfully');
      return { success: true, error: null };
    } catch (error) {
      console.error('  ❌ Unexpected error accepting booking:', error);
      return { success: false, error };
    }
  }

  async completeBooking(bookingId: string, providerId: string): Promise<{ success: boolean; error: any }> {
    try {
      console.log('\n🔵 BookingService.completeBooking called');
      console.log('  bookingId:', bookingId);
      console.log('  providerId:', providerId);

      const booking = await this.getBookingById(bookingId);
      if (!booking) {
        console.log('  ❌ Booking not found');
        return { success: false, error: new Error('Booking not found') };
      }
      console.log('  ✅ Booking found:', booking.id, 'status:', booking.status);

      if (booking.provider_id !== providerId) {
        console.log('  ❌ Unauthorized - provider mismatch');
        return { success: false, error: new Error('Unauthorized') };
      }

      if (!['confirmed', 'in_progress'].includes(booking.status)) {
        console.log('  ❌ Invalid status:', booking.status);
        return { success: false, error: new Error('Booking cannot be completed in current status') };
      }

      console.log('  📝 Updating booking status to completed...');
      const { error } = await this.supabase
        .from('bookings')
        .update({ status: 'completed', completed_at: new Date().toISOString() })
        .eq('id', bookingId);

      if (error) {
        console.error('  ❌ Error updating booking:', error);
        return { success: false, error };
      }
      console.log('  ✅ Booking status updated - escrow release trigger should fire');

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending SMS to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'completed',
          `Your booking for ${booking.service_name} has been completed. Thank you for using VibeLinx!`
        );
      }

      if (provider && provider.phone) {
        console.log('  📱 Sending SMS to provider...');
        await notificationService.sendCustomMessage(
          provider.phone,
          `Booking ${bookingId} completed! Your payment of ZMW ${booking.total_amount.toFixed(2)} will be released to your wallet.`
        );
      }

      console.log('  ✅ Complete booking finished successfully');
      return { success: true, error: null };
    } catch (error) {
      console.error('  ❌ Unexpected error completing booking:', error);
      return { success: false, error };
    }
  }

  async declineBooking(bookingId: string, providerId: string, reason?: string): Promise<{ success: boolean; error: any }> {
    try {
      console.log('\n🔵 BookingService.declineBooking called');
      console.log('  bookingId:', bookingId);
      console.log('  providerId:', providerId);
      console.log('  reason:', reason || 'N/A');

      const booking = await this.getBookingById(bookingId);
      if (!booking) {
        console.log('  ❌ Booking not found');
        return { success: false, error: new Error('Booking not found') };
      }
      console.log('  ✅ Booking found:', booking.id, 'status:', booking.status);

      if (booking.provider_id !== providerId) {
        console.log('  ❌ Unauthorized - provider mismatch');
        return { success: false, error: new Error('Unauthorized') };
      }

      if (booking.status !== 'pending') {
        console.log('  ❌ Invalid status:', booking.status);
        return { success: false, error: new Error('Booking cannot be declined in current status') };
      }

      console.log('  📝 Updating booking status to declined...');
      const { error } = await this.supabase
        .from('bookings')
        .update({ 
          status: 'declined', 
          declined_at: new Date().toISOString(),
          cancellation_reason: reason || 'Provider declined'
        })
        .eq('id', bookingId);

      if (error) {
        console.error('  ❌ Error updating booking:', error);
        return { success: false, error };
      }
      console.log('  ✅ Booking status updated - refund trigger should fire');

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending SMS to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'declined',
          `Your booking for ${booking.service_name} has been declined by the provider. ${reason ? 'Reason: ' + reason : ''} Your payment will be refunded.`
        );
      }

      if (provider && provider.phone) {
        console.log('  📱 Sending SMS to provider...');
        await notificationService.sendCustomMessage(
          provider.phone,
          `You have declined booking ${bookingId}. The client will be notified and refunded.`
        );
      }

      console.log('  ✅ Decline booking finished successfully');
      return { success: true, error: null };
    } catch (error) {
      console.error('  ❌ Unexpected error declining booking:', error);
      return { success: false, error };
    }
  }
}

export const bookingService = new BookingService();
