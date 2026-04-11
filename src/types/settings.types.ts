export interface SystemSetting {
  id: string;
  setting_key: string;
  setting_value: any;
  setting_type: 'currency' | 'number' | 'text' | 'boolean' | 'json';
  description: string | null;
  display_name: string;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface SettingValue {
  value: number | string | boolean | object;
}

export interface UpdateSettingRequest {
  setting_key: string;
  setting_value: any;
  admin_id: string;
}

export interface SettingsResponse {
  success: boolean;
  data?: SystemSetting | SystemSetting[];
  message?: string;
  error?: string;
}

export type SettingKey = 
  | 'min_withdrawal_amount'
  | 'monthly_subscription_fee'
  | 'annual_subscription_fee';
