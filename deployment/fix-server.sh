#!/bin/bash
# Fix server - restore from backup and add endpoint properly

ssh user@159.26.94.94 << 'ENDSSH'
cd /home/user/morning-would-payments

echo "=== Checking server log ==="
tail -20 server.log 2>/dev/null || echo "No log file"

echo ""
echo "=== Checking for backups ==="
ls -la server.js* 2>/dev/null

echo ""
echo "=== Restoring from backup if exists ==="
if [ -f server.js.backup ]; then
    cp server.js.backup server.js
    echo "Restored from server.js.backup"
elif [ -f server.js.backup2 ]; then
    cp server.js.backup2 server.js
    echo "Restored from server.js.backup2"
else
    echo "No backup found - checking file for issues"
    # Remove any duplicate endpoint additions at the end
    # Find where app.listen starts and truncate after that block
fi

echo ""
echo "=== Checking if endpoint exists ==="
grep -n "recipient-invites/code-only" server.js || echo "Endpoint not found"

echo ""
echo "=== Trying to start server ==="
pkill -f "node server.js" 2>/dev/null
sleep 1
node server.js &
sleep 3

echo ""
echo "=== Checking if running ==="
pgrep -f "node server.js" && echo "Server is running" || echo "Server NOT running"

echo ""
echo "=== Last 10 lines of log ==="
tail -10 server.log 2>/dev/null
ENDSSH
