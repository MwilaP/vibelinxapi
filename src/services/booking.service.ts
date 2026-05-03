import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { Booking, Provider, BookingNotification } from '../types';
import { notificationService } from './notification.service';
import { walletService } from './wallet.service';
import { escrowService } from './escrow.service';
import { logger } from '../utils/logger';

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
        provider_name: provider.name || 'Provider',
        client_name: client.name || 'Client',
        service_name: booking.service_name,
        booking_date: booking.booking_date,
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
          duration_minutes: bookingData.duration_minutes || 120,
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

      if (isFull && booking) {
        try {
          const platformFee = parseFloat(bookingData.platform_fee || '0');
          if (platformFee > 0) {
            const { referralService } = require('./referral.service');
            await referralService.processEvent('booking_platform_fee', booking.id, bookingData.client_id, platformFee);
            await referralService.processEvent('booking_platform_fee', booking.id, bookingData.provider_id, platformFee);
          }
        } catch (refError) {
          logger.error('Error processing referral earnings for full payment booking:', refError);
        }
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

      if (client && client.phone && provider) {
        console.log('  📱 Sending confirmation SMS to client...');
        const clientNotification: BookingNotification = {
          booking_id: booking.id,
          provider_phone: provider.phone,
          provider_name: provider.name || 'Provider',
          client_name: client.name || 'Client',
          client_phone: client.phone,
          service_name: booking.service_name,
          booking_date: booking.booking_date,
          total_amount: booking.total_amount,
        };
        await notificationService.sendClientConfirmation(clientNotification);
      }

      console.log('  ✅ Accept booking completed successfully');

      // 7. Process Referral Earnings
      try {
        const platformFee = Number(booking.platform_fee || 0);
        if (platformFee > 0) {
          const { referralService } = require('./referral.service');
          
          // Reward client's referrer
          await referralService.processEvent(
            'booking_platform_fee',
            booking.id,
            booking.client_id,
            platformFee
          );

          // Reward provider's referrer
          await referralService.processEvent(
            'booking_platform_fee',
            booking.id,
            booking.provider_id,
            platformFee
          );
        }
      } catch (refError) {
        logger.error('Error processing referral earnings for booking:', refError);
      }

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
      console.log('  ✅ Booking status updated');

      if (booking.payment_type === 'wallet') {
        console.log('  💰 Releasing escrow to provider...');
        const escrowResult = await this.releaseEscrowForBooking(bookingId);
        if (!escrowResult.success) {
          console.error('  ⚠️ Failed to release escrow:', escrowResult.error);
        } else {
          console.log('  ✅ Escrow released to provider wallet');
        }
      }

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending completion SMS to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'completed',
          `Your booking for ${booking.service_name} has been completed. Thank you for using VibeLinx!`
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
      console.log('  ✅ Booking status updated');

      if (booking.payment_type === 'wallet') {
        console.log('  💰 Refunding escrow to client...');
        const escrowResult = await this.refundEscrowForBooking(
          bookingId, 
          reason || 'Provider declined booking'
        );
        if (!escrowResult.success) {
          console.error('  ⚠️ Failed to refund escrow:', escrowResult.error);
        } else {
          console.log('  ✅ Escrow refunded to client wallet');
        }
      }

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending decline notification to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'declined',
          `Your booking for ${booking.service_name} has been declined by the provider. ${reason ? 'Reason: ' + reason : ''} Your payment will be refunded.`
        );
      }

      console.log('  ✅ Decline booking finished successfully');
      return { success: true, error: null };
    } catch (error) {
      console.error('  ❌ Unexpected error declining booking:', error);
      return { success: false, error };
    }
  }

  async cancelBookingByProvider(bookingId: string, providerId: string, reason?: string): Promise<{ success: boolean; error: any }> {
    try {
      console.log('\n🔵 BookingService.cancelBookingByProvider called');
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

      if (!['confirmed', 'in_progress'].includes(booking.status)) {
        console.log('  ❌ Invalid status:', booking.status);
        return { success: false, error: new Error('Only confirmed or in-progress bookings can be cancelled') };
      }

      console.log('  📝 Updating booking status to cancelled...');
      const { error } = await this.supabase
        .from('bookings')
        .update({ 
          status: 'cancelled', 
          cancelled_at: new Date().toISOString(),
          cancellation_reason: reason || 'Provider cancelled booking'
        })
        .eq('id', bookingId);

      if (error) {
        console.error('  ❌ Error updating booking:', error);
        return { success: false, error };
      }
      console.log('  ✅ Booking status updated');

      if (booking.payment_type === 'wallet') {
        console.log('  💰 Refunding escrow to client...');
        const escrowResult = await this.refundEscrowForBooking(
          bookingId, 
          reason || 'Provider cancelled booking'
        );
        if (!escrowResult.success) {
          console.error('  ⚠️ Failed to refund escrow:', escrowResult.error);
        } else {
          console.log('  ✅ Escrow refunded to client wallet');
        }
      }

      console.log('  📞 Fetching client and provider details...');
      const client = await this.getClientDetails(booking.client_id);
      const provider = await this.getProviderDetails(booking.provider_id);
      console.log('  Client phone:', client?.phone || 'N/A');
      console.log('  Provider phone:', provider?.phone || 'N/A');

      if (client && client.phone) {
        console.log('  📱 Sending cancellation notification to client...');
        await notificationService.sendBookingStatusUpdate(
          client.phone,
          bookingId,
          'cancelled',
          `Your booking for ${booking.service_name} has been cancelled by the provider. ${reason ? 'Reason: ' + reason : ''} Your payment will be refunded to your wallet.`
        );
      }

      console.log('  ✅ Cancel booking by provider finished successfully');
      return { success: true, error: null };
    } catch (error) {
      console.error('  ❌ Unexpected error cancelling booking by provider:', error);
      return { success: false, error };
    }
  }

  async createBookingWithWallet(bookingData: any): Promise<{ booking: any | null; error: any }> {
    try {
      logger.info('Creating booking with wallet', {
        clientId: bookingData.client_id,
        providerId: bookingData.provider_id,
        commitmentFee: bookingData.commitment_fee,
      });

      const { wallet: clientWallet, error: clientWalletError } = await walletService.getWalletByUserId(
        bookingData.client_id,
        'client'
      );

      if (clientWalletError || !clientWallet) {
        logger.error('Client wallet not found', { clientId: bookingData.client_id });
        return { booking: null, error: clientWalletError || new Error('Client wallet not found') };
      }

      const { wallet: providerWallet, error: providerWalletError } = await walletService.getWalletByUserId(
        bookingData.provider_id,
        'provider'
      );

      if (providerWalletError || !providerWallet) {
        logger.error('Provider wallet not found', { providerId: bookingData.provider_id });
        return { booking: null, error: providerWalletError || new Error('Provider wallet not found') };
      }

      const availableBalance = parseFloat(clientWallet.available_balance);
      const commitmentFee = parseFloat(bookingData.commitment_fee);

      if (availableBalance < commitmentFee) {
        logger.warn('Insufficient wallet balance', {
          required: commitmentFee,
          available: availableBalance,
        });
        return { 
          booking: null, 
          error: { 
            code: 'INSUFFICIENT_BALANCE',
            message: 'Insufficient wallet balance',
            required: commitmentFee,
            available: availableBalance,
          } 
        };
      }

      const { data: booking, error: bookingError } = await this.supabase
        .from('bookings')
        .insert({
          client_id: bookingData.client_id,
          provider_id: bookingData.provider_id,
          service_name: bookingData.service_name,
          service_duration: bookingData.service_duration,
          service_price: bookingData.service_price,
          booking_date: bookingData.booking_date,
          duration_minutes: bookingData.duration_minutes || 120,
          client_notes: bookingData.client_notes || null,
          platform_fee: bookingData.platform_fee,
          commitment_fee: commitmentFee,
          balance_due: bookingData.balance_due,
          total_amount: bookingData.total_amount,
          payment_type: 'wallet',
          commitment_paid: true,
          commitment_paid_at: new Date().toISOString(),
          status: 'pending'
        })
        .select()
        .single();

      if (bookingError) {
        logger.error('Error creating booking:', bookingError);
        return { booking: null, error: bookingError };
      }

      // Calculate escrow amount (commitment fee minus platform fee)
      // Platform fee is 1% of service price and goes to platform
      // Commitment is 10% of service price and goes to escrow
      // Total commitment fee paid = platform fee + 10% commitment
      const platformFee = parseFloat(bookingData.platform_fee) || 0;
      const providerEscrowAmount = commitmentFee - platformFee;

      // Deduct platform fee from wallet (non-refundable)
      if (platformFee > 0) {
        logger.info('Deducting platform fee from client wallet', {
          walletId: clientWallet.id,
          platformFee,
          bookingId: booking.id,
        });

        const deductResult = await walletService.deductFromWallet({
          wallet_id: clientWallet.id,
          amount: platformFee,
          reference_id: booking.id,
          reference_type: 'booking',
          description: 'Platform fee for booking',
        });

        if (!deductResult.success) {
          logger.error('Failed to deduct platform fee, rolling back booking', {
            error: deductResult.error,
            bookingId: booking.id,
          });
          // Rollback booking if platform fee deduction fails
          await this.supabase
            .from('bookings')
            .delete()
            .eq('id', booking.id);
          return { booking: null, error: deductResult.error };
        }

        logger.info('Platform fee deducted successfully', {
          walletId: clientWallet.id,
          platformFee,
        });
      }

      // Lock commitment fee in escrow (refundable)
      const { escrow, error: escrowError } = await escrowService.createEscrow({
        booking_id: booking.id,
        client_wallet_id: clientWallet.id,
        provider_wallet_id: providerWallet.id,
        amount: providerEscrowAmount,
        metadata: {
          service_name: bookingData.service_name,
          booking_date: bookingData.booking_date,
          platform_fee_deducted: platformFee,
          original_commitment_fee: commitmentFee,
        },
      });

      if (escrowError) {
        logger.error('Error creating escrow, rolling back booking and platform fee', { error: escrowError });
        
        // Refund platform fee if escrow creation fails
        if (platformFee > 0) {
          await walletService.creditWallet({
            wallet_id: clientWallet.id,
            amount: platformFee,
            transaction_id: booking.id,
            description: 'Platform fee refund due to booking creation failure',
          });
        }

        // Delete booking
        await this.supabase
          .from('bookings')
          .delete()
          .eq('id', booking.id);
        return { booking: null, error: escrowError };
      }

      logger.info('Booking created with wallet and escrow', {
        bookingId: booking.id,
        escrowId: escrow.id,
        amount: commitmentFee,
      });

      return { booking, error: null };
    } catch (error) {
      logger.error('Unexpected error creating booking with wallet:', error);
      return { booking: null, error };
    }
  }

  async releaseEscrowForBooking(bookingId: string): Promise<{ success: boolean; error: any }> {
    try {
      logger.info('Releasing escrow for booking', { bookingId });

      const { escrow, error: escrowFetchError } = await escrowService.getEscrowByBookingId(bookingId);

      if (escrowFetchError || !escrow) {
        logger.error('Escrow not found for booking', { bookingId });
        return { success: false, error: escrowFetchError || new Error('Escrow not found') };
      }

      const releaseResult = await escrowService.releaseEscrow({
        escrow_id: escrow.id,
        reason: 'Service completed successfully',
      });

      if (!releaseResult.success) {
        logger.error('Failed to release escrow', { error: releaseResult.error });
        return releaseResult;
      }

      logger.info('Escrow released successfully', { bookingId, escrowId: escrow.id });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error releasing escrow:', error);
      return { success: false, error };
    }
  }

  async refundEscrowForBooking(bookingId: string, reason: string): Promise<{ success: boolean; error: any }> {
    try {
      logger.info('Refunding escrow for booking', { bookingId, reason });

      const { escrow, error: escrowFetchError } = await escrowService.getEscrowByBookingId(bookingId);

      if (escrowFetchError || !escrow) {
        logger.error('Escrow not found for booking', { bookingId });
        return { success: false, error: escrowFetchError || new Error('Escrow not found') };
      }

      const refundResult = await escrowService.refundEscrow({
        escrow_id: escrow.id,
        reason: reason,
      });

      if (!refundResult.success) {
        logger.error('Failed to refund escrow', { error: refundResult.error });
        return refundResult;
      }

      logger.info('Escrow refunded successfully', { bookingId, escrowId: escrow.id });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error refunding escrow:', error);
      return { success: false, error };
    }
  }
}

export const bookingService = new BookingService();
