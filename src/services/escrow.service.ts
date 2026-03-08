import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';
import { walletService } from './wallet.service';

interface CreateEscrowData {
  booking_id: string;
  client_wallet_id: string;
  provider_wallet_id: string;
  amount: number;
  metadata?: any;
}

interface ReleaseEscrowData {
  escrow_id: string;
  reason?: string;
  resolved_by?: string;
}

interface RefundEscrowData {
  escrow_id: string;
  reason: string;
  resolved_by?: string;
}

class EscrowService {
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

  async createEscrow(data: CreateEscrowData): Promise<{ escrow: any | null; error: any }> {
    try {
      logger.info('Creating escrow transaction', {
        bookingId: data.booking_id,
        amount: data.amount,
      });

      const lockResult = await walletService.lockFunds(
        data.client_wallet_id,
        data.amount,
        data.booking_id
      );

      if (!lockResult.success) {
        logger.error('Failed to lock funds for escrow', {
          error: lockResult.error,
          walletId: data.client_wallet_id,
        });
        return { escrow: null, error: lockResult.error };
      }

      const { data: escrow, error } = await this.supabase
        .from('escrow_transactions')
        .insert({
          booking_id: data.booking_id,
          client_wallet_id: data.client_wallet_id,
          provider_wallet_id: data.provider_wallet_id,
          amount: data.amount,
          status: 'locked',
          locked_at: new Date().toISOString(),
          metadata: data.metadata,
        })
        .select()
        .single();

      if (error) {
        logger.error('Error creating escrow record:', error);
        await walletService.unlockFunds(
          data.client_wallet_id,
          data.amount,
          data.booking_id,
          true
        );
        return { escrow: null, error };
      }

      logger.info('Escrow created successfully', {
        escrowId: escrow.id,
        bookingId: data.booking_id,
        amount: data.amount,
      });

      return { escrow, error: null };
    } catch (error) {
      logger.error('Unexpected error creating escrow:', error);
      return { escrow: null, error };
    }
  }

  async releaseEscrow(data: ReleaseEscrowData): Promise<{ success: boolean; error: any }> {
    try {
      logger.info('Releasing escrow to provider', {
        escrowId: data.escrow_id,
      });

      const { escrow, error: fetchError } = await this.getEscrowById(data.escrow_id);
      
      if (fetchError || !escrow) {
        logger.error('Escrow not found', { escrowId: data.escrow_id });
        return { success: false, error: fetchError || new Error('Escrow not found') };
      }

      if (escrow.status !== 'locked') {
        logger.warn('Escrow not in locked state', {
          escrowId: data.escrow_id,
          currentStatus: escrow.status,
        });
        return { success: false, error: new Error('Escrow is not in locked state') };
      }

      const transferResult = await walletService.transferLockedFunds(
        escrow.client_wallet_id,
        escrow.provider_wallet_id,
        parseFloat(escrow.amount),
        escrow.booking_id
      );

      if (!transferResult.success) {
        logger.error('Failed to transfer locked funds', {
          error: transferResult.error,
        });
        return { success: false, error: transferResult.error };
      }

      const { error: updateError } = await this.supabase
        .from('escrow_transactions')
        .update({
          status: 'released',
          released_at: new Date().toISOString(),
          released_to_provider_at: new Date().toISOString(),
          reason: data.reason || 'Service completed successfully',
          resolved_by: data.resolved_by,
          updated_at: new Date().toISOString(),
        })
        .eq('id', data.escrow_id);

      if (updateError) {
        logger.error('Error updating escrow status:', updateError);
        return { success: false, error: updateError };
      }

      logger.info('Escrow released successfully', {
        escrowId: data.escrow_id,
        amount: escrow.amount,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error releasing escrow:', error);
      return { success: false, error };
    }
  }

  async refundEscrow(data: RefundEscrowData): Promise<{ success: boolean; error: any }> {
    try {
      logger.info('Refunding escrow to client', {
        escrowId: data.escrow_id,
        reason: data.reason,
      });

      const { escrow, error: fetchError } = await this.getEscrowById(data.escrow_id);
      
      if (fetchError || !escrow) {
        logger.error('Escrow not found', { escrowId: data.escrow_id });
        return { success: false, error: fetchError || new Error('Escrow not found') };
      }

      if (escrow.status !== 'locked' && escrow.status !== 'disputed') {
        logger.warn('Escrow not in refundable state', {
          escrowId: data.escrow_id,
          currentStatus: escrow.status,
        });
        return { success: false, error: new Error('Escrow is not in refundable state') };
      }

      const unlockResult = await walletService.unlockFunds(
        escrow.client_wallet_id,
        parseFloat(escrow.amount),
        escrow.booking_id,
        true
      );

      if (!unlockResult.success) {
        logger.error('Failed to unlock and refund funds', {
          error: unlockResult.error,
        });
        return { success: false, error: unlockResult.error };
      }

      const { error: updateError } = await this.supabase
        .from('escrow_transactions')
        .update({
          status: 'refunded',
          refunded_at: new Date().toISOString(),
          reason: data.reason,
          resolved_by: data.resolved_by,
          updated_at: new Date().toISOString(),
        })
        .eq('id', data.escrow_id);

      if (updateError) {
        logger.error('Error updating escrow status:', updateError);
        return { success: false, error: updateError };
      }

      logger.info('Escrow refunded successfully', {
        escrowId: data.escrow_id,
        amount: escrow.amount,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error refunding escrow:', error);
      return { success: false, error };
    }
  }

  async disputeEscrow(escrowId: string, reason: string): Promise<{ success: boolean; error: any }> {
    try {
      const { error } = await this.supabase
        .from('escrow_transactions')
        .update({
          status: 'disputed',
          reason: reason,
          updated_at: new Date().toISOString(),
        })
        .eq('id', escrowId);

      if (error) {
        logger.error('Error marking escrow as disputed:', error);
        return { success: false, error };
      }

      logger.info('Escrow marked as disputed', {
        escrowId,
        reason,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error disputing escrow:', error);
      return { success: false, error };
    }
  }

  async cancelEscrow(escrowId: string, reason: string): Promise<{ success: boolean; error: any }> {
    try {
      const { escrow, error: fetchError } = await this.getEscrowById(escrowId);
      
      if (fetchError || !escrow) {
        return { success: false, error: fetchError || new Error('Escrow not found') };
      }

      if (escrow.status !== 'locked') {
        return { success: false, error: new Error('Only locked escrow can be cancelled') };
      }

      const unlockResult = await walletService.unlockFunds(
        escrow.client_wallet_id,
        parseFloat(escrow.amount),
        escrow.booking_id,
        true
      );

      if (!unlockResult.success) {
        return { success: false, error: unlockResult.error };
      }

      const { error: updateError } = await this.supabase
        .from('escrow_transactions')
        .update({
          status: 'cancelled',
          reason: reason,
          updated_at: new Date().toISOString(),
        })
        .eq('id', escrowId);

      if (updateError) {
        logger.error('Error cancelling escrow:', updateError);
        return { success: false, error: updateError };
      }

      logger.info('Escrow cancelled successfully', {
        escrowId,
        reason,
      });

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error cancelling escrow:', error);
      return { success: false, error };
    }
  }

  async getEscrowById(escrowId: string): Promise<{ escrow: any | null; error: any }> {
    try {
      const { data: escrow, error } = await this.supabase
        .from('escrow_transactions')
        .select('*')
        .eq('id', escrowId)
        .single();

      if (error) {
        logger.error('Error fetching escrow:', error);
        return { escrow: null, error };
      }

      return { escrow, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching escrow:', error);
      return { escrow: null, error };
    }
  }

  async getEscrowByBookingId(bookingId: string): Promise<{ escrow: any | null; error: any }> {
    try {
      const { data: escrow, error } = await this.supabase
        .from('escrow_transactions')
        .select('*')
        .eq('booking_id', bookingId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single();

      if (error && error.code !== 'PGRST116') {
        logger.error('Error fetching escrow by booking:', error);
        return { escrow: null, error };
      }

      return { escrow: escrow || null, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching escrow by booking:', error);
      return { escrow: null, error };
    }
  }

  async getEscrowsByWallet(walletId: string, status?: string): Promise<{ escrows: any[]; error: any }> {
    try {
      let query = this.supabase
        .from('escrow_transactions')
        .select('*')
        .or(`client_wallet_id.eq.${walletId},provider_wallet_id.eq.${walletId}`)
        .order('created_at', { ascending: false });

      if (status) {
        query = query.eq('status', status);
      }

      const { data: escrows, error } = await query;

      if (error) {
        logger.error('Error fetching escrows by wallet:', error);
        return { escrows: [], error };
      }

      return { escrows: escrows || [], error: null };
    } catch (error) {
      logger.error('Unexpected error fetching escrows by wallet:', error);
      return { escrows: [], error };
    }
  }

  async getAllEscrows(filters?: {
    status?: string;
    limit?: number;
    offset?: number;
  }): Promise<{ escrows: any[]; total: number; error: any }> {
    try {
      let query = this.supabase
        .from('escrow_transactions')
        .select('*, bookings(*), wallets!client_wallet_id(*)', { count: 'exact' })
        .order('created_at', { ascending: false });

      if (filters?.status) {
        query = query.eq('status', filters.status);
      }

      if (filters?.limit) {
        query = query.limit(filters.limit);
      }

      if (filters?.offset) {
        query = query.range(filters.offset, filters.offset + (filters.limit || 50) - 1);
      }

      const { data: escrows, error, count } = await query;

      if (error) {
        logger.error('Error fetching all escrows:', error);
        return { escrows: [], total: 0, error };
      }

      return { escrows: escrows || [], total: count || 0, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching all escrows:', error);
      return { escrows: [], total: 0, error };
    }
  }
}

export const escrowService = new EscrowService();
