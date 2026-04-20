# Stripe → Airwallex Migration: Feasibility Report

**Created:** April 7, 2026
**Status:** Research / Assessment

---

## Executive Summary

Switching from Stripe to Airwallex is **doable but intensive**. Airwallex covers most of what you need — iOS SDK with payment sheet, Apple Pay, and payouts to individuals. However, the migration touches **every money path** in the app across 3 codebases (iOS, backend, web) and the database schema. This is the single most invasive change you could make to EOS because Stripe is embedded in every financial operation.

**Estimated effort: 2-3 weeks of focused work.**

---

## Current Stripe Usage (What Needs Replacing)

Your app uses **6 distinct Stripe products**:

| Stripe Product | What It Does in EOS | Touchpoints |
|---|---|---|
| **Payment Intents** | Creates charges when users deposit money | Backend endpoint + iOS client |
| **PaymentSheet** | Drop-in UI for card entry + Apple Pay | iOS SDK (`StripePaymentSheet`) |
| **Customers** | Saves user payment methods for reuse | Backend creates/stores Stripe customer IDs |
| **Ephemeral Keys** | Securely authenticates PaymentSheet sessions | Backend generates, iOS consumes |
| **Connect (Custom Accounts)** | Creates sub-accounts for recipients to receive payouts | Backend creates accounts for withdrawal recipients |
| **Transfers + Payouts** | Moves money from your platform to recipient bank accounts/cards | Backend withdrawal flow + queued retry system |

Plus **Apple Pay** via Stripe's PaymentSheet configuration.

### File Counts Affected

| Location | Files | Lines to Change (est.) |
|---|---|---|
| `ContentView.swift` | 1 | ~200 lines (deposit service, Apple Pay config, import, all `StripeConfig.backendURL` refs) |
| `morning_wouldApp.swift` | 1 | ~5 lines (SDK init, URL callback handler) |
| `StripeConfig.swift` | 1 | Full rewrite → `AirwallexConfig.swift` |
| `OnboardingView.swift` | 1 | ~2 lines (import) |
| `backend/server.js` | 1 | ~400+ lines (every endpoint touching Stripe) |
| `web/withdraw.html` | 1 | ~150 lines (Stripe.js, Elements, tokenization, Connect UI) |
| `web/portal.html` | 1 | TBD (if Stripe referenced) |
| SQL migrations | 1-2 | Column renames / additions |
| `web/terms.html` | 1 | Legal references to Stripe |
| Xcode project | 1 | SPM dependency swap |

---

## Airwallex Feature Mapping

### What Airwallex HAS (direct replacements)

| EOS Feature | Stripe | Airwallex Equivalent | Notes |
|---|---|---|---|
| **Deposits (card payments)** | `stripe.paymentIntents.create()` | `PaymentIntent` API | Same concept, different SDK |
| **In-app payment UI** | `PaymentSheet` | `AirwallexPaymentSheet` / `AWXUIContext` | Drop-in native UI, SPM/CocoaPods |
| **Apple Pay** | PaymentSheet config | `AWXApplePayOptions` | Supported, needs new merchant cert |
| **Saved payment methods** | Customers + Ephemeral Keys | Airwallex Customer API | Similar concept, different IDs |
| **Payouts to individuals** | Connect Custom Accounts + Transfers + Payouts | Connected Accounts + Payouts API | Airwallex has Connected Accounts model |
| **Bank account payouts** | Stripe Connect → bank transfer | Airwallex Payouts → local rails (ACH) | Supported in US |
| **Web card/bank input** | Stripe Elements (`stripe.elements()`) | Airwallex Drop-in Element | JavaScript equivalent |
| **Platform balance** | `stripe.balance.retrieve()` | Airwallex Balances API | Different API shape |

### What's DIFFERENT (may cause friction)

| Area | Stripe | Airwallex | Impact |
|---|---|---|---|
| **Instant card payouts** | `stripe.payouts.create({method:'instant'})` to debit cards | Not clear if supported for US consumer cards | **HIGH** — your instant withdrawal to debit card may not work the same way |
| **Ephemeral Keys** | Used to auth PaymentSheet client-side | No direct equivalent — Airwallex uses a `clientSecret` from the PaymentIntent | **MEDIUM** — different auth pattern, need to refactor deposit flow |
| **Stripe Customer IDs** | Stored in `users.stripe_customer_id` | Need new `airwallex_customer_id` column | **MEDIUM** — DB migration, can't reuse Stripe customer IDs |
| **Connect onboarding UX** | Stripe hosted onboarding or custom | Airwallex Connected Account onboarding | **MEDIUM** — withdrawal setup flow needs rebuilding |
| **Webhook verification** | Stripe webhook signatures | Airwallex webhook signatures (different format) | **LOW** — straightforward swap |
| **Test mode** | Toggle between test/live keys | Airwallex has demo/live environments | **LOW** — same concept |
| **URL redirect scheme** | `eos-app://stripe-redirect` | Need new redirect scheme or reuse | **LOW** |
| **Apple Pay merchant ID** | `merchant.com.emayne.eos` (existing) | Same merchant ID, new processing cert from Airwallex | **LOW** — Apple Pay merchant ID stays, just re-cert |

### What Airwallex DOESN'T have (or is unclear)

| Feature | Risk | Workaround |
|---|---|---|
| **Instant debit card payouts (US)** | Stripe's killer feature for instant withdrawals. Airwallex docs mention bank transfers (ACH, etc.) but instant card payouts for US consumers are not clearly documented. | Fall back to standard bank transfer (1-2 business days) or investigate Airwallex's card payout capabilities further |
| **Mature US consumer payout ecosystem** | Airwallex's strength is cross-border B2B. Their consumer/individual payout in the US is newer and less battle-tested than Stripe Connect. | May need more KYC friction for recipients; test thoroughly |
| **Community/docs maturity** | Stripe has vastly more StackOverflow answers, tutorials, and iOS integration guides. Airwallex docs are good but thinner. | More self-reliance, direct support contact |
| **Stripe Radar (fraud)** | Built-in fraud detection on payments | Airwallex has fraud tools but may need separate config | Evaluate Airwallex's fraud offering |

---

## What Will Break

### 1. Every Deposit Flow (CRITICAL)
- iOS `DepositPaymentService` class — completely rewrite for Airwallex SDK
- `POST /create-payment-intent` backend endpoint — new Airwallex API calls
- Customer creation/lookup — new Airwallex Customer API
- PaymentSheet presentation — new `AWXUIContext` pattern
- Apple Pay config — new `AWXApplePayOptions`

### 2. Every Withdrawal Flow (CRITICAL)
- `POST /withdraw` endpoint — replace Connect account creation, transfers, payouts
- `POST /withdrawals/process-queue` — replace queued transfer/payout logic
- `web/withdraw.html` — replace Stripe.js with Airwallex Drop-in Element
- Instant card payouts — may not be available, needs investigation
- All `stripe_connect_account_id` references in DB and code

### 3. Competition Buy-In / Refund (CRITICAL)
- Buy-in deduction comes from user balance (internal ledger) — no Stripe call, so this is OK
- But deposits to fund the balance go through Stripe — those break

### 4. Missed Objective Payouts (MEDIUM)
- `POST /users/:userId/trigger-payout` — deducts from internal balance (OK)
- But if the recipient withdrawal uses Stripe Connect, that path breaks

### 5. Database Schema (MEDIUM)
- `users.stripe_customer_id` → needs `airwallex_customer_id`
- `recipients.stripe_connect_account_id` → needs `airwallex_connected_account_id`
- `transactions.stripe_payment_id` → rename or add parallel column
- `withdrawal_requests.stripe_connect_account_id`, `stripe_transfer_id`, `stripe_payout_id` → all need updating

### 6. Web Pages (MEDIUM)
- `withdraw.html` — Stripe.js SDK, Elements, tokenization — full rewrite of payment UI
- `terms.html` — legal references to "processed through Stripe"

### 7. Hardcoded Keys (LOW but must-fix)
- `StripeConfig.swift` — live publishable key
- `withdraw.html` — hardcoded `pk_live_*` key
- `.env` on server — all `STRIPE_*` env vars

---

## Migration Approach

### Phase 1: Deposits (get money IN)
1. Add Airwallex iOS SDK via SPM (`AirwallexPaymentSheet`)
2. Create `AirwallexConfig.swift` replacing `StripeConfig.swift`
3. Rewrite `DepositPaymentService` for Airwallex PaymentIntent + PaymentSheet
4. Rewrite `POST /create-payment-intent` on backend for Airwallex API
5. Configure Apple Pay with Airwallex processing certificate
6. Test deposits end-to-end

### Phase 2: Withdrawals (get money OUT)
1. Rewrite `POST /withdraw` to use Airwallex Connected Accounts + Payouts
2. Rewrite `web/withdraw.html` with Airwallex Drop-in Element
3. Update `POST /withdrawals/process-queue` for Airwallex retry logic
4. Migrate or parallel-track DB columns (`stripe_*` → `airwallex_*`)
5. Test full withdrawal cycle

### Phase 3: Cleanup
1. Remove Stripe SDK from Xcode project
2. Remove `stripe` npm package from backend
3. Remove Stripe.js from web pages
4. Update terms of service
5. Update all env vars on server
6. Audit for any remaining Stripe references

### Phase 4: Data Migration (if needed)
- Existing users with `stripe_customer_id` will need new Airwallex customer records on their next deposit
- Existing recipients with `stripe_connect_account_id` will need new Airwallex connected accounts on their next withdrawal
- Historical transaction `stripe_payment_id` values can stay as-is (audit trail)

---

## Fee Comparison

| | Stripe | Airwallex |
|---|---|---|
| **Domestic card** | 2.9% + $0.30 | 2.8% + $0.30 |
| **International card** | 4.4% + $0.30 | 4.3% + $0.30 |
| **Payouts (ACH)** | $0.25/payout | TBD (varies by method) |
| **Instant card payout** | 1% (min $0.50) | Unclear / may not be available |
| **Connect account fee** | $2/month per active account | TBD |
| **Fraud screening** | $0.02/transaction (Radar) | Included (varies) |

Savings are marginal on processing (0.1% per transaction). The real question is whether Airwallex meets your **functional** needs, not fee savings.

---

## Honest Assessment

### Why this is hard:
- Stripe is in **42+ locations** across your codebase
- **3 critical money paths** (deposit, withdrawal, queued withdrawal) all need rewriting
- The withdrawal flow is the most complex — Connect account creation, KYC, transfers, payouts, instant card payouts, retry queue
- You have **live users with Stripe customer IDs and Connect accounts** — migration needs to handle them gracefully
- Airwallex's US consumer payout story is less proven than Stripe Connect

### Why you might NOT want to switch:
- **0.1% fee difference** doesn't justify the risk/effort unless you're processing high volume
- Stripe Connect is the industry standard for marketplace payouts — Airwallex is catching up but isn't there yet for US consumer P2P
- Your instant debit card withdrawal feature may not survive the switch
- 2-3 weeks of migration work = 2-3 weeks not building features

### Why you might want to switch:
- Airwallex's multi-currency/global treasury is better if you're expanding internationally
- Better cross-border payout rates
- Airwallex's Connected Accounts may have lighter KYC for your use case
- Strategic reasons (relationship, terms, support, etc.) that only you know

---

## Recommendation

Before committing to the full migration, I'd suggest:

1. **Verify instant card payouts** — Contact Airwallex sales/support and confirm they support instant payouts to US consumer debit cards. If they don't, your withdrawal UX takes a major hit.

2. **Prototype the deposit flow first** — Swap just the deposit path (iOS SDK + backend endpoint) as a proof of concept. This is the simplest path and validates the SDK integration without touching the complex withdrawal system.

3. **Consider running both in parallel** — Airwallex for deposits, Stripe for withdrawals (temporarily). This reduces risk and lets you migrate incrementally. The internal balance ledger is processor-agnostic.

4. **Talk to Airwallex about your use case** — Your model (consumer deposits → platform holds balance → payouts to designated individuals) is somewhat unusual. Make sure their compliance team is comfortable with it.
