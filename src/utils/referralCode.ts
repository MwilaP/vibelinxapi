/**
 * Referral Code Obfuscation Utility (Node.js/Backend)
 *
 * Mirror of the frontend utility in vibeslinx/src/utils/referralCode.ts.
 * Must use the same SALT.
 */

const SALT = 'VBX_2026_SECRET';

/**
 * Encodes a referral code into a URL-safe opaque token.
 * e.g. "PANGA-9388" → "HhcBFQkxGjY"
 */
export function encodeReferralCode(code: string): string {
  try {
    const saltBytes = Buffer.from(SALT);
    const xored = Buffer.from(
      code.split('').map((c, i) => c.charCodeAt(0) ^ saltBytes[i % saltBytes.length])
    );
    // Base64URL encode (URL-safe, no padding)
    return xored.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  } catch {
    return code;
  }
}

/**
 * Decodes an opaque URL token back to the original referral code.
 * e.g. "HhcBFQkxGjY" → "PANGA-9388"
 */
export function decodeReferralCode(token: string): string {
  // If the token already looks like a raw referral code (e.g. MWILA-4823)
  if (/^[A-Z0-9]+-\d+$/i.test(token)) {
    return token;
  }

  try {
    // Restore base64url → standard base64
    const base64 = token.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64 + '=='.slice(0, (4 - (base64.length % 4)) % 4);
    const bytes = Buffer.from(padded, 'base64');
    const saltBytes = Buffer.from(SALT);
    return Buffer.from(
      bytes.map((b, i) => b ^ saltBytes[i % saltBytes.length])
    ).toString('utf8');
  } catch {
    // Fallback: treat as raw referral code (for legacy unencoded links)
    return token;
  }
}
