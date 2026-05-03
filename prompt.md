You are a senior full-stack engineer working on a two-sided service marketplace app.
The platform connects CLIENTS (who book services) and PROVIDERS (who offer services).
Your task is to implement a complete referral and subscription gating system from scratch.
Do not simplify or skip any section. Implement everything described below precisely.

═══════════════════════════════════════════════════════════
SECTION 1 — PLATFORM OVERVIEW & EXISTING FEE STRUCTURE
═══════════════════════════════════════════════════════════

The platform already handles:
- User registration with a role: either CLIENT or PROVIDER
- Service listings created by providers
- Bookings created by clients

Existing fee logic on every booking:
  • Commitment fee  = 10% of total service value (paid upfront by client at booking)
  • Platform fee    = 1% of total service value (deducted from the booking transaction)
  • Provider payout = remaining balance after commitment fee is settled and platform fee deducted

You must not break or alter the existing booking fee logic.
All referral reward calculations layer ON TOP of existing transactions.

═══════════════════════════════════════════════════════════
SECTION 2 — SUBSCRIPTION & VISIBILITY FEE MODEL
═══════════════════════════════════════════════════════════

Two paid plans exist on the platform:

  CLIENT SUBSCRIPTION
  - Fee: K50 per subscription period (period = 30 days unless admin changes it)
  - Grants: access to referral earnings while active
  - Table: client_subscriptions

  PROVIDER VISIBILITY FEE
  - Fee: K30 per visibility period (period = 30 days unless admin changes it)
  - Grants: boosted listing visibility + access to referral earnings while active
  - Table: provider_visibility

Rules:
  • A subscription is ACTIVE if paid and not expired (expires_at > NOW())
  • A subscription is LAPSED if expires_at <= NOW() and not renewed
  • On lapse, referral earnings PAUSE — they do not disappear
  • On renewal, referral earnings RESUME immediately
  • Each renewal creates a new subscription row with a new expires_at
  • Both clients and providers can hold referral codes regardless of status
    but earnings are only credited when their subscription/visibility is ACTIVE

═══════════════════════════════════════════════════════════
SECTION 3 — REFERRAL SYSTEM RULES
═══════════════════════════════════════════════════════════

3.1 Referral Code
  • Every user (client or provider) gets a unique referral code on registration
  • Format: {FIRSTNAME}-{4-digit-random} e.g. JOHN-4821 (uppercase)
  • Also generate a referral link: https://{domain}/ref/{code}
  • Store in: users.referral_code (unique, indexed)

3.2 Referral Tracking
  • When a new user signs up using a referral code/link, store:
      - referred_by_user_id (FK to users)
      - referral_code_used
      - joined_at timestamp
  • A user can only have ONE referrer — set at signup, never changeable
  • A user cannot refer themselves — validate: referral_code != own code

3.3 Earning Events — when a referrer earns
  Earning only happens if referrer's subscription/visibility is ACTIVE at the time of the event.
  If not active, the event is logged as MISSED (not retroactively paid when they resubscribe).

  EVENT 1 — Referred user pays CLIENT subscription (K50):
    Referrer earns: 15% of K50 = K7.50
    Trigger: on successful payment of client_subscriptions

  EVENT 2 — Referred user pays PROVIDER visibility fee (K30):
    Referrer earns: 15% of K30 = K4.50
    Trigger: on successful payment of provider_visibility

  EVENT 3 — Referred user generates a BOOKING (as client or provider):
    Platform fee on booking = 1% of service value
    Referrer earns: 20% of that platform fee
    Example: K500 service → platform fee = K5 → referrer earns K1.00
    Trigger: on booking status = CONFIRMED and payment settled

  EVENT 4 — Referred user RENEWS their subscription:
    Same rates as Event 1 and Event 2 apply on each renewal
    Each renewal cycle is a new earning event

3.4 What the platform keeps
  • On subscription referral: 85% of K50 = K42.50 net to platform
  • On visibility referral:   85% of K30 = K25.50 net to platform
  • On booking platform fee:  80% of 1%  = platform keeps 0.8% per booking
  • Referral rewards are funded from subscription and platform fee revenue only
  • No separate referral budget — rewards come out of existing fee income

3.5 Anti-abuse rules
  • Self-referral: blocked at API level — return 400 error with message
  • Multi-level (MLM): disabled — only DIRECT referrer earns, never chain
  • Duplicate referral code signup: rejected — code must match existing user
  • Fraud flag: if a user generates 3+ referrals from the same device/IP
    within 24 hours, flag account for admin review (do not auto-block)

═══════════════════════════════════════════════════════════
SECTION 4 — DATABASE SCHEMA
═══════════════════════════════════════════════════════════

Implement the following tables (use your existing ORM/migration tool):

  TABLE: users (extend existing)
    + referral_code          VARCHAR(20) UNIQUE NOT NULL
    + referred_by_user_id    UUID NULL FK(users.id)
    + referral_code_used     VARCHAR(20) NULL
    + referral_joined_at     TIMESTAMP NULLP

  TABLE: referral_earnings
    id                       UUID PK
    referrer_user_id         UUID FK(users.id)
    referred_user_id         UUID FK(users.id)
    event_type               ENUM('client_subscription','provider_visibility',
                                  'booking_platform_fee','subscription_renewal')
    source_id                UUID   -- FK to the triggering record (booking id, subscription id, etc.)
    gross_amount             DECIMAL(10,2)   -- full fee collected (e.g. K50, K5)
    reward_rate              DECIMAL(5,4)    -- e.g. 0.1500 for 15%
    reward_amount            DECIMAL(10,2)   -- computed: gross_amount * reward_rate
    status                   ENUM('pending','confirmed','missed','paid_out')
    referrer_was_active      BOOLEAN         -- true if sub was active at event time
    missed_reason            TEXT NULL       -- populated if status = missed
    created_at               TIMESTAMP

  TABLE: referral_wallets
    id                       UUID PK
    user_id                  UUID FK(users.id) UNIQUE
    balance                  DECIMAL(10,2) DEFAULT 0.00
    total_earned             DECIMAL(10,2) DEFAULT 0.00
    total_paid_out           DECIMAL(10,2) DEFAULT 0.00
    last_updated_at          TIMESTAMP

  TABLE: referral_payouts
    id                       UUID PK
    user_id                  UUID FK(users.id)
    amount                   DECIMAL(10,2)
    method                   ENUM('mobile_money','bank_transfer','platform_credit')
    status                   ENUM('requested','processing','completed','failed')
    reference                VARCHAR(100) NULL
    requested_at             TIMESTAMP
    completed_at             TIMESTAMP NULL

  TABLE: referral_fraud_flags
    id                       UUID PK
    user_id                  UUID FK(users.id)
    flag_reason              TEXT
    ip_address               VARCHAR(50) NULL
    device_fingerprint       VARCHAR(200) NULL
    flagged_at               TIMESTAMP
    reviewed                 BOOLEAN DEFAULT FALSE
    reviewed_by              UUID NULL FK(users.id)

  INDEXES:
    users(referral_code)
    users(referred_by_user_id)
    referral_earnings(referrer_user_id, status)
    referral_earnings(referred_user_id)
    referral_earnings(source_id)
    referral_wallets(user_id)

═══════════════════════════════════════════════════════════
SECTION 5 — BACKEND SERVICES & BUSINESS LOGIC
═══════════════════════════════════════════════════════════

Implement these service modules:

  5.1 ReferralCodeService
    - generateCode(user): creates unique {FIRSTNAME}-{4-digit} code
    - validateCode(code, requestingUserId): returns referrer or throws
      • throws if code does not exist
      • throws if code belongs to requesting user (self-referral)
    - attachReferral(newUserId, code): writes referred_by and referral_code_used
    - checkFraud(newUserId, ipAddress, deviceFingerprint): checks referral
      count from same IP/device in last 24h, flags if >= 3

  

  5.3 ReferralEarningService
    - processEvent(eventType, sourceId, referredUserId, grossAmount):
      1. Look up referredUserId.referred_by_user_id — if null, return (no referrer)
      2. Call isActiveReferrer(referrerId)
      3. If not active:
           Insert referral_earnings row with status = 'missed',
           referrer_was_active = false,
           missed_reason = 'referrer subscription not active at event time'
           Return without crediting wallet
      4. If active:
           Determine reward_rate by event_type:
             client_subscription    → 0.15
             provider_visibility    → 0.15
             booking_platform_fee   → 0.20
             subscription_renewal   → 0.15
           reward_amount = grossAmount * reward_rate
           Insert referral_earnings row with status = 'confirmed',
           referrer_was_active = true
           Call WalletService.credit(referrerId, reward_amount)

  5.4 WalletService
    - credit(userId, amount): upserts referral_wallets, adds to balance
      and total_earned, updates last_updated_at
      Use DB transaction to prevent race conditions
    - getBalance(userId): returns current balance
    - requestPayout(userId, amount, method):
      • Validate amount >= K20 (minimum threshold)
      • Validate balance >= amount
      • Deduct from balance
      • Insert referral_payouts row with status = 'requested'
      • Trigger payout processing (webhook or queue)
    - applyAsCredit(userId, amount): deducts from wallet, applies as
      platform credit to user's account balance


═══════════════════════════════════════════════════════════
SECTION 7 — HOOKS INTO EXISTING BOOKING FLOW
═══════════════════════════════════════════════════════════

In the existing booking confirmation handler (where platform fee is collected):

  After booking status is set to CONFIRMED and payment settled:
    const platformFee = bookingValue * 0.01;
    await ReferralEarningService.processEvent(
      'booking_platform_fee',
      booking.id,
      booking.clientUserId,   // client who booked (check their referrer)
      platformFee
    );

  Also check the provider side:
    await ReferralEarningService.processEvent(
      'booking_platform_fee',
      booking.id,
      booking.providerUserId, // provider on the booking (check their referrer)
      platformFee
    );

  NOTE: Both client and provider may have separate referrers.
  Each is processed independently. The platform fee is not split —
  each referral reward is paid from platform revenue, not from each other.

═══════════════════════════════════════════════════════════
SECTION 8 — FRONTEND MODAL SCREENS
═══════════════════════════════════════════════════════════

Build a ReferralModal component with 3 conditional states:

  STATE A — Referrer is ACTIVE (subscription/visibility current):
    Show: referral code, copy link button, stats (referrals, earned, pending),
    earning breakdown table (per sub, per visibility, per booking),
    wallet balance, cash out button (disabled if balance < K20)

  STATE B — Referrer is LOCKED (no active sub/visibility):
    Show: lock icon, "Referral earnings locked" heading,
    count of referrals already made (signed up but not earning),
    estimated missed earnings (calculated but not paid),
    strong CTA: "Subscribe to unlock earnings" → opens upgrade plan modal

  STATE C — Upgrade prompt:
    Show: two plan cards side by side
      Card 1 — Client subscription K50 (highlighted/recommended)
        Lists: earn 15% on client subs, 20% of booking fees
      Card 2 — Provider visibility K30
        Lists: earn 15% on provider visibility, 20% of booking fees
    Both cards have pay CTA that calls the respective subscribe endpoint
    After payment: modal transitions to State A automatically

  On every modal open: fetch /api/referral/dashboard to determine which
  state to render. Do not cache — always fresh data.

═══════════════════════════════════════════════════════════
SECTION 9 — NOTIFICATIONS
═══════════════════════════════════════════════════════════

Send in-app notifications (and optionally SMS/email) for:

  • "You earned K7.50! [Name] subscribed using your referral code."
  • "You earned K1.00 from a booking your referral generated."
  • "Your referral earnings are paused — your subscription expired. Renew to resume."
  • "Your subscription renews in 3 days. Keep earning from referrals."
  • "Payout of K50 is being processed to your mobile money."
  • "Someone signed up with your referral link!" (even if referrer is locked — awareness nudge)

═══════════════════════════════════════════════════════════
SECTION 10 — ADMIN CONTROLS
═══════════════════════════════════════════════════════════

Build an admin panel section: Settings > Referral Configuration

  Configurable fields (stored in a platform_settings table):
    referral_client_sub_rate       DECIMAL  default 0.15  (15%)
    referral_visibility_rate       DECIMAL  default 0.15  (15%)
    referral_booking_fee_rate      DECIMAL  default 0.20  (20%)
    referral_min_payout            DECIMAL  default 20.00 (K20)
    referral_sub_period_days       INT      default 30
    referral_fraud_threshold       INT      default 3     (referrals per IP per 24h)
    referral_enabled               BOOLEAN  default true

  Admin can update these without a code deploy.
  All services must read rates from platform_settings at runtime, not hardcoded.

═══════════════════════════════════════════════════════════
SECTION 11 — TESTING REQUIREMENTS
═══════════════════════════════════════════════════════════

Write unit tests for:
  • ReferralCodeService.validateCode — self-referral blocked, invalid code blocked
  • ReferralEarningService.processEvent — earnings credited when active,
    missed record created when lapsed, no earning when no referrer
  • WalletService.credit — concurrent credits do not cause race condition
  • WalletService.requestPayout — blocked below K20, blocked if insufficient balance

Write integration tests for:
  • Full signup flow with referral code → earning event on first subscription
  • Subscription lapse → missed event logged → renewal → earnings resume
  • Booking confirmed → both client and provider referrers credited independently

═══════════════════════════════════════════════════════════
SECTION 12 — IMPLEMENTATION ORDER
═══════════════════════════════════════════════════════════

Implement in this exact sequence to avoid dependency errors:

  1. DB migrations (Section 4)
  2. ReferralCodeService — generation + validation
  3. Hook referral code into user registration flow
  4. SubscriptionService — client sub + provider visibility
  5. WalletService — credit, balance, payout
  6. ReferralEarningService — full event processing logic
  7. Hook ReferralEarningService into existing booking confirmation
  8. Hook ReferralEarningService into subscription payment handlers
  9. All API endpoints (Section 6)
  10. Frontend modal component (Section 8) — all 3 states
  11. Notification triggers (Section 9)
  12. Admin config panel (Section 10)
  13. Tests (Section 11)

At each step, confirm the previous step works before proceeding.
Ask for clarification if any business rule conflicts with the existing codebase.
Do not hardcode any rates, amounts, or periods — read from platform_settings.