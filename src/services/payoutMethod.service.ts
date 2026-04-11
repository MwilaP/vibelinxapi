import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';

interface SavePayoutMethodData {
  user_id: string;
  payment_method: 'mtn' | 'airtel' | 'zamtel';
  payment_phone: string;
  account_name?: string;
  is_default?: boolean;
}

class PayoutMethodService {
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

  private validatePhoneNumber(phone: string, method: string): boolean {
    // Remove spaces and special characters
    const cleaned = phone.replace(/[\s\-\(\)]/g, '');
    
    // Check if it's a valid Zambian number
    const zambianPattern = /^(260|0)?(76|77|75|96|97|95)\d{7}$/;
    
    if (!zambianPattern.test(cleaned)) {
      return false;
    }

    // Validate operator-specific prefixes
    const prefix = cleaned.replace(/^(260|0)/, '').substring(0, 2);
    
    if (method === 'mtn' && !['96', '76'].includes(prefix)) {
      return false;
    }
    if (method === 'airtel' && !['97', '77'].includes(prefix)) {
      return false;
    }
    if (method === 'zamtel' && !['95', '75'].includes(prefix)) {
      return false;
    }

    return true;
  }

  async savePayoutMethod(data: SavePayoutMethodData): Promise<{ method: any | null; error: any }> {
    try {
      logger.info('Saving payout method', {
        userId: data.user_id,
        paymentMethod: data.payment_method,
      });

      // Validate phone number
      if (!this.validatePhoneNumber(data.payment_phone, data.payment_method)) {
        return {
          method: null,
          error: {
            message: `Invalid phone number for ${data.payment_method.toUpperCase()}`,
            code: 'INVALID_PHONE_NUMBER'
          }
        };
      }

      // Check if method already exists
      const { data: existing } = await this.supabase
        .from('payout_methods')
        .select('*')
        .eq('user_id', data.user_id)
        .eq('payment_phone', data.payment_phone)
        .single();

      if (existing) {
        // Update existing method
        const { data: updated, error: updateError } = await this.supabase
          .from('payout_methods')
          .update({
            payment_method: data.payment_method,
            account_name: data.account_name,
            is_default: data.is_default || false,
            updated_at: new Date().toISOString(),
          })
          .eq('id', existing.id)
          .select()
          .single();

        if (updateError) {
          logger.error('Error updating payout method:', updateError);
          return { method: null, error: updateError };
        }

        return { method: updated, error: null };
      }

      // Check if this is the first method for the user
      const { data: existingMethods } = await this.supabase
        .from('payout_methods')
        .select('id')
        .eq('user_id', data.user_id);

      const isFirstMethod = !existingMethods || existingMethods.length === 0;

      // Create new method
      const { data: method, error: insertError } = await this.supabase
        .from('payout_methods')
        .insert({
          user_id: data.user_id,
          payment_method: data.payment_method,
          payment_phone: data.payment_phone,
          account_name: data.account_name,
          is_default: data.is_default || isFirstMethod, // First method is default
          is_verified: false,
        })
        .select()
        .single();

      if (insertError) {
        logger.error('Error creating payout method:', insertError);
        return { method: null, error: insertError };
      }

      logger.info('Payout method saved', { methodId: method.id });
      return { method, error: null };
    } catch (error) {
      logger.error('Unexpected error saving payout method:', error);
      return { method: null, error };
    }
  }

  async getPayoutMethods(userId: string): Promise<{ methods: any[]; error: any }> {
    try {
      const { data: methods, error } = await this.supabase
        .from('payout_methods')
        .select('*')
        .eq('user_id', userId)
        .order('is_default', { ascending: false })
        .order('last_used_at', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false });

      if (error) {
        logger.error('Error fetching payout methods:', error);
        return { methods: [], error };
      }

      return { methods: methods || [], error: null };
    } catch (error) {
      logger.error('Unexpected error fetching payout methods:', error);
      return { methods: [], error };
    }
  }

  async getDefaultPayoutMethod(userId: string): Promise<{ method: any | null; error: any }> {
    try {
      const { data: method, error } = await this.supabase
        .from('payout_methods')
        .select('*')
        .eq('user_id', userId)
        .eq('is_default', true)
        .single();

      if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
        logger.error('Error fetching default payout method:', error);
        return { method: null, error };
      }

      return { method: method || null, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching default payout method:', error);
      return { method: null, error };
    }
  }

  async setDefaultPayoutMethod(userId: string, methodId: string): Promise<{ success: boolean; error: any }> {
    try {
      // Verify method belongs to user
      const { data: method, error: fetchError } = await this.supabase
        .from('payout_methods')
        .select('*')
        .eq('id', methodId)
        .eq('user_id', userId)
        .single();

      if (fetchError || !method) {
        return { success: false, error: fetchError || new Error('Method not found') };
      }

      // Update method to be default (trigger will handle unsetting others)
      const { error: updateError } = await this.supabase
        .from('payout_methods')
        .update({ is_default: true })
        .eq('id', methodId);

      if (updateError) {
        logger.error('Error setting default payout method:', updateError);
        return { success: false, error: updateError };
      }

      logger.info('Default payout method set', { methodId });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error setting default payout method:', error);
      return { success: false, error };
    }
  }

  async deletePayoutMethod(userId: string, methodId: string): Promise<{ success: boolean; error: any }> {
    try {
      // Verify method belongs to user
      const { data: method, error: fetchError } = await this.supabase
        .from('payout_methods')
        .select('*')
        .eq('id', methodId)
        .eq('user_id', userId)
        .single();

      if (fetchError || !method) {
        return { success: false, error: fetchError || new Error('Method not found') };
      }

      const wasDefault = method.is_default;

      // Delete method
      const { error: deleteError } = await this.supabase
        .from('payout_methods')
        .delete()
        .eq('id', methodId);

      if (deleteError) {
        logger.error('Error deleting payout method:', deleteError);
        return { success: false, error: deleteError };
      }

      // If deleted method was default, set another as default
      if (wasDefault) {
        const { data: remainingMethods } = await this.supabase
          .from('payout_methods')
          .select('id')
          .eq('user_id', userId)
          .order('last_used_at', { ascending: false, nullsFirst: false })
          .limit(1);

        if (remainingMethods && remainingMethods.length > 0) {
          await this.supabase
            .from('payout_methods')
            .update({ is_default: true })
            .eq('id', remainingMethods[0].id);
        }
      }

      logger.info('Payout method deleted', { methodId });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error deleting payout method:', error);
      return { success: false, error };
    }
  }

  async updateLastUsed(methodId: string): Promise<{ success: boolean; error: any }> {
    try {
      const { error } = await this.supabase
        .from('payout_methods')
        .update({ last_used_at: new Date().toISOString() })
        .eq('id', methodId);

      if (error) {
        logger.error('Error updating last used timestamp:', error);
        return { success: false, error };
      }

      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error updating last used:', error);
      return { success: false, error };
    }
  }
}

export const payoutMethodService = new PayoutMethodService();
