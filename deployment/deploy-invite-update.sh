#!/bin/bash

# Script to deploy the updated invite page and server endpoint
# Run this script to update the recipient landing page on your server

echo "🚀 Deploying EOS Invite Page Updates..."
echo ""

# Server details
SERVER="user@159.26.94.94"

echo "📄 Step 1: Upload the new invite page HTML"
echo "Run this command:"
echo ""
echo "scp /Users/emayne/invite-page-update.html $SERVER:/tmp/index.html"
echo ""
echo "Then SSH into your server and run:"
echo "sudo mv /tmp/index.html /var/www/invite/index.html"
echo "sudo chown www-data:www-data /var/www/invite/index.html"
echo ""

echo "📝 Step 2: Add the new endpoint to your server.js"
echo "The new endpoint code is in /Users/emayne/server-update.js"
echo ""
echo "SSH into your server:"
echo "ssh $SERVER"
echo ""
echo "Then edit your server.js file:"
echo "cd ~/morning-would-payments"
echo "nano server.js"
echo ""
echo "Add the endpoint code from server-update.js (before the app.listen at the end)"
echo ""
echo "Save and restart the server:"
echo "pm2 restart server || node server.js"
echo ""

echo "✅ After completing these steps, the invite page will have:"
echo "   - Functional card input form"
echo "   - Proper EOS styling with gold/black theme"
echo "   - Card validation and formatting"
echo "   - Secure Stripe integration"
echo "   - No date of birth field (removed)"
echo ""
echo "📱 Test the page at: https://app.live-eos.com"