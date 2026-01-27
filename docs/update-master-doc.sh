#!/bin/bash

# Update master documentation on server
SERVER="user@159.26.94.94"

echo "📝 Updating EOS Master Documentation on server..."

# Copy the updated documentation
scp /Users/emayne/morning-would/docs/EOS-MASTER-DOCUMENTATION.md $SERVER:~/EOS-MASTER-DOCUMENTATION.md

# Add backup with timestamp
ssh $SERVER << 'EOF'
cd ~
cp EOS-MASTER-DOCUMENTATION.md "EOS-MASTER-DOCUMENTATION-backup-$(date +%Y%m%d-%H%M%S).md"
echo "✅ Master documentation updated and backed up"
echo ""
echo "📋 Current project structure:"
echo "=========================="
echo "Local: /Users/emayne/morning-would/"
echo "  ├── backend/     - Server code & endpoints"
echo "  ├── deployment/  - Deploy scripts"
echo "  ├── docs/        - Documentation & guides"
echo "  ├── sql/         - Database schemas"
echo "  └── morning-would/ - iOS app source"
echo ""
echo "Server: ~/morning-would-payments/"
echo "  └── server.js   - Live API"
echo ""
echo "Master Doc: ~/EOS-MASTER-DOCUMENTATION.md"
EOF