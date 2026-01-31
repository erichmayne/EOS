# 🎯 EOS (Morning Would) - Master System Documentation
> Last Updated: January 30, 2026
> Version: 2.6 - Recipient Linking Fixed

---

## 🆕 Latest Updates (Jan 30, 2026)

### Recipient Linking Architecture Fix
- **Root cause identified**: iOS was expecting `Int` for invite IDs, but database uses UUID strings
- **Backend bug**: `/users/:userId/invites` was querying wrong table (`users` instead of `recipients`)
- **Status check bug**: Duplicate detection checked for `status === 'active'` but we set `'accepted'`
- **Added**: Detailed recipient linking architecture docs (see Database Schema section)

### Key Fixes Applied
1. iOS `syncInviteStatuses()` now handles UUID strings for invite IDs
2. Backend `/users/:userId/invites` now correctly queries `recipients` table
3. Backend `/recipient-signup` status check fixed (`'accepted'` not `'active'`)
4. Added extensive logging to recipient signup flow

### Previous Fixes (Jan 29)
- **payoutType casing bug**: Fixed server returning "Charity" vs UI expecting "charity"
- **Live Stripe key**: Added `pk_live_...` to iOS app
- Stripe CLI installed for testing

---

## 📋 Table of Contents
1. [System Overview](#-system-overview)
2. [Beginner Setup & Deployment](#-beginner-setup--deployment)
3. [Architecture Diagram](#-architecture)
4. [Credentials & API Keys](#-credentials--api-keys-master-list)
5. [Local Environment (macOS)](#-local-environment-macos)
6. [Remote Server (Ubuntu)](#-remote-server-ubuntu)
7. [Database Schema](#-database-schema)
8. [Backend API Reference](#-backend-api-reference)
9. [iOS App Structure](#-ios-app-structure)
10. [Web Components](#-web-components)
11. [Third-Party Integrations](#-third-party-integrations)
12. [Payment Flow](#-payment-flow)
13. [Email System (SendGrid + Google Workspace)](#-email-system)
14. [Cron Jobs & Automation](#-cron-jobs--automation)
15. [Security & Authentication](#-security--authentication)
16. [File Path Reference](#-file-path-reference)
17. [Deployment Procedures](#-deployment-procedures)
18. [Update Log](#-update-log)

---

## 🌐 System Overview

**EOS** is a commitment-based fitness app where users pledge money that gets paid out if they miss their daily objectives.

### Core Concept: "Do or Donate"
- Users commit a payout amount (e.g., $25)
- Set daily objectives (currently pushups, future: multiple types)
- Complete objectives before deadline or money is sent to charity/friend
- Financial accountability drives habit formation

### Key Components
| Component | Technology | Location |
|-----------|------------|----------|
| iOS App | SwiftUI + Stripe SDK | Local `/Users/emayne/morning-would/` |
| Backend API | Node.js/Express | Remote `159.26.94.94:/home/user/morning-would-payments/` |
| Database | Supabase (PostgreSQL) | Cloud: `ddehnllsqoxmisnyjerf.supabase.co` |
| Payments | Stripe & Stripe Connect | API Integration |
| SMS | Twilio | API Integration |
| Email | SendGrid + Google Workspace | API Integration (To Be Configured) |
| Web Hosting | Nginx + Let's Encrypt | Remote `159.26.94.94` |

---

## 🧭 Beginner Setup & Deployment

This section is a step-by-step, plain-English guide to get EOS working locally, then pushed to GitHub, and finally deployed on any server. It is written for someone who is not deep in devops.

### A. What actually runs where
**Think of EOS as three separate pieces:**
- **iOS app (SwiftUI)**: runs on your Mac/Xcode and on users' phones. Not containerized.
- **Backend API (Node.js/Express)**: runs on a server. This is what you can containerize.
- **Database (Supabase)**: hosted by Supabase in the cloud.

### B. The minimum workflow (quick start)
1. Run backend locally (or connect to remote).
2. Run the iOS app in Xcode and point it to the backend URL.
3. Use real Stripe + Supabase keys for production.
4. Deploy backend to a server and keep it running.

---

### C. GitHub setup (one-time)
1. **Make sure secrets are not committed**
   - Add `.env` to `.gitignore`
   - Never commit Stripe keys, Supabase service role, or Twilio tokens

2. **Initialize git**
```bash
cd /Users/emayne/morning-would
git init
git add .
git commit -m "Initial commit"
```

3. **Create a private repo on GitHub**
   - Name: `morning-would`
   - Private (recommended)

4. **Push to GitHub**
```bash
git remote add origin git@github.com:YOUR_USER/morning-would.git
git branch -M main
git push -u origin main
```

---

### D. Backend: local run (Node.js)
1. **Install Node.js 18+**
2. **Create `.env` inside the backend directory**
```env
STRIPE_SECRET_KEY=YOUR_STRIPE_SECRET_KEY
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SERVICE_KEY=YOUR_SUPABASE_SERVICE_KEY
TWILIO_ACCOUNT_SID=YOUR_TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN=YOUR_TWILIO_AUTH_TOKEN
TWILIO_FROM_NUMBER=YOUR_TWILIO_FROM_NUMBER
```

3. **Install dependencies**
```bash
cd /Users/emayne/morning-would/backend
npm install
```

4. **Run**
```bash
node server.js
```
Backend should listen on the configured port (current setup uses Nginx to proxy to port 4242).

---

### E. iOS app: local run (Xcode)
1. Open `morning-would.xcodeproj`
2. Update API base URL in the app configuration
3. Build and run on simulator or device

**If sign-in fails**, check that:
- Backend is reachable
- `userId` is saved correctly in app storage
- Supabase keys are valid

---

### F. Containerize backend (for easy server moves)
**Goal:** Make the backend portable between servers with one command.

Create `backend/Dockerfile`:
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "server.js"]
```

Create `backend/.dockerignore`:
```
node_modules
.env
```

Create `docker-compose.yml` in repo root:
```yaml
version: "3.9"
services:
  api:
    build: ./backend
    ports:
      - "3000:3000"
    env_file:
      - ./backend/.env
    restart: unless-stopped
```

---

### G. Deploy to any server (Ubuntu)
1. **Install Docker**
```bash
curl -fsSL https://get.docker.com | sh
```

2. **Clone repo**
```bash
git clone git@github.com:YOUR_USER/morning-would.git
cd morning-would
```

3. **Create `.env` file**
```bash
cp backend/.env.example backend/.env
# Fill values
```

4. **Start**
```bash
docker compose up -d --build
```

Now your backend is portable to any server that can run Docker.

---

### H. How to move servers later (fast checklist)
1. Provision new server
2. Install Docker
3. `git clone` repo
4. Add `.env`
5. `docker compose up -d --build`
6. Update DNS to new IP

---

### K. SSH push deployment (GitHub Actions)
**Goal:** Every push to `main` auto-deploys the backend to the server.

**Server path (standard):** `/home/user/EOS`  
All new servers should deploy to this folder.

**1) Add this workflow file**
Path: `.github/workflows/deploy.yml`  
This is already in the repo and will run on every `main` push.

**2) Add GitHub Secrets**
In your repo → Settings → Secrets and variables → Actions, add:
- `SSH_HOST` (server IP, e.g. `159.26.94.94`)
- `SSH_USER` (usually `user`)
- `SSH_PRIVATE_KEY` (private key with access to the server)
- `SSH_PORT` (optional, default `22`)

**3) Server setup (one time)**
On the server:
```bash
mkdir -p /home/user/EOS
cd /home/user/EOS
git clone git@github.com:erichmayne/EOS.git .
```

**4) First deploy**
Push any commit to `main` and GitHub Actions will:
- `git reset --hard origin/main`
- run `docker compose up -d --build` if a compose file exists
- otherwise run Node with `pm2`

**Notes**
- The workflow assumes the backend lives in `backend/` if you are not using Docker.
- If you want a different deploy command, edit the workflow `script` block.

---

### I. Production checklist (important)
- Stripe keys switched to live
- Supabase keys set
- Nginx proxy points to container port
- Cron jobs configured (if used)
- Backups enabled for Supabase

---

### J. Common mistakes and fixes
- **No payouts happening**: Stripe available balance is 0
- **Sign-in fails**: missing `userId` save in app
- **Objective updates not syncing**: backend `objectives/settings` endpoint not called
- **Apple Pay missing**: `applePay` flag disabled in Stripe config

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EOS ECOSYSTEM                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐      HTTPS       ┌──────────────────────────────────────┐ │
│  │   iOS App    │─────────────────▶│     REMOTE SERVER (159.26.94.94)     │ │
│  │   (SwiftUI)  │                  │                                      │ │
│  │              │                  │  ┌─────────────────────────────────┐ │ │
│  │ LOCAL MACHINE│                  │  │         NGINX PROXY             │ │ │
│  │              │                  │  │ live-eos.com (landing)          │ │ │
│  │ Files:       │                  │  │ app.live-eos.com (invite)       │ │ │
│  │ /Users/emayne│                  │  │ api.live-eos.com → :4242        │ │ │
│  │ /morning-would                  │  └─────────────────────────────────┘ │ │
│  └──────────────┘                  │                 │                    │ │
│         │                          │                 ▼                    │ │
│         │                          │  ┌─────────────────────────────────┐ │ │
│         │                          │  │      Node.js Server (:4242)     │ │ │
│         │                          │  │  /home/user/morning-would-      │ │ │
│         │                          │  │       payments/server.js        │ │ │
│         │                          │  └─────────────────────────────────┘ │ │
│         │                          │         │          │          │      │ │
│         │                          └─────────┼──────────┼──────────┼──────┘ │
│         │                                    │          │          │        │
│         │         ┌──────────────────────────┘          │          │        │
│         │         │                                     │          │        │
│         ▼         ▼                                     ▼          ▼        │
│  ┌──────────────────────┐  ┌────────────────┐  ┌─────────────┐  ┌────────┐ │
│  │      SUPABASE        │  │    STRIPE      │  │   TWILIO    │  │SENDGRID│ │
│  │   (PostgreSQL)       │  │  (Payments)    │  │   (SMS)     │  │(Email) │ │
│  │                      │  │                │  │             │  │        │ │
│  │ ddehnllsqoxmisny     │  │ Live Mode ✅   │  │ +1(947)     │  │ TO BE  │ │
│  │ jerf.supabase.co     │  │                │  │ 777-7518    │  │ CONFIG │ │
│  └──────────────────────┘  └────────────────┘  └─────────────┘  └────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Domain Configuration
| Domain | Purpose | SSL | Root Path |
|--------|---------|-----|-----------|
| `live-eos.com` | Marketing landing page | ✅ Let's Encrypt | `/var/www/live-eos/` |
| `www.live-eos.com` | Redirects to main | ✅ | - |
| `app.live-eos.com` | Recipient onboarding/invite | ✅ Let's Encrypt | `/var/www/invite/` |
| `api.live-eos.com` | Backend API (proxy to :4242) | ✅ Let's Encrypt | Proxy only |

---

## 🔑 Credentials & API Keys (Master List)

### ⚠️ SECURITY NOTE
> These credentials are LIVE/PRODUCTION. Store securely. Never commit to public repos.
> Use `docs/SECRETS-LOCAL.md` for the real values on your machine (file is gitignored).

---

### 1. STRIPE (Payment Processing)

**Dashboard**: https://dashboard.stripe.com  
**Account Email**: `erich.maynefamily@gmail.com`  
**Account Password**: `[PLACEHOLDER - YOUR STRIPE PASSWORD]`

| Key Type | Value | Used In |
|----------|-------|---------|
| **Publishable Key (Live)** | `[SET IN StripeConfig.swift]` | iOS App (`StripeConfig.swift`) |
| **Secret Key (Live)** | `[STORE IN .env ONLY - DO NOT COMMIT]` | Server `.env` |
| **Stripe Connect** | Enabled | Recipients onboarding |
| **Webhook Secret** | `[NOT YET CONFIGURED]` | Server (for payment events) |

**Stripe Connect Account Types:**

| Type | Onboarding | Transfers | Use Case |
|------|-----------|-----------|----------|
| **Custom** (current) | All info on our page | Immediate | New recipients |
| **Express** (legacy) | Stripe hosted redirect | After onboarding | Existing accounts |

**Custom Account Flow (NEW RECIPIENTS):**
- All identity info collected on invite page (DOB, address, SSN last 4)
- Bank account or debit card added directly
- TOS accepted programmatically
- **Transfers enabled immediately** - no redirect needed

**Express Account Flow (LEGACY):**
Some existing recipients have Express accounts that need Stripe hosted onboarding.

**Generate onboarding links for Express accounts:**
```bash
curl -X POST "https://api.live-eos.com/recipients/RECIPIENT_ID/onboarding-link" \
  -H "Content-Type: application/json" -d '{}'
```

**Check recipient status:**
```bash
curl "https://api.live-eos.com/recipients/RECIPIENT_ID/status"
```

**File Locations**:
- iOS: `/Users/emayne/morning-would/morning-would/StripeConfig.swift` (set publishable key locally; do not commit)
- Server: `/home/user/morning-would-payments/.env`

---

### 2. SUPABASE (Database)

**Dashboard**: https://supabase.com/dashboard  
**Project**: `ddehnllsqoxmisnyjerf`  
**Account Email**: `[PLACEHOLDER - YOUR SUPABASE LOGIN EMAIL]`  
**Account Password**: `[PLACEHOLDER - YOUR SUPABASE PASSWORD]`

| Key Type | Value | Used In |
|----------|-------|---------|
| **Project URL** | `https://ddehnllsqoxmisnyjerf.supabase.co` | Server `.env` |
| **Anon Key (Public)** | `[RETRIEVE FROM DASHBOARD]` | iOS App (if needed) |
| **Service Role Key** | `[STORE IN .env ONLY - DO NOT COMMIT]` | Server `.env` |
| **DB Password** | `[PLACEHOLDER - SET IN SUPABASE DASHBOARD]` | Direct DB access |

**File Locations**:
- Server: `/home/user/morning-would-payments/.env`
- SQL Schema: `/Users/emayne/morning-would/sql/`

---

### 3. TWILIO (SMS)

**Dashboard**: https://console.twilio.com  
**Account Email**: `[PLACEHOLDER - YOUR TWILIO LOGIN EMAIL]`  
**Account Password**: `[PLACEHOLDER - YOUR TWILIO PASSWORD]`

| Key Type | Value | Used In |
|----------|-------|---------|
| **Account SID** | `[STORE IN .env ONLY - DO NOT COMMIT]` | Server `.env` |
| **Auth Token** | `[STORE IN .env ONLY - DO NOT COMMIT]` | Server `.env` |
| **Phone Number** | `[SET IN .env]` | Server `.env`, SMS "From" |

**File Locations**:
- Server: `/home/user/morning-would-payments/.env`

---

### 4. SENDGRID (Email) - TO BE CONFIGURED

**Dashboard**: https://app.sendgrid.com  
**Account Email**: `[PLACEHOLDER - YOUR SENDGRID LOGIN EMAIL]`  
**Account Password**: `[PLACEHOLDER - YOUR SENDGRID PASSWORD]`

| Key Type | Value | Used In |
|----------|-------|---------|
| **API Key** | `[PLACEHOLDER - GET FROM SENDGRID]` | Server `.env` |
| **Verified Sender** | `noreply@live-eos.com` | Transactional emails |
| **DNS Records** | `[TO BE ADDED TO live-eos.com]` | Domain verification |

**Email Addresses to Create**:
- `noreply@live-eos.com` - Automated emails (password reset, etc.)
- `support@live-eos.com` - Support inquiries
- `payouts@live-eos.com` - Payout notifications

---

### 5. GOOGLE WORKSPACE (Email Hosting) - TO BE CONFIGURED

**Dashboard**: https://admin.google.com  
**Domain**: `live-eos.com`  
**Super Admin Email**: `[PLACEHOLDER - e.g., admin@live-eos.com]`  
**Super Admin Password**: `[PLACEHOLDER - YOUR GOOGLE WORKSPACE ADMIN PASSWORD]`

| Setting | Value |
|---------|-------|
| **Admin Console URL** | https://admin.google.com |
| **Gmail Login** | https://mail.google.com |
| **MX Records** | `[TO BE CONFIGURED - See Google Setup Wizard]` |

**Accounts to Create**:
| Email | Password | Purpose |
|-------|----------|---------|
| `admin@live-eos.com` | `[PLACEHOLDER]` | Super admin account |
| `support@live-eos.com` | `[PLACEHOLDER]` | Customer support inbox |
| `team@live-eos.com` | `[PLACEHOLDER]` | Internal team communications |
| `noreply@live-eos.com` | `[PLACEHOLDER]` | SendGrid verified sender |

---

### 6. APPLE DEVELOPER (iOS & Apple Pay)

**Dashboard**: https://developer.apple.com  
**Account Email**: `erich.maynefamily@gmail.com`  
**Account Password**: `[PLACEHOLDER - YOUR APPLE ID PASSWORD]`  
**2FA**: Enabled (Apple requires this)

| Setting | Value | Notes |
|---------|-------|-------|
| **Team ID** | `[CHECK IN DEVELOPER PORTAL]` | Required for Push Notifications |
| **Bundle ID** | `com.emayne.eos` | App identifier |
| **Merchant ID** | `merchant.com.emayne.eos` | Apple Pay (entitlements) |
| **App Store Connect** | `[SETUP WHEN READY]` | For distribution |

**File Locations**:
- Entitlements: `/Users/emayne/morning-would/morning-would/Entitlements.entitlements`
- Project: `/Users/emayne/morning-would/Eos.xcodeproj/`

---

### 🍎 APPLE PAY INTEGRATION (CRITICAL)

> ⚠️ **Apple Pay will NOT work without completing BOTH Stripe and Apple Developer setup!**

#### Certificate Requirement
Apple Pay requires a **Payment Processing Certificate** that links your Apple Developer account to Stripe. This certificate must be:
1. Generated via Stripe Dashboard
2. Uploaded to Apple Developer Portal
3. The resulting `.cer` file uploaded back to Stripe

#### Certificate File Location
| File | Path | Purpose |
|------|------|---------|
| `apple_pay.cer` | `/Users/emayne/morning-would/apple_pay.cer` | Apple Pay certificate from Stripe |

#### Current Configuration Status
| Component | Value | Status |
|-----------|-------|--------|
| Merchant ID | `merchant.com.emayne.eos` | ✅ Configured |
| Bundle ID | `com.emayne.eos` | ✅ Matches |
| Certificate Created | January 13, 2026 | ✅ Valid |
| Certificate Expires | February 12, 2028 | ✅ Active |
| Stripe Dashboard | Apple Pay enabled | ✅ Configured |

#### iOS App Configuration
**ContentView.swift** (lines ~780-784):
```swift
configuration.applePay = .init(
    merchantId: "merchant.com.emayne.eos",
    merchantCountryCode: "US"
)
```

**Entitlements.entitlements**:
```xml
<key>com.apple.developer.in-app-payments</key>
<array>
    <string>merchant.com.emayne.eos</string>
</array>
```

#### Backend Requirements
The `/create-payment-intent` endpoint MUST return these 3 fields for Apple Pay:
```json
{
    "paymentIntentClientSecret": "pi_xxx_secret_xxx",
    "customer": "cus_xxx",
    "ephemeralKeySecret": "ek_live_xxx"
}
```

#### Setup Process (If Reconfiguring)

**Step 1: Stripe Dashboard**
1. Go to https://dashboard.stripe.com/settings/payments/apple_pay
2. Click **"Add new application"** under iOS certificates
3. Select **"For your platform account"**
4. Download the CSR (Certificate Signing Request) file

**Step 2: Apple Developer Portal**
1. Go to https://developer.apple.com/account
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click **Identifiers** → **Merchant IDs**
4. Select `merchant.com.emayne.eos`
5. Click **Create Certificate**
6. Upload the CSR from Stripe
7. Download the `.cer` file
8. Save as `apple_pay.cer` in `/Users/emayne/morning-would/`

**Step 3: Upload to Stripe**
1. Return to Stripe Dashboard Apple Pay settings
2. Upload the `.cer` certificate

**Step 4: Xcode**
1. Open project in Xcode
2. Go to **Signing & Capabilities**
3. Ensure **Apple Pay** capability is added
4. Verify `merchant.com.emayne.eos` is checked
5. Clean build folder (Cmd + Shift + K)
6. Delete app from device
7. Build and run fresh

#### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Apple Pay not available in EOS" | Certificate not uploaded to Stripe | Complete Step 3 above |
| Apple Pay button not showing | `configuration.applePay = nil` in code | Set to `.init(merchantId:...)` |
| "Invalid backend response" | Backend not returning required fields | Fix `/create-payment-intent` endpoint |
| Apple Pay works on device but not simulator | Expected behavior | Apple Pay only works on real devices |

---

### 7. VERCEL (Domain Registrar & DNS)

**Dashboard**: https://vercel.com/dashboard  
**Account Email**: `[PLACEHOLDER - YOUR VERCEL LOGIN EMAIL]`  
**Account Password**: `[PLACEHOLDER - YOUR VERCEL PASSWORD]`  
**Domain**: `live-eos.com`

| Record Type | Host | Value | Status |
|-------------|------|-------|--------|
| A | @ | `159.26.94.94` | ✅ Configured |
| A | www | `159.26.94.94` | ✅ Configured |
| A | app | `159.26.94.94` | ✅ Configured |
| A | api | `159.26.94.94` | ✅ Configured |
| MX | @ | `[GOOGLE WORKSPACE MX - TO BE ADDED]` | ⏳ Pending |
| MX | @ | `ASPMX.L.GOOGLE.COM` (priority 1) | ⏳ After GW setup |
| MX | @ | `ALT1.ASPMX.L.GOOGLE.COM` (priority 5) | ⏳ After GW setup |
| TXT | @ | `[SENDGRID VERIFICATION - TO BE ADDED]` | ⏳ Pending |
| TXT | @ | `v=spf1 include:_spf.google.com ~all` | ⏳ After GW setup |
| CNAME | em._domainkey | `[SENDGRID DKIM - TO BE ADDED]` | ⏳ Pending |

**Vercel DNS Panel**: https://vercel.com/dashboard/domains/live-eos.com

---

### 8. SERVER SSH ACCESS

**Provider**: `[PLACEHOLDER - YOUR VPS PROVIDER e.g., DigitalOcean, Linode, Vultr]`  
**Provider Dashboard**: `[PLACEHOLDER - URL TO YOUR VPS DASHBOARD]`  
**Provider Email**: `[PLACEHOLDER - YOUR VPS ACCOUNT EMAIL]`  
**Provider Password**: `[PLACEHOLDER - YOUR VPS ACCOUNT PASSWORD]`

| Setting | Value |
|---------|-------|
| **Host IP** | `159.26.94.94` |
| **SSH User** | `user` |
| **SSH Password** | `[PLACEHOLDER - IF USING PASSWORD AUTH]` |
| **Auth Method** | SSH Key (recommended) |
| **SSH Key Location** | `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` |
| **Root Password** | `[PLACEHOLDER - SERVER ROOT PASSWORD]` |
| **OS** | Ubuntu 22.04 LTS |

**Quick Access**: `ssh user@159.26.94.94`

---

### 9. GITHUB (Code Repository)

**Dashboard**: https://github.com  
**Account Username**: `erichmayne`  
**Repo URL**: https://github.com/erichmayne/EOS  
**SSH Clone**: `git@github.com:erichmayne/EOS.git`  
**Branch**: `main`

**Repo Structure**:
```
EOS/
├── morning-would/        # iOS app (SwiftUI)
├── backend/
│   └── server.js         # Live production backend
├── docs/                  # Documentation
├── sql/                   # Database schemas
└── deployment/            # Deploy scripts
```

---

### 🔐 MASTER CREDENTIALS SUMMARY

| Service | Login URL | Email | Password |
|---------|-----------|-------|----------|
| Stripe | dashboard.stripe.com | `erich.maynefamily@gmail.com` | `[PLACEHOLDER]` |
| Supabase | supabase.com/dashboard | `[PLACEHOLDER]` | `[PLACEHOLDER]` |
| Twilio | console.twilio.com | `[PLACEHOLDER]` | `[PLACEHOLDER]` |
| SendGrid | app.sendgrid.com | `[PLACEHOLDER]` | `[PLACEHOLDER]` |
| Google Workspace | admin.google.com | `admin@live-eos.com` | `[PLACEHOLDER]` |
| Apple Developer | developer.apple.com | `erich.maynefamily@gmail.com` | `[PLACEHOLDER]` |
| Vercel | vercel.com | `[PLACEHOLDER]` | `[PLACEHOLDER]` |
| VPS Provider | `[PLACEHOLDER]` | `[PLACEHOLDER]` | `[PLACEHOLDER]` |
| GitHub | github.com/erichmayne/EOS | `erichmayne` | SSH key auth |
| Server SSH | `ssh user@159.26.94.94` | N/A | SSH Key / `[PLACEHOLDER]` |

---

## 💻 Local Environment (macOS)

### Directory Structure
```
/Users/emayne/morning-would/
├── Eos.xcodeproj/                      # Xcode project file
│   └── project.pbxproj                 # Build settings, dependencies
│
├── morning-would/                      # iOS App Source
│   ├── Assets.xcassets/                # App icons, images
│   ├── ContentView.swift               # Main UI (2300+ lines)
│   ├── SplashView.swift                # Boot animation
│   ├── StripeConfig.swift              # Stripe keys & backend URL
│   ├── morning_wouldApp.swift          # App entry point
│   ├── Persistence.swift               # CoreData (not heavily used)
│   ├── Info.plist                      # App configuration
│   ├── Entitlements.entitlements       # Apple Pay merchant ID
│   └── morning-would.entitlements      # Backup entitlements
│
├── backend/                            # Backend code (reference/staging)
│   ├── complete-server-update.js       # Full server code for deployment
│   ├── multi-objective-endpoints.js    # Future: multi-objective API
│   ├── objective-endpoints.js          # Objective tracking endpoints
│   ├── objective-cron.js               # Cron job for missed objectives
│   ├── server-update.js                # Partial server updates
│   └── simplified-objective-backend.js # Simplified objective system
│
├── sql/                                # Database schemas
│   ├── simplified-objective-schema.sql # Current production schema
│   ├── multi-objective-schema.sql      # Future: multi-objective tables
│   └── *.sql                           # Various schema files
│
├── deployment/                         # Deployment scripts
│   ├── deploy-objectives.sh
│   └── *.sh
│
├── docs/                               # Documentation
│   └── EOS-MASTER-DOCUMENTATION.md     # THIS FILE
│
├── branding/                           # Logo, icons, style guide
│   ├── eos-app-icon-*.png
│   ├── eos-logo-*.svg
│   └── EOS-BRANDING-GUIDE.md
│
├── apple_pay.cer                       # Apple Pay certificate (from Stripe)
│
└── README.md                           # Project overview
```

### Key Files - iOS App

| File | Purpose | Key Contents |
|------|---------|--------------|
| `ContentView.swift` | Main UI logic | All views, profile, objectives, payments |
| `StripeConfig.swift` | API config | Publishable key, backend URL |
| `SplashView.swift` | Boot screen | EOS logo animation |
| `Info.plist` | App config | ATS exceptions (IP whitelist) |
| `Entitlements.entitlements` | Capabilities | Apple Pay merchant ID |

### iOS Dependencies (Swift Package Manager)
```
stripe-ios v25.3.1
├── Stripe
├── StripeApplePay
├── StripeCardScan
├── StripeConnect
├── StripeFinancialConnections
└── StripePaymentSheet
```

---

## 🖥️ Remote Server (Ubuntu)

**Host**: `159.26.94.94`  
**User**: `user`  
**OS**: Ubuntu 22.04 LTS

### Directory Structure
```
/home/user/
└── morning-would-payments/              # Backend API
    ├── server.js                        # MAIN SERVER FILE (production)
    ├── .env                             # Environment variables (secrets)
    ├── package.json                     # Node dependencies
    ├── package-lock.json
    ├── node_modules/
    ├── server.log                       # Server output log
    ├── server.backup*.js                # Various backups
    ├── custom-onboarding-endpoint.js    # Stripe Connect onboarding
    └── recipient-endpoints.js           # Recipient management

/var/www/
├── live-eos/                            # Main landing page
│   └── index.html                       # Marketing page
└── invite/                              # Recipient onboarding
    └── index.html                       # Card input form

/etc/nginx/
├── sites-available/
│   ├── live-eos.com                     # Main site config
│   ├── app-live-eos                     # Invite subdomain config
│   └── eos-api                          # API proxy config
└── sites-enabled/
    └── [symlinks to above]

/etc/letsencrypt/live/
├── live-eos.com/                        # SSL certs for main
├── app.live-eos.com/                    # SSL certs for app subdomain
└── api.live-eos.com/                    # SSL certs for API
```

### Server Environment File (`.env`)
```bash
# /home/user/morning-would-payments/.env

# Stripe
STRIPE_SECRET_KEY=YOUR_STRIPE_SECRET_KEY

# Supabase
SUPABASE_URL=https://ddehnllsqoxmisnyjerf.supabase.co
SUPABASE_SERVICE_KEY=YOUR_SUPABASE_SERVICE_KEY

# Twilio
TWILIO_ACCOUNT_SID=YOUR_TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN=YOUR_TWILIO_AUTH_TOKEN
TWILIO_PHONE_NUMBER=+1xxxxxxxxxx
TWILIO_FROM_NUMBER=+1xxxxxxxxxx

# SendGrid (TO BE ADDED)
# SENDGRID_API_KEY=[PLACEHOLDER]

# Google Workspace (TO BE ADDED)
# GOOGLE_WORKSPACE_ADMIN=[PLACEHOLDER]
# GOOGLE_WORKSPACE_PASSWORD=[PLACEHOLDER]
```

### Running Processes
```bash
# Check what's running
ps aux | grep node

# Server runs on port 4242
# Nginx proxies api.live-eos.com → localhost:4242
# PM2 manages process (auto-restart, auto-boot) - configured Jan 28, 2026

# PM2 Commands (RECOMMENDED)
pm2 status                # Check server status  
pm2 restart eos-backend   # Restart after code changes
pm2 logs eos-backend      # View logs (Ctrl+C to exit)
pm2 monit                 # Real-time monitoring dashboard

# Manual fallback (if PM2 not working)
cd /home/user/morning-would-payments
pkill node
nohup node server.js > server.log 2>&1 &
```

---

## 💾 Database Schema

### Supabase Project Info
- **Project ID**: `ddehnllsqoxmisnyjerf`
- **Region**: `[CHECK DASHBOARD]`
- **URL**: `https://ddehnllsqoxmisnyjerf.supabase.co`

### Core Tables

#### 1. `users` - Primary user accounts
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    phone VARCHAR(50),
    password_hash VARCHAR(255),
    balance_cents INTEGER DEFAULT 0,
    stripe_customer_id VARCHAR(255),
    stripe_payment_method_id VARCHAR(255),
    
-- Objective settings
    objective_type VARCHAR(50) DEFAULT 'pushups',
    objective_count INTEGER DEFAULT 50,
    objective_schedule VARCHAR(20) DEFAULT 'daily',
    objective_deadline TIME DEFAULT '09:00',
    missed_goal_payout DECIMAL(10,2) DEFAULT 0.00,
    payout_destination VARCHAR(20) DEFAULT 'charity',
    payout_committed BOOLEAN DEFAULT FALSE,
    custom_recipient_id UUID REFERENCES recipients(id),
    timezone VARCHAR(50) DEFAULT 'America/New_York',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 2. `recipients` - Payout recipients (friends/family)
```sql
CREATE TABLE recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255),
    full_name VARCHAR(255),
    phone VARCHAR(50),
    stripe_account_id VARCHAR(255),
    onboarding_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 3. `recipient_invites` - SMS invitation tracking
```sql
CREATE TABLE recipient_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payer_user_id UUID REFERENCES users(id),
    recipient_id UUID REFERENCES recipients(id),
    phone VARCHAR(50),
    invite_code VARCHAR(20) UNIQUE,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 4. `objective_sessions` - Daily objective tracking
```sql
CREATE TABLE objective_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    session_date DATE NOT NULL,
    objective_type VARCHAR(50),
    objective_count INTEGER,
    completed_count INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending',
    deadline_time TIME,
    payout_triggered BOOLEAN DEFAULT FALSE,
    payout_transaction_id UUID REFERENCES transactions(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, session_date)
);
```

#### 5. `transactions` - Financial transaction log
```sql
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    type VARCHAR(50),  -- 'deposit', 'payout', 'refund'
    amount_cents INTEGER,
    status VARCHAR(50) DEFAULT 'pending',
    stripe_payment_id VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 🔗 Recipient Linking Architecture (IMPORTANT)

Understanding how recipients are linked is critical for debugging. There are **TWO separate IDs** for each recipient:

#### ID Structure Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                         USERS TABLE                             │
│  (Main accounts - both payers AND recipients log in here)       │
├─────────────────────────────────────────────────────────────────┤
│  id (UUID)              │ 0bff145b... (Test03 - PAYER)          │
│  email                  │ 0@gmail.com                           │
│  custom_recipient_id    │ bf1020c7... → points to RECIPIENTS    │
│  payout_destination     │ "custom"                              │
├─────────────────────────────────────────────────────────────────┤
│  id (UUID)              │ 4d89a3db... (Payout5 - RECIPIENT)     │
│  email                  │ 05@gmail.com                          │
│  custom_recipient_id    │ null (they're a recipient, not payer) │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ FK constraint requires
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       RECIPIENTS TABLE                          │
│  (Payout destination records - required for FK)                 │
├─────────────────────────────────────────────────────────────────┤
│  id (UUID)              │ bf1020c7... (Payout5's PAYOUT DEST)   │
│  name                   │ "Payout 5"                            │
│  email                  │ 05@gmail.com                          │
│  stripe_connect_id      │ null (set during withdrawal)          │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ recipient_id links here
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    RECIPIENT_INVITES TABLE                      │
│  (Tracks invite codes and their status)                         │
├─────────────────────────────────────────────────────────────────┤
│  id (UUID)              │ 27846b64... (invite record)           │
│  payer_user_id          │ 0bff145b... → Test03 in users         │
│  invite_code            │ "HS2ZAWUY"                            │
│  status                 │ "accepted"                            │
│  recipient_id           │ bf1020c7... → recipients table        │
└─────────────────────────────────────────────────────────────────┘
```

#### Why Two IDs?
1. **User ID** (`users.id`): The recipient's login account. They use this to sign in to the web portal.
2. **Recipient ID** (`recipients.id`): The payout destination record. This is what the payer's `custom_recipient_id` points to.

**The FK constraint on `users.custom_recipient_id` references `recipients` table, NOT `users` table.** This is a legacy design that requires creating entries in both tables when a recipient signs up.

#### Recipient Signup Flow (via invite code)
```
1. Payer generates invite code
   └── Creates row in recipient_invites (status: 'pending')

2. Recipient visits invite link and signs up
   └── Creates row in users table (their login account)
   └── Creates row in recipients table (payout destination)
   └── Updates recipient_invites (status: 'accepted', recipient_id set)
   └── Updates payer's custom_recipient_id → points to recipients entry

3. iOS app syncs via /users/:userId/invites
   └── Returns invites with recipient info from recipients table
   └── iOS displays recipient name/email with status "active"
```

#### Key Points
- `users.custom_recipient_id` → references `recipients.id` (NOT `users.id`)
- When querying recipient info, always query `recipients` table
- Recipient has login via `users` table, payout destination via `recipients` table
- Status values: `pending` (waiting), `accepted` (signed up), `expired`

---

### Database Functions (PostgreSQL/Supabase)

#### `create_daily_objective_sessions()`
- **Purpose**: Creates daily sessions for users with `payout_committed = true`
- **Trigger**: Cron job at midnight
- **Logic**:
```sql
-- For each user with payout_committed = true
-- Creates a new row in objective_sessions for today
-- Sets objective_type, objective_count, deadline_time from user settings
```

#### `check_missed_objectives()`
- **Purpose**: Returns sessions past deadline with incomplete status
- **Returns**: Array of `{session_id, user_id, payout_amount, payout_destination}`
- **Logic**:
```sql
-- Finds objective_sessions WHERE:
--   session_date = TODAY
--   AND current_time > deadline_time
--   AND completed_count < objective_count
--   AND payout_triggered = FALSE
```

---

## 🔌 Backend API Reference (Complete)

**Base URL**: `https://api.live-eos.com`  
**Server Port**: `4242`  
**Server File**: `/home/user/morning-would-payments/server.js`

---

### 🏥 Health & Debug Endpoints

#### `GET /health`
**Purpose**: Server health check  
**Response**: `{"status": "ok", "timestamp": "..."}`

#### `GET /debug/database`
**Purpose**: Test Supabase connectivity  
**Database Operations**:
```javascript
// Checks connection to Supabase
supabase.from('users').select('count')
supabase.from('recipients').select('count')
supabase.from('recipient_invites').select('count')
```
**Response**: `{"supabaseConnected": true, "usersTable": {"count": X}, ...}`

---

### 👤 Authentication Endpoints

#### `POST /signin`
**Purpose**: Authenticate existing user  
**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "userpassword"
}
```
**Database Operations**:
```javascript
// 1. Find user by email (case-insensitive)
const { data: user } = await supabase
    .from('users')
    .select('*')
    .eq('email', email.trim().toLowerCase())
    .single();

// 2. Compare password_hash (NOTE: Currently plain text - needs bcrypt!)
if (user.password_hash !== password) → 401 error
```
**Success Response**:
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "...",
    "full_name": "...",
    "phone": "...",
    "balance_cents": 0,
    "objective_type": "pushups",
    "objective_count": 50,
    "objective_schedule": "daily",
    "objective_deadline": "09:00",
    "missed_goal_payout": 0,
    "payout_destination": "charity",
    "payout_committed": false
  }
}
```
**Error Responses**:
- `400`: Missing email or password
- `401`: Invalid credentials
- `500`: Server error

---

#### `POST /users/profile`
**Purpose**: Create new user OR update existing user  
**Request Body**:
```json
{
  "email": "user@example.com",
  "fullName": "John Doe",
  "phone": "+1234567890",
  "password": "userpassword",
  "balanceCents": 0,
  "objective_type": "pushups",
  "objective_count": 50,
  "objective_schedule": "daily",
  "objective_deadline": "09:00",
  "missed_goal_payout": 25.00,
  "payout_destination": "charity",
  "committedPayoutAmount": 25.00,
  "payoutCommitted": true
}
```
**Database Operations**:
```javascript
// 1. Check if user exists
const { data: existingUser } = await supabase
    .from('users')
    .select('id')
    .eq('email', email)
    .single();

// 2. Build user data object
let userData = {
    email, full_name, phone, balance_cents,
    objective_type, objective_count, objective_schedule,
    objective_deadline, missed_goal_payout, payout_destination,
    payout_committed
};

// 3. Only add password for NEW users
if (!existingUser && password) {
    userData.password_hash = password;
}

// 4. Insert or Update
if (existingUser) {
    await supabase.from('users').update(userData).eq('id', existingUser.id);
} else {
    await supabase.from('users').insert(userData);
}
```
**Success Response**: `{"message": "Profile saved successfully", "userId": "uuid"}`
**Error Response**: `{"detail": "error message"}`

---

### 📨 Recipient & Invite Endpoints

#### `POST /recipient-invites`
**Purpose**: Send SMS invite to potential payout recipient  
**Request Body**:
```json
{
  "payerEmail": "payer@example.com",
  "payerName": "John Doe",
  "phone": "+1234567890"
}
```
**Database Operations**:
```javascript
// 1. Look up payer by email
const { data: payerUser } = await supabase
    .from('users')
    .select('*')
    .eq('email', payerEmail)
    .single();

// 2. Check for existing pending invite
const { data: existingInvite } = await supabase
    .from('recipient_invites')
    .select('*')
    .eq('payer_user_id', payerUser.id)
    .eq('phone', phone)
    .eq('status', 'pending')
    .single();

// 3. If exists, resend; otherwise create new
const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();

await supabase.from('recipient_invites').insert({
    payer_user_id: payerUser.id,
    phone: phone,
    invite_code: inviteCode,
    status: 'pending'
});
```
**Twilio SMS Sent**:
```
"${payerName} has invited you to receive cash payouts through EOS. 
Set up your payout details at: https://app.live-eos.com/invite/${inviteCode}"
```
**Success Response**: `{"inviteCode": "ABC123", "message": "Invite sent successfully"}`

---

#### `POST /recipient-invites/code-only` *(Added Jan 28, 2026)*
**Purpose**: Generate invite code WITHOUT sending SMS - for manual sharing  
**Request Body**:
```json
{
  "payerEmail": "payer@example.com",
  "payerName": "John Doe"
}
```
**Database Operations**:
```javascript
// 1. Look up payer by email
const { data: payerUser } = await supabase
    .from('users')
    .select('id, full_name')
    .eq('email', payerEmail)
    .single();

// 2. Generate 8-char code (no ambiguous chars)
const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
let inviteCode = '';
for (let i = 0; i < 8; i++) {
    inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
}

// 3. Insert invite with phone = null
await supabase.from('recipient_invites').insert({
    payer_user_id: payerUser.id,
    phone: null,
    invite_code: inviteCode,
    status: 'pending'
});
```
**Success Response**: `{"inviteCode": "ABC123XY", "message": "Invite code generated successfully. Share it manually."}`  
**iOS Usage**: Called by `AddRecipientSheet.generateInviteCode()` in `ContentView.swift`

---

#### `POST /verify-invite`
**Purpose**: Validate invite code before recipient onboarding  
**Request Body**: `{"inviteCode": "ABC123"}`  
**Database Operations**:
```javascript
const { data: invite } = await supabase
    .from('recipient_invites')
    .select('*, payer:users(full_name, email)')
    .eq('invite_code', inviteCode.toUpperCase())
    .single();

// Check status is 'pending'
```
**Success Response**:
```json
{
  "inviteCode": "ABC123",
  "payerName": "John Doe",
  "payerEmail": "john@example.com"
}
```

---

#### `POST /recipient-hybrid-onboarding`
**Purpose**: Complete recipient onboarding in one step - NO REDIRECT  
**Account Type**: Stripe Connect **Custom** (not Express)  
**Request Body** (all fields collected on invite page):
```json
{
  "inviteCode": "ABC123",
  "name": "Jane Smith",
  "email": "recipient@example.com",
  "dob": { "month": 1, "day": 15, "year": 1990 },
  "address": {
    "line1": "123 Main St",
    "city": "San Francisco",
    "state": "CA",
    "postal_code": "94102"
  },
  "ssnLast4": "1234",
  "payoutMethod": "bank",  // or "card"
  "paymentToken": "btok_xxx"  // bank token or card token from Stripe.js
}
```
**Success Response**:
```json
{
  "success": true,
  "message": "Setup complete! You will receive payouts when goals are missed.",
  "recipientId": "uuid",
  "stripeAccountId": "acct_xxx",
  "transfersEnabled": true,
  "payoutsEnabled": true
}
```
**Key Features**:
- **No redirect** - everything happens on one page
- **Custom accounts** - all identity info collected upfront
- **Immediate activation** - transfers capability enabled right away
- **Debit cards OR bank accounts** supported
- **Payout statement descriptor** - set at account creation via `settings.payouts.statement_descriptor` (default: `EOS PAYOUT`)

---

#### `POST /recipients/:recipientId/onboarding-link`
**Purpose**: Generate new Stripe onboarding link for existing recipient  
**Use Case**: When recipient didn't complete onboarding initially  
**Response**: `{"url": "https://connect.stripe.com/setup/e/acct_xxx/xxx"}`

---

#### `GET /recipients/:recipientId/status`
**Purpose**: Check if recipient can receive payouts  
**Response**:
```json
{
  "recipientId": "uuid",
  "name": "Jane Smith",
  "canReceivePayouts": true/false,
  "payoutsEnabled": true/false,
  "requirementsDue": 0,
  "requirements": []
}
```

---

#### `POST /recipient-onboarding-custom` (DEPRECATED)
**Note**: This endpoint collected full card details inline but is deprecated in favor of Stripe hosted onboarding.  
**Request Body**:
```json
{
  "inviteCode": "ABC123",
  "email": "recipient@example.com",
  "cardholderName": "Jane Smith",
  "cardNumber": "4242424242424242",
  "expiryMonth": "12",
  "expiryYear": "25",
  "cvc": "123",
  "zipCode": "12345"
}
```
**Operations**:
```javascript
// 1. Verify invite code is valid and pending
// 2. Create Stripe Connect Custom account
const account = await stripe.accounts.create({
    type: 'custom',
    country: 'US',
    email: email,
    business_type: 'individual',
    capabilities: { card_payments: {requested: true}, transfers: {requested: true} }
});

// 3. Create card token and attach as external account
const token = await stripe.tokens.create({ card: {...} });
await stripe.accounts.createExternalAccount(account.id, { external_account: token.id });

// 4. Create/update recipient in database
await supabase.from('recipients').upsert({
    email, full_name: cardholderName, phone: invite.phone,
    stripe_account_id: account.id, onboarding_completed: true
});

// 5. Update invite status to 'completed'
await supabase.from('recipient_invites')
    .update({ status: 'completed', recipient_id: recipient.id })
    .eq('id', invite.id);
```

---

### 🎯 Objective Tracking Endpoints

#### `GET /objectives/today/:userId`
**Purpose**: Get user's objective session for today  
**Database Operations**:
```javascript
// 1. Ensure today's sessions exist
await supabase.rpc('create_daily_objective_sessions');

// 2. Get today's session for user
const { data } = await supabase
    .from('objective_sessions')
    .select('*')
    .eq('user_id', userId)
    .eq('session_date', new Date().toISOString().split('T')[0])
    .single();
```

#### `POST /objectives/sessions/start`
**Purpose**: Start/create today's objective session  
**Request Body**: `{"userId": "uuid"}`

#### `POST /objectives/sessions/log`
**Purpose**: Log progress (e.g., pushup count)  
**Request Body**:
```json
{
  "sessionId": "uuid",
  "completedCount": 25
}
```
**Database Operations**:
```javascript
await supabase
    .from('objective_sessions')
    .update({
        completed_count: completedCount,
        status: completedCount >= session.objective_count ? 'completed' : 'in_progress'
    })
    .eq('id', sessionId);
```

#### `POST /objectives/check-missed`
**Purpose**: Check for missed objectives and trigger payouts  
**Database Operations**:
```javascript
// 1. Fetch pending sessions (oldest -> newest), batch size 10
const { data: sessions } = await supabase
  .from('objective_sessions')
  .select('*, users!inner(...)')
  .in('status', ['pending', 'missed'])
  .eq('payout_triggered', false)
  .order('session_date', { ascending: true })
  .limit(10);

// 2. For each session (sequential):
// - Skip if before deadline in user's timezone
// - Mark accepted if completed
// - If custom payout: attempt Stripe transfer to recipient
// - If charity: record charity_payouts entry (manual payout later)
// - Create transaction record
// - Deduct balance_cents
// - Mark session payout_triggered = true
```
**Notes**:
- **Retry basis**: cron now retries **transactions with `stripe_payment_id = null`** (custom payouts only).
- **Charity**: skipped in retry logic (manual payout flow keeps `stripe_payment_id` null).
- **Batch size**: up to **10** transactions per run, **oldest to newest** by `created_at`.
- **Balance precheck**: checks platform available balance once; skips transfers that exceed remaining balance.
- **Stripe ID**: `stripe_payment_id` is only set when a transfer succeeds; otherwise it remains null and will be retried.

---

### 💳 Payment Endpoints (Stripe)

#### `POST /create-payment-intent`
**Purpose**: Create Stripe payment intent for deposits  
**Request Body**: `{"amount": 2500}` (in cents)  
**Stripe Operations**:
```javascript
// 1. Create customer
const customer = await stripe.customers.create();

// 2. Create ephemeral key for client-side security
const ephemeralKey = await stripe.ephemeralKeys.create(
    { customer: customer.id },
    { apiVersion: '2023-10-16' }
);

// 3. Create payment intent
const paymentIntent = await stripe.paymentIntents.create({
    amount: amount,
    currency: 'usd',
    customer: customer.id,
    automatic_payment_methods: { enabled: true }
});
```
**Success Response**:
```json
{
  "paymentIntentClientSecret": "pi_xxx_secret_xxx",
  "customer": "cus_xxx",
  "ephemeralKeySecret": "ek_xxx"
}
```

#### `POST /create-checkout-session`
**Purpose**: Alternative Stripe Checkout flow  
**Request Body**: `{"amount": 2500}`  
**Returns**: `{"sessionId": "cs_xxx"}`

---

## 📱 iOS App Structure

### View Hierarchy
```
EOSApp (App Entry)
└── SplashView (Boot Animation)
    └── ContentView (Main Container)
        ├── Home Screen
        │   ├── EOS Logo
        │   ├── Today's Goal Status
        │   ├── Progress Counter
        │   └── Complete By Time
        │
        ├── ProfileView (Sheet)
        │   ├── Account Info (Name, Email, Phone)
        │   ├── Payout Settings
        │   │   ├── Destination (Charity/Custom)
        │   │   ├── Amount Selection ($10, $50, $100, Custom)
        │   │   └── Commit Button
        │   ├── Balance & Deposits
        │   └── Recipient Management
        │
        ├── ObjectiveSettingsView (Sheet)
        │   ├── Target Count (Pushups)
        │   ├── Schedule (Daily/Weekdays)
        │   └── Deadline Time
        │
        └── PushUpSessionView (Sheet)
            ├── Camera View
            └── Rep Counter
```

### Key State Variables (`ContentView.swift`)
```swift
// User state (persisted locally via @AppStorage)
@AppStorage("isSignedIn") var isSignedIn: Bool
@AppStorage("profileCompleted") var profileCompleted: Bool
@AppStorage("profileUsername") var profileUsername: String
@AppStorage("profileEmail") var profileEmail: String
@AppStorage("profilePhone") var profilePhone: String

// Payout commitment
@AppStorage("payoutCommitted") var payoutCommitted: Bool
@AppStorage("committedPayoutAmount") var committedPayoutAmount: Double
@AppStorage("missedGoalPayout") var missedGoalPayout: Double
@AppStorage("payoutType") var payoutType: String  // "Charity" or "Custom"

// Objective settings
@AppStorage("pushupObjective") var pushupObjective: Int
@AppStorage("objectiveDeadline") var objectiveDeadline: Date
@AppStorage("scheduleType") var scheduleType: String  // "Daily" or "Weekdays"

// Balance
@AppStorage("profileCashHoldings") var profileCashHoldings: Double
```

### Complete UserDefaults Keys (Cleared on Sign Out)

All 22 keys that must be cleared when user signs out to prevent data bleeding:

| Category | Key | Default Value |
|----------|-----|---------------|
| **Profile** | `isSignedIn` | `false` |
| | `profileUsername` | `""` |
| | `profileEmail` | `""` |
| | `profilePhone` | `""` |
| | `profileCompleted` | `false` |
| | `profileCashHoldings` | `0.0` |
| | `userId` | `""` (removed) |
| **Payout** | `missedGoalPayout` | `0.0` |
| | `payoutCommitted` | `false` |
| | `committedPayoutAmount` | `0.0` |
| | `payoutType` | `"charity"` |
| | `selectedCharity` | `"Global Learning Fund"` |
| **Destination** | `destinationCommitted` | `false` |
| | `committedDestination` | `"charity"` |
| | `committedRecipientId` | `""` |
| | `selectedRecipientId` | `""` |
| | `customRecipientsData` | `Data()` (removed) |
| **Objectives** | `pushupObjective` | `10` |
| | `scheduleType` | `"Daily"` |
| | `objectiveDeadline` | `10 PM` |
| | `hasCompletedTodayPushUps` | `false` |
| | `todayPushUpCount` | `0` |

**Sign Out Code Location**: `ContentView.swift` → `ProfileView` → Sign Out button action

---

## 📲 iOS ↔ Backend Interaction Logic

### Complete User Flow Diagrams

#### 1. CREATE ACCOUNT FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CREATE ACCOUNT FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (CreateAccountView)                                                     │
│  ========================                                                    │
│  User fills: name, email, phone, password                                    │
│  Taps "Create Account" button                                                │
│           │                                                                  │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /users/profile                                                      ││
│  │ Body: {                                                                  ││
│  │   fullName: "John Doe",                                                  ││
│  │   email: "john@example.com",                                             ││
│  │   phone: "+1234567890",                                                  ││
│  │   password: "mypassword",                                                ││
│  │   balanceCents: 0                                                        ││
│  │ }                                                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. Check if user with email exists → NO (new user)                          │
│  2. Build userData with password_hash                                        │
│  3. INSERT into users table                                                  │
│           │                                                                  │
│           ▼                                                                  │
│  Supabase (users table)                                                      │
│  ======================                                                      │
│  New row created with:                                                       │
│  - id: auto-generated UUID                                                   │
│  - email, full_name, phone, password_hash                                    │
│  - balance_cents: 0                                                          │
│  - objective defaults (pushups, 50, daily, 09:00)                            │
│  - payout defaults (0, charity, false)                                       │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Updates Local State                                                     │
│  =======================                                                     │
│  profileUsername = name                                                      │
│  profileEmail = email                                                        │
│  profilePhone = phone                                                        │
│  profileCompleted = true                                                     │
│  isSignedIn = true                                                           │
│  → Dismisses CreateAccountView → Shows ProfileView                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 2. SIGN IN FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SIGN IN FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (SignInView)                                                            │
│  ================                                                            │
│  User enters: email, password                                                │
│  Taps "Sign In" button                                                       │
│           │                                                                  │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /signin                                                             ││
│  │ Body: { email: "john@example.com", password: "mypassword" }              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. SELECT * FROM users WHERE email = $email (case-insensitive)              │
│  2. Compare password_hash with provided password                             │
│  3. If match → Return user data (excluding password_hash)                    │
│  4. If no match → Return 401 Unauthorized                                    │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Parses Response                                                         │
│  ===================                                                         │
│  On success, populate from response.user:                                    │
│  - userId = user.id                                                          │
│  - profileUsername = user.full_name                                          │
│  - profileEmail = user.email                                                 │
│  - profilePhone = user.phone                                                 │
│  - profileCashHoldings = user.balance_cents / 100                            │
│  - payoutCommitted = user.payout_committed                                   │
│  - committedPayoutAmount = user.missed_goal_payout                           │
│  - pushupObjective = user.objective_count                                    │
│  - scheduleType = user.objective_schedule ("daily"→"Daily")                  │
│  - objectiveDeadline = parse(user.objective_deadline) as Date                │
│  Set: isSignedIn = true, profileCompleted = true                             │
│  → Dismisses SignInView → Shows ProfileView with ALL loaded data             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 3. SAVE/UPDATE PROFILE FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SAVE/UPDATE PROFILE FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (ProfileView)                                                           │
│  =================                                                           │
│  User edits profile info or commits payout                                   │
│  Taps "Update" or "Commit Payout" button                                     │
│           │                                                                  │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /users/profile                                                      ││
│  │ Body: {                                                                  ││
│  │   fullName: profileUsername,                                             ││
│  │   email: profileEmail,                                                   ││
│  │   phone: profilePhone,                                                   ││
│  │   password: profilePassword, // Only if entered (new users)              ││
│  │   balanceCents: profileCashHoldings * 100,                               ││
│  │   objective_type: "pushups",                                             ││
│  │   objective_count: 50,                                                   ││
│  │   objective_schedule: "daily",                                           ││
│  │   objective_deadline: "09:00",                                           ││
│  │   missed_goal_payout: committedPayoutAmount || missedGoalPayout,         ││
│  │   payout_destination: payoutType.lowercased(),                           ││
│  │   committedPayoutAmount: committedPayoutAmount,                          ││
│  │   payoutCommitted: payoutCommitted                                       ││
│  │ }                                                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. Check if user exists by email → YES (existing user)                      │
│  2. Build userData WITHOUT password_hash (for updates)                       │
│  3. UPDATE users SET ... WHERE id = existingUser.id                          │
│           │                                                                  │
│           ▼                                                                  │
│  Supabase (users table)                                                      │
│  ======================                                                      │
│  Row updated with new values                                                 │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Updates Local State                                                     │
│  =======================                                                     │
│  profileCompleted = true                                                     │
│  isSignedIn = true                                                           │
│  isAccountExpanded = false (collapse dropdown)                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 3b. SAVE OBJECTIVE SETTINGS FLOW (NEW)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SAVE OBJECTIVE SETTINGS FLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (ObjectiveSettingsView)                                                 │
│  ===========================                                                 │
│  User changes: pushup count, schedule, deadline                              │
│  Taps "Save" button                                                          │
│           │                                                                  │
│           ▼                                                                  │
│  Local State Update                                                          │
│  - objective = tempObjective                                                 │
│  - deadline = tempDeadline                                                   │
│  - scheduleType = tempScheduleType                                           │
│           │                                                                  │
│           ▼                                                                  │
│  Check userId from UserDefaults                                              │
│  - If empty: Print "SYNC FAILED: No userId" and skip                         │
│  - If found: Continue to sync                                                │
│           │                                                                  │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /objectives/settings/:userId                                        ││
│  │ Body: {                                                                  ││
│  │   objective_type: "pushups",                                             ││
│  │   objective_count: 50,                                                   ││
│  │   objective_schedule: "daily",                                           ││
│  │   objective_deadline: "21:00:00",                                        ││
│  │   missed_goal_payout: 25.00                                              ││
│  │ }                                                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. UPDATE users SET objective_* fields WHERE id = userId                    │
│  2. UPSERT objective_sessions for today with new target/deadline             │
│  3. Return { success: true, user: {...}, session: {...} }                    │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Confirms Sync                                                           │
│  - Print "✅ Objectives synced successfully!"                                │
│  - Dismiss ObjectiveSettingsView                                             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 4. SEND RECIPIENT INVITE FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SEND RECIPIENT INVITE FLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (AddRecipientSheet)                                                     │
│  =======================                                                     │
│  User selects contact, taps "Invite"                                         │
│           │                                                                  │
│           ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /recipient-invites                                                  ││
│  │ Body: {                                                                  ││
│  │   payerEmail: profileEmail,                                              ││
│  │   payerName: profileUsername,                                            ││
│  │   phone: "+1234567890"                                                   ││
│  │ }                                                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. SELECT user WHERE email = payerEmail                                     │
│  2. Check for existing pending invite with same phone                        │
│  3. Generate invite code: "ABC123"                                           │
│  4. INSERT into recipient_invites                                            │
│           │                                                                  │
│           ▼                                                                  │
│  Twilio SMS                                                                  │
│  ==========                                                                  │
│  From: +1xxxxxxxxxx                                                          │
│  To: recipient's phone                                                       │
│  Body: "John Doe has invited you to receive cash payouts through EOS.        │
│         Set up at: https://app.live-eos.com/invite/ABC123"                   │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Updates Local State                                                     │
│  =======================                                                     │
│  Add recipient to customRecipients array                                     │
│  Save to customRecipientsData (@AppStorage)                                  │
│  Dismiss AddRecipientSheet                                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 5. DEPOSIT FUNDS FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DEPOSIT FUNDS FLOW                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (ProfileView - Balance Section)                                         │
│  ===================================                                         │
│  User enters amount, taps "Deposit"                                          │
│           │                                                                  │
│           ▼                                                                  │
│  DepositPaymentService.preparePaymentSheet()                                 │
│  ===========================================                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ POST /create-payment-intent                                              ││
│  │ Body: { amount: 2500 } // in cents                                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. stripe.customers.create() → customer                                     │
│  2. stripe.ephemeralKeys.create() → ephemeralKey                             │
│  3. stripe.paymentIntents.create() → paymentIntent                           │
│  4. Return { customer, ephemeralKeySecret, paymentIntentClientSecret }       │
│           │                                                                  │
│           ▼                                                                  │
│  iOS (StripePaymentSheet)                                                    │
│  ========================                                                    │
│  Configure PaymentSheet with:                                                │
│  - merchantDisplayName: "EOS"                                                │
│  - customer: customer.id                                                     │
│  - ephemeralKeySecret: ephemeralKey.secret                                   │
│  - paymentIntentClientSecret: paymentIntent.client_secret                    │
│           │                                                                  │
│           ▼                                                                  │
│  User Completes Payment in Stripe UI                                         │
│  ===================================                                         │
│  - Enters card details                                                       │
│  - Confirms payment                                                          │
│           │                                                                  │
│           ▼                                                                  │
│  Stripe Processes Payment                                                    │
│  =======================                                                     │
│  - Charges card                                                              │
│  - Returns success/failure                                                   │
│           │                                                                  │
│           ▼                                                                  │
│  iOS Updates Balance (Local)                                                 │
│  ===========================                                                 │
│  profileCashHoldings += depositAmount                                        │
│  // NOTE: Should also update server via /users/profile                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 6. PAYOUT COMMITMENT FLOW
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     PAYOUT COMMITMENT FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  iOS (ProfileView - Payout Section)                                          │
│  ==================================                                          │
│  User selects amount ($10, $50, $100, or custom)                             │
│  Taps "Commit Payout" button                                                 │
│           │                                                                  │
│           ▼                                                                  │
│  commitPayout() function                                                     │
│  =======================                                                     │
│  1. committedPayoutAmount = missedGoalPayout                                 │
│  2. payoutCommitted = true                                                   │
│  3. showPayoutSelector = false (collapse to minimized bar)                   │
│  4. saveProfile() → calls /users/profile                                     │
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  UPDATE users SET                                                            │
│    missed_goal_payout = committedPayoutAmount,                               │
│    payout_committed = true                                                   │
│  WHERE email = $email                                                        │
│           │                                                                  │
│           ▼                                                                  │
│  UI Shows Minimized Bar                                                      │
│  =====================                                                       │
│  "$25 committed for payout"                                                  │
│  Tap to expand and modify                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 7. MISSED OBJECTIVE PAYOUT FLOW (Automated)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  MISSED OBJECTIVE PAYOUT FLOW (CRON)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Cron Job (Hourly)                                                           │
│  =================                                                           │
│  curl -X POST https://api.live-eos.com/objectives/check-missed               │
│           │                                                                  │
│           ▼                                                                  │
│  Server (server.js)                                                          │
│  ==================                                                          │
│  1. supabase.rpc('check_missed_objectives')                                  │
│           │                                                                  │
│           ▼                                                                  │
│  Database Function                                                           │
│  =================                                                           │
│  Returns sessions WHERE:                                                     │
│    - session_date = TODAY                                                    │
│    - current_time > deadline_time                                            │
│    - completed_count < objective_count                                       │
│    - payout_triggered = FALSE                                                │
│    - payout_committed = TRUE (from user)                                     │
│           │                                                                  │
│           ▼                                                                  │
│  For Each Missed Session                                                     │
│  =======================                                                     │
│  1. INSERT into transactions (type: 'payout', status: 'pending')             │
│  2. UPDATE objective_sessions SET payout_triggered = true                    │
│  3. [FUTURE] Stripe transfer to recipient                                    │
│  4. [FUTURE] SendGrid email notification                                     │
│  5. [FUTURE] Update user balance_cents                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🌐 Web Components

### 1. Landing Page (`live-eos.com`)
**Path**: `/var/www/live-eos/index.html`

- Marketing site with "Do or Donate" messaging
- Product vision and features
- App Store links (when ready)
- EOS branding (gold/black/white)

### 2. Invite/Onboarding Page (`app.live-eos.com`)
**Path**: `/var/www/invite/index.html`

- Recipients land here from SMS invites
- Card details input form
- Creates Stripe Connect account
- Validates invite codes

---

## 🔗 Third-Party Integrations

### Integration Flow Diagram
```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA FLOW                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  USER ACTION          →    BACKEND         →    THIRD PARTY         │
│                                                                      │
│  Create Account       →    server.js       →    Supabase (users)    │
│  Add Payment Method   →    server.js       →    Stripe (customers)  │
│  Make Deposit         →    server.js       →    Stripe (payments)   │
│  Invite Recipient     →    server.js       →    Twilio (SMS)        │
│  Recipient Onboards   →    server.js       →    Stripe Connect      │
│  Miss Objective       →    cron job        →    Stripe (transfer)   │
│  Password Reset       →    [TO BE BUILT]   →    SendGrid (email)    │
│  Payout Notification  →    [TO BE BUILT]   →    SendGrid (email)    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Service Dependencies
| Service | Critical? | Fallback |
|---------|-----------|----------|
| Supabase | YES | None - core database |
| Stripe | YES | None - all payments |
| Twilio | NO | Manual invite process |
| SendGrid | NO | No automated emails |

---

## 💳 Payment Flow

### Deposits (User → EOS Balance)
```
1. User enters amount in app
2. App calls POST /create-payment-intent
3. Server creates Stripe Customer (if new)
4. Server creates PaymentIntent
5. Server returns {customer, ephemeralKeySecret, paymentIntentClientSecret}
6. App shows Stripe PaymentSheet
7. User completes payment
8. Server updates user.balance_cents in Supabase
```

### Payouts (EOS → Recipient)
```
1. Cron job calls POST /objectives/check-missed (every 5 min)
2. Server checks objective_sessions past deadline
3. For each missed session:
   a. Get user's committed payout amount
   b. Get recipient's Stripe Connect account
   c. Create Stripe Transfer (platform → Connect account):
      stripe.transfers.create({
          amount: payoutAmountCents,
          currency: "usd",
          destination: recipient.stripe_connect_account_id
      });
   d. Create Instant Payout (Connect account → debit card):
      stripe.payouts.create({
          amount: payoutAmountCents,
          currency: "usd",
          method: "instant"  // Falls back to "standard" if instant unavailable
      }, { stripeAccount: recipientConnectAccountId });
   e. Update user.balance_cents
   f. Record in transactions table
   g. Send SMS notification to recipient
```

### Stripe Connect Requirements (CRITICAL)
For recipients to receive payouts, their Connect account MUST have:

| Requirement | How It's Set | Status |
|-------------|--------------|--------|
| `business_profile.url` | Auto-set to `https://live-eos.com` during signup | ✅ |
| `tos_acceptance` | Captured during signup (date + IP) | ✅ |
| External account (debit card) | User enters on `app.live-eos.com` | ✅ |
| `payouts_enabled = true` | Stripe enables after requirements met | ✅ |

**If `payouts_enabled = false`:** Check `account.requirements.currently_due` for missing fields.

### Payout Test (Verified Working ✅)
```bash
# Test executed January 15, 2026
Transfer: tr_1Sph8lJvjEmusMrWJxczDNHd ($1.00)
Payout: po_1Sph8nF29DCsARao1xPNuWO1 (instant to **** 6263 Visa)
Status: SUCCESS - funds delivered to debit card
```

---

## 📧 Email System

### Architecture (To Be Implemented)
```
┌─────────────────────────────────────────────────────────────────┐
│                    EMAIL FLOW                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Google Workspace                    SendGrid                    │
│  ┌──────────────────┐               ┌──────────────────┐        │
│  │ @live-eos.com    │               │ Transactional    │        │
│  │ email hosting    │               │ Email API        │        │
│  │                  │               │                  │        │
│  │ • Inbox/Outbox   │               │ • Password Reset │        │
│  │ • Manual emails  │               │ • Payout Notifs  │        │
│  │ • Support        │               │ • Welcome Email  │        │
│  └──────────────────┘               └──────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Google Workspace Setup (TODO)
1. Sign up at https://workspace.google.com
2. Verify `live-eos.com` domain
3. Add MX records to DNS
4. Create email accounts

### SendGrid Setup (TODO)
1. Sign up at https://sendgrid.com (or via Twilio)
2. Verify `live-eos.com` domain
3. Add DNS records (SPF, DKIM, CNAME)
4. Generate API key
5. Add to server `.env`
6. Implement email templates

### Email Types to Implement
| Email | Trigger | Template |
|-------|---------|----------|
| Welcome | Account creation | `welcome.html` |
| Password Reset | Reset request | `password-reset.html` |
| Payout Sent | Missed objective | `payout-sent.html` |
| Deposit Confirmation | Payment complete | `deposit-confirmed.html` |
| Invite Sent | Recipient invited | `invite-sent.html` |

---

## ⏰ Cron Jobs & Automation

### Currently Running Crons (on server)
```bash
# View current crontab
ssh user@159.26.94.94 "crontab -l"

# Active cron jobs:
*/5 * * * * /home/user/morning-would-payments/check-missed-cron.sh   # Every 5 min
0 0 * * *   /home/user/morning-would-payments/midnight-reset.sh      # Midnight daily
```

### Midnight Reset (`midnight-reset.sh`)
- Marks yesterday's pending sessions as `missed`
- Creates new `objective_sessions` for today for all `payout_committed` users
- Logs to `/home/user/morning-would-payments/reset.log`

### Check Missed (`check-missed-cron.sh`)
- Runs every 5 minutes
- Retries **custom payouts** where `transactions.stripe_payment_id` is null
- Skips **charity** payouts (manual payout flow)
- Processes **oldest to newest** by `created_at`
- **Batch size: 10** payouts per run
- **Balance precheck**: reads platform available balance once and skips transfers that exceed remaining balance
- Logs to `/home/user/morning-would-payments/cron.log`

### Manual Trigger Commands
```bash
# Trigger missed objective check manually
curl -X POST https://api.live-eos.com/objectives/check-missed

# Trigger midnight reset manually
curl -X POST https://api.live-eos.com/objectives/midnight-reset

# Create/update today's session for a user
curl -X POST https://api.live-eos.com/objectives/ensure-session/{userId}
```

### Setup Commands
```bash
# On server, edit crontab
ssh user@159.26.94.94
crontab -e

# Add lines above, save and exit
```

---

## 🔒 Security & Authentication

### Current Implementation
| Feature | Status | Notes |
|---------|--------|-------|
| Password Storage | ⚠️ Plain text | NEEDS: bcrypt hashing |
| API Authentication | ❌ None | NEEDS: JWT tokens |
| Rate Limiting | ❌ None | NEEDS: express-rate-limit |
| HTTPS | ✅ Enabled | Let's Encrypt SSL |
| Supabase RLS | ✅ Enabled | Row-level security |
| CORS | ✅ Configured | Restricted origins |

### Security TODO
1. [ ] Implement bcrypt password hashing
2. [ ] Add JWT authentication
3. [ ] Implement rate limiting
4. [ ] Add input validation/sanitization
5. [ ] Set up Stripe webhooks for payment verification
6. [ ] Configure Supabase auth (optional)

---

## 📁 File Path Reference

### Quick Reference Table

| What | Local Path | Remote Path |
|------|------------|-------------|
| iOS Project | `/Users/emayne/morning-would/` | N/A |
| Main Swift File | `.../morning-would/ContentView.swift` | N/A |
| Stripe Config | `.../morning-would/StripeConfig.swift` | N/A |
| Backend Server | `.../backend/complete-server-update.js` | `/home/user/morning-would-payments/server.js` |
| Environment Vars | N/A | `/home/user/morning-would-payments/.env` |
| SQL Schemas | `.../sql/*.sql` | Run in Supabase SQL Editor |
| Landing Page | `.../branding/` (source) | `/var/www/live-eos/index.html` |
| Invite Page | `.../docs/invite-page-update.html` (ref) | `/var/www/invite/index.html` |
| Nginx Configs | N/A | `/etc/nginx/sites-available/` |
| SSL Certs | N/A | `/etc/letsencrypt/live/` |
| This Doc | `.../docs/EOS-MASTER-DOCUMENTATION.md` | Copy to server if needed |

---

## 🚀 Deployment Procedures

### Deploying Backend Changes
```bash
# 1. Edit locally
code /Users/emayne/morning-would/backend/complete-server-update.js

# 2. Copy to server
scp /Users/emayne/morning-would/backend/complete-server-update.js \
    user@159.26.94.94:/home/user/morning-would-payments/server.js

# 3. Restart server
# 3. Restart server with PM2
ssh user@159.26.94.94 "source ~/.nvm/nvm.sh && pm2 restart eos-backend"

# 4. Verify
curl https://api.live-eos.com/health
```

### Deploying Web Changes
```bash
# Landing page
scp /path/to/index.html user@159.26.94.94:/var/www/live-eos/index.html

# Invite page
scp /path/to/index.html user@159.26.94.94:/var/www/invite/index.html
```

### Database Changes
```bash
# 1. Open Supabase Dashboard
# 2. Go to SQL Editor
# 3. Paste and run SQL from /Users/emayne/morning-would/sql/
# 4. Verify in Table Editor
```

### iOS Deployment
```bash
# 1. Open Xcode
open /Users/emayne/morning-would/Eos.xcodeproj

# 2. Select target device/simulator
# 3. Cmd+R to build and run
# 4. For App Store: Product → Archive
```

---

## 🔄 Update Log

### January 28, 2026 - v2.4 (PM2 + Code-Only Invites)

#### PM2 Process Manager - Installed & Configured ✅
- **Installed PM2** for production process management
- Server now auto-restarts on crash
- Server auto-starts on reboot via systemd
- PM2 Commands:
  ```bash
  pm2 status          # Check server status
  pm2 logs eos-backend   # View logs
  pm2 restart eos-backend # Restart after code changes
  pm2 monit           # Real-time monitoring
  ```

#### New Endpoint: `/recipient-invites/code-only`
- **Added**: `POST /recipient-invites/code-only`
- Generates invite codes WITHOUT sending SMS (Twilio)
- For manual sharing via text/email
- Request: `{ "payerEmail": "user@example.com", "payerName": "John" }`
- Response: `{ "inviteCode": "ABC123XY", "message": "..." }`
- iOS app uses this in `AddRecipientSheet.generateInviteCode()`

#### Server Process Fix
- Killed stale server process (running since Jan 17)
- Server now managed exclusively by PM2 (name: `eos-backend`)

#### Key Files Changed
| File | Change |
|------|--------|
| `server.js` (remote) | Added `/recipient-invites/code-only` endpoint |
| PM2 config | Created systemd service for auto-restart |

---

### January 15, 2026 - v2.3 (Payout System Verified ✅)

#### Stripe Connect Payouts - FULLY WORKING
- **End-to-end payout test successful**: $1.00 transferred and paid out
- Transfer ID: `tr_1Sph8lJvjEmusMrWJxczDNHd`
- Payout ID: `po_1Sph8nF29DCsARao1xPNuWO1`
- Instant payout to debit card (**** 6263 Visa) confirmed

#### Critical Fix: `business_profile.url`
- **Problem**: Stripe Connect accounts had `payouts_enabled = false`
- **Cause**: Missing `business_profile.url` requirement
- **Fix**: Added `business_profile: { url: "https://live-eos.com" }` to account creation
- All new accounts now auto-include this field

#### Objective Settings → Session Sync
- `/objectives/settings/:userId` now ALSO creates/updates today's `objective_session`
- No longer need to wait for midnight cron to see changes take effect
- Preserves `completed_count` if session already exists

#### Sign Out - Complete Data Reset
- Sign out now clears **ALL 22 UserDefaults keys** for clean slate
- Prevents data bleeding between accounts
- Keys cleared: profile, payout, destination, objective settings, userId

#### Objective Settings Sync (iOS ↔ Server)
- **SAVE**: Objectives now sync TO server when saved in app
  - Endpoint: `POST /objectives/settings/:userId`
  - Syncs: count, schedule, deadline, payout amount
- **LOAD**: Objectives now load FROM server on sign-in
  - Added `@AppStorage` for objectives in SignInView
  - Parses `objective_count`, `objective_schedule`, `objective_deadline` from response

#### Server Fixes
- Fixed `/signin` endpoint: was returning `user.name` instead of `user.full_name`
- Now correctly populates name on sign-in

#### Stripe Connect - Custom vs Express Accounts
- **NEW recipients**: Use **Custom accounts** (all info collected on one page, no redirect)
- **Existing recipients**: Have Express accounts (need Stripe hosted onboarding)
- Custom accounts enable immediate transfers without redirect
- Updated `/recipient-hybrid-onboarding` endpoint for Custom account creation

#### UI Fixes
- Fixed phone input field styling in CreateAccountView (was missing padding/background)
- Added better debugging logs for objective sync (`🔍`, `📤`, `✅`, `❌` prefixes)

#### Key Endpoints Updated
| Endpoint | Change |
|----------|--------|
| `POST /signin` | Returns `user.full_name` correctly |
| `POST /objectives/settings/:userId` | Updates user objectives + creates/updates daily session |
| `POST /recipient-hybrid-onboarding` | Creates Custom Stripe account with `business_profile.url` |
| `POST /recipients/:id/onboarding-link` | Generates Stripe onboarding link for Express accounts |
| `GET /recipients/:id/status` | Check if recipient can receive payouts |

---

### January 11, 2026 - v2.1
- Added Vercel as domain registrar
- Added password placeholders for ALL services
- Added Master Credentials Summary table
- Added GitHub section
- Added VPS provider placeholders

### January 14, 2026 - v2.1
- Added comprehensive Apple Pay Integration section
- Documented Apple Pay certificate requirement (`apple_pay.cer`)
- Added troubleshooting guide for Apple Pay errors
- Documented backend response requirements for Apple Pay
- Apple Pay now fully functional ✅

### January 11, 2026 - v2.0
- Complete ecosystem documentation overhaul
- Added all credentials and API keys
- Mapped local vs remote file structure
- Added Google Workspace & SendGrid placeholders
- Documented payout commitment system
- Added file path reference table

### January 11, 2026 - v1.0
- Initial documentation created
- Payout commitment system implemented
- Multi-objective architecture designed
- File organization completed

---

## ⚠️ What's Missing / TODO

### 🔐 Passwords to Fill In (Search for `[PLACEHOLDER]`)
- [ ] Stripe Dashboard password
- [ ] Supabase account email & password
- [ ] Supabase database password
- [ ] Twilio account email & password
- [ ] SendGrid account email & password
- [ ] SendGrid API Key
- [ ] Google Workspace super admin password
- [ ] Google Workspace user passwords (support, team, noreply)
- [ ] Apple Developer account password
- [ ] Vercel account email & password
- [ ] VPS provider account email & password
- [ ] Server SSH password (if using password auth)
- [ ] Server root password
- [ ] GitHub account credentials (if applicable)

### API Keys Still Needed
- [ ] SendGrid API Key
- [ ] Stripe Webhook Secret
- [ ] Apple Developer Team ID
- [ ] Supabase Anon Key (if using client-side)
- [ ] GitHub Personal Access Token (if applicable)

### Features Not Yet Implemented
- [ ] Email system (SendGrid integration)
- [ ] Password reset flow
- [ ] JWT authentication
- [ ] Multi-objective support
- [ ] Push notifications
- [ ] App Store submission

### Documentation Gaps
- [ ] Stripe webhook setup guide
- [ ] Google Workspace MX record setup
- [ ] SendGrid DNS verification steps
- [ ] iOS provisioning profile setup
- [ ] TestFlight distribution guide

---

## 📞 Quick Commands Reference

```bash
# SSH to server
ssh user@159.26.94.94

# Check server status
curl https://api.live-eos.com/health

# View server logs (PM2)
ssh user@159.26.94.94 "source ~/.nvm/nvm.sh && pm2 logs eos-backend --lines 50"

# Restart server (PM2)
ssh user@159.26.94.94 "source ~/.nvm/nvm.sh && pm2 restart eos-backend"

# Check PM2 status
ssh user@159.26.94.94 "source ~/.nvm/nvm.sh && pm2 status"

# Check nginx status
ssh user@159.26.94.94 "sudo systemctl status nginx"

# Renew SSL certs
ssh user@159.26.94.94 "sudo certbot renew"

# Test database connection
curl https://api.live-eos.com/debug/database
```

---

**Document maintained by**: Development Team  
**For questions**: Refer to code comments or this documentation  
**For another AI agent**: All paths, credentials, and integrations are documented above. Start with the architecture diagram, then check specific sections as needed.

---

## UPDATE LOG - January 15, 2026 (Late Night Session)

### Charity Payout System
**New feature to handle charity donations when users miss objectives.**

#### Database Changes (`sql/charity-tracking.sql`):
- `users.committed_charity` - Stores the specific charity name when locked
- `charity_payouts` table - Logs each charity payout event:
  - `user_id`, `charity_name`, `amount_cents`, `session_id`, `status`
- `charity_totals` view - Aggregates total amounts per charity

#### Server Endpoints:
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/admin/charity-totals` | GET | View aggregated charity payout totals |
| `/admin/charity-payout/:charityName` | POST | Mark charity payouts as paid out |

#### Payout Flow:
- **Charity destination**: Amount deducted from balance, logged to `charity_payouts` table, NO Stripe transfer (stays in EOS Stripe account for manual donation)
- **Custom recipient**: Amount deducted from balance, Stripe transfer to recipient's connected account

#### iOS App:
- `@AppStorage("committedCharity")` - Stores selected charity when locking
- `commitDestination()` saves `selectedCharity` when type is "charity"

---

### Timezone Fix
**Critical bug fix for payout timing.**

#### Problem:
- Server was checking deadlines against UTC time
- Users setting deadlines in PST were getting payouts triggered at wrong times

#### Solution:
1. Added `timezone` field to user profile sync
2. Server now converts current time to user's timezone before comparing
3. iOS app sends `TimeZone.current.identifier` with objective settings

#### Code Changes:
**iOS (`ContentView.swift`):**
```swift
let deviceTimezone = TimeZone.current.identifier
let payload: [String: Any] = [
    // ... other fields
    "timezone": deviceTimezone
]
```

**Server (`server.js`):**
```javascript
function getCurrentTimeInTimezone(tz) {
    const options = { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: tz };
    return new Date().toLocaleTimeString("en-US", options);
}
```

---

### Cron Job Schedule
| Schedule | Script | Purpose |
|----------|--------|---------|
| `* * * * *` | `check-missed-cron.sh` | Check missed objectives (every 1 minute) |
| `0 0 * * *` | `midnight-reset.sh` | Create new daily sessions at midnight |

---

### Recipient Status Flow
**Fixed invite-to-recipient linking.**

#### Database Status Values:
- `pending` - Invite sent, waiting for recipient signup
- `accepted` - Recipient completed signup with Stripe account
- `expired` - Invite expired or superseded

#### iOS Display:
- `pending` → Orange badge
- `accepted`/`active` → Green badge

---

### Keyboard Done Button Fix
**Single toolbar at Form level handles all TextFields in ProfileView.**

```swift
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
            isPayoutAmountFocused = false
            isDepositAmountFocused = false
            isProfileNameFocused = false
            isProfileEmailFocused = false
            isProfilePhoneFocused = false
            isProfilePasswordFocused = false
            UIApplication.shared.eos_dismissKeyboard()
        }
    }
}
```

---

### Destination Lock Protection
**Users cannot lock a pending recipient as payout destination.**

```swift
private var selectedRecipientIsActive: Bool {
    if payoutType.lowercased() != "custom" { return true }
    if let recipient = customRecipients.first(where: { $0.id == selectedRecipientId }) {
        return recipient.status == "active"
    }
    return false
}
```

- Button disabled when recipient is pending
- Shows warning: "Recipient Setup Pending"
- Guard in `commitDestination()` prevents locking

---

### File Changes Summary
| File | Changes |
|------|---------|
| `server.js` | Timezone support, charity payout handling, admin endpoints |
| `ContentView.swift` | Timezone sync, committedCharity, keyboard fix, recipient lock protection |
| `sql/charity-tracking.sql` | New file for charity system |
| Crontab | Changed from */5 to * (every minute) |

