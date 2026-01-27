#!/bin/bash

# Deploy script for objective tracking system

echo "🎯 EOS Objective Tracking System Deployment"
echo "==========================================="
echo ""

# Step 1: Apply database schema
echo "📊 Step 1: Applying database schema..."
echo "Please run the SQL in objective-tracking-schema.sql in your Supabase dashboard"
echo "Press Enter when complete..."
read

# Step 2: Update server endpoints
echo "🔧 Step 2: Updating server endpoints..."
cat << 'EOF'

Add the endpoints from objective-endpoints.js to your server.js file.
The key endpoints are:

1. Updated /users/profile - saves objective settings
2. GET /objectives/today/:userId - get today's session
3. POST /objectives/sessions/start - start a session
4. POST /objectives/sessions/log - log progress
5. POST /objectives/check-missed - check for missed objectives
6. GET /objectives/history/:userId - get user history
7. GET /objectives/leaderboard - get leaderboard

Press Enter when complete...
EOF
read

# Step 3: Set up cron job
echo "⏰ Step 3: Setting up cron job..."
echo ""
echo "To automatically check for missed objectives, add this to your server's crontab:"
echo ""
echo "# Check for missed objectives every hour"
echo "0 * * * * /usr/bin/node /home/user/morning-would-payments/objective-cron.js >> /var/log/eos-objectives.log 2>&1"
echo ""
echo "Or run it at specific times after common deadlines:"
echo "10 7,8,9,10,11,12 * * * /usr/bin/node /home/user/morning-would-payments/objective-cron.js"
echo ""
echo "Press Enter when complete..."
read

# Step 4: Test the system
echo "✅ Step 4: Testing the system..."
echo ""
echo "Test checklist:"
echo "[ ] Create/update user profile with objective settings"
echo "[ ] Verify objective data is saved in database"
echo "[ ] Start an objective session"
echo "[ ] Log progress (pushups completed)"
echo "[ ] Test deadline expiration and payout trigger"
echo ""

echo "🎉 Deployment complete!"
echo ""
echo "=========================================="
echo "📝 How the System Works:"
echo "=========================================="
echo ""
echo "1. DAILY SESSION CREATION:"
echo "   - Automatically creates sessions for users with active objectives"
echo "   - Respects 'daily' vs 'weekdays' schedule settings"
echo "   - Each user gets one session per eligible day"
echo ""
echo "2. OBJECTIVE TRACKING:"
echo "   - Users start session when beginning their objective"
echo "   - Progress is logged in real-time (e.g., after each set of pushups)"
echo "   - Video proof can be attached to logs"
echo "   - Session marked 'completed' when target is reached"
echo ""
echo "3. MISSED OBJECTIVE DETECTION:"
echo "   - Cron job runs hourly (or at specific times)"
echo "   - Checks for sessions past deadline with incomplete objectives"
echo "   - Marks them as 'missed' and triggers payouts"
echo ""
echo "4. PAYOUT PROCESSING:"
echo "   - Charity: Charges user's card, sends to charity"
echo "   - Custom: Charges user's card, transfers to recipient"
echo "   - All payouts tracked in transactions table"
echo ""
echo "=========================================="
echo "🔍 Monitoring Commands:"
echo "=========================================="
echo ""
echo "# View today's objectives across all users:"
echo "SELECT * FROM today_objectives;"
echo ""
echo "# Check for missed objectives manually:"
echo "SELECT * FROM check_missed_objectives();"
echo ""
echo "# View recent transactions:"
echo "SELECT * FROM transactions WHERE type = 'payout' ORDER BY created_at DESC LIMIT 10;"
echo ""
echo "# Check cron job logs:"
echo "tail -f /var/log/eos-objectives.log"
echo ""