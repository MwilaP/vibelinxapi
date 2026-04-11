import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import { logger } from '../utils/logger';
import { SystemSetting, UpdateSettingRequest } from '../types/settings.types';

class SettingsService {
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

  async getSettings(): Promise<{ settings: SystemSetting[] | null; error: any }> {
    try {
      const { data: settings, error } = await this.supabase
        .from('system_settings')
        .select('*')
        .order('setting_key', { ascending: true });

      if (error) {
        logger.error('Error fetching settings:', error);
        return { settings: null, error };
      }

      return { settings, error: null };
    } catch (error) {
      logger.error('Unexpected error fetching settings:', error);
      return { settings: null, error };
    }
  }

  async getSetting(key: string): Promise<{ setting: SystemSetting | null; error: any }> {
    try {
      const { data: setting, error } = await this.supabase
        .from('system_settings')
        .select('*')
        .eq('setting_key', key)
        .single();

      if (error) {
        logger.error(`Error fetching setting ${key}:`, error);
        return { setting: null, error };
      }

      return { setting, error: null };
    } catch (error) {
      logger.error(`Unexpected error fetching setting ${key}:`, error);
      return { setting: null, error };
    }
  }

  async updateSetting(data: UpdateSettingRequest): Promise<{ success: boolean; error: any }> {
    try {
      logger.info('Updating setting', {
        key: data.setting_key,
        value: data.setting_value,
        adminId: data.admin_id,
      });

      // Use the database function to update with audit trail
      const { data: result, error } = await this.supabase
        .rpc('update_setting', {
          p_setting_key: data.setting_key,
          p_setting_value: data.setting_value,
          p_updated_by: data.admin_id,
        });

      if (error) {
        logger.error('Error updating setting:', error);
        return { success: false, error };
      }

      if (!result) {
        return { success: false, error: new Error('Setting not found') };
      }

      logger.info('Setting updated successfully', { key: data.setting_key });
      return { success: true, error: null };
    } catch (error) {
      logger.error('Unexpected error updating setting:', error);
      return { success: false, error };
    }
  }

  async getMinWithdrawalAmount(): Promise<number> {
    try {
      const { data, error } = await this.supabase
        .rpc('get_setting_decimal', { p_setting_key: 'min_withdrawal_amount' });

      if (error) {
        logger.error('Error fetching min withdrawal amount:', error);
        return 50; // Fallback to default
      }

      return data || 50;
    } catch (error) {
      logger.error('Unexpected error fetching min withdrawal amount:', error);
      return 50; // Fallback to default
    }
  }

  async getSubscriptionPrice(planType: 'monthly' | 'annual'): Promise<number> {
    try {
      const settingKey = planType === 'monthly' 
        ? 'monthly_subscription_fee' 
        : 'annual_subscription_fee';

      const { data, error } = await this.supabase
        .rpc('get_setting_decimal', { p_setting_key: settingKey });

      if (error) {
        logger.error(`Error fetching ${planType} subscription price:`, error);
        return planType === 'monthly' ? 50 : 500; // Fallback to defaults
      }

      return data || (planType === 'monthly' ? 50 : 500);
    } catch (error) {
      logger.error(`Unexpected error fetching ${planType} subscription price:`, error);
      return planType === 'monthly' ? 50 : 500; // Fallback to defaults
    }
  }
}

export const settingsService = new SettingsService();
