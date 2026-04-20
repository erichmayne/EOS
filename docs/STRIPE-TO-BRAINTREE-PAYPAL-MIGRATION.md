# Stripe → Braintree + PayPal Migration Plan

**Created:** April 7, 2026
**Status:** Research / Plan
**Model:** StepBet's proven two-processor approach

---

## The Model

Copy StepBet's exact payment architecture:

| Direction | Processor | Method |
|-----------|-----------|--------|
| **Money IN** (deposits, buy-ins) | **Braintree** | Cards, Apple Pay, Google Pay, Venmo, PayPal |
| **Money OUT** (withdrawals, winnings) | **PayPal Payouts API** | Send to email/phone → PayPal or Venmo wallet |

Both products are owned by PayPal. They share infrastructure and work together seamlessly.

---

## Why This Is Better Than Stripe for EOS

1. **StepBet proved this model works** for skill-based competition apps — including with SEC filings acknowledging it
2. **Venmo payouts** — your demographic (young fitness users) overwhelmingly has Venmo. Stripe can't send to Venmo.
3. **Simpler withdrawals** — no Stripe Connect KYC, no custom accounts, no bank routing numbers. Just "enter your PayPal email" and money lands.
4. **Lower payout cost** — $0.25 flat per payout vs Stripe's Connect account fees + transfer fees + instant payout percentages
5. **Apple Pay, cards, Venmo all in one SDK** — Braintree handles everything on the deposit side
6. **Legal precedent** — StepBet's SEC filing explicitly frames this as skill-based with the same payout model

---

## Fee Comparison

| | Stripe (Current) | Braintree + PayPal |
|---|---|---|
| **Deposit (card)** | 2.9% + $0.30 | 2.59% + $0.49 |
| **Deposit (Apple Pay)** | Same as card | Same as card |
| **Deposit (Venmo)** | Not available | 2.59% + $0.49 |
| **Withdrawal** | Connect setup + $0.25 ACH or 1% instant | **$0.25 flat** (PayPal Payouts API) |
| **Connect monthly fee** | $2/active account | **$0 — no accounts needed** |
| **Recipient onboarding** | Full KYC, bank details, SSN last 4 | **Just a PayPal/Venmo email** |

On a $20 deposit: Stripe = $0.88, Braintree = $1.01 (13¢ more)
On a $50 deposit: Stripe = $1.75, Braintree = $1.79 (4¢ more)
On a $100 deposit: Stripe = $3.20, Braintree = $3.08 (**12¢ less**)

Deposits cost roughly the same. **Withdrawals are dramatically simpler and cheaper.**

---

## What Changes

### iOS App

#### Remove
- `import StripePaymentSheet` (from ContentView.swift, OnboardingView.swift, morning_wouldApp.swift)
- `STPAPIClient.shared.publishableKey` initialization
- `StripeAPI.handleURLCallback` URL handler
- `StripeConfig.swift` (entire file)
- `DepositPaymentService` class (PaymentSheet-based)
- Stripe SPM package dependency
- `merchant.com.emayne.eos` processing cert (gets new Braintree cert, same merchant ID)

#### Add
- `import Braintree` / `import BraintreeApplePay` / `import BraintreeCard`
- `BraintreeConfig.swift` — client token URL, backend URL
- New `DepositPaymentService` using Braintree's payment flow
- Custom payment UI (card input + Apple Pay button + Venmo button) since Drop-in is being deprecated Sep 2026
- `BTApplePayClient` for Apple Pay tokenization
- `BTCardClient` for card tokenization
- `UIViewControllerRepresentable` wrapper for Apple Pay sheet (`PKPaymentAuthorizationViewController`)

#### Files Affected
| File | Changes |
|------|---------|
| `morning_wouldApp.swift` | Remove Stripe init (~3 lines), add Braintree setup |
| `ContentView.swift` | Rewrite `DepositPaymentService` (~100 lines), update deposit UI |
| `StripeConfig.swift` | Delete → create `BraintreeConfig.swift` |
| `OnboardingView.swift` | Remove `import StripePaymentSheet` |
| `Eos.xcodeproj` | Swap Stripe SPM for Braintree SPM |

### Backend (server.js)

#### Remove
- `const Stripe = require('stripe')` and all Stripe SDK usage
- `POST /create-payment-intent` — Stripe PaymentIntent creation
- Stripe Customer creation/lookup
- Ephemeral Key generation
- All Stripe Connect code (`stripe.accounts.create`, `stripe.transfers.create`, `stripe.payouts.create`)
- All `stripe.balance.retrieve()` calls
- Stripe fee calculation logic

#### Add
- `braintree` npm package for server-side transaction processing
- `@paypal/payouts-sdk` npm package for PayPal Payouts
- `POST /create-client-token` — Braintree client token generation (replaces payment intent)
- `POST /process-deposit` — Braintree transaction sale (charges the nonce)
- `POST /withdraw` — rewrite to use PayPal Payouts API (send to email/Venmo handle)
- `POST /withdrawals/process-queue` — rewrite retry logic for PayPal Payouts

#### Endpoints Changed
| Endpoint | Current (Stripe) | New (Braintree/PayPal) |
|----------|-----------------|----------------------|
| `POST /create-payment-intent` | Creates Stripe PaymentIntent + Customer + Ephemeral Key | → `POST /create-client-token` — returns Braintree client token |
| (new) | — | → `POST /process-deposit` — charges Braintree nonce, credits balance |
| `POST /withdraw` | Creates Stripe Connect account, transfer, payout | → PayPal Payouts API (`POST /v1/payments/payouts`) |
| `POST /withdrawals/process-queue` | Retries Stripe transfers/payouts | → Retries PayPal payout batches |

### Web (withdraw.html)

#### Remove
- `<script src="https://js.stripe.com/v3/">` Stripe.js SDK
- All Stripe Elements code (card input, bank account tokenization)
- Connect account agreement link
- Hardcoded Stripe publishable key

#### Add
- Simplified form: just "Enter your PayPal email" or "Enter your Venmo handle"
- No card/bank input needed — PayPal handles the payout destination
- Status tracking via PayPal Payout batch status API

**This makes the withdrawal page dramatically simpler.** No SSN, no bank routing numbers, no card numbers. Just an email address.

### Database

#### Migration SQL
```sql
-- Add PayPal/Braintree columns
ALTER TABLE users
  ADD COLUMN braintree_customer_id TEXT,
  ADD COLUMN paypal_email TEXT,
  ADD COLUMN venmo_handle TEXT;

-- Add PayPal payout tracking to withdrawal requests
ALTER TABLE withdrawal_requests
  ADD COLUMN paypal_payout_batch_id TEXT,
  ADD COLUMN paypal_payout_item_id TEXT;

-- Add payout tracking to transactions
ALTER TABLE transactions
  ADD COLUMN paypal_payout_id TEXT;

-- Keep stripe columns for historical data (don't drop them)
-- Old stripe_customer_id, stripe_connect_account_id, etc. stay as-is
```

### Legal / Terms
- `web/terms.html` — change "processed through Stripe" → "processed through Braintree (PayPal)"
- `ContentView.swift` competition rules — update Stripe mention
- Add PayPal terms acceptance for payouts

---

## How the New Flows Work

### Deposit Flow (Braintree)

```
1. User taps "Deposit $50" in EOS app
2. iOS calls POST /create-client-token → backend returns Braintree client token
3. iOS shows custom payment UI:
   - Apple Pay button (BTApplePayClient → PKPaymentAuthorizationViewController)
   - Card input fields (BTCardClient)
   - Venmo button (BTVenmoClient) — one-tap if Venmo app installed
4. User pays → Braintree returns a payment nonce
5. iOS sends nonce to POST /process-deposit
6. Backend calls braintree.transaction.sale({ amount, nonce })
7. On success → credit user's balance_cents in DB
8. Return updated balance to iOS
```

### Withdrawal Flow (PayPal Payouts)

```
1. User goes to withdraw page (web or in-app)
2. Enters their PayPal email or Venmo handle (one-time setup, saved to profile)
3. Submits withdrawal request for $X
4. Backend calls PayPal Payouts API:
   POST https://api.paypal.com/v1/payments/payouts
   {
     "sender_batch_header": {
       "sender_batch_id": "unique-id",
       "email_subject": "Your RunMatch winnings!"
     },
     "items": [{
       "recipient_type": "EMAIL",  // or "PHONE" for Venmo
       "amount": { "value": "47.00", "currency": "USD" },
       "receiver": "winner@email.com",
       "note": "Competition winnings from RunMatch"
     }]
   }
5. PayPal sends money to recipient's PayPal/Venmo
6. If recipient doesn't have PayPal → they get an email to claim funds (30 day window)
7. Backend tracks payout status via webhook or polling
```

### Missed Objective Payout Flow

```
1. Cron detects missed objective
2. Deducts stake amount from user's internal balance (same as today)
3. Credits recipient's internal balance OR
4. Triggers PayPal Payout to recipient's PayPal/Venmo email
   (recipient just needs a PayPal email on file, no Connect account needed)
```

### Competition Winner Payout Flow

```
1. Competition ends, winner determined
2. Pool amount credited to winner's internal balance (same as today)
3. Winner withdraws via PayPal Payout whenever they want
```

---

## What Gets SIMPLER

| Area | Before (Stripe) | After (Braintree + PayPal) |
|------|-----------------|---------------------------|
| **Recipient onboarding** | Create Stripe Connect Custom Account, collect SSN last 4, DOB, address, bank details, legal name | **Enter PayPal email.** Done. |
| **withdraw.html** | 693 lines with Stripe.js, Elements, card tokenization, bank tokenization, Connect agreement | ~200 lines — email input + submit button |
| **Withdrawal backend** | Create Connect account → add external account → check platform balance → transfer → check Connect balance → payout → handle failures → queue retries | `paypal.payouts.create()` → done |
| **Recipient invite flow** | Recipient needs to set up Stripe Connect, enter bank info | Recipient just needs a PayPal/Venmo account |
| **Server env vars** | `STRIPE_SECRET_KEY` | `BRAINTREE_MERCHANT_ID`, `BRAINTREE_PUBLIC_KEY`, `BRAINTREE_PRIVATE_KEY`, `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET` |

---

## What Gets HARDER / Watch Out For

| Risk | Detail | Mitigation |
|------|--------|------------|
| **No drop-in UI after Sep 2026** | Braintree's `BTDropInController` is deprecated Sep 2026. You'll need to build custom payment UI with `BTCardClient` + `BTApplePayClient`. | Build custom UI from the start — it's more work upfront but future-proof and matches your brand better anyway |
| **PayPal Payouts requires pre-funding** | Your PayPal business account must hold enough balance to cover payouts + fees. Unlike Stripe which draws from platform balance. | Set up auto-transfer from Braintree → PayPal balance, or manually fund. Monitor balance. |
| **Unclaimed payouts** | If recipient doesn't have PayPal and doesn't claim within 30 days, money returns to you. | Show clear "link your PayPal" prompt to recipients; track unclaimed status |
| **PayPal Payouts API access** | Requires approval — not auto-enabled. Need to request access from PayPal business dashboard. | Apply early, usually approved within a few days for legitimate businesses |
| **Two dashboards** | Braintree dashboard for deposits, PayPal dashboard for payouts. | Minor inconvenience, both accessible from same PayPal business account |
| **Venmo payout limits** | Venmo payouts only work in the US. Venmo handle format is different from email. | Default to PayPal email, offer Venmo as option for US users |

---

## Size Estimate

| Component | Effort | Lines Changed (est.) |
|-----------|--------|---------------------|
| **iOS: Remove Stripe SDK** | Small | -50 lines |
| **iOS: Add Braintree SDK + config** | Small | +30 lines |
| **iOS: Custom deposit UI (card + Apple Pay + Venmo)** | Medium-Large | +250-350 lines |
| **Backend: New deposit endpoints** | Medium | ~100 lines |
| **Backend: Rewrite withdrawal with PayPal Payouts** | Medium | ~80 lines (simpler than current Stripe Connect code) |
| **Backend: Rewrite queue processor** | Small | ~40 lines |
| **Web: Rewrite withdraw.html** | Medium | Net -400 lines (massive simplification) |
| **DB: Migration** | Small | ~15 lines SQL |
| **Legal: Terms update** | Small | ~10 lines |
| **Testing & edge cases** | Medium | — |

**Total: ~1.5-2 weeks of focused work.** Less than the Airwallex migration because:
- Withdrawal flow gets dramatically simpler (no Connect accounts)
- withdraw.html shrinks by 60%
- Proven model (StepBet) reduces uncertainty

---

## Migration Order

### Week 1: Deposits (get money IN via Braintree)
1. Create PayPal Business account + Braintree merchant account
2. Request PayPal Payouts API access (do this first — approval takes a few days)
3. Add Braintree iOS SDK via SPM
4. Build custom deposit UI (card fields + Apple Pay button + Venmo button)
5. Create `POST /create-client-token` and `POST /process-deposit` backend endpoints
6. Configure Apple Pay with Braintree processing certificate
7. Test deposits end-to-end in sandbox
8. Go live on deposits — can run alongside Stripe temporarily

### Week 2: Withdrawals (get money OUT via PayPal Payouts)
1. Add PayPal email/Venmo handle field to user profile (iOS + backend)
2. Rewrite `POST /withdraw` to use PayPal Payouts API
3. Rewrite `POST /withdrawals/process-queue`
4. Rebuild `withdraw.html` (simple email-based form)
5. Test full withdrawal cycle in sandbox
6. Go live on withdrawals
7. Remove all Stripe code, dependencies, and env vars
8. Update terms of service

### Post-Migration
- Existing users with Stripe data: keep historical columns, create Braintree customer on next deposit
- Monitor PayPal Payouts balance, set up auto-funding
- Add "link your PayPal" prompt to app for withdrawal readiness
