# 🎯 EOS (Morning Would) - Project Repository

## 📁 Project Structure

```
morning-would/
├── backend/              # Server code
│   ├── complete-server-update.js    # Full server.js with all endpoints
│   ├── multi-objective-endpoints.js # Future multi-objective features
│   └── objective-*.js              # Modular endpoint files
│
├── deployment/           # Deployment scripts
│   ├── deploy-objectives.sh        # Deploy objective system
│   └── update-server-objectives.sh # Update server endpoints
│
├── docs/                 # Documentation
│   ├── EOS-MASTER-DOCUMENTATION.md # Complete system documentation
│   ├── payout-commit-update.swift  # iOS update guide
│   └── invite-page-update.html     # Web page updates
│
├── sql/                  # Database schemas
│   ├── simplified-objective-schema.sql  # Current production schema
│   ├── multi-objective-schema.sql      # Future features schema
│   └── supabase-schema.sql            # Complete database setup
│
├── morning-would/        # iOS App Source (SwiftUI)
│   ├── ContentView.swift           # Main app view
│   ├── SplashView.swift           # Boot animation
│   └── Assets.xcassets/           # Images and colors
│
└── Eos.xcodeproj/       # Xcode project file
```

## 🚀 Quick Start

### iOS App
1. Open `Eos.xcodeproj` in Xcode
2. Build and run on simulator/device

### Backend Server
1. Copy `backend/complete-server-update.js` to your server
2. Update environment variables
3. Run `node server.js`

### Database
1. Run `sql/simplified-objective-schema.sql` in Supabase
2. Tables will be created automatically

## 📖 Documentation

**Master Documentation**: See `docs/EOS-MASTER-DOCUMENTATION.md` for:
- Complete system architecture
- API endpoints reference
- Database schema details
- Deployment instructions
- Payment flow diagrams

## 🔄 Recent Updates

- **Jan 11, 2026**: 
  - Organized project structure
  - Added multi-objective support (future)
  - Created master documentation
  - Implemented payout commitment system

## 🌟 Key Features

- **Do or Donate**: Complete objectives or money goes to charity/friends
- **Payout Commitment**: Users must commit amount before tracking begins
- **Objective Tracking**: Daily pushup goals with deadlines
- **Recipient System**: Send payouts to friends via SMS invites
- **Future Ready**: Architecture supports multiple objective types

## 🛠️ Tech Stack

- **iOS**: SwiftUI, Stripe SDK
- **Backend**: Node.js, Express
- **Database**: Supabase (PostgreSQL)
- **Payments**: Stripe & Stripe Connect
- **SMS**: Twilio

## 📱 Contact

Server: `user@159.26.94.94`