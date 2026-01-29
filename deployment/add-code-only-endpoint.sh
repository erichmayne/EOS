#!/bin/bash
# Add /recipient-invites/code-only endpoint to server

ssh user@159.26.94.94 << 'ENDSSH'
cd /home/user/morning-would-payments

# Check if endpoint already exists
if grep -q "recipient-invites/code-only" server.js; then
    echo "Endpoint already exists"
else
    echo "Adding endpoint..."
    cat >> server.js << 'ENDPOINT'

// Generate invite code only (no SMS) - for manual sharing
app.post("/recipient-invites/code-only", async (req, res) => {
    try {
        const { payerEmail, payerName } = req.body;
        
        if (!payerEmail) {
            return res.status(400).json({ detail: "Missing required field: payerEmail" });
        }
        
        const { data: payerUser, error: userError } = await supabase
            .from("users")
            .select("*")
            .eq("email", payerEmail)
            .single();
        
        if (userError || !payerUser) {
            return res.status(404).json({ detail: "Payer user not found. Please save your profile first." });
        }
        
        const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        let inviteCode = "";
        for (let i = 0; i < 8; i++) {
            inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        const { data: newInvite, error: insertError } = await supabase
            .from("recipient_invites")
            .insert({
                payer_user_id: payerUser.id,
                phone: null,
                invite_code: inviteCode,
                status: "pending"
            })
            .select()
            .single();
        
        if (insertError) {
            return res.status(500).json({ detail: "Failed to create invite: " + insertError.message });
        }
        
        res.json({ inviteCode: inviteCode, message: "Invite code generated successfully." });
    } catch (error) {
        res.status(500).json({ detail: error.message || "Internal server error" });
    }
});
ENDPOINT
    echo "Endpoint added"
fi

# Restart server
echo "Restarting server..."
pkill -f "node server.js" 2>/dev/null
sleep 2
nohup node server.js > server.log 2>&1 &
sleep 2

# Verify server is running
if pgrep -f "node server.js" > /dev/null; then
    echo "Server restarted successfully"
else
    echo "ERROR: Server failed to start. Check server.log"
fi

# Test endpoint
echo "Testing endpoint..."
curl -s -X POST http://localhost:4242/recipient-invites/code-only \
  -H "Content-Type: application/json" \
  -d '{"payerEmail":"test@test.com"}' | head -100
ENDSSH
