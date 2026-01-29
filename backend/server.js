require('dotenv').config();

const express = require('express');
const cors = require('cors');
const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const bcrypt = require('bcryptjs');
const twilio = require('twilio');
const crypto = require('crypto');

const app = express();

// Stripe client (LIVE mode)
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: '2023-10-16',
});

// Supabase client
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY
);

// Twilio client
const twilioClient = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

app.use(cors());
app.use(express.json());

// -----------------------------------------------------------------------------
// Health check
// -----------------------------------------------------------------------------
app.get('/health', (req, res) => res.json({ ok: true }));

// -----------------------------------------------------------------------------
// Payments: create PaymentIntent + Customer + Ephemeral Key
// -----------------------------------------------------------------------------
app.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount } = req.body; // amount in cents

    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    // Calculate charge with Stripe fee (2.9% + $0.30) so user gets full deposit
    const stripeFeeFixed = 30; // 30 cents
    const stripeFeePercent = 0.029; // 2.9%
    const chargeAmount = Math.ceil((amount + stripeFeeFixed) / (1 - stripeFeePercent));
    console.log(`Deposit: $${(amount/100).toFixed(2)} -> Charge: $${(chargeAmount/100).toFixed(2)}`);

    const customer = await stripe.customers.create();

    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: '2023-10-16' }
    );

    const paymentIntent = await stripe.paymentIntents.create({
      amount: chargeAmount, // Charge includes Stripe fee
      currency: 'usd',
      customer: customer.id,
      automatic_payment_methods: { enabled: true },
    });

    res.json({
      paymentIntentClientSecret: paymentIntent.client_secret,
      customer: customer.id,
      ephemeralKeySecret: ephemeralKey.secret,
    });
  } catch (err) {
    console.error('Error in /create-payment-intent:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// -----------------------------------------------------------------------------
// Users: create / update profile (mandatory password)
// -----------------------------------------------------------------------------
app.post("/users/profile", async (req, res) => {
  try {
    const {
      fullName,
      email,
      phone,
      password,
      balanceCents,
      // Objective fields
      objective_type,
      objective_count,
      objective_schedule,
      objective_deadline,
      // Payout fields
      missed_goal_payout,
      payout_destination,
      committedPayoutAmount,
      payoutCommitted,
      // Destination commit fields
      destinationCommitted,
      committedDestination,
      custom_recipient_id,
      committedRecipientId,
      committedCharity,
      createOnly  // If true, reject if email already exists
    } = req.body || {};
    console.log("DEBUG /users/profile:", { payout_destination, committedDestination, destinationCommitted, email, createOnly });

    if (!fullName || typeof fullName !== "string" || !fullName.trim()) {
      return res.status(400).json({ error: "Full name is required." });
    }
    if (!email || typeof email !== "string" || !email.trim()) {
      return res.status(400).json({ error: "Email is required." });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const normalizedName = fullName.trim();
    const activeBalanceCents = typeof balanceCents === "number" && balanceCents >= 0 ? Math.floor(balanceCents) : 0;

    // Check for existing user
    const { data: existingUser, error: fetchError } = await supabase
      .from("users")
      .select("*")
      .eq("email", normalizedEmail)
      .maybeSingle();

    if (fetchError) {
      console.error("Supabase fetch user error:", fetchError);
      return res.status(500).json({ error: "Failed to load user.", detail: String(fetchError.message ?? fetchError) });
    }
    
    // Block duplicate emails on account creation
    if (createOnly && existingUser) {
      return res.status(409).json({ error: "An account with this email already exists. Please sign in instead." });
    }

    let stripeCustomerId = existingUser?.stripe_customer_id ?? null;

    if (!stripeCustomerId) {
      const customer = await stripe.customers.create({
        email: normalizedEmail,
        name: normalizedName,
        phone: phone || undefined,
      });
      stripeCustomerId = customer.id;
    }
    // Validate recipient IDs before using them
    let validCustomRecipientId = null;
    let validCommittedRecipientId = null;
    if (custom_recipient_id) {
      const { data: recipientCheck } = await supabase.from("recipients").select("id").eq("id", custom_recipient_id).single();
      if (recipientCheck) validCustomRecipientId = custom_recipient_id;
      else console.log("Invalid custom_recipient_id - not found in recipients:", custom_recipient_id);
    }
    if (committedRecipientId) {
      const { data: recipientCheck2 } = await supabase.from("recipients").select("id").eq("id", committedRecipientId).single();
      if (recipientCheck2) validCommittedRecipientId = committedRecipientId;
      else console.log("Invalid committedRecipientId - not found in recipients:", committedRecipientId);
    }

    // Build update object with all fields
    const updateData = {
      full_name: normalizedName,
      phone: phone || null,
      stripe_customer_id: stripeCustomerId,
      // Only update balance if provided
      ...(typeof balanceCents === "number" && { balance_cents: activeBalanceCents }),
      // Objective fields
      ...(objective_type && { objective_type }),
      ...(typeof objective_count === "number" && { objective_count }),
      ...(objective_schedule && { objective_schedule }),
      ...(objective_deadline && { objective_deadline }),
      // Payout fields
      ...(typeof missed_goal_payout === "number" && { missed_goal_payout }),
      ...(payout_destination && { payout_destination }),
      ...(typeof payoutCommitted === "boolean" && { payout_committed: payoutCommitted }),
      // Destination commit fields
      ...(typeof destinationCommitted === "boolean" && { destination_committed: destinationCommitted }),
      ...(committedDestination && { committed_destination: committedDestination }),
      ...(committedCharity && { committed_charity: committedCharity }),
      ...(validCustomRecipientId && { custom_recipient_id: validCustomRecipientId }),
      ...(validCommittedRecipientId && { committed_recipient_id: validCommittedRecipientId }),
      
    };

    let userRow;

    if (!existingUser) {
      // Hash password for new user
      const passwordHash = password ? await bcrypt.hash(password, 10) : null;
      
      const { data, error: insertError } = await supabase
        .from("users")
        .insert({
          ...updateData,
          email: normalizedEmail,
          password_hash: passwordHash,
        })
        .select()
        .single();

      if (insertError) {
        console.error("Supabase insert user error:", insertError);
        return res.status(500).json({ error: "Failed to create user.", detail: String(insertError.message ?? insertError) });
      }
      userRow = data;
    } else {
      // Only update password if provided
      if (password && password.trim()) {
        updateData.password_hash = await bcrypt.hash(password, 10);
      }

      const { data, error: updateError } = await supabase
        .from("users")
        .update(updateData)
        .eq("id", existingUser.id)
        .select()
        .single();

      if (updateError) {
        console.error("Supabase update user error:", updateError);
        return res.status(500).json({ error: "Failed to update user.", detail: String(updateError.message ?? updateError) });
      }
      userRow = data;
    }

    // Store userId for reference
    return res.json({
      id: userRow.id,
      fullName: userRow.full_name,
      email: userRow.email,
      phone: userRow.phone,
      balanceCents: userRow.balance_cents,
      objective_type: userRow.objective_type,
      objective_count: userRow.objective_count,
      objective_schedule: userRow.objective_schedule,
      objective_deadline: userRow.objective_deadline,
      missed_goal_payout: userRow.missed_goal_payout,
      payout_destination: userRow.payout_destination,
      payout_committed: userRow.payout_committed,
      destination_committed: userRow.destination_committed,
      committed_destination: userRow.committed_destination,
      stripeCustomerId: userRow.stripe_customer_id,
    });
  } catch (err) {
    console.error("Profile endpoint error:", err);
    return res.status(500).json({ error: "Internal server error", detail: err.message });
  }
});

// -----------------------------------------------------------------------------
// Helper: send recipient invite SMS via Twilio
// -----------------------------------------------------------------------------
async function sendRecipientInviteSMS({ toPhone, payerName, inviteCode }) {
  if (!process.env.TWILIO_FROM_NUMBER) {
    throw new Error("TWILIO_FROM_NUMBER not configured");
  }

  const url = `https://app.live-eos.com/invite`;

  const body =
    `🎯 EOS Accountability Invite\n\n` +
    `${payerName} selected you to receive payouts when they miss their fitness goals.\n\n` +
    `Your code: ${inviteCode}\n\n` +
    `Setup payouts: ${url}\n\n` +
    `Reply STOP to opt out.`;

  await twilioClient.messages.create({
    to: toPhone,
    from: process.env.TWILIO_FROM_NUMBER,
    body,
  });
}

// -----------------------------------------------------------------------------
// Recipient invites (for custom recipients via SMS)
// -----------------------------------------------------------------------------
app.post('/recipient-invites', async (req, res) => {
  try {
    const { payerEmail, payerName, phone } = req.body || {};

    if (!payerEmail || !payerEmail.trim()) {
      return res.status(400).json({ error: 'payerEmail is required.' });
    }
    if (!payerName || !payerName.trim()) {
      return res.status(400).json({ error: 'payerName is required.' });
    }
    if (!phone || !phone.trim()) {
      return res.status(400).json({ error: 'Recipient phone is required.' });
    }

    const normalizedEmail = payerEmail.trim().toLowerCase();

    const { data: payerUser, error: userError } = await supabase
      .from('users')
      .select('id')
      .eq('email', normalizedEmail)
      .maybeSingle();

    if (userError) {
      console.error('Supabase fetch payer user error:', userError);
      return res.status(500).json({ error: 'Failed to load payer user.', detail: String(userError.message ?? userError) });
    }
    if (!payerUser) {
      return res.status(404).json({ error: 'Payer user not found.' });
    }

    const inviteCode = crypto.randomBytes(4).toString('hex').toUpperCase();

    const { data: invite, error: insertError } = await supabase
      .from('recipient_invites')
      .insert({
        payer_user_id: payerUser.id,
        phone,
        invite_code: inviteCode,
        status: 'pending',
      })
      .select()
      .single();

    if (insertError) {
      console.error('Supabase insert invite error:', insertError);
      return res.status(500).json({ error: 'Failed to create invite.', detail: String(insertError.message ?? insertError) });
    }

    await sendRecipientInviteSMS({
      toPhone: phone,
      payerName: payerName.trim(),
      inviteCode,
    });

    res.json({
      id: invite.id,
      inviteCode,
      status: invite.status,
    });
  } catch (err) {
    console.error('Error in /recipient-invites:', err);
    res.status(500).json({ error: 'Failed to send invite.', detail: String(err) });
  }
});
// -----------------------------------------------------------------------------
// Generate invite code only (no SMS) - for manual sharing
// -----------------------------------------------------------------------------
app.post('/recipient-invites/code-only', async (req, res) => {
  try {
    const { payerEmail, payerName } = req.body || {};

    if (!payerEmail || !payerEmail.trim()) {
      return res.status(400).json({ error: 'payerEmail is required.' });
    }

    const normalizedEmail = payerEmail.trim().toLowerCase();

    const { data: payerUser, error: userError } = await supabase
      .from('users')
      .select('id, full_name')
      .eq('email', normalizedEmail)
      .maybeSingle();

    if (userError) {
      console.error('Supabase fetch payer user error:', userError);
      return res.status(500).json({ error: 'Failed to load payer user.', detail: String(userError.message ?? userError) });
    }
    if (!payerUser) {
      return res.status(404).json({ detail: 'Payer user not found. Please save your profile first.' });
    }

    // Generate 8-char code without ambiguous chars
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let inviteCode = '';
    for (let i = 0; i < 8; i++) {
      inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const { data: invite, error: insertError } = await supabase
      .from('recipient_invites')
      .insert({
        payer_user_id: payerUser.id,
        phone: '',
        invite_code: inviteCode,
        status: 'pending',
      })
      .select()
      .single();

    if (insertError) {
      console.error('Supabase insert invite error:', insertError);
      return res.status(500).json({ error: 'Failed to create invite.', detail: String(insertError.message ?? insertError) });
    }

    res.json({
      inviteCode: inviteCode,
      message: 'Invite code generated successfully. Share it manually.'
    });
  } catch (err) {
    console.error('Error in /recipient-invites/code-only:', err);
    res.status(500).json({ error: 'Failed to generate invite code.', detail: String(err) });
  }
});

// -----------------------------------------------------------------------------
// Optional: Supabase debug endpoint
// -----------------------------------------------------------------------------
app.get('/debug/supabase', async (req, res) => {
  try {
    const { data, error } = await supabase.from('users').select('id').limit(1);
    if (error) throw error;
    res.json({ ok: true, sample: data });
  } catch (err) {
    console.error('Supabase debug error:', err);
    res.status(500).json({ error: 'Supabase error', detail: String(err) });
  }
});

// -----------------------------------------------------------------------------
// Start server
// -----------------------------------------------------------------------------
const port = process.env.PORT || 4242;

// ========== RECIPIENT & PAYOUT ENDPOINTS ==========

// Get user recipient status (for iOS app)
app.get("/users/:userId/recipient", async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("custom_recipient_id, payout_destination")
            .eq("id", userId)
            .single();
        
        if (userError || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        const recipientId = user.custom_recipient_id;
        
        if (!recipientId) {
            return res.json({
                hasRecipient: false,
                recipient: null,
                isCommitted: false,
                destination: user.payout_destination || "charity"
            });
        }
        
        const { data: recipient } = await supabase
            .from("recipients")
            .select("id, name, email, phone")
            .eq("id", recipientId)
            .single();
        
        res.json({
            hasRecipient: true,
            recipient: recipient || null,
            isCommitted: false,
            destination: user.payout_destination || "custom"
        });
        
    } catch (error) {
        console.error("Get recipient error:", error);
        res.status(500).json({ error: error.message });
    }
});

// Commit payout destination
app.post("/users/:userId/commit-destination", async (req, res) => {
    try {
        const { userId } = req.params;
        const { destination, recipientId } = req.body;
        
        if (!["charity", "custom"].includes(destination)) {
            return res.status(400).json({ error: "Invalid destination" });
        }
        
        const updateData = {
            destination_committed: true,
            committed_destination: destination,
            payout_destination: destination
        };
        
        if (destination === "custom" && recipientId) {
            updateData.committed_recipient_id = recipientId;
            updateData.custom_recipient_id = recipientId;
        }
        
        const { error } = await supabase
            .from("users")
            .update(updateData)
            .eq("id", userId);
        
        if (error) {
            return res.status(500).json({ error: "Failed to commit destination" });
        }
        
        res.json({ success: true, destination, committed: true });
        
    } catch (error) {
        console.error("Commit destination error:", error);
        res.status(500).json({ error: error.message });
    }
});

// Get user invites with recipient status
app.get("/users/:userId/invites", async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: invites, error } = await supabase
            .from("recipient_invites")
            .select("id, phone, invite_code, status, created_at, recipient_id")
            .eq("payer_user_id", userId)
            .order("created_at", { ascending: false });
        
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        
        // Enrich with recipient info
        const enriched = await Promise.all((invites || []).map(async (inv) => {
            if (inv.recipient_id) {
                const { data: r } = await supabase
                    .from("recipients")
                    .select("name, email")
                    .eq("id", inv.recipient_id)
                    .single();
                return { ...inv, recipient: r };
            }
            return inv;
        }));
        
        res.json({ invites: enriched });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET endpoint for verify-invite (for web page)
app.get("/verify-invite/:code", async (req, res) => {
    try {
        const inviteCode = req.params.code;
        
        const { data: invite, error } = await supabase
            .from("recipient_invites")
            .select("*, payer:users(full_name, email)")
            .eq("invite_code", inviteCode.toUpperCase())
            .single();
        
        if (error || !invite) {
            return res.status(404).json({ error: "Invalid invite code" });
        }
        
        if (invite.status !== "pending") {
            return res.status(400).json({ error: "Invite already used" });
        }
        
        res.json({ 
            inviteCode: invite.invite_code,
            payerName: invite.payer?.full_name || "Unknown",
            payerEmail: invite.payer?.email
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});


// ========== OBJECTIVE CHECK & PAYOUT ENDPOINTS ==========

// Check for missed objectives and trigger payouts
app.post("/objectives/check-missed", async (req, res) => {
    try {
        // Helper: Get current time in user's timezone
        function getCurrentTimeInTimezone(tz) {
            const options = { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: tz || "America/New_York" };
            return new Date().toLocaleTimeString("en-US", options).replace(/^24:/, "00:");
        }
        // Helper: Get today's date in user's timezone
        function getTodayInTimezone(tz) {
            return new Date().toLocaleDateString("en-CA", { timeZone: tz || "America/New_York" });
        }
        
        const now = new Date();
        
        // Find pending sessions where deadline has passed
        // Note: We check ALL pending sessions and filter by timezone per-user
        const { data: sessions, error: sessionsError } = await supabase
            .from("objective_sessions")
            .select("*, users!inner(id, email, balance_cents, missed_goal_payout, payout_destination, committed_destination, committed_recipient_id, custom_recipient_id, stripe_customer_id, timezone)")
            .in("status", ["pending", "missed"])
            .eq("payout_triggered", false);
        
        if (sessionsError) {
            return res.status(400).json({ error: sessionsError.message });
        }
        
        const results = [];
        
        for (const session of sessions || []) {
            const user = session.users;
            const userTimezone = user?.timezone || "America/New_York";
            const currentTime = getCurrentTimeInTimezone(userTimezone);
            const today = getTodayInTimezone(userTimezone);
            
            // Skip sessions older than 2 days (stale)
            const sessionDate = new Date(session.session_date + "T00:00:00");
            const now = new Date();
            const daysDiff = (now - sessionDate) / (1000 * 60 * 60 * 24);
            if (daysDiff > 2) continue;
            
            const deadline = (session.deadline || "09:00").slice(0, 5);
            if (currentTime < deadline) continue;
            
            // Check if completed
            if (session.completed_count >= session.target_count) {
                await supabase.from("objective_sessions").update({ status: "accepted" }).eq("id", session.id);
                continue;
            }
            
            const userBalance = user?.balance_cents || 0;
            if (userBalance <= 0 || session.payout_amount <= 0) continue;
            
            const payoutAmountCents = Math.round(session.payout_amount * 100);
            const destination = user.committed_destination || user.payout_destination || "charity";
            const recipientId = user.committed_recipient_id || user.custom_recipient_id;
            
            let stripeTransferId = null;
            
            // Handle charity payout (no Stripe transfer - stays in our account)
            if (destination === "charity") {
                const charityName = user.committed_charity || "General Charity Fund";
                
                // Record charity payout in database
                await supabase.from("charity_payouts").insert({
                    user_id: user.id,
                    charity_name: charityName,
                    amount_cents: payoutAmountCents,
                    session_id: session.id,
                    status: "pending"
                });
                
                console.log("Charity payout recorded:", charityName, payoutAmountCents, "cents");
            }
            
            // Transfer to recipient if custom
            if (destination === "custom" && recipientId) {
                const { data: recipient } = await supabase
                    .from("recipients")
                    .select("stripe_connect_account_id")
                    .eq("id", recipientId)
                    .single();
                
                if (recipient?.stripe_connect_account_id) {
                    try {
                        const transfer = await stripe.transfers.create({
                            amount: payoutAmountCents,
                            currency: "usd",
                            destination: recipient.stripe_connect_account_id,
                            description: `EOS auto-payout - missed objective`,
                            metadata: { user_id: user.id, session_id: session.id }
                        });
                        stripeTransferId = transfer.id;
                        console.log("Transfer success:", transfer.id, "to", recipient.stripe_connect_account_id);
                        
                        // Trigger instant payout to recipients card
                        try {
                            const recipientBalance = await stripe.balance.retrieve({ stripeAccount: recipient.stripe_connect_account_id });
                            const availableAmount = recipientBalance.available[0]?.amount || 0;
                            if (availableAmount > 0) {
                                const payout = await stripe.payouts.create({
                                    amount: availableAmount,
                                    currency: "usd",
                                    method: "instant"
                                }, { stripeAccount: recipient.stripe_connect_account_id });
                                console.log("Instant payout triggered:", payout.id, "Amount:", availableAmount);
                            }
                        } catch (payoutErr) {
                            console.error("Instant payout failed (will use daily):", payoutErr.message);
                        }
                    } catch (err) {
                        console.error("Stripe transfer failed:", err.message);
                    }
                }
            }
            
            // Create transaction
            const { data: tx } = await supabase
                .from("transactions")
                .insert({
                    user_id: session.user_id,
                    type: "payout",
                    amount_cents: payoutAmountCents,
                    status: "accepted",
                    description: "Missed objective payout (auto)",
                    stripe_payment_id: stripeTransferId
                })
                .select()
                .single();
            
            // Deduct balance and mark session
            const newBalance = Math.max(0, userBalance - payoutAmountCents);
            await supabase.from("users").update({ balance_cents: newBalance }).eq("id", session.user_id);
            await supabase.from("objective_sessions").update({ 
                status: "missed", 
                payout_triggered: true,
                payout_transaction_id: tx?.id 
            }).eq("id", session.id);
            
            results.push({
                userId: session.user_id,
                sessionId: session.id,
                amount: session.payout_amount,
                destination: destination,
                stripeTransferId: stripeTransferId,
                newBalanceCents: newBalance
            });
        }
        
        res.json({ checked: true, serverTime: new Date().toISOString(), payoutsProcessed: results.length, results });
    } catch (error) {
        console.error("Check missed error:", error);
        res.status(500).json({ error: error.message });
    }
});


app.post("/users/:userId/deduct-balance", async (req, res) => {
    try {
        const { userId } = req.params;
        const { amount, reason } = req.body;
        
        if (!amount || amount <= 0) {
            return res.status(400).json({ error: "Valid amount required" });
        }
        
        const amountCents = Math.round(amount * 100);
        
        // Create transaction
        const { data: tx, error: txError } = await supabase
            .from("transactions")
            .insert({
                user_id: userId,
                type: "payout",
                amount_cents: amountCents,
                status: "accepted",
                description: reason || "Manual payout deduction"
            })
            .select()
            .single();
        
        if (txError) {
            return res.status(500).json({ error: txError.message });
        }
        
        // Deduct balance
        const { data: user, error: updateError } = await supabase
            .from("users")
            .update({ 
                balance_cents: supabase.raw("balance_cents - " + amountCents)
            })
            .eq("id", userId)
            .select("balance_cents")
            .single();
        
        // Alternative: direct SQL update
        const { error: deductError } = await supabase.rpc("deduct_user_balance", {
            p_user_id: userId,
            p_amount_cents: amountCents
        });
        
        res.json({
            success: true,
            transactionId: tx.id,
            amountDeducted: amount
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get user balance
app.get("/users/:userId/balance", async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: user, error } = await supabase
            .from("users")
            .select("balance_cents")
            .eq("id", userId)
            .single();
        
        if (error || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        res.json({
            balanceCents: user.balance_cents || 0,
            balanceDollars: (user.balance_cents || 0) / 100
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(port, () => console.log(`Stripe backend listening on port ${port}`));


// -----------------------------------------------------------------------------
// Verify invite code
// -----------------------------------------------------------------------------
app.get('/verify-invite/:code', async (req, res) => {
  try {
    const { code } = req.params;
    
    const { data: invite, error } = await supabase
      .from('recipient_invites')
      .select(`
        *,
        payer:users!payer_user_id (
          full_name,
          email
        )
      `)
      .eq('invite_code', code.toUpperCase())
      .eq('status', 'pending')
      .single();
    
    if (error || !invite) {
      return res.status(404).json({ error: 'Invalid or expired invite code' });
    }
    
    res.json({
      code: invite.invite_code,
      payerName: invite.payer?.full_name || 'EOS User',
      payerEmail: invite.payer?.email,
      payoutAmount: 5, // TODO: Make this dynamic from payer settings
      phone: invite.phone
    });
  } catch (err) {
    console.error('Error verifying invite:', err);
    res.status(500).json({ error: 'Failed to verify invite' });
  }
});

// -----------------------------------------------------------------------------
// Recipient onboarding with Stripe Connect
// -----------------------------------------------------------------------------
app.post('/recipient-onboarding', async (req, res) => {
  try {
    const { inviteCode, name, email } = req.body;
    
    // Verify invite code again
    const { data: invite, error: inviteError } = await supabase
      .from('recipient_invites')
      .select('*, payer:users!payer_user_id (*)')
      .eq('invite_code', inviteCode.toUpperCase())
      .eq('status', 'pending')
      .single();
    
    if (inviteError || !invite) {
      return res.status(404).json({ error: 'Invalid invite code' });
    }
    
    // Check if recipient already exists
    let recipient;
    const { data: existingRecipient } = await supabase
      .from('recipients')
      .select('*')
      .eq('phone', invite.phone)
      .single();
    
    if (existingRecipient) {
      recipient = existingRecipient;
    } else {
      // Create Stripe Connect account
      const account = await stripe.accounts.create({
        type: "express",
        business_profile: { url: "https://live-eos.com" },
        country: 'US',
        email: email,
        capabilities: {
          transfers: { requested: true },
        },
        business_type: 'individual',
        individual: {
          email: email,
          first_name: name.split(' ')[0],
          last_name: name.split(' ').slice(1).join(' ') || name.split(' ')[0],
        },
      });
      
      // Save recipient to database
      const { data: newRecipient, error: recipientError } = await supabase
        .from('recipients')
        .insert({
          type: 'individual',
          name: name,
          phone: invite.phone,
          email: email,
          stripe_connect_account_id: account.id
        })
        .select()
        .single();
      
      if (recipientError) {
        throw new Error('Failed to save recipient');
      }
      
      recipient = newRecipient;
    }
    
    // Update invite status
    await supabase
      .from('recipient_invites')
      .update({
        status: 'accepted',
        recipient_id: recipient.id
      })
      .eq('id', invite.id);
    
    // Create payout rule
    await supabase
      .from('payout_rules')
      .insert({
        payer_user_id: invite.payer_user_id,
        recipient_id: recipient.id,
        fixed_amount_cents: 500, //  default - TODO: Make dynamic
        active: true
      });
    
    // Create Stripe Connect onboarding link
    if (!existingRecipient || !existingRecipient.stripe_connect_account_id) {
      const accountLink = await stripe.accountLinks.create({
        account: recipient.stripe_connect_account_id,
        refresh_url: `https://app.live-eos.com/invite?code=${inviteCode}`,
        return_url: `https://app.live-eos.com/invite?setup_complete=true`,
        type: 'account_onboarding',
      });
      
      res.json({ onboardingUrl: accountLink.url });
    } else {
      res.json({ success: true, message: 'Recipient already set up' });
    }
  } catch (err) {
    console.error('Error in recipient onboarding:', err);
    res.status(500).json({ error: 'Failed to complete onboarding', detail: String(err.message) });
  }
});

// -----------------------------------------------------------------------------
// Process missed goal payout (with INSTANT PAYOUTS)
// -----------------------------------------------------------------------------
app.post('/process-payout', async (req, res) => {
  try {
    const { payerUserId, goalDate } = req.body;
    
    // Get active payout rules for this payer
    const { data: rules, error: rulesError } = await supabase
      .from('payout_rules')
      .select(`
        *,
        recipient:recipients(*),
        payer:users!payer_user_id(*)
      `)
      .eq('payer_user_id', payerUserId)
      .eq('active', true);
    
    if (rulesError || !rules || rules.length === 0) {
      return res.json({ message: 'No active payout rules' });
    }
    
    const payouts = [];
    
    for (const rule of rules) {
      // Check if payer has sufficient balance
      if (rule.payer.active_balance_cents < rule.fixed_amount_cents) {
        console.log('Insufficient balance for payout');
        continue;
      }
      
      // Create payout event record
      const { data: payoutEvent, error: eventError } = await supabase
        .from('payout_events')
        .insert({
          payer_user_id: payerUserId,
          recipient_id: rule.recipient_id,
          amount_cents: rule.fixed_amount_cents,
          goal_date: goalDate,
          status: 'processing'
        })
        .select()
        .single();
      
      if (eventError) {
        console.error('Failed to create payout event:', eventError);
        continue;
      }
      
      try {
        // Step 1: Transfer from EOS platform to connected account
        const transfer = await stripe.transfers.create({
          amount: rule.fixed_amount_cents,
          currency: 'usd',
          destination: rule.recipient.stripe_connect_account_id,
          description: `EOS missed goal payout from ${rule.payer.name}`,
          metadata: {
            payout_event_id: payoutEvent.id,
            payer_user_id: payerUserId,
            recipient_id: rule.recipient_id
          }
        });
        
        // Step 2: Trigger INSTANT payout from connected account to their debit card
        let payoutResult = { method: 'standard' };
        let payoutId = null;
        
        try {
          // Try instant payout first (arrives in ~30 minutes)
          const instantPayout = await stripe.payouts.create({
            amount: rule.fixed_amount_cents,
            currency: 'usd',
            method: 'instant',
            description: 'EOS instant payout'
          }, {
            stripeAccount: rule.recipient.stripe_connect_account_id
          });
          
          payoutResult = { method: 'instant', id: instantPayout.id };
          payoutId = instantPayout.id;
          console.log('Instant payout successful:', instantPayout.id);
          
        } catch (instantError) {
          // If instant fails (card doesn't support it), fall back to standard
          console.log('Instant payout not available, using standard:', instantError.message);
          
          try {
            const standardPayout = await stripe.payouts.create({
              amount: rule.fixed_amount_cents,
              currency: 'usd',
              method: 'standard',
              description: 'EOS standard payout'
            }, {
              stripeAccount: rule.recipient.stripe_connect_account_id
            });
            payoutResult = { method: 'standard', id: standardPayout.id };
            payoutId = standardPayout.id;
          } catch (stdError) {
            console.log('Payout will process on Stripe schedule:', stdError.message);
            payoutResult = { method: 'scheduled' };
          }
        }
        
        // Update payout event with transfer ID and payout info
        await supabase
          .from('payout_events')
          .update({
            status: 'paid',
            stripe_transfer_id: transfer.id,
            stripe_payout_id: payoutId,
            payout_method: payoutResult.method
          })
          .eq('id', payoutEvent.id);
        
        // Deduct from payer balance
        await supabase
          .from('users')
          .update({
            active_balance_cents: rule.payer.active_balance_cents - rule.fixed_amount_cents
          })
          .eq('id', payerUserId);
        
        // Send SMS notification to recipient
        if (rule.recipient.phone && process.env.TWILIO_FROM_NUMBER) {
          const amountFormatted = (rule.fixed_amount_cents / 100).toFixed(2);
          const timeMessage = payoutResult.method === 'instant' 
            ? 'Funds will arrive within minutes!' 
            : 'Funds will arrive in 1-2 business days.';
          
          await twilioClient.messages.create({
            to: rule.recipient.phone,
            from: process.env.TWILIO_FROM_NUMBER,
            body: `💰 You received $${amountFormatted} from ${rule.payer.name} for missing their EOS fitness goal. ${timeMessage}`
          });
        }
        
        payouts.push({
          recipient: rule.recipient.name,
          amount: rule.fixed_amount_cents,
          status: 'paid',
          method: payoutResult.method
        });
        
      } catch (transferError) {
        console.error('Transfer failed:', transferError);
        
        await supabase
          .from('payout_events')
          .update({
            status: 'failed',
            error_message: transferError.message
          })
          .eq('id', payoutEvent.id);
      }
    }
    
    res.json({ payouts });
  } catch (err) {
    console.error('Error processing payouts:', err);
    res.status(500).json({ error: 'Failed to process payouts' });
  }
});


// -----------------------------------------------------------------------------
// Start server
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Hybrid recipient onboarding (no redirect needed)
// -----------------------------------------------------------------------------
app.post("/recipient-hybrid-onboarding", async (req, res) => {
  try {
    const {
      inviteCode,
      name,
      email,
      dob,
      address,
      ssnLast4,
      payoutMethod,
      paymentToken
    } = req.body;
    
    // Validate required fields
    if (!inviteCode || !name || !email) {
      return res.status(400).json({ error: "Invite code, name, and email are required" });
    }
    if (!dob || !dob.month || !dob.day || !dob.year) {
      return res.status(400).json({ error: "Date of birth is required" });
    }
    if (!address || !address.line1 || !address.city || !address.state || !address.postal_code) {
      return res.status(400).json({ error: "Full address is required" });
    }
    if (!ssnLast4 || ssnLast4.length !== 4) {
      return res.status(400).json({ error: "Last 4 digits of SSN are required" });
    }
    if (!paymentToken) {
      return res.status(400).json({ error: "Payment method (bank or card) is required" });
    }
    
    // Verify invite code
    const { data: invite, error: inviteError } = await supabase
      .from("recipient_invites")
      .select("*")
      .eq("invite_code", inviteCode.toUpperCase())
      .in("status", ["pending", "missed"])
      .single();
    
    if (inviteError || !invite) {
      return res.status(404).json({ error: "Invalid or expired invite code" });
    }
    
    // Check if recipient already exists
    const { data: existingRecipient } = await supabase
      .from("recipients")
      .select("*")
      .eq("phone", invite.phone)
      .single();
    
    if (existingRecipient) {
      return res.status(400).json({ error: "Recipient already registered with this phone number" });
    }
    
    // Parse name
    const nameParts = name.trim().split(" ");
    const firstName = nameParts[0];
    const lastName = nameParts.slice(1).join(" ") || firstName;
    
    // Get client IP for TOS acceptance
    const clientIP = req.headers["x-forwarded-for"]?.split(",")[0] || req.ip || "127.0.0.1";
    
    // Create Stripe CUSTOM account (not Express!)
    const account = await stripe.accounts.create({
      type: "custom",
      business_profile: { url: "https://live-eos.com" },
      country: "US",
      email: email,
      capabilities: {
        transfers: { requested: true }
      },
      business_type: "individual",
      individual: {
        first_name: firstName,
        last_name: lastName,
        email: email,
        phone: invite.phone,
        dob: {
          day: parseInt(dob.day),
          month: parseInt(dob.month),
          year: parseInt(dob.year)
        },
        address: {
          line1: address.line1,
          city: address.city,
          state: address.state,
          postal_code: address.postal_code,
          country: "US"
        },
        ssn_last_4: ssnLast4
      },
      external_account: paymentToken,
      tos_acceptance: {
        date: Math.floor(Date.now() / 1000),
        ip: clientIP
      },
      settings: {
        payouts: {
          schedule: { interval: "manual" }
        }
      }
    });
    
    console.log("Created Custom account:", account.id, "transfers:", account.capabilities?.transfers);
    
    // Save recipient to database
    const { data: recipient, error: recipientError } = await supabase
      .from("recipients")
      .insert({
        type: "individual",
        name: name,
        phone: invite.phone,
        email: email,
        stripe_connect_account_id: account.id
      })
      .select()
      .single();
    
    if (recipientError) {
      console.error("Failed to save recipient:", recipientError);
      try { await stripe.accounts.del(account.id); } catch(e) {}
      return res.status(500).json({ error: "Failed to save recipient: " + recipientError.message });
    }
    
    // Update invite status
    await supabase.from("recipient_invites")
      .update({ status: "accepted", recipient_id: recipient.id })
      .eq("id", invite.id);
    
    // Link recipient to payer
    await supabase.from("users")
      .update({ custom_recipient_id: recipient.id, payout_destination: "custom" })
      .eq("id", invite.payer_user_id);
    
    // Get payer info for payout rule
    const { data: payer } = await supabase
      .from("users")
      .select("full_name, missed_goal_payout")
      .eq("id", invite.payer_user_id)
      .single();
    
    // Create payout rule
    const payoutAmount = Math.round((payer?.missed_goal_payout || 5) * 100);
    await supabase.from("payout_rules").insert({
      payer_user_id: invite.payer_user_id,
      recipient_id: recipient.id,
      fixed_amount_cents: payoutAmount,
      active: true
    });
    
    // Send confirmation SMS
    if (process.env.TWILIO_PHONE_NUMBER) {
      try {
        const payoutMethodName = paymentToken.startsWith("btok_") ? "bank account" : "debit card";
        const amountFormatted = (payoutAmount / 100).toFixed(2);
        
        await twilioClient.messages.create({
          to: invite.phone,
          from: process.env.TWILIO_PHONE_NUMBER,
          body: `✅ EOS setup complete! You will receive $${amountFormatted} to your ${payoutMethodName} each time ${payer?.full_name || "your partner"} misses their fitness goal.`
        });
      } catch (smsError) {
        console.error("SMS send error:", smsError);
      }
    }
    
    // Check account status
    const accountStatus = await stripe.accounts.retrieve(account.id);
    
    res.json({ 
      success: true, 
      message: "Setup complete! You will receive payouts when goals are missed.",
      recipientId: recipient.id,
      stripeAccountId: account.id,
      transfersEnabled: accountStatus.capabilities?.transfers === "active",
      payoutsEnabled: accountStatus.payouts_enabled
    });
    
  } catch (err) {
    console.error("Hybrid onboarding error:", err);
    res.status(500).json({ 
      error: "Failed to complete setup", 
      detail: err.message 
    });
  }
});
app.get('/debug/database', async (req, res) => {
    try {
        const results = {};
        
        // Check if Supabase client is initialized
        results.supabaseConnected = !!supabase;
        
        // Test users table
        const { data: usersData, error: usersError } = await supabase
            .from('users')
            .select('count');
        results.usersTable = usersError ? { error: usersError.message } : { count: usersData?.length || 0 };
        
        // Test recipients table
        const { data: recipientsData, error: recipientsError } = await supabase
            .from('recipients')
            .select('count');
        results.recipientsTable = recipientsError ? { error: recipientsError.message } : { count: recipientsData?.length || 0 };
        
        // Test recipient_invites table
        const { data: invitesData, error: invitesError } = await supabase
            .from('recipient_invites')
            .select('count');
        results.invitesTable = invitesError ? { error: invitesError.message } : { count: invitesData?.length || 0 };
        
        res.json({
            status: 'Database connectivity check',
            timestamp: new Date().toISOString(),
            results: results
        });
    } catch (error) {
        res.status(500).json({ 
            error: error.message,
            stack: error.stack 
        });
    }
});


// Manual trigger payout (for when objective is missed)
app.post("/users/:userId/trigger-payout", async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Get user info with recipient details
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("id, email, balance_cents, missed_goal_payout, payout_destination, payout_committed, committed_destination, committed_recipient_id, custom_recipient_id, stripe_customer_id")
            .eq("id", userId)
            .single();
        
        if (userError || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        if (!user.payout_committed || user.missed_goal_payout <= 0) {
            return res.status(400).json({ error: "No payout committed" });
        }
        
        if ((user.balance_cents || 0) <= 0) {
            return res.status(400).json({ error: "Insufficient balance" });
        }
        
        const payoutAmountCents = Math.round(user.missed_goal_payout * 100);
        const destination = user.committed_destination || user.payout_destination || "charity";
        const recipientId = user.committed_recipient_id || user.custom_recipient_id;
        
        let stripeTransferId = null;
        let recipientStripeAccount = null;
        
        // If custom destination, get recipient and transfer via Stripe
        if (destination === "custom" && recipientId) {
            const { data: recipient } = await supabase
                .from("recipients")
                .select("id, name, email, stripe_connect_account_id")
                .eq("id", recipientId)
                .single();
            
            if (recipient && recipient.stripe_connect_account_id) {
                recipientStripeAccount = recipient.stripe_connect_account_id;
                
                try {
                    // Create Stripe Transfer to recipient
                    const transfer = await stripe.transfers.create({
                        amount: payoutAmountCents,
                        currency: "usd",
                        destination: recipient.stripe_connect_account_id,
                        description: `EOS payout from ${user.email} - missed objective`,
                        metadata: {
                            user_id: userId,
                            recipient_id: recipientId,
                            type: "missed_objective_payout"
                        }
                    });
                    stripeTransferId = transfer.id;
                    console.log("Stripe transfer created:", transfer.id);
                    
                    // Trigger instant payout to recipients card
                    try {
                        const recipientBalance = await stripe.balance.retrieve({ stripeAccount: recipient.stripe_connect_account_id });
                        const availableAmount = recipientBalance.available[0]?.amount || 0;
                        if (availableAmount > 0) {
                            const payout = await stripe.payouts.create({
                                amount: availableAmount,
                                currency: "usd",
                                method: "instant"
                            }, { stripeAccount: recipient.stripe_connect_account_id });
                            console.log("Instant payout triggered:", payout.id, "Amount:", availableAmount);
                        }
                    } catch (payoutErr) {
                        console.error("Instant payout failed (will use daily):", payoutErr.message);
                    }
                } catch (stripeErr) {
                    console.error("Stripe transfer failed:", stripeErr.message);
                    // Continue with balance deduction even if transfer fails
                    // Transaction will be marked with error
                }
            }
        }
        
        // Create transaction record
        const { data: tx, error: txError } = await supabase
            .from("transactions")
            .insert({
                user_id: userId,
                type: "payout",
                amount_cents: payoutAmountCents,
                status: stripeTransferId ? "completed" : (destination === "charity" ? "completed" : "pending_transfer"),
                description: destination === "charity" ? "Missed objective - charity donation" : "Missed objective payout to recipient",
                stripe_payment_id: stripeTransferId,
                metadata: {
                    destination: destination,
                    recipient_id: recipientId,
                    recipient_stripe_account: recipientStripeAccount
                }
            })
            .select()
            .single();
        
        if (txError) {
            return res.status(500).json({ error: "Failed to create transaction: " + txError.message });
        }
        
        // Deduct from balance
        const newBalance = Math.max(0, (user.balance_cents || 0) - payoutAmountCents);
        await supabase
            .from("users")
            .update({ balance_cents: newBalance })
            .eq("id", userId);
        
        res.json({
            success: true,
            payoutAmount: user.missed_goal_payout,
            destination: destination,
            previousBalanceCents: user.balance_cents,
            newBalanceCents: newBalance,
            transactionId: tx.id,
            stripeTransferId: stripeTransferId,
            transferredToRecipient: !!stripeTransferId
        });
        
    } catch (error) {
        console.error("Trigger payout error:", error);
        res.status(500).json({ error: error.message });
    }
});


// ========== DAILY OBJECTIVE RESET SYSTEM ==========

// Create daily sessions for all committed users (called at midnight)
app.post("/objectives/create-daily-sessions", async (req, res) => {
    try {
        const today = new Date().toISOString().slice(0, 10);
        
        // Get all users with committed payouts
        const { data: users, error: usersError } = await supabase
            .from("users")
            .select("id, objective_type, objective_count, objective_deadline, missed_goal_payout")
            .eq("payout_committed", true);
        
        if (usersError) {
            return res.status(400).json({ error: usersError.message });
        }
        
        const results = [];
        
        for (const user of users || []) {
            // Check if session already exists for today
            const { data: existing } = await supabase
                .from("objective_sessions")
                .select("id")
                .eq("user_id", user.id)
                .eq("session_date", today)
                .limit(1);
            
            if (existing && existing.length > 0) {
                continue; // Already has today session
            }
            
            // Create new session
            const { data: session, error: sessionError } = await supabase
                .from("objective_sessions")
                .insert({
                    user_id: user.id,
                    session_date: today,
                    objective_type: user.objective_type || "pushups",
                    target_count: user.objective_count || 50,
                    completed_count: 0,
                    deadline: user.objective_deadline || "09:00",
                    status: "pending",
                    payout_amount: user.missed_goal_payout || 0
                })
                .select()
                .single();
            
            if (!sessionError) {
                results.push({ userId: user.id, sessionId: session.id });
            }
        }
        
        res.json({ 
            created: results.length, 
            date: today,
            sessions: results 
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get today session for a user
app.get("/objectives/today/:userId", async (req, res) => {
    try {
        const { userId } = req.params;
        const today = new Date().toISOString().slice(0, 10);
        
        const { data: session, error } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today)
            .single();
        
        if (error && error.code !== "PGRST116") {
            return res.status(400).json({ error: error.message });
        }
        
        res.json({ session: session || null, date: today });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Mark objective as completed
app.post("/objectives/complete/:userId", async (req, res) => {
    try {
        const { userId } = req.params;
        const { completedCount } = req.body;
        const today = new Date().toISOString().slice(0, 10);
        
        // Get today session
        const { data: session, error: getError } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today)
            .single();
        
        if (getError && getError.code === "PGRST116") {
            return res.status(404).json({ error: "No session found for today" });
        }
        
        // Check if already completed
        if (session.status === "completed") {
            return res.json({ message: "Already completed", session });
        }
        
        // Update session
        const newCount = completedCount || session.target_count;
        const isComplete = newCount >= session.target_count;
        
        const { data: updated, error: updateError } = await supabase
            .from("objective_sessions")
            .update({
                completed_count: newCount,
                status: isComplete ? "completed" : "pending",
                
            })
            .eq("id", session.id)
            .select()
            .single();
        
        if (updateError) {
            return res.status(400).json({ error: updateError.message });
        }
        
        res.json({ 
            success: true, 
            completed: isComplete,
            session: updated 
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Reset all sessions at midnight (mark missed ones, create new ones)
app.post("/objectives/midnight-reset", async (req, res) => {
    try {
        const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
        const today = new Date().toISOString().slice(0, 10);
        
        // 1. Mark any pending sessions from yesterday as missed
        const { data: missedSessions } = await supabase
            .from("objective_sessions")
            .update({ status: "missed" })
            .eq("session_date", yesterday)
            .in("status", ["pending", "missed"])
            .select();
        
        // 2. Create new sessions for today
        const { data: users } = await supabase
            .from("users")
            .select("id, objective_type, objective_count, objective_deadline, missed_goal_payout")
            .eq("payout_committed", true);
        
        const newSessions = [];
        for (const user of users || []) {
            const { data: existing } = await supabase
                .from("objective_sessions")
                .select("id")
                .eq("user_id", user.id)
                .eq("session_date", today)
                .limit(1);
            
            if (!existing || existing.length === 0) {
                const { data: newSession } = await supabase
                    .from("objective_sessions")
                    .insert({
                        user_id: user.id,
                        session_date: today,
                        objective_type: user.objective_type || "pushups",
                        target_count: user.objective_count || 50,
                        completed_count: 0,
                        deadline: user.objective_deadline || "09:00",
                        status: "pending",
                        payout_amount: user.missed_goal_payout || 0
                    })
                    .select()
                    .single();
                
                if (newSession) newSessions.push(newSession.id);
            }
        }
        
        res.json({
            missedYesterday: missedSessions?.length || 0,
            newSessionsCreated: newSessions.length,
            date: today
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== SIGN IN ENDPOINT ==========
app.post("/signin", async (req, res) => {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ error: "Email and password are required." });
        }

        const normalizedEmail = email.trim().toLowerCase();

        // Find user by email
        const { data: user, error } = await supabase
            .from("users")
            .select("*")
            .eq("email", normalizedEmail)
            .single();

        if (error && error.code === "PGRST116") {
            return res.status(401).json({ error: "Invalid email or password." });
        }
        if (error) {
            console.error("Sign-in error:", error);
            return res.status(500).json({ error: "An error occurred during sign-in." });
        }

        // Verify password
        const passwordValid = await bcrypt.compare(password, user.password_hash || "");
        if (!passwordValid) {
            return res.status(401).json({ error: "Invalid email or password." });
        }

        // Return full user data
        res.json({
            message: "Sign-in successful",
            user: {
                id: user.id,
                full_name: user.full_name,
                email: user.email,
                phone: user.phone,
                balance_cents: user.balance_cents,
                objective_type: user.objective_type,
                objective_count: user.objective_count,
                objective_schedule: user.objective_schedule,
                objective_deadline: user.objective_deadline,
                missed_goal_payout: user.missed_goal_payout,
                payout_destination: user.payout_destination,
                payout_committed: user.payout_committed,
                destination_committed: user.destination_committed,
                committed_destination: user.committed_destination,
                custom_recipient_id: user.custom_recipient_id,
                stripe_customer_id: user.stripe_customer_id
            }
        });

    } catch (error) {
        console.error("Sign-in endpoint exception:", error);
        res.status(500).json({ error: "Internal server error." });
    }
});

// === STRIPE CONNECT ONBOARDING ===

// Generate onboarding link for recipient to complete Stripe setup
app.post("/recipients/:recipientId/onboarding-link", async (req, res) => {
    try {
        const { recipientId } = req.params;
        const { returnUrl, refreshUrl } = req.body || {};
        
        const { data: recipient, error } = await supabase
            .from("recipients")
            .select("stripe_connect_account_id")
            .eq("id", recipientId)
            .single();
        
        if (error || !recipient?.stripe_connect_account_id) {
            return res.status(404).json({ error: "Recipient or Stripe account not found" });
        }
        
        const accountLink = await stripe.accountLinks.create({
            account: recipient.stripe_connect_account_id,
            refresh_url: refreshUrl || "https://app.live-eos.com/invite?refresh=true",
            return_url: returnUrl || "https://app.live-eos.com/invite?success=true",
            type: "account_onboarding",
        });
        
        res.json({ url: accountLink.url });
    } catch (error) {
        console.error("Onboarding link error:", error);
        res.status(500).json({ error: error.message });
    }
});

// Check if recipient can receive payouts
app.get("/recipients/:recipientId/status", async (req, res) => {
    try {
        const { recipientId } = req.params;
        
        const { data: recipient, error } = await supabase
            .from("recipients")
            .select("id, name, email, stripe_connect_account_id")
            .eq("id", recipientId)
            .single();
        
        if (error || !recipient) {
            return res.status(404).json({ error: "Recipient not found" });
        }
        
        if (!recipient.stripe_connect_account_id) {
            return res.json({ 
                recipientId,
                canReceivePayouts: false,
                reason: "No Stripe account"
            });
        }
        
        const account = await stripe.accounts.retrieve(recipient.stripe_connect_account_id);
        
        res.json({
            recipientId,
            name: recipient.name,
            canReceivePayouts: account.capabilities?.transfers === "active",
            payoutsEnabled: account.payouts_enabled,
            chargesEnabled: account.charges_enabled,
            requirementsDue: account.requirements?.currently_due?.length || 0,
            requirements: account.requirements?.currently_due
        });
    } catch (error) {
        console.error("Recipient status error:", error);
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Objective Settings - Update user objective configuration
// -----------------------------------------------------------------------------
app.post("/objectives/settings/:userId", async (req, res) => {
    try {
        const { userId } = req.params;
        const { objective_type, objective_count, objective_schedule, objective_deadline, missed_goal_payout, timezone } = req.body;
        
        const updateData = {};
        if (objective_type) updateData.objective_type = objective_type;
        if (objective_count) updateData.objective_count = objective_count;
        if (objective_schedule) updateData.objective_schedule = objective_schedule;
        if (objective_deadline) updateData.objective_deadline = objective_deadline;
        if (typeof missed_goal_payout === "number") { 
            updateData.missed_goal_payout = missed_goal_payout; 
            if (missed_goal_payout > 0) updateData.payout_committed = true; 
        }
        if (timezone) updateData.timezone = timezone;
        
        // 1. Update user settings
        const { data: userData, error: userError } = await supabase
            .from("users")
            .update(updateData)
            .eq("id", userId)
            .select()
            .single();
        
        if (userError) {
            console.error("User update error:", userError);
            return res.status(400).json({ error: userError.message });
        }
        
        // 2. Also upsert todays session with new values
        const today = new Date().toISOString().slice(0, 10);
        const newTargetCount = objective_count || userData.objective_count || 50;
        const newDeadline = objective_deadline || userData.objective_deadline || "09:00:00";
        const newPayoutAmount = (typeof missed_goal_payout === "number") ? missed_goal_payout : (userData.missed_goal_payout || 0);
        
        // Check if session exists for today
        const { data: existingSession } = await supabase
            .from("objective_sessions")
            .select("id, completed_count, status")
            .eq("user_id", userId)
            .eq("session_date", today)
            .single();
        
        let sessionResult = null;
        if (existingSession) {
            // Update existing session (preserve completed_count, dont reset if already completed)
            // Always reset session when settings change (fresh start)
            if (true) {
                const { data: updatedSession } = await supabase
                    .from("objective_sessions")
                    .update({
                        target_count: newTargetCount,
                        status: "pending",
                        payout_triggered: false,
                        deadline: newDeadline,
                        payout_amount: newPayoutAmount
                    })
                    .eq("id", existingSession.id)
                    .select()
                    .single();
                sessionResult = updatedSession;
            } else {
                sessionResult = existingSession;
            }
        } else {
            // Create new session
            const { data: newSession } = await supabase
                .from("objective_sessions")
                .insert({
                    user_id: userId,
                    session_date: today,
                    target_count: newTargetCount,
                        status: "pending",
                        payout_triggered: false,
                    deadline: newDeadline,
                    payout_amount: newPayoutAmount,
                    completed_count: 0,
                    status: "pending",
                    payout_triggered: false
                })
                .select()
                .single();
            sessionResult = newSession;
        }
        
        console.log("Settings saved for user", userId, "- session:", sessionResult?.id);
        res.json({ success: true, user: userData, session: sessionResult });
        
    } catch (error) {
        console.error("Error in /objectives/settings:", error);
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Ensure Today Session - Create session for user if it does not exist
// -----------------------------------------------------------------------------
app.post("/objectives/ensure-session/:userId", async (req, res) => {
    try {
        const { userId } = req.params;
        const today = new Date().toISOString().slice(0, 10);
        
        // Check if session exists
        const { data: existing } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today)
            .limit(1);
        
        if (existing && existing.length > 0) {
            return res.json({ session: existing[0], created: false });
        }
        
        // Get user settings
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("objective_type, objective_count, objective_deadline, missed_goal_payout, payout_committed")
            .eq("id", userId)
            .single();
        
        if (userError || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        // Create new session
        const { data: session, error: sessionError } = await supabase
            .from("objective_sessions")
            .insert({
                user_id: userId,
                session_date: today,
                objective_type: user.objective_type || "pushups",
                target_count: user.objective_count || 50,
                completed_count: 0,
                deadline: user.objective_deadline || "09:00",
                status: "pending",
                payout_amount: user.missed_goal_payout || 0
            })
            .select()
            .single();
        
        if (sessionError) {
            return res.status(400).json({ error: sessionError.message });
        }
        
        res.json({ session, created: true });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Admin endpoint: Get charity payout totals
app.get("/admin/charity-totals", async (req, res) => {
    try {
        const { data, error } = await supabase
            .from("charity_payouts")
            .select("charity_name, amount_cents, status, created_at");
        
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        
        // Aggregate by charity
        const totals = {};
        for (const payout of (data || [])) {
            if (!totals[payout.charity_name]) {
                totals[payout.charity_name] = {
                    charity_name: payout.charity_name,
                    total_cents: 0,
                    pending_cents: 0,
                    paid_out_cents: 0,
                    payout_count: 0
                };
            }
            totals[payout.charity_name].total_cents += payout.amount_cents;
            totals[payout.charity_name].payout_count++;
            if (payout.status === "pending") {
                totals[payout.charity_name].pending_cents += payout.amount_cents;
            } else if (payout.status === "paid_out") {
                totals[payout.charity_name].paid_out_cents += payout.amount_cents;
            }
        }
        
        res.json({ 
            charities: Object.values(totals),
            grand_total_cents: Object.values(totals).reduce((sum, c) => sum + c.total_cents, 0)
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Admin endpoint: Mark charity payouts as paid out
app.post("/admin/charity-payout/:charityName", async (req, res) => {
    try {
        const { charityName } = req.params;
        
        const { data, error } = await supabase
            .from("charity_payouts")
            .update({ status: "paid_out" })
            .eq("charity_name", charityName)
            .eq("status", "pending")
            .select();
        
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        
        res.json({ 
            message: "Marked as paid out",
            updated_count: data?.length || 0
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
