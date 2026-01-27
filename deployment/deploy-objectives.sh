#!/bin/bash

echo "🎯 EOS Objective Tracking Deployment"
echo "====================================="
echo ""
echo "This script will deploy the objective tracking system to your server."
echo ""

# Deploy to server
SERVER="user@159.26.94.94"

echo "📋 Step 1: Database Schema"
echo "--------------------------"
echo "Please copy the content from simplified-objective-schema.sql"
echo "and run it in your Supabase SQL Editor."
echo ""
echo "Key tables/columns to add:"
echo "  ✓ users table: objective_type, objective_count, payout_committed, etc."
echo "  ✓ objective_sessions table: daily tracking"
echo "  ✓ Functions: create_daily_objective_sessions(), check_missed_objectives()"
echo ""
read -p "Press Enter after running the SQL..."

echo ""
echo "🔧 Step 2: Updating Server Endpoints"
echo "------------------------------------"
ssh $SERVER << 'EOF'
cd ~/morning-would-payments

# Backup current server.js
cp server.js server.js.backup.objectives.$(date +%Y%m%d_%H%M%S)
echo "✅ Backed up server.js"

# Note: You need to manually add the endpoints from simplified-objective-backend.js
echo ""
echo "📝 Please manually add these endpoints to server.js:"
echo "  - Updated POST /users/profile (saves objective settings)"
echo "  - GET /objectives/today/:userId"
echo "  - POST /objectives/sessions/start"
echo "  - POST /objectives/sessions/log"
echo "  - POST /objectives/check-missed"
echo ""
EOF

echo ""
echo "⏰ Step 3: Setting Up Cron Job"
echo "-------------------------------"
echo "Add this to your server's crontab to check for missed objectives:"
echo ""
echo "# Check every hour for missed objectives"
echo "0 * * * * curl -X POST https://api.live-eos.com/objectives/check-missed"
echo ""
echo "Or check at specific times (10 minutes after common deadlines):"
echo "10 7,8,9,10,11,12 * * * curl -X POST https://api.live-eos.com/objectives/check-missed"
echo ""
read -p "Press Enter after setting up the cron job (optional, can do later)..."

echo ""
echo "📱 Step 4: Update iOS App"
echo "------------------------"
echo "Apply the changes from payout-commit-update.swift:"
echo "  ✓ Add @AppStorage variables for payoutCommitted and committedPayoutAmount"
echo "  ✓ Add showPayoutSelector @State variable"
echo "  ✓ Replace the Payout Amount section with new UI"
echo "  ✓ Add commitPayout() function"
echo "  ✓ Update saveProfile() to send committed amount"
echo ""

echo ""
echo "✅ Deployment Checklist"
echo "-----------------------"
echo "[ ] Database schema updated in Supabase"
echo "[ ] Server endpoints added to server.js"
echo "[ ] Server restarted (pm2 restart server or pkill node && nohup node server.js &)"
echo "[ ] iOS app updated with payout commit UI"
echo "[ ] Test payout commitment flow"
echo "[ ] (Optional) Cron job configured"
echo ""

echo "🎉 Done! The simplified objective tracking system is ready."
echo ""
echo "How it works:"
echo "1. User commits a payout amount in the app"
echo "2. System creates daily objective sessions for committed users"
echo "3. User logs progress through the day"
echo "4. After deadline, system checks for missed objectives"
echo "5. Automatic payouts triggered for missed goals"