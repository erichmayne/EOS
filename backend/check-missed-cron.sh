#!/bin/bash
curl -s -X POST "http://localhost:4242/objectives/check-missed" -H "Content-Type: application/json" >> /home/user/morning-would-payments/cron.log 2>&1
echo "" >> /home/user/morning-would-payments/cron.log
curl -s -X POST "http://localhost:4242/compete/check-completed" -H "Content-Type: application/json" >> /home/user/morning-would-payments/cron.log 2>&1
echo "" >> /home/user/morning-would-payments/cron.log
