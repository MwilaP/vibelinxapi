import { Request, Response } from 'express';
import { createClient } from '@supabase/supabase-js';
import { config } from '../config';
import sharp from 'sharp';
import axios from 'axios';

const supabase = createClient(
  config.supabase.url,
  config.supabase.serviceKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);

/**
 * Pay for provider profile visibility
 */
export const payVisibilityFee = async (req: Request, res: Response) => {
  try {
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'user_id is required',
      });
    }

    // 1. Get visibility fee from settings
    const { data: feeData, error: feeError } = await supabase
      .rpc('get_setting_decimal', { p_setting_key: 'provider_visibility_fee' });

    if (feeError) {
      console.error('[PROVIDER] Error fetching visibility fee:', feeError);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch visibility fee setting',
      });
    }

    const visibilityFee = feeData || 100.00; // Fallback to 100 if not found

    // 2. Check if provider already has active visibility
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('visibility_status, role')
      .eq('id', user_id)
      .single();

    if (profileError || !profile) {
      return res.status(404).json({
        success: false,
        error: 'Provider profile not found',
      });
    }

    if (profile.role !== 'provider') {
      return res.status(400).json({
        success: false,
        error: 'Only providers can pay for visibility',
      });
    }

    if (profile.visibility_status === 'active') {
      return res.status(400).json({
        success: false,
        error: 'Provider visibility is already active',
      });
    }

    // 2.1 Check if visibility fee is required
    const { data: requireFeeData, error: requireFeeError } = await supabase
      .rpc('get_setting_value', { p_setting_key: 'require_visibility_fee' });

    if (requireFeeError) {
      console.error('[PROVIDER] Error fetching require_visibility_fee setting:', requireFeeError);
    } else if (requireFeeData !== null) {
      const requireFee = requireFeeData === true || requireFeeData === 'true';
      if (!requireFee) {
        return res.status(400).json({
          success: false,
          error: 'Visibility fee is currently not required',
        });
      }
    }

    // 3. Get provider wallet
    let { data: wallet, error: walletError } = await supabase
      .from('wallets')
      .select('id, available_balance')
      .eq('user_id', user_id)
      .eq('user_type', 'provider')
      .single();

    if (walletError || !wallet) {
      return res.status(404).json({
        success: false,
        error: 'Provider wallet not found',
      });
    }

    // 4. Check balance
    if (wallet.available_balance < visibilityFee) {
      return res.status(400).json({
        success: false,
        error: 'Insufficient wallet balance',
        data: {
          required: visibilityFee,
          available: wallet.available_balance,
        },
      });
    }

    // 5. Process payment (Transaction)
    
    // Deduct from wallet
    const { error: walletUpdateError } = await supabase
      .from('wallets')
      .update({
        available_balance: wallet.available_balance - visibilityFee,
        updated_at: new Date().toISOString(),
      })
      .eq('id', wallet.id);

    if (walletUpdateError) {
      return res.status(500).json({
        success: false,
        error: 'Failed to update wallet balance',
      });
    }

    // Create public transaction record
    const { data: transaction, error: txError } = await supabase
      .from('transactions')
      .insert({
        user_id,
        amount: -visibilityFee,
        type: 'payment',
        status: 'completed',
        description: 'Provider Visibility Fee',
        metadata: {
          fee_type: 'visibility_fee',
          amount: visibilityFee,
        },
      })
      .select()
      .single();

    if (txError) {
      // Rollback wallet (best effort)
      await supabase.from('wallets').update({
        available_balance: wallet.available_balance,
      }).eq('id', wallet.id);

      return res.status(500).json({
        success: false,
        error: 'Failed to create transaction record',
      });
    }

    // Create wallet transaction record
    await supabase.from('wallet_transactions').insert({
      wallet_id: wallet.id,
      transaction_type: 'service_payment',
      amount: -visibilityFee,
      balance_before: wallet.available_balance,
      balance_after: wallet.available_balance - visibilityFee,
      description: 'Provider Visibility Fee',
      reference_id: transaction.id,
      reference_type: 'payment',
    });

    // 6. Update profile visibility status
    const { error: profileUpdateError } = await supabase
      .from('profiles')
      .update({
        visibility_status: 'active',
        updated_at: new Date().toISOString(),
      })
      .eq('id', user_id);

    if (profileUpdateError) {
      return res.status(500).json({
        success: false,
        error: 'Failed to update profile visibility status',
      });
    }

    // Process Referral Earnings
    try {
      const { referralService } = require('../services/referral.service');
      await referralService.processEvent(
        'provider_visibility',
        transaction.id,
        user_id,
        visibilityFee
      );
    } catch (refError) {
      console.error('[PROVIDER] Error processing referral earnings:', refError);
    }

    return res.status(200).json({
      success: true,
      message: 'Visibility fee paid successfully',
      data: {
        transaction_id: transaction.id,
        amount_paid: visibilityFee,
        visibility_status: 'active',
      },
    });
  } catch (error: any) {
    console.error('[PROVIDER] Error paying visibility fee:', error);
    return res.status(500).json({
      success: false,
      error: error.message || 'Internal server error',
    });
  }
};

/**
 * Generate branded share preview image for a provider
 */
export const generateShareImage = async (req: Request, res: Response) => {
  try {
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'user_id is required',
      });
    }

    // 1. Fetch provider details
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('display_name, photos, is_verified, role, slug')
      .eq('id', user_id)
      .single();

    if (profileError || !profile) {
      return res.status(404).json({
        success: false,
        error: 'Provider profile not found',
      });
    }

    if (profile.role !== 'provider') {
      return res.status(400).json({
        success: false,
        error: 'Only providers can generate share images',
      });
    }

    // 2. Fetch primary photo and base64 encode it
    const photoUrl = profile.photos && profile.photos.length > 0 ? profile.photos[0] : null;
    let base64Photo = '';

    if (photoUrl) {
      try {
        const imgRes = await axios.get(photoUrl, { responseType: 'arraybuffer' });
        const imgBuffer = Buffer.from(imgRes.data);
        const mimeType = imgRes.headers['content-type'] || 'image/jpeg';
        base64Photo = `data:${mimeType};base64,${imgBuffer.toString('base64')}`;
      } catch (err: any) {
        console.error('[GENERATE_SHARE_IMAGE] Error downloading photo:', err.message);
      }
    }

    // 3. Construct branded SVG (1200x630)
    const verifiedBadge = profile.is_verified
      ? `<g transform="translate(700, 370)">
           <rect width="160" height="42" rx="21" fill="#0ea5e9" />
           <circle cx="21" cy="21" r="11" fill="#ffffff" />
           <path d="M16 21l3 3 5-5" stroke="#0ea5e9" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none" />
           <text x="42" y="27" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-weight="bold" font-size="14" fill="#ffffff">VERIFIED</text>
         </g>`
      : '';

    const photoElement = base64Photo
      ? `<image href="${base64Photo}" x="100" y="135" width="360" height="360" clip-path="url(#circleView)" preserveAspectRatio="xMidYMid slice" />`
      : `<circle cx="280" cy="315" r="180" fill="#1e293b" />
         <text x="280" y="345" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-weight="bold" font-size="96" fill="#64748b" text-anchor="middle">${profile.display_name?.charAt(0) || 'P'}</text>`;

    const svgString = `
      <svg width="1200" height="630" viewBox="0 0 1200 630" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#0f172a;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#1e293b;stop-opacity:1" />
          </linearGradient>
          <clipPath id="circleView">
            <circle cx="280" cy="315" r="180" />
          </clipPath>
        </defs>
        
        <!-- Background -->
        <rect width="1200" height="630" fill="url(#bgGrad)" />
        <circle cx="950" cy="150" r="300" fill="#0ea5e9" opacity="0.03" filter="blur(50px)" />
        
        <!-- Outer Ring for Profile Photo -->
        <circle cx="280" cy="315" r="186" fill="none" stroke="#0ea5e9" stroke-width="6" />
        
        <!-- Profile Photo -->
        ${photoElement}
        
        <!-- Brand Logo (VIBELINX) -->
        <g transform="translate(700, 140)">
          <rect width="54" height="54" rx="14" fill="#0ea5e9" fill-opacity="0.1" stroke="#0ea5e9" stroke-width="4" />
          <path d="M15 17l12 20 12-20" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" fill="none" />
          <text x="74" y="41" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-weight="900" font-size="40" fill="#ffffff" letter-spacing="1">VIBE<tspan fill="#0ea5e9">LINX</tspan></text>
        </g>
        
        <text x="700" y="235" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-weight="bold" font-size="16" fill="#64748b" letter-spacing="3">VERIFIED MEMBER PROFILE</text>
        
        <!-- Provider Display Name -->
        <text x="700" y="325" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-weight="900" font-size="56" fill="#ffffff">${profile.display_name}</text>
        
        <!-- Verified Badge -->
        ${verifiedBadge}
        
        <!-- Footer Text -->
        <text x="700" y="525" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif" font-size="16" fill="#475569">View my profile and book services safely on vibeslinx.com</text>
      </svg>
    `;

    // 4. Render to PNG buffer
    const pngBuffer = await sharp(Buffer.from(svgString)).png().toBuffer();

    // 5. Upload to Supabase Storage in "profile-photos" bucket under "{user_id}/share-preview.png"
    const filePath = `${user_id}/share-preview.png`;
    const { error: uploadError } = await supabase.storage
      .from('profile-photos')
      .upload(filePath, pngBuffer, {
        contentType: 'image/png',
        upsert: true
      });

    if (uploadError) {
      console.error('[GENERATE_SHARE_IMAGE] Storage upload error:', uploadError);
      return res.status(500).json({
        success: false,
        error: 'Failed to upload share image to storage',
      });
    }

    // 6. Get public URL and version it
    const { data: { publicUrl } } = supabase.storage
      .from('profile-photos')
      .getPublicUrl(filePath);

    const versionedUrl = `${publicUrl}?v=${Date.now()}`;

    // 7. Save to profiles.share_image_url
    const { error: updateError } = await supabase
      .from('profiles')
      .update({
        share_image_url: versionedUrl,
        updated_at: new Date().toISOString()
      })
      .eq('id', user_id);

    if (updateError) {
      console.error('[GENERATE_SHARE_IMAGE] Profile update error:', updateError);
      return res.status(500).json({
        success: false,
        error: 'Failed to save share image URL in profile',
      });
    }

    return res.status(200).json({
      success: true,
      message: 'Share image generated successfully',
      data: {
        share_image_url: versionedUrl,
      },
    });

  } catch (error: any) {
    console.error('[GENERATE_SHARE_IMAGE] Unexpected error:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message,
    });
  }
};
