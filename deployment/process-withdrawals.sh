#!/bin/bash
# Process pending withdrawal queue
# Run via cron every hour at :30

cd /home/user/morning-would-payments

echo "$(date): Processing withdrawal queue..." >> /home/user/morning-would-payments/withdrawal-cron.log

curl -s -X POST https://api.live-eos.com/withdrawals/process-queue >> /home/user/morning-would-payments/withdrawal-cron.log 2>&1

echo "" >> /home/user/morning-would-payments/withdrawal-cron.log
