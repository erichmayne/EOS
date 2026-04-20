require('dotenv').config();

const express = require('express');
const cors = require('cors');
const Stripe = require('stripe');
const { createClient } = require('@supabase/supabase-js');
const bcrypt = require('bcryptjs');
const twilio = require('twilio');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');

const JWT_SECRET = process.env.JWT_SECRET || '';
const JWT_EXPIRY = '30d';

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

// Email transporter (Google Workspace SMTP)
const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: false, // true for 465, false for other ports
  auth: {
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || ''
  }
});

app.use(cors({
    origin: ['https://runmatch.io', 'https://www.runmatch.io', 'https://api.runmatch.io', 'https://runmatch.io', 'https://www.runmatch.io', 'https://api.runmatch.io'],
    methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json());

// -----------------------------------------------------------------------------
// Security: Rate limiting
// -----------------------------------------------------------------------------
const globalLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
    skip: (req) => req.ip === '127.0.0.1' || req.ip === '::1',
    message: { error: 'Too many requests. Please try again shortly.' }
});

const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 10,
    message: { error: 'Too many login attempts. Please try again in 15 minutes.' }
});

const paymentLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 10,
    message: { error: 'Too many payment requests. Please slow down.' }
});

app.use(globalLimiter);

// -----------------------------------------------------------------------------
// Security: Cron/Admin endpoint protection
// -----------------------------------------------------------------------------
const CRON_SECRET = process.env.CRON_SECRET || '';

function requireCronSecret(req, res, next) {
    const auth = req.headers.authorization;
    if (!CRON_SECRET) return next();
    if (auth === `Bearer ${CRON_SECRET}`) return next();
    console.log('🚫 Unauthorized cron/admin access attempt:', req.path);
    return res.status(401).json({ error: 'Unauthorized' });
}

// -----------------------------------------------------------------------------
// Security: JWT token generation
// -----------------------------------------------------------------------------
function generateToken(userId, email) {
    if (!JWT_SECRET) return null;
    return jwt.sign({ userId, email }, JWT_SECRET, { expiresIn: JWT_EXPIRY });
}

// -----------------------------------------------------------------------------
// Security: Optional auth middleware (accepts both authenticated and unauthenticated)
// During transition: logs auth status but never blocks requests
// -----------------------------------------------------------------------------
function optionalAuth(req, res, next) {
    req.authenticatedUserId = null;
    const auth = req.headers.authorization;
    if (auth && auth.startsWith('Bearer ') && JWT_SECRET) {
        const token = auth.slice(7);
        try {
            const decoded = jwt.verify(token, JWT_SECRET);
            req.authenticatedUserId = decoded.userId;
        } catch (e) {
            // Invalid token — log but don't block during transition
        }
    }
    next();
}

// -----------------------------------------------------------------------------
// Helper: Get today's date (YYYY-MM-DD) in a user's timezone
// -----------------------------------------------------------------------------
function getTodayForTimezone(tz) {
    return new Date().toLocaleDateString("en-CA", { timeZone: tz || "America/New_York" });
}

// -----------------------------------------------------------------------------
// Helper: Get current HH:MM in a user's timezone
// -----------------------------------------------------------------------------
function getCurrentTimeForTimezone(tz) {
    return new Date().toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: tz || "America/New_York" }).replace(/^24:/, "00:");
}

// -----------------------------------------------------------------------------
// Helper: Send Slack notification (non-blocking, never throws)
// -----------------------------------------------------------------------------
const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL || '';

async function notifySlack(text) {
    try {
        await fetch(SLACK_WEBHOOK_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text })
        });
    } catch (e) {
        console.error('Slack notification failed (non-fatal):', e.message);
    }
}

// -----------------------------------------------------------------------------
// Helper: Extract HH:MM from various time formats (TIME, TIMESTAMPTZ, string)
// -----------------------------------------------------------------------------
function parseDeadlineTime(deadline) {
    if (!deadline) return "09:00";
    const dl = String(deadline);
    // Match HH:MM from formats like "07:00:00", "07:00:00-08:00", "2026-01-01T07:00:00Z"
    const timeMatch = dl.match(/(\d{2}):(\d{2})/);
    if (timeMatch) {
        return `${timeMatch[1]}:${timeMatch[2]}`;
    }
    return "09:00";
}

// -----------------------------------------------------------------------------
// Health check
// -----------------------------------------------------------------------------
app.get('/health', (req, res) => res.json({ ok: true }));

// -----------------------------------------------------------------------------
// Payments: create PaymentIntent + Customer + Ephemeral Key
// -----------------------------------------------------------------------------
app.post('/create-payment-intent', paymentLimiter, optionalAuth, async (req, res) => {
  try {
    const { amount, userId } = req.body; // amount in cents, userId optional

    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid amount' });
    }

    // Calculate charge with Stripe fee (2.9% + $0.30) so user gets full deposit
    const stripeFeeFixed = 30; // 30 cents
    const stripeFeePercent = 0.029; // 2.9%
    const chargeAmount = Math.ceil((amount + stripeFeeFixed) / (1 - stripeFeePercent));
    console.log(`Deposit: $${(amount/100).toFixed(2)} -> Charge: $${(chargeAmount/100).toFixed(2)} for user: ${userId || 'anonymous'}`);

    // Get or create Stripe customer
    let customerId = null;
    let user = null;
    
    if (userId) {
      // Check if user already has a Stripe customer
      const { data: userData } = await supabase
        .from('users')
        .select('id, email, full_name, stripe_customer_id')
        .eq('id', userId)
        .single();
      
      user = userData;
      
      if (user?.stripe_customer_id) {
        customerId = user.stripe_customer_id;
        console.log('Using existing Stripe customer:', customerId);
      }
    }
    
    // Create new Stripe customer if needed
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user?.email || undefined,
        name: user?.full_name || undefined,
      });
      customerId = customer.id;
      console.log('Created new Stripe customer:', customerId);
      
      // Save customer ID to user record if we have a userId
      if (userId) {
        await supabase
          .from('users')
          .update({ stripe_customer_id: customerId })
          .eq('id', userId);
      }
    }

    // Try to create ephemeral key, handle case where customer doesn't exist (e.g., test->live switch)
    let ephemeralKey;
    try {
      ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
      { apiVersion: '2023-10-16' }
    );
    } catch (ephemeralError) {
      // If customer doesn't exist (test mode customer in live mode), create new one
      if (ephemeralError.code === 'resource_missing') {
        console.log('Customer not found (likely test mode ID in live mode), creating new customer...');
        const newCustomer = await stripe.customers.create({
          email: user?.email || undefined,
          name: user?.full_name || undefined,
        });
        customerId = newCustomer.id;
        console.log('Created new Stripe customer:', customerId);
        
        // Update user record with new customer ID
        if (userId) {
          await supabase
            .from('users')
            .update({ stripe_customer_id: customerId })
            .eq('id', userId);
        }
        
        // Retry ephemeral key creation
        ephemeralKey = await stripe.ephemeralKeys.create(
          { customer: customerId },
          { apiVersion: '2023-10-16' }
        );
      } else {
        throw ephemeralError; // Re-throw if different error
      }
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: chargeAmount, // Charge includes Stripe fee
      currency: 'usd',
      customer: customerId,
      automatic_payment_methods: { enabled: true },
    });

    const depositDollars = (amount / 100).toFixed(2);
    notifySlack(`💰 *New Deposit*\n• Amount: $${depositDollars}\n• User: ${userId || 'Unknown'}`);
    
    res.json({
      paymentIntentClientSecret: paymentIntent.client_secret,
      customer: customerId,
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
    
    console.log("📥 /users/profile request:", JSON.stringify({ 
      email, 
      balanceCents, 
      payout_destination, 
      committedDestination, 
      destinationCommitted,
      payoutCommitted,
      missed_goal_payout
    }, null, 2));

    // Email is always required
    if (!email || typeof email !== "string" || !email.trim()) {
      return res.status(400).json({ error: "Email is required." });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const activeBalanceCents = typeof balanceCents === "number" && balanceCents >= 0 ? Math.floor(balanceCents) : 0;

    // Check for existing user
    const { data: existingUser, error: fetchError } = await supabase
      .from("users")
      .select("*")
      .eq("email", normalizedEmail)
      .maybeSingle();

    if (fetchError) {
      console.error("Supabase fetch user error:", fetchError);
      return res.status(500).json({ error: "Failed to load user." });
    }

    // Block duplicate emails on account creation
    if (createOnly && existingUser) {
      return res.status(409).json({ error: "An account with this email already exists. Please sign in instead." });
    }
    
    // Full name only required for NEW users
    if (!existingUser && (!fullName || typeof fullName !== "string" || !fullName.trim())) {
      return res.status(400).json({ error: "Full name is required for new accounts." });
    }
    
    const normalizedName = fullName ? fullName.trim() : (existingUser?.full_name || "");

    // Don't create Stripe customer during signup - defer until first deposit
    let stripeCustomerId = existingUser?.stripe_customer_id ?? null;
    // Stripe customer will be created lazily in /create-payment-intent when user deposits
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
      // Only update balance if provided as a number (update both columns for consistency)
      ...(typeof balanceCents === "number" && { balance_cents: activeBalanceCents, active_balance_cents: activeBalanceCents }),
      // Objective fields
      ...(objective_type && { objective_type }),
      ...(typeof objective_count === "number" && { objective_count }),
      ...(objective_schedule && { objective_schedule }),
      ...(objective_deadline && { objective_deadline }),
      // Payout fields - use explicit checks for strings
      ...(typeof missed_goal_payout === "number" && { missed_goal_payout }),
      ...(typeof payout_destination === "string" && payout_destination && { payout_destination }),
      ...(typeof payoutCommitted === "boolean" && { payout_committed: payoutCommitted }),
      // Destination commit fields
      ...(typeof destinationCommitted === "boolean" && { destination_committed: destinationCommitted }),
      ...(typeof committedDestination === "string" && committedDestination && { committed_destination: committedDestination }),
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
        return res.status(500).json({ error: "Failed to create user." });
      }
      userRow = data;
      notifySlack(`🆕 *New User Signed Up*\n• Name: ${data.full_name || 'Unknown'}\n• Email: ${normalizedEmail}`);
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
        return res.status(500).json({ error: "Failed to update user." });
      }
      userRow = data;
      console.log("✅ User updated:", { 
        id: userRow.id, 
        balance_cents: userRow.balance_cents,
        payout_destination: userRow.payout_destination,
        committed_destination: userRow.committed_destination 
      });
    }

    // Generate auth token
    const token = generateToken(userRow.id, userRow.email);
    
    // Store userId for reference
    return res.json({
      id: userRow.id,
      token,
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
    return res.status(500).json({ error: "Internal server error" });
  }
});

// -----------------------------------------------------------------------------
// Helper: send recipient invite SMS via Twilio
// -----------------------------------------------------------------------------
async function sendRecipientInviteSMS({ toPhone, payerName, inviteCode }) {
  if (!process.env.TWILIO_FROM_NUMBER) {
    throw new Error("TWILIO_FROM_NUMBER not configured");
  }

  const url = `https://app.runmatch.io/invite`;

  const body =
    `🎯 RunMatch Accountability Invite\n\n` +
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
      return res.status(500).json({ error: 'Failed to create invite.' });
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
    res.status(500).json({ error: 'Failed to send invite.' });
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
      return res.status(500).json({ error: 'Failed to create invite.' });
    }

    res.json({
      inviteCode: inviteCode,
      message: 'Invite code generated successfully. Share it manually.'
    });
  } catch (err) {
    console.error('Error in /recipient-invites/code-only:', err);
    res.status(500).json({ error: 'Failed to generate invite code.' });
  }
});

// -----------------------------------------------------------------------------
// Recipient Signup - Creates user account from invite (no Stripe Connect)
// -----------------------------------------------------------------------------
app.post('/recipient-signup', async (req, res) => {
  try {
    const { inviteCode, fullName, email, phone, password } = req.body || {};
    
    console.log('📥 /recipient-signup:', { inviteCode, email, fullName });
    
    // Validate required fields (phone is optional)
    if (!inviteCode || !fullName || !email || !password) {
      return res.status(400).json({ error: 'Required fields: inviteCode, fullName, email, password' });
    }
    
    const normalizedEmail = email.trim().toLowerCase();
    
    // Find the invite
    const { data: invite, error: inviteError } = await supabase
      .from('recipient_invites')
      .select('*, payer:payer_user_id(id, full_name, email)')
      .eq('invite_code', inviteCode.toUpperCase())
      .maybeSingle();
    
    if (inviteError || !invite) {
      return res.status(404).json({ error: 'Invalid invite code' });
    }
    
    if (invite.status === 'accepted') {
      return res.status(400).json({ error: 'This invite has already been used' });
    }
    
    // Check if email already exists
    const { data: existingUser } = await supabase
      .from('users')
      .select('id')
      .eq('email', normalizedEmail)
      .maybeSingle();
    
    if (existingUser) {
      return res.status(409).json({ error: 'An account with this email already exists. Please sign in instead.' });
    }
    
    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);
    
    // Create new user (recipient becomes a full RunMatch user)
    const { data: newUser, error: userError } = await supabase
      .from('users')
      .insert({
        full_name: fullName.trim(),
        email: normalizedEmail,
        phone: phone || null,
        password_hash: passwordHash,
        balance_cents: 0,
        active_balance_cents: 0,
        payout_destination: 'charity', // Recipients default to charity too
      })
      .select()
      .single();
    
    if (userError) {
      console.error('Failed to create recipient user:', userError);
      return res.status(500).json({ error: 'Failed to create account', detail: userError.message });
    }
    
    // Update invite status to accepted (DB constraint requires specific values: pending, accepted)
    const { error: inviteUpdateError } = await supabase
      .from('recipient_invites')
      .update({ status: 'accepted' })
      .eq('id', invite.id);
    
    if (inviteUpdateError) {
      console.error('Warning: Failed to update invite status:', inviteUpdateError);
    }
    
    // Create entry in recipients table (required for FK constraint on users.custom_recipient_id)
    console.log('📝 Creating recipients table entry for:', normalizedEmail);
    
    const { data: recipientEntry, error: recipientError } = await supabase
      .from('recipients')
      .insert({
        name: fullName.trim(),
        email: normalizedEmail,
        phone: phone || null,
        type: 'individual'
      })
      .select()
      .single();
    
    if (recipientError) {
      console.error('❌ Failed to create recipient entry:', recipientError);
      // This is critical - without this, we can't link to payer
      return res.status(500).json({ error: 'Failed to create recipient record', detail: recipientError.message });
    }
    
    console.log('✅ Recipient entry created with ID:', recipientEntry.id);
    
    // Update payer's custom_recipient_id with the recipient entry (not user ID due to FK constraint)
    if (recipientEntry) {
      console.log('📝 Updating payer:', invite.payer_user_id, 'with custom_recipient_id:', recipientEntry.id);
      
      const { data: updatedPayer, error: payerUpdateError } = await supabase
        .from('users')
        .update({ 
          custom_recipient_id: recipientEntry.id,
          payout_destination: 'custom'
        })
        .eq('id', invite.payer_user_id)
        .select('id, full_name, custom_recipient_id, payout_destination')
        .single();
      
      if (payerUpdateError) {
        console.error('❌ Failed to update payer custom_recipient_id:', payerUpdateError);
      } else {
        console.log('✅ Payer updated successfully:', updatedPayer);
      }
      
      // Also update invite with recipient_id AND recipient_user_id (CRITICAL for iOS linking)
      const { error: inviteLinkError } = await supabase
        .from('recipient_invites')
        .update({ 
          recipient_id: recipientEntry.id,
          recipient_user_id: newUser.id  // THIS WAS MISSING - links the actual user
        })
        .eq('id', invite.id);
      
      if (inviteLinkError) {
        console.error('⚠️ Failed to link recipient_user_id to invite:', inviteLinkError);
      } else {
        console.log('✅ Linked recipient_user_id:', newUser.id, 'to invite:', invite.id);
      }
    }
    
    notifySlack(`🆕 *New User Signed Up* (via invite)\n• Name: ${newUser.full_name || 'Unknown'}\n• Email: ${normalizedEmail}\n• Invited by: ${invite.payer?.full_name || 'Unknown'}`);
    
    console.log('✅ Recipient user created:', { 
      recipientId: newUser.id, 
      recipientEmail: normalizedEmail,
      payerId: invite.payer_user_id,
      payerName: invite.payer?.full_name,
      inviteCode: inviteCode
    });
    
    const token = generateToken(newUser.id, newUser.email);
    
    res.json({
      success: true,
      userId: newUser.id,
      token,
      message: 'Account created successfully',
      payerName: invite.payer?.full_name || 'Your accountability partner',
      // Include user data for auto-login on portal
      user: {
        id: newUser.id,
        email: newUser.email,
        full_name: newUser.full_name,
        phone: newUser.phone,
        balance_cents: newUser.balance_cents || 0,
        created_at: newUser.created_at
      }
    });
    
  } catch (err) {
    console.error('Error in /recipient-signup:', err);
    res.status(500).json({ error: 'Failed to create account' });
  }
});

// -----------------------------------------------------------------------------
// Web Auth - Login endpoint for portal
// -----------------------------------------------------------------------------
app.post('/auth/login', authLimiter, async (req, res) => {
  try {
    const { email, password } = req.body || {};
    
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    
    const normalizedEmail = email.trim().toLowerCase();
    
    // Find user
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('*')
      .eq('email', normalizedEmail)
      .maybeSingle();
    
    if (userError || !user) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }
    
    // Check password
    if (!user.password_hash) {
      return res.status(401).json({ error: 'Please reset your password' });
    }
    
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }
    
    console.log('✅ User logged in:', { id: user.id, email: user.email });
    
    const token = generateToken(user.id, user.email);
    
    // Return user data (excluding sensitive fields)
    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name,
        phone: user.phone,
        balance_cents: user.balance_cents,
        created_at: user.created_at,
        settings_locked_until: user.settings_locked_until
      }
    });
    
  } catch (err) {
    console.error('Error in /auth/login:', err);
    res.status(500).json({ error: 'Login failed' });
  }
});

// -----------------------------------------------------------------------------
// Password Reset - Request reset email
// -----------------------------------------------------------------------------
app.post('/auth/forgot-password', async (req, res) => {
  try {
    const { email } = req.body || {};
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    const normalizedEmail = email.trim().toLowerCase();
    
    // Find user
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, email, full_name')
      .eq('email', normalizedEmail)
      .maybeSingle();
    
    // Always return success (don't reveal if email exists)
    if (!user) {
      console.log('Password reset requested for non-existent email:', normalizedEmail);
      return res.json({ success: true, message: 'If an account exists, a reset link has been sent.' });
    }
    
    // Generate secure token
    const resetToken = crypto.randomBytes(32).toString('hex');
    const resetExpires = new Date(Date.now() + 3600000); // 1 hour from now
    
    // Store token in database
    const { error: updateError } = await supabase
      .from('users')
      .update({
        password_reset_token: resetToken,
        password_reset_expires: resetExpires.toISOString()
      })
      .eq('id', user.id);
    
    if (updateError) {
      console.error('Failed to store reset token:', updateError);
      return res.status(500).json({ error: 'Failed to process request' });
    }
    
    // Send email
    const resetUrl = `https://runmatch.io/reset-password?token=${resetToken}`;
    
    try {
      await emailTransporter.sendMail({
        from: `"RunMatch" <${process.env.SMTP_USER || 'connect@runmatch.io'}>`,
        to: user.email,
        subject: 'Reset Your RunMatch Password',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
          </head>
          <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; margin: 0; padding: 40px 20px;">
            <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.1);">
              <div style="background: linear-gradient(135deg, #000 0%, #333 100%); padding: 32px; text-align: center;">
                <h1 style="color: #D9A600; margin: 0; font-size: 32px; font-weight: 800;">RunMatch</h1>
              </div>
              <div style="padding: 32px;">
                <h2 style="margin: 0 0 16px; color: #000; font-size: 20px;">Reset Your Password</h2>
                <p style="color: #666; line-height: 1.6; margin: 0 0 24px;">
                  Hi${user.full_name ? ' ' + user.full_name.split(' ')[0] : ''},<br><br>
                  We received a request to reset your password. Click the button below to choose a new password.
                </p>
                <a href="${resetUrl}" style="display: block; background: linear-gradient(135deg, #D9A600 0%, #F0BA00 100%); color: #fff; text-decoration: none; padding: 14px 24px; border-radius: 12px; font-weight: 600; text-align: center; margin-bottom: 24px;">
                  Reset Password
                </a>
                <p style="color: #999; font-size: 13px; line-height: 1.5; margin: 0;">
                  This link expires in 1 hour. If you didn't request this, you can safely ignore this email.
                </p>
              </div>
              <div style="background: #f9f9f9; padding: 20px 32px; text-align: center; border-top: 1px solid #eee;">
                <p style="color: #999; font-size: 12px; margin: 0;">© 2026 RunMatch. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        `
      });
      console.log('Password reset email sent to:', user.email);
    } catch (emailError) {
      console.error('Failed to send reset email:', emailError);
      // Still return success to not reveal email existence
    }
    
    res.json({ success: true, message: 'If an account exists, a reset link has been sent.' });
    
  } catch (err) {
    console.error('Error in /auth/forgot-password:', err);
    res.status(500).json({ error: 'Failed to process request' });
  }
});

// -----------------------------------------------------------------------------
// Password Reset - Verify token and update password
// -----------------------------------------------------------------------------
app.post('/auth/reset-password', async (req, res) => {
  try {
    const { token, newPassword } = req.body || {};
    
    if (!token || !newPassword) {
      return res.status(400).json({ error: 'Token and new password are required' });
    }
    
    if (newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }
    
    // Find user with valid token
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, email, password_reset_expires')
      .eq('password_reset_token', token)
      .maybeSingle();
    
    if (!user) {
      return res.status(400).json({ error: 'Invalid or expired reset link' });
    }
    
    // Check if token is expired
    if (new Date(user.password_reset_expires) < new Date()) {
      return res.status(400).json({ error: 'Reset link has expired. Please request a new one.' });
    }
    
    // Hash new password
    const passwordHash = await bcrypt.hash(newPassword, 10);
    
    // Update password and clear reset token
    const { error: updateError } = await supabase
      .from('users')
      .update({
        password_hash: passwordHash,
        password_reset_token: null,
        password_reset_expires: null
      })
      .eq('id', user.id);
    
    if (updateError) {
      console.error('Failed to update password:', updateError);
      return res.status(500).json({ error: 'Failed to update password' });
    }
    
    console.log('Password reset successful for:', user.email);
    res.json({ success: true, message: 'Password has been reset successfully' });
    
  } catch (err) {
    console.error('Error in /auth/reset-password:', err);
    res.status(500).json({ error: 'Failed to reset password' });
  }
});

// -----------------------------------------------------------------------------
// Get user transactions for portal
// -----------------------------------------------------------------------------
app.get("/users/:userId/transactions", optionalAuth, async (req, res) => {
  try {
    const { userId } = req.params;
    
    const { data: transactions, error } = await supabase
      .from('transactions')
      .select('*')
      .or(`payer_user_id.eq.${userId},recipient_user_id.eq.${userId}`)
      .order('created_at', { ascending: false })
      .limit(50);
    
    if (error) {
      console.error('Error fetching transactions:', error);
      return res.status(500).json({ error: 'Failed to load transactions' });
    }
    
    // Add description based on transaction type
    const enrichedTransactions = (transactions || []).map(tx => {
      let description = 'Transaction';
      let amount_cents = 0;
      
      if (tx.recipient_user_id === userId) {
        description = 'Received from missed goal';
        amount_cents = tx.amount_cents || 0;
      } else if (tx.payer_user_id === userId) {
        description = 'Missed goal payout';
        amount_cents = -(tx.amount_cents || 0);
      }
      
      return {
        ...tx,
        description,
        amount_cents
      };
    });
    
    res.json({ transactions: enrichedTransactions });
    
  } catch (err) {
    console.error('Error in /users/:userId/transactions:', err);
    res.status(500).json({ error: 'Failed to load transactions' });
  }
});

// -----------------------------------------------------------------------------
// Withdrawal - Create Stripe Connect & transfer funds (with queue for insufficient balance)
// -----------------------------------------------------------------------------
app.post('/withdraw', paymentLimiter, optionalAuth, async (req, res) => {
  try {
    const { 
      userId, 
      amount, 
      legalName, 
      dob, 
      address, 
      ssnLast4, 
      payoutMethod, 
      paymentToken 
    } = req.body || {};
    
    console.log('📤 /withdraw request:', { userId, amount, payoutMethod });
    
    // Validate required fields
    if (!userId || !amount || !legalName || !dob || !address || !ssnLast4 || !paymentToken) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    // Get user and verify balance
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('*')
      .eq('id', userId)
      .single();
    
    if (userError || !user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    const amountCents = Math.round(amount * 100);
    const platformFeeCents = Math.round(amountCents * 0.03);
    const transferAmountCents = amountCents - platformFeeCents;
    
    if ((user.balance_cents || 0) < amountCents) {
      return res.status(400).json({ error: 'Insufficient balance', available: (user.balance_cents || 0) / 100 });
    }
    
    console.log(`💰 Withdrawal breakdown: total=${amountCents/100}, fee=${platformFeeCents/100} (3%), transfer=${transferAmountCents/100}`);
    
    // Check if settings are locked - block withdrawal if locked
    if (user.settings_locked_until) {
      const lockDate = new Date(user.settings_locked_until);
      if (lockDate > new Date()) {
        console.log('🔒 Withdrawal blocked - settings locked until:', lockDate);
        return res.status(403).json({ 
          error: 'Withdrawals are locked until your objective is completed',
          lockedUntil: user.settings_locked_until
        });
      }
    }
    
    let stripeConnectAccountId = user.stripe_connect_account_id;
    
    // Create Stripe Connect account if user doesn't have one
    if (!stripeConnectAccountId) {
      try {
        const account = await stripe.accounts.create({
          type: 'custom',
          country: 'US',
          email: user.email,
          capabilities: {
            card_payments: { requested: false },
            transfers: { requested: true }
          },
          business_type: 'individual',
          individual: {
            first_name: legalName.split(' ')[0],
            last_name: legalName.split(' ').slice(1).join(' ') || legalName.split(' ')[0],
            email: user.email,
            ...(user.phone && user.phone.length >= 10 ? { phone: user.phone } : {}),
            dob: {
              day: dob.day,
              month: dob.month,
              year: dob.year
            },
            address: {
              line1: address.line1,
              city: address.city,
              state: address.state,
              postal_code: address.postal_code,
              country: 'US'
            },
            ssn_last_4: ssnLast4
          },
          business_profile: {
            mcc: '7941',
            url: 'https://runmatch.io'
          },
          tos_acceptance: {
            date: Math.floor(Date.now() / 1000),
            ip: req.ip || '0.0.0.0'
          }
        });
        
        stripeConnectAccountId = account.id;
        
        // Save Connect account ID to user
        await supabase
          .from('users')
          .update({ stripe_connect_account_id: stripeConnectAccountId })
          .eq('id', userId);
        
        console.log('✅ Created Stripe Connect account:', stripeConnectAccountId);
        
      } catch (stripeErr) {
        console.error('Failed to create Connect account:', stripeErr.message);
        return res.status(500).json({ error: 'Failed to create payout account: ' + stripeErr.message });
      }
    }
    
    // Add external account (bank or card)
    try {
      await stripe.accounts.createExternalAccount(stripeConnectAccountId, {
        external_account: paymentToken,
        default_for_currency: true
      });
      console.log('✅ Added external account to Connect account');
    } catch (extErr) {
      // If error is "already exists", continue
      if (!extErr.message.includes('already exists')) {
        console.error('Failed to add external account:', extErr.message);
        return res.status(500).json({ error: 'Failed to add bank account: ' + extErr.message });
      }
    }
    
    // Check RunMatch platform balance BEFORE attempting transfer
    let eosBalance = 0;
    try {
      const platformBalance = await stripe.balance.retrieve();
      eosBalance = platformBalance.available.reduce((sum, b) => sum + (b.currency === 'usd' ? b.amount : 0), 0);
      console.log('💰 RunMatch platform available balance:', eosBalance / 100);
    } catch (balErr) {
      console.error('Failed to check platform balance:', balErr.message);
    }
    
    // Deduct user's DB balance FIRST (prevents double-withdrawal)
    const newBalance = Math.max(0, (user.balance_cents || 0) - amountCents);
    await supabase
      .from('users')
      .update({ 
        balance_cents: newBalance, 
        active_balance_cents: newBalance 
      })
      .eq('id', userId);
    console.log('💳 User DB balance deducted:', { userId, oldBalance: user.balance_cents, newBalance });
    
    // If insufficient RunMatch balance, queue the withdrawal
    if (eosBalance < amountCents) {
      console.log('⏳ Insufficient RunMatch balance, queuing withdrawal');
      
      // Save to withdrawal_requests queue (net of platform fee)
      const { data: queuedRequest, error: queueError } = await supabase
        .from('withdrawal_requests')
        .insert({
          user_id: userId,
          amount_cents: transferAmountCents,
          status: 'pending',
          stripe_connect_account_id: stripeConnectAccountId,
          payout_method: payoutMethod,
          legal_name: legalName,
          dob: dob,
          address: address,
          ssn_last4: ssnLast4
        })
        .select()
        .single();
      
      if (queueError) {
        console.error('Failed to queue withdrawal:', queueError);
        // Refund the user's balance since we couldn't queue
        await supabase
          .from('users')
          .update({ 
            balance_cents: user.balance_cents, 
            active_balance_cents: user.balance_cents 
          })
          .eq('id', userId);
        return res.status(500).json({ error: 'Failed to process withdrawal request' });
      }
      
      // Record pending transaction
      await supabase
        .from('transactions')
        .insert({
          user_id: userId,
          payer_user_id: userId,
          type: 'withdrawal',
          amount_cents: -amountCents,
          status: 'pending',
          description: 'Withdrawal queued - processing within 5-7 business days',
          stripe_payment_id: null
        });
      
      console.log('📋 Withdrawal queued:', { requestId: queuedRequest.id, userId, amount });
      
      return res.json({
        success: true,
        queued: true,
        requestId: queuedRequest.id,
        message: 'Your withdrawal has been submitted. Funds will be deposited to your account within 5-7 business days.',
        amountWithdrawn: amount,
        newBalanceCents: newBalance
      });
    }
    
    // Transfer funds from RunMatch platform to Connect account
    let transferId = null;
    try {
      const transfer = await stripe.transfers.create({
        amount: transferAmountCents,
        currency: 'usd',
        destination: stripeConnectAccountId,
        description: `RunMatch withdrawal ($${(amountCents/100).toFixed(2)} - $${(platformFeeCents/100).toFixed(2)} fee)`,
        metadata: { user_id: userId, gross_amount: amountCents, platform_fee: platformFeeCents }
      });
      transferId = transfer.id;
      console.log('✅ Transfer created:', transferId);
    } catch (transferErr) {
      console.error('Transfer failed, queuing instead:', transferErr.message);
      
      // Queue it instead of failing (net of platform fee)
      const { data: queuedRequest } = await supabase
        .from('withdrawal_requests')
        .insert({
          user_id: userId,
          amount_cents: transferAmountCents,
          status: 'pending',
          stripe_connect_account_id: stripeConnectAccountId,
          payout_method: payoutMethod,
          legal_name: legalName,
          dob: dob,
          address: address,
          ssn_last4: ssnLast4,
          error_message: transferErr.message
        })
        .select()
        .single();
      
      await supabase
        .from('transactions')
        .insert({
          user_id: userId,
          payer_user_id: userId,
          type: 'withdrawal',
          amount_cents: -amountCents,
          status: 'pending',
          description: 'Withdrawal queued - processing within 5-7 business days'
        });
      
      return res.json({
        success: true,
        queued: true,
        requestId: queuedRequest?.id,
        message: 'Your withdrawal has been submitted. Funds will be deposited to your account within 5-7 business days.',
        amountWithdrawn: amount,
        newBalanceCents: newBalance
      });
    }
    
    // Trigger immediate payout to their bank/card
    let payoutId = null;
    try {
      const balance = await stripe.balance.retrieve({ stripeAccount: stripeConnectAccountId });
      const available = balance.available[0]?.amount || 0;
      
      if (available > 0) {
        const payout = await stripe.payouts.create({
          amount: available,
          currency: 'usd',
          method: payoutMethod === 'card' ? 'instant' : 'standard'
        }, { stripeAccount: stripeConnectAccountId });
        payoutId = payout.id;
        console.log('✅ Payout initiated:', payoutId);
      }
    } catch (payoutErr) {
      console.error('Payout warning (funds will arrive via daily payout):', payoutErr.message);
    }
    
    // Record completed transaction
    await supabase
      .from('transactions')
      .insert({
        user_id: userId,
        payer_user_id: userId,
        type: 'withdrawal',
        amount_cents: -amountCents,
        status: 'completed',
        description: 'Withdrawal to ' + (payoutMethod === 'bank' ? 'bank account' : 'debit card'),
        stripe_payment_id: transferId
      });
    
    console.log('✅ Withdrawal complete:', { userId, amount, transferId, newBalance });
    
    res.json({
      success: true,
      queued: false,
      transferId,
      payoutId,
      message: 'Withdrawal complete! Funds will be deposited to your account within 5-7 business days.',
      amountWithdrawn: amount,
      amountTransferred: transferAmountCents / 100,
      platformFee: platformFeeCents / 100,
      newBalanceCents: newBalance
    });
    
  } catch (err) {
    console.error('Error in /withdraw:', err);
    res.status(500).json({ error: 'Withdrawal failed: ' + err.message });
  }
});

// -----------------------------------------------------------------------------
// Process queued withdrawals (called by cron)
// -----------------------------------------------------------------------------
app.post('/withdrawals/process-queue', requireCronSecret, async (req, res) => {
  try {
    console.log('🔄 Processing withdrawal queue...');
    
    // Check RunMatch platform balance
    let eosBalance = 0;
    try {
      const platformBalance = await stripe.balance.retrieve();
      eosBalance = platformBalance.available.reduce((sum, b) => sum + (b.currency === 'usd' ? b.amount : 0), 0);
      console.log('💰 RunMatch platform available balance:', eosBalance / 100);
    } catch (balErr) {
      console.error('Failed to check platform balance:', balErr.message);
      return res.status(500).json({ error: 'Failed to check platform balance' });
    }
    
    if (eosBalance <= 0) {
      console.log('⚠️ No available balance, skipping queue processing');
      return res.json({ processed: 0, message: 'No available balance' });
    }
    
    // Get pending withdrawal requests (oldest first, limit 10)
    const { data: pendingRequests, error: fetchError } = await supabase
      .from('withdrawal_requests')
      .select('*')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(10);
    
    if (fetchError) {
      console.error('Failed to fetch pending requests:', fetchError);
      return res.status(500).json({ error: 'Failed to fetch queue' });
    }
    
    if (!pendingRequests || pendingRequests.length === 0) {
      console.log('📋 No pending withdrawals in queue');
      return res.json({ processed: 0, message: 'No pending withdrawals' });
    }
    
    console.log(`📋 Found ${pendingRequests.length} pending withdrawals`);
    
    const results = [];
    let remainingBalance = eosBalance;
    
    for (const request of pendingRequests) {
      // Skip if not enough balance for this request
      if (remainingBalance < request.amount_cents) {
        console.log(`⏭️ Skipping request ${request.id}: need ${request.amount_cents}, have ${remainingBalance}`);
        continue;
      }
      
      // Mark as processing
      await supabase
        .from('withdrawal_requests')
        .update({ status: 'processing' })
        .eq('id', request.id);
      
      try {
        // Transfer funds
        const transfer = await stripe.transfers.create({
          amount: request.amount_cents,
          currency: 'usd',
          destination: request.stripe_connect_account_id,
          description: 'RunMatch withdrawal (queued)',
          metadata: { user_id: request.user_id, request_id: request.id }
        });
        
        console.log('✅ Transfer created for queued request:', transfer.id);
        
        // Trigger payout
        let payoutId = null;
        try {
          const connectBalance = await stripe.balance.retrieve({ stripeAccount: request.stripe_connect_account_id });
          const available = connectBalance.available[0]?.amount || 0;
          
          if (available > 0) {
            const payout = await stripe.payouts.create({
              amount: available,
              currency: 'usd',
              method: request.payout_method === 'card' ? 'instant' : 'standard'
            }, { stripeAccount: request.stripe_connect_account_id });
            payoutId = payout.id;
            console.log('✅ Payout initiated:', payoutId);
          }
        } catch (payoutErr) {
          console.error('Payout warning:', payoutErr.message);
        }
        
        // Mark as completed
        await supabase
          .from('withdrawal_requests')
          .update({ 
            status: 'completed',
            stripe_transfer_id: transfer.id,
            stripe_payout_id: payoutId,
            processed_at: new Date().toISOString()
          })
          .eq('id', request.id);
        
        // Update transaction status
        await supabase
          .from('transactions')
          .update({ status: 'completed', stripe_payment_id: transfer.id })
          .eq('user_id', request.user_id)
          .eq('type', 'withdrawal')
          .eq('status', 'pending')
          .eq('amount_cents', -request.amount_cents);
        
        remainingBalance -= request.amount_cents;
        results.push({ requestId: request.id, status: 'completed', transferId: transfer.id });
        
      } catch (transferErr) {
        console.error('Transfer failed for request:', request.id, transferErr.message);
        
        // Increment retry count
        const newRetryCount = (request.retry_count || 0) + 1;
        const newStatus = newRetryCount >= 5 ? 'failed' : 'pending';
        
        await supabase
          .from('withdrawal_requests')
          .update({ 
            status: newStatus,
            retry_count: newRetryCount,
            error_message: transferErr.message
          })
          .eq('id', request.id);
        
        results.push({ requestId: request.id, status: newStatus, error: transferErr.message, retryCount: newRetryCount });
      }
    }
    
    console.log('🔄 Queue processing complete:', { processed: results.length, results });
    
    res.json({ 
      processed: results.filter(r => r.status === 'completed').length,
      total: results.length,
      remainingBalance: remainingBalance / 100,
      results 
    });
    
  } catch (err) {
    console.error('Error processing queue:', err);
    res.status(500).json({ error: 'Queue processing failed: ' + err.message });
  }
});

// -----------------------------------------------------------------------------
// Get user's pending withdrawals
// -----------------------------------------------------------------------------
app.get('/withdrawals/pending/:userId', optionalAuth, async (req, res) => {
  try {
    const { userId } = req.params;
    
    const { data: pending, error } = await supabase
      .from('withdrawal_requests')
      .select('id, amount_cents, status, created_at, error_message, retry_count')
      .eq('user_id', userId)
      .in('status', ['pending', 'processing'])
      .order('created_at', { ascending: false });
    
    if (error) {
      return res.status(500).json({ error: error.message });
    }
    
    res.json({ pending: pending || [] });
    
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------------------------------------------------------
// Optional: Supabase debug endpoint
// -----------------------------------------------------------------------------
// Debug endpoints removed for security

// -----------------------------------------------------------------------------
// Start server
// -----------------------------------------------------------------------------
const port = process.env.PORT || 4242;

// ========== RECIPIENT & PAYOUT ENDPOINTS ==========

// Get user recipient status (for iOS app)
app.get("/users/:userId/recipient", optionalAuth, async (req, res) => {
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
app.post("/users/:userId/commit-destination", optionalAuth, async (req, res) => {
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
// Returns: ALL accepted recipients (with isSelected flag) + pending invites
app.get("/users/:userId/invites", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Get payer's currently selected recipient
        const { data: payer } = await supabase
            .from("users")
            .select("custom_recipient_id, payout_destination")
            .eq("id", userId)
            .single();
        
        const selectedRecipientId = payer?.custom_recipient_id;
        
        // Get ALL accepted invites with their recipient info
        const { data: acceptedInvites, error: acceptedError } = await supabase
            .from("recipient_invites")
            .select("id, invite_code, status, created_at, recipient_id")
            .eq("payer_user_id", userId)
            .eq("status", "accepted")
            .order("created_at", { ascending: false });
        
        if (acceptedError) {
            console.error("Error fetching accepted invites:", acceptedError);
        }
        
        // Get the most recent pending invite
        const { data: pendingInvites, error: pendingError } = await supabase
            .from("recipient_invites")
            .select("id, invite_code, status, created_at")
            .eq("payer_user_id", userId)
            .eq("status", "pending")
            .order("created_at", { ascending: false })
            .limit(1);
        
        if (pendingError) {
            console.error("Error fetching pending invites:", pendingError);
        }
        
        // Build the invites array with recipient info
        const invites = [];
        const seenRecipientIds = new Set(); // Avoid duplicates (multiple invites can point to same recipient)
        
        // FIRST: Always include the currently selected recipient (even if no invite record)
        if (selectedRecipientId) {
            const { data: selectedR } = await supabase
                .from("recipients")
                .select("id, name, email")
                .eq("id", selectedRecipientId)
                .single();
            
            if (selectedR) {
                seenRecipientIds.add(selectedR.id);
                invites.push({
                    id: selectedR.id,
                    status: 'accepted',
                    isSelected: true,
                    recipient: {
                        name: selectedR.name,
                        email: selectedR.email,
                        recipientId: selectedR.id
                    }
                });
            }
        }
        
        // Add other accepted recipients from invites (deduplicated by recipient_id)
        for (const inv of (acceptedInvites || [])) {
            if (!inv.recipient_id || seenRecipientIds.has(inv.recipient_id)) {
                continue; // Skip if no recipient or already added
            }
            seenRecipientIds.add(inv.recipient_id);
            
            // Get recipient info
                const { data: r } = await supabase
                    .from("recipients")
                .select("id, name, email")
                    .eq("id", inv.recipient_id)
                    .single();
            
            if (r) {
                const isSelected = r.id === selectedRecipientId;
                invites.push({
                    id: r.id,  // Use recipient ID as the invite ID for selection
                    status: isSelected ? 'accepted' : 'inactive', // 'accepted' = selected, 'inactive' = available but not selected
                    isSelected: isSelected,
                    recipient: {
                        name: r.name,
                        email: r.email,
                        recipientId: r.id
                    }
                });
            }
        }
        
        // Sort: selected first, then by name
        invites.sort((a, b) => {
            if (a.isSelected && !b.isSelected) return -1;
            if (!a.isSelected && b.isSelected) return 1;
            return (a.recipient?.name || '').localeCompare(b.recipient?.name || '');
        });
        
        // Add pending invites at the end
        for (const inv of (pendingInvites || [])) {
            invites.push({
                id: inv.id,
                invite_code: inv.invite_code,
                status: 'pending',
                created_at: inv.created_at
            });
        }
        
        // Find current selected recipient for response
        const currentRecipient = invites.find(i => i.isSelected)?.recipient || null;
        
        console.log('📋 Returning invites for user:', userId, 
            '- Total recipients:', seenRecipientIds.size, 
            '- Selected:', currentRecipient?.name || 'none',
            '- Pending:', pendingInvites?.length || 0);
        
        res.json({ 
            invites,
            currentRecipient: currentRecipient ? {
                id: currentRecipient.recipientId,
                name: currentRecipient.name,
                email: currentRecipient.email,
                status: 'active'
            } : null,
            totalRecipients: seenRecipientIds.size,
            pendingCount: pendingInvites?.length || 0
        });
        
    } catch (error) {
        console.error("Error in /users/:userId/invites:", error);
        res.status(500).json({ error: error.message });
    }
});

// Switch active recipient (select a different one from the list)
app.post("/users/:userId/select-recipient", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        const { recipientId } = req.body || {};
        
        console.log('🔄 Switching recipient for user:', userId, 'to:', recipientId);
        
        if (!recipientId) {
            return res.status(400).json({ error: "recipientId is required" });
        }
        
        // Verify the recipient exists in the recipients table
        const { data: recipient, error: recipientError } = await supabase
            .from("recipients")
            .select("id, name, email")
            .eq("id", recipientId)
            .single();
        
        if (recipientError || !recipient) {
            return res.status(404).json({ error: "Recipient not found" });
        }
        
        // Verify this recipient is linked to this user via an invite
        const { data: linkedInvite } = await supabase
            .from("recipient_invites")
            .select("id")
            .eq("payer_user_id", userId)
            .eq("recipient_id", recipientId)
            .limit(1);
        
        if (!linkedInvite || linkedInvite.length === 0) {
            // Also check by recipient email match (legacy invites)
            const { data: emailInvite } = await supabase
                .from("recipient_invites")
                .select("id")
                .eq("payer_user_id", userId)
                .eq("recipient_email", recipient.email)
                .limit(1);
            
            if (!emailInvite || emailInvite.length === 0) {
                console.log(`🚫 Recipient ${recipientId} not linked to user ${userId}`);
                return res.status(403).json({ error: "This recipient is not linked to your account." });
            }
        }
        
        // Update the user's custom_recipient_id
        const { data: updatedUser, error: updateError } = await supabase
            .from("users")
            .update({ 
                custom_recipient_id: recipientId,
                payout_destination: 'custom'  // Ensure payout goes to custom
            })
            .eq("id", userId)
            .select("id, custom_recipient_id, payout_destination")
            .single();
        
        if (updateError) {
            console.error("Failed to update custom_recipient_id:", updateError);
            return res.status(500).json({ error: "Failed to switch recipient" });
        }
        
        console.log('✅ Switched recipient successfully:', {
            userId,
            newRecipientId: recipientId,
            recipientName: recipient.name
        });
        
        res.json({
            success: true,
            selectedRecipient: {
                id: recipient.id,
                name: recipient.name,
                email: recipient.email
            }
        });
        
    } catch (error) {
        console.error("Error in /users/:userId/select-recipient:", error);
        res.status(500).json({ error: error.message });
    }
});

// GET endpoint for verify-invite (for web page)
app.get("/verify-invite/:code", async (req, res) => {
    try {
        const inviteCode = req.params.code;
        
        const { data: invite, error } = await supabase
            .from("recipient_invites")
            .select("*, payer:users!payer_user_id(full_name, email, missed_goal_payout)")
            .eq("invite_code", inviteCode.toUpperCase())
            .eq("status", "pending")
            .single();
        
        if (error || !invite) {
            return res.status(404).json({ error: "Invalid or expired invite code" });
        }
        
        res.json({ 
            code: invite.invite_code,
            payerName: invite.payer?.full_name || "RunMatch User",
            payerEmail: invite.payer?.email,
            payoutAmount: invite.payer?.missed_goal_payout || 0,
            phone: invite.phone
        });
    } catch (error) {
        console.error("Error verifying invite:", error);
        res.status(500).json({ error: error.message });
    }
});


// ========== OBJECTIVE CHECK & PAYOUT ENDPOINTS ==========

// Check for missed objectives and trigger payouts
// Supports multi-objective: ALL enabled objectives must be complete, or day fails
app.post("/objectives/check-missed", requireCronSecret, async (req, res) => {
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
        
        // Get all users with enabled objectives and check deadline
        const { data: usersWithObjectives, error: usersError } = await supabase
            .from("users")
            .select("id, email, balance_cents, missed_goal_payout, payout_destination, committed_destination, committed_recipient_id, custom_recipient_id, stripe_customer_id, timezone, objective_deadline")
            .gt("missed_goal_payout", 0);
        
        if (usersError) {
            return res.status(400).json({ error: usersError.message });
        }
        
        const results = [];
        
        for (const user of usersWithObjectives || []) {
            const userTimezone = user?.timezone || "America/New_York";
            const currentTime = getCurrentTimeInTimezone(userTimezone);
            const today = getTodayInTimezone(userTimezone);
            
            // Skip if no deadline set (user removed it — stakes paused)
            if (!user.objective_deadline) continue;
            
            const deadline = parseDeadlineTime(user.objective_deadline);
            
            // Skip if deadline hasn't passed yet
            if (currentTime < deadline) continue;
            
            
            // Get user's enabled objectives from user_objectives table
            const { data: enabledObjectives } = await supabase
                .from("user_objectives")
                .select("objective_type, target_value")
                .eq("user_id", user.id)
                .eq("enabled", true);
            
            // If no enabled objectives, skip
            if (!enabledObjectives || enabledObjectives.length === 0) continue;
            
            // Get today's sessions for this user
            const { data: todaySessions } = await supabase
                .from("objective_sessions")
                .select("objective_type, completed_count, target_count, status, payout_triggered")
                .eq("user_id", user.id)
                .eq("session_date", today);
            
            // Check if payout already triggered today (check BOTH sessions and transactions)
            const alreadyTriggered = (todaySessions || []).some(s => s.payout_triggered);
            if (alreadyTriggered) continue;
            
            // DOUBLE-CHECK: Also verify no transaction exists for today (prevents race conditions)
            const { data: existingTx } = await supabase
                .from("transactions")
                .select("id")
                .eq("user_id", user.id)
                .eq("type", "payout")
                .gte("created_at", today + "T00:00:00")
                .lt("created_at", today + "T23:59:59")
                .limit(1);
            
            if (existingTx && existingTx.length > 0) {
                console.log(`⚠️ Skipping ${user.email} - payout already exists for ${today}`);
                continue;
            }
            
            // Check if ALL enabled objectives are completed
            const sessionMap = {};
            (todaySessions || []).forEach(s => { sessionMap[s.objective_type] = s; });
            
            let allComplete = true;
            let missedObjectives = [];
            
            for (const obj of enabledObjectives) {
                const session = sessionMap[obj.objective_type];
                const isComplete = session && session.completed_count >= session.target_count;
                if (!isComplete) {
                    allComplete = false;
                    missedObjectives.push(obj.objective_type);
                }
            }
            
            // If all complete, mark sessions as accepted and continue
            if (allComplete) {
                for (const s of todaySessions || []) {
                    if (s.status === "pending") {
                        await supabase.from("objective_sessions").update({ status: "accepted" }).eq("user_id", user.id).eq("session_date", today).eq("objective_type", s.objective_type);
                    }
                }
                continue;
            }
            
            // MISSED: At least one objective not complete
            console.log(`❌ User ${user.email} missed objectives: ${missedObjectives.join(", ")}`);
            
            // Use first session or create a tracking session
            let session = todaySessions?.[0];
            if (!session) {
                // Create a session to track payout
                const { data: newSession } = await supabase
                    .from("objective_sessions")
                    .insert({
                        user_id: user.id,
                        session_date: today,
                        objective_type: missedObjectives[0],
                        target_count: enabledObjectives[0].target_value,
                        completed_count: 0,
                        status: "pending",
                        deadline: deadline,
                        payout_amount: user.missed_goal_payout || 0
                    })
                    .select()
                    .single();
                session = newSession;
            }
            
            const userBalance = user?.balance_cents || 0;
            const payoutAmount = user?.missed_goal_payout || 0;
            
            if (payoutAmount <= 0) continue;
            
            const payoutAmountCents = Math.round(payoutAmount * 100);
            const destination = user.committed_destination || user.payout_destination || "charity";
            const recipientId = user.committed_recipient_id || user.custom_recipient_id;
            
            // No recipient set on custom destination: skip deduction, mark as missed
            if (destination === "custom" && !recipientId) {
                await supabase.from("objective_sessions").update({ 
                    status: "missed", 
                    payout_triggered: true
                }).eq("user_id", user.id).eq("session_date", today);
                
                await supabase.from("users").update({ 
                    settings_locked_until: null
                }).eq("id", user.id);
                
                console.log(`⚠️ User ${user.email} missed objectives but has no recipient set — skipping deduction`);
                continue;
            }
            
            // Zero balance: mark as missed but don't attempt deduction or transfer
            if (userBalance <= 0) {
                await supabase.from("objective_sessions").update({ 
                    status: "missed", 
                    payout_triggered: true
                }).eq("user_id", user.id).eq("session_date", today);
                
                await supabase.from("users").update({ 
                    settings_locked_until: null
                }).eq("id", user.id);
                
                console.log(`⚠️ User ${user.email} missed objectives but has $0 balance — marked as missed, no deduction`);
                
                results.push({
                    userId: user.id,
                    sessionId: session?.id,
                    missedObjectives: missedObjectives,
                    amount: 0,
                    destination: "none (zero balance)",
                    stripeTransferId: null,
                    newBalanceCents: 0,
                    settingsLockReset: true
                });
                continue;
            }
            
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
            
            // Transfer DB balance to recipient if custom
            // NOTE: Real money stays in RunMatch account until recipient withdraws
            if (destination === "custom" && recipientId) {
                // Look up the recipient entry to get their email
                const { data: recipientEntry } = await supabase
                    .from("recipients")
                    .select("id, email, name")
                    .eq("id", recipientId)
                    .single();
                
                if (!recipientEntry) {
                    console.error("Recipient entry not found in recipients table:", recipientId);
                } else {
                    // Find the user account by email (recipients table links to users via email)
                    const { data: recipientUser, error: recipientError } = await supabase
                        .from("users")
                        .select("id, balance_cents, active_balance_cents, full_name, email")
                        .eq("email", recipientEntry.email)
                        .single();
                    
                    if (recipientUser) {
                        // Add payout amount to recipient's balance (DB only, no Stripe transfer)
                        const newRecipientBalance = (recipientUser.balance_cents || 0) + payoutAmountCents;
                        await supabase
                            .from("users")
                            .update({ 
                                balance_cents: newRecipientBalance, 
                                active_balance_cents: newRecipientBalance 
                            })
                            .eq("id", recipientUser.id);
                        
                        console.log("💰 DB balance transfer:", {
                            from: user.email,
                            to: recipientUser.full_name,
                            recipientUserId: recipientUser.id,
                            recipientEmail: recipientUser.email,
                            amount: payoutAmountCents / 100,
                            newRecipientBalance: newRecipientBalance / 100
                        });
                    } else {
                        console.error("Recipient user not found by email:", recipientEntry.email, recipientError);
                    }
                }
                
                /* COMMENTED OUT - Old Stripe Connect auto-transfer
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
                            description: `RunMatch auto-payout - missed objective`,
                            metadata: { user_id: user.id, session_id: session.id }
                        });
                        stripeTransferId = transfer.id;
                        console.log("Transfer success:", transfer.id, "to", recipient.stripe_connect_account_id);
                        
                        // Trigger instant payout
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
                            console.error("Instant payout failed:", payoutErr.message);
                        }
                    } catch (err) {
                        console.error("Stripe transfer failed:", err.message);
                    }
                }
                */
            }
            
            // Create transaction (with recipient_user_id for DB transfers)
            const { data: tx } = await supabase
                .from("transactions")
                .insert({
                    user_id: user.id,
                    payer_user_id: user.id,
                    recipient_user_id: destination === "custom" ? recipientId : null,
                    type: "payout",
                    amount_cents: payoutAmountCents,
                    status: "completed",
                    description: destination === "charity" 
                        ? `Missed objective (${missedObjectives.join(", ")}) - charity donation` 
                        : `Missed objective (${missedObjectives.join(", ")}) payout`,
                    stripe_payment_id: stripeTransferId
                })
                .select()
                .single();
            
            // Deduct balance, reset settings lock, and mark session
            // Reset settings_locked_until so user can start fresh after failing
            const newBalance = Math.max(0, userBalance - payoutAmountCents);
            await supabase.from("users").update({ 
                balance_cents: newBalance, 
                active_balance_cents: newBalance,
                settings_locked_until: null  // Reset lock - user paid the price, gets fresh start
            }).eq("id", user.id);
            
            // Mark all today's sessions as missed and payout triggered
            await supabase.from("objective_sessions").update({ 
                status: "missed", 
                payout_triggered: true,
                payout_transaction_id: tx?.id 
            }).eq("user_id", user.id).eq("session_date", today);
            
            console.log("🔓 Settings lock reset for user:", user.email, "- missed objective payout processed");
            
            results.push({
                userId: user.id,
                sessionId: session?.id,
                missedObjectives: missedObjectives,
                amount: payoutAmount,
                destination: destination,
                stripeTransferId: stripeTransferId,
                newBalanceCents: newBalance,
                settingsLockReset: true
            });
        }
        
        res.json({ checked: true, serverTime: new Date().toISOString(), payoutsProcessed: results.length, results });
    } catch (error) {
        console.error("Check missed error:", error);
        res.status(500).json({ error: error.message });
    }
});


// NOTE: /users/:userId/deduct-balance was removed (Feb 9 2026)
// It used supabase.raw() and supabase.rpc() which don't exist in Supabase JS client.
// Nothing called it — the actual withdrawal flow uses POST /withdraw.

// Get user balance
app.get("/users/:userId/balance", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: user, error } = await supabase
            .from("users")
            .select("balance_cents, settings_locked_until")
            .eq("id", userId)
            .single();
        
        if (error || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        res.json({
            balanceCents: user.balance_cents || 0,
            balanceDollars: (user.balance_cents || 0) / 100,
            settings_locked_until: user.settings_locked_until,
            stravaConnected: !!user.strava_connection_id
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Delete user account (App Store Guideline 5.1.1(v) - required)
// -----------------------------------------------------------------------------
app.post("/users/delete-account", optionalAuth, async (req, res) => {
    try {
        const { userId, email, password } = req.body;
        
        if (!userId || !email || !password) {
            return res.status(400).json({ error: "Missing required fields" });
        }
        
        console.log(`🗑️ Delete account request for user: ${userId}, email: ${email}`);
        
        // Verify user exists and password matches
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("id, email, password_hash")
            .eq("id", userId)
            .single();
        
        if (userError || !user) {
            console.log(`❌ User not found: ${userId}`);
            return res.status(404).json({ error: "User not found" });
        }
        
        // Verify email matches
        if (user.email.toLowerCase() !== email.toLowerCase()) {
            console.log(`❌ Email mismatch for user: ${userId}`);
            return res.status(401).json({ error: "Invalid credentials" });
        }
        
        // Verify password (bcrypt hash or plain text legacy)
        const bcrypt = require("bcryptjs");
        let passwordValid = false;
        
        if (user.password_hash && user.password_hash.startsWith("$2")) {
            passwordValid = await bcrypt.compare(password, user.password_hash);
        }
        
        if (!passwordValid) {
            console.log(`❌ Invalid password for user: ${userId}`);
            return res.status(401).json({ error: "Incorrect password" });
        }
        
        // Delete user data from all related tables
        console.log(`🗑️ Deleting data for user: ${userId}`);
        
        const { error: sessionsError } = await supabase
            .from("objective_sessions").delete().eq("user_id", userId);
        if (sessionsError) console.log("Error deleting sessions:", sessionsError);
        
        const { error: objectivesError } = await supabase
            .from("user_objectives").delete().eq("user_id", userId);
        if (objectivesError) console.log("Error deleting objectives:", objectivesError);
        
        const { error: invitesSentError } = await supabase
            .from("recipient_invites").delete().eq("payer_user_id", userId);
        if (invitesSentError) console.log("Error deleting sent invites:", invitesSentError);
        
        const { error: invitesReceivedError } = await supabase
            .from("recipient_invites").delete().eq("recipient_user_id", userId);
        if (invitesReceivedError) console.log("Error deleting received invites:", invitesReceivedError);
        
        const { error: transactionsError } = await supabase
            .from("transactions").delete().eq("user_id", userId);
        if (transactionsError) console.log("Error deleting transactions:", transactionsError);
        
        const { error: withdrawalsError } = await supabase
            .from("withdrawal_requests").delete().eq("user_id", userId);
        if (withdrawalsError) console.log("Error deleting withdrawals:", withdrawalsError);
        
        // Finally delete the user record
        const { error: deleteUserError } = await supabase
            .from("users").delete().eq("id", userId);
        
        if (deleteUserError) {
            console.log(`❌ Error deleting user: ${deleteUserError.message}`);
            return res.status(500).json({ error: "Failed to delete user record" });
        }
        
        console.log(`✅ Account deleted successfully for user: ${userId}`);
        res.json({ success: true, message: "Account deleted successfully" });
        
    } catch (error) {
        console.error("Delete account error:", error);
        res.status(500).json({ error: error.message });
    }
});

// Delete a specific invite relationship
app.delete('/invites/:inviteId', optionalAuth, async (req, res) => {
    try {
        const { inviteId } = req.params;
        const { userId } = req.body;
        
        if (!inviteId || !userId) {
            return res.status(400).json({ error: 'Missing inviteId or userId' });
        }
        
        // iOS sends a recipient ID (from recipients table) or an invite ID (from recipient_invites)
        // Try deleting invites that reference this recipient_id
        const { error: byRecipient } = await supabase
            .from('recipient_invites')
            .delete()
            .eq('recipient_id', inviteId)
            .eq('payer_user_id', userId);
        
        // Also try deleting by invite ID directly
        const { error: byId } = await supabase
            .from('recipient_invites')
            .delete()
            .eq('id', inviteId)
            .eq('payer_user_id', userId);
        
        // Clear the user's custom_recipient_id if it matches what we're deleting
        const { data: user } = await supabase
            .from('users')
            .select('custom_recipient_id')
            .eq('id', userId)
            .single();
        
        if (user?.custom_recipient_id === inviteId) {
            await supabase.from('users')
                .update({ custom_recipient_id: null })
                .eq('id', userId);
            console.log(`🗑️ Cleared custom_recipient_id for user ${userId}`);
        }
        
        // Also delete from recipients table
        await supabase.from('recipients').delete().eq('id', inviteId);
        
        console.log(`🗑️ Invite/recipient ${inviteId} deleted by user ${userId}`);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Send invite to an existing RunMatch user by email
app.post('/invites/send-to-user', async (req, res) => {
    try {
        const { payerId, recipientEmail } = req.body;
        
        if (!payerId || !recipientEmail) {
            return res.status(400).json({ error: 'Missing payerId or recipientEmail' });
        }
        
        const normalizedEmail = recipientEmail.trim().toLowerCase();
        
        // Look up payer
        const { data: payer } = await supabase
            .from('users').select('id, full_name, email').eq('id', payerId).single();
        if (!payer) {
            return res.status(404).json({ error: 'Payer account not found.' });
        }
        
        if (payer.email === normalizedEmail) {
            return res.status(400).json({ error: "You can't invite yourself." });
        }
        
        // Look up recipient - must be an existing user
        const { data: recipientUser } = await supabase
            .from('users').select('id, full_name, email').eq('email', normalizedEmail).maybeSingle();
        if (!recipientUser) {
            return res.status(404).json({ error: 'No RunMatch account found with that email. They need to create an account first, or use Generate a Code for new users.' });
        }
        
        // Check for existing pending invite between these two
        const { data: allPayerInvites } = await supabase
            .from('recipient_invites')
            .select('id, status, recipient_user_id')
            .eq('payer_user_id', payerId)
            .in('status', ['pending', 'accepted']);
        
        const existingInvite = (allPayerInvites || []).find(inv => inv.recipient_user_id === recipientUser.id);
        
        if (existingInvite) {
            const msg = existingInvite.status === 'accepted' 
                ? 'This user is already linked as your recipient.'
                : 'You already have a pending invite to this user.';
            return res.status(400).json({ error: msg });
        }
        
        // Generate invite code
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let inviteCode = '';
        for (let i = 0; i < 8; i++) {
            inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        // Create recipient_invites entry then set recipient_user_id
        const { data: invite, error: inviteError } = await supabase
            .from('recipient_invites')
            .insert({
                payer_user_id: payerId,
                invite_code: inviteCode,
                status: 'pending',
                phone: recipientUser.email
            })
            .select()
            .single();
        
        if (!inviteError && invite) {
            await supabase.from('recipient_invites')
                .update({ recipient_user_id: recipientUser.id })
                .eq('id', invite.id);
        }
        
        if (inviteError) {
            console.error('Create invite error:', inviteError);
            return res.status(500).json({ error: 'Failed to create invite.' });
        }
        
        // Send email to recipient
        const acceptUrl = `https://api.runmatch.io/invites/accept/${invite.id}`;
        
        await emailTransporter.sendMail({
            from: `"RunMatch" <${process.env.SMTP_USER || 'connect@runmatch.io'}>`,
            to: recipientUser.email,
            subject: `${payer.full_name || 'Someone'} wants you as their accountability recipient on RunMatch`,
            text: `${payer.full_name} has invited you to be their designated recipient on RunMatch. If they miss their fitness goals, their stakes go to you.\n\nAccept here: ${acceptUrl}`,
            html: `
                <div style="font-family:sans-serif;max-width:500px;margin:0 auto;padding:30px">
                    <h2 style="color:#d9a600">You've been invited!</h2>
                    <p><strong>${payer.full_name || 'A RunMatch user'}</strong> wants you to be their designated recipient.</p>
                    <p>If they miss their fitness goals, their accountability stakes go to you.</p>
                    <a href="${acceptUrl}" style="display:inline-block;background:#d9a600;color:white;padding:14px 28px;border-radius:8px;text-decoration:none;font-weight:bold;margin:20px 0">Accept Invite</a>
                    <p style="color:#888;font-size:12px;margin-top:30px">— RunMatch | Bet on a Better You</p>
                </div>
            `
        });
        
        console.log(`📧 Invite email sent to ${recipientUser.email} from ${payer.full_name}`);
        res.json({ success: true, recipientName: recipientUser.full_name || recipientUser.email });
        
    } catch (error) {
        console.error('Send invite to user error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Accept an invite (clicked from email)
app.get('/invites/accept/:inviteId', async (req, res) => {
    try {
        const { inviteId } = req.params;
        
        const { data: invite } = await supabase
            .from('recipient_invites')
            .select('*, payer:payer_user_id(id, full_name, email)')
            .eq('id', inviteId)
            .single();
        
        const pageHead = '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>';
        const pageStyle = 'font-family:-apple-system,sans-serif;text-align:center;padding:40px 24px;max-width:500px;margin:0 auto';
        
        if (!invite) {
            return res.send(`${pageHead}<body style="${pageStyle}"><h2>Invite not found</h2><p style="font-size:17px;color:#666">This invite link is invalid or has expired.</p></body></html>`);
        }
        
        if (invite.status === 'accepted') {
            return res.send(`${pageHead}<body style="${pageStyle}"><h2 style="color:#d9a600;font-size:24px">Already Accepted</h2><p style="font-size:17px;color:#666">You've already accepted this invite from ${invite.payer?.full_name || 'the user'}.</p><p style="font-size:15px;color:#888;margin-top:24px">Open the RunMatch app to continue.</p></body></html>`);
        }
        
        // Find recipient - try recipient_user_id first, fall back to phone field (stores email for email invites)
        let recipientUser = null;
        if (invite.recipient_user_id) {
            const { data } = await supabase.from('users').select('id, full_name, email').eq('id', invite.recipient_user_id).single();
            recipientUser = data;
        }
        if (!recipientUser && invite.phone && invite.phone.includes('@')) {
            const { data } = await supabase.from('users').select('id, full_name, email').eq('email', invite.phone.toLowerCase()).single();
            recipientUser = data;
        }
        
        if (!recipientUser) {
            return res.send(`${pageHead}<body style="${pageStyle}"><h2>Error</h2><p style="font-size:17px;color:#666">Recipient account not found. Make sure you have a RunMatch account.</p></body></html>`);
        }
        
        // Create recipients table entry (needed for FK on users.custom_recipient_id)
        const { data: recipientEntry, error: recipientError } = await supabase
            .from('recipients')
            .insert({
                name: recipientUser.full_name || recipientUser.email,
                email: recipientUser.email,
                type: 'individual'
            })
            .select()
            .single();
        
        if (recipientError) {
            console.error('Failed to create recipient entry:', recipientError);
            return res.send(`${pageHead}<body style="${pageStyle}"><h2>Error</h2><p style="font-size:17px;color:#666">Failed to link accounts. Please try again.</p></body></html>`);
        }
        
        // Update invite to accepted
        await supabase.from('recipient_invites')
            .update({ 
                status: 'accepted',
                recipient_id: recipientEntry.id
            })
            .eq('id', inviteId);
        
        // Update payer's custom_recipient_id
        await supabase.from('users')
            .update({ 
                custom_recipient_id: recipientEntry.id,
                payout_destination: 'custom'
            })
            .eq('id', invite.payer_user_id);
        
        const payerName = invite.payer?.full_name || 'the user';
        console.log(`✅ Invite accepted: ${recipientUser.email} is now recipient for ${payerName}`);
        
        res.send(`
            ${pageHead}<body style="${pageStyle}">
                <div style="font-size:48px;margin-bottom:16px">🤝</div>
                <h2 style="color:#d9a600;font-size:24px;margin-bottom:8px">Invite Accepted!</h2>
                <p style="font-size:18px;line-height:1.5">You are now <strong>${payerName}'s</strong> designated recipient on RunMatch.</p>
                <p style="font-size:16px;color:#666;line-height:1.5">If they miss their fitness goals, their accountability stakes will be sent to you.</p>
                <p style="font-size:15px;color:#888;margin-top:32px">Open the RunMatch app to see the update.</p>
                <p style="color:#aaa;font-size:13px;margin-top:40px">— RunMatch | Bet on a Better You</p>
            </body></html>
        `);
        
    } catch (error) {
        console.error('Accept invite error:', error);
        res.send('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="font-family:-apple-system,sans-serif;text-align:center;padding:40px 24px"><h2>Error</h2><p style="font-size:17px;color:#666">Something went wrong. Please try again.</p></body></html>');
    }
});

// Check if current user is a recipient for anyone
app.get('/users/:userId/is-recipient', optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Find this user's email, then find recipient entries with that email, then find invites pointing to those
        const { data: thisUser } = await supabase.from('users').select('email').eq('id', userId).single();
        if (!thisUser?.email) {
            return res.json({ isRecipient: false, payers: [] });
        }
        
        const { data: recipientEntries } = await supabase
            .from('recipients')
            .select('id')
            .eq('email', thisUser.email);
        
        const recipientIds = (recipientEntries || []).map(r => r.id);
        if (recipientIds.length === 0) {
            return res.json({ isRecipient: false, payers: [] });
        }
        
        const { data: invitesRaw } = await supabase
            .from('recipient_invites')
            .select('payer_user_id, status, recipient_id, payer:payer_user_id(full_name, email)')
            .eq('status', 'accepted')
            .in('recipient_id', recipientIds);
        
        const invites = (invitesRaw || []).filter(inv => inv.payer_user_id !== userId);
        
        if (!invites || invites.length === 0) {
            return res.json({ isRecipient: false, payers: [] });
        }
        
        if (!invites || invites.length === 0) {
            return res.json({ isRecipient: false, payers: [] });
        }
        
        const payers = invites.map(inv => ({
            payerId: inv.payer_user_id,
            name: inv.payer?.full_name || inv.payer?.email || 'Unknown'
        }));
        
        res.json({ isRecipient: true, payers });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Strava Integration
// -----------------------------------------------------------------------------

const STRAVA_CLIENT_ID = process.env.STRAVA_CLIENT_ID;
const STRAVA_CLIENT_SECRET = process.env.STRAVA_CLIENT_SECRET;
const STRAVA_VERIFY_TOKEN = process.env.STRAVA_VERIFY_TOKEN || 'eos-strava-verify-2026';

// Start Strava OAuth flow
app.get('/strava/connect/:userId', (req, res) => {
    const { userId } = req.params;
    const redirectUri = encodeURIComponent('https://api.runmatch.io/strava/callback');
    const scope = 'activity:read';
    const authUrl = `https://www.strava.com/oauth/authorize?client_id=${STRAVA_CLIENT_ID}&redirect_uri=${redirectUri}&response_type=code&scope=${scope}&state=${userId}`;
    res.redirect(authUrl);
});

// Strava OAuth callback
app.get('/strava/callback', async (req, res) => {
    try {
        const { code, state: userId, error } = req.query;
        
        if (error) {
            console.log('Strava OAuth denied:', error);
            return res.redirect('https://runmatch.io/portal?strava=denied');
        }
        
        if (!code || !userId) {
            return res.redirect('https://runmatch.io/portal?strava=error');
        }
        
        // Exchange code for tokens
        const tokenResponse = await fetch('https://www.strava.com/oauth/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                client_id: STRAVA_CLIENT_ID,
                client_secret: STRAVA_CLIENT_SECRET,
                code: code,
                grant_type: 'authorization_code'
            })
        });
        
        const tokenData = await tokenResponse.json();
        
        if (!tokenData.access_token) {
            console.error('Strava token exchange failed:', tokenData);
            return res.redirect('https://runmatch.io/portal?strava=error');
        }
        
        const { access_token, refresh_token, expires_at, athlete } = tokenData;
        
        // Upsert into strava_connections
        const { data: stravaConn, error: connError } = await supabase
            .from('strava_connections')
            .upsert({
                strava_user_id: athlete.id,
                access_token: access_token,
                refresh_token: refresh_token,
                token_expires_at: new Date(expires_at * 1000).toISOString(),
                athlete_name: `${athlete.firstname || ''} ${athlete.lastname || ''}`.trim(),
                updated_at: new Date().toISOString()
            }, { onConflict: 'strava_user_id' })
            .select()
            .single();
        
        if (connError) {
            console.error('Strava connection save error:', connError);
            return res.redirect('https://runmatch.io/portal?strava=error');
        }
        
        // Check if another user already has this Strava account linked
        const { data: existingUsers } = await supabase
            .from('users')
            .select('id, email')
            .eq('strava_connection_id', stravaConn.id)
            .neq('id', userId);
        
        if (existingUsers && existingUsers.length > 0) {
            console.log(`🚫 Strava account already linked to ${existingUsers[0].email}, rejecting for ${userId}`);
            return res.redirect('https://runmatch.io/portal?strava=already_linked');
        }
        
        // Link to user
        await supabase
            .from('users')
            .update({ strava_connection_id: stravaConn.id })
            .eq('id', userId);
        
        console.log(`✅ Strava connected for user ${userId}, athlete: ${athlete.firstname}`);
        
        // Redirect back - use custom URL scheme for iOS app or web portal
        res.redirect('https://runmatch.io/portal?strava=connected');
        
    } catch (error) {
        console.error('Strava callback error:', error);
        res.redirect('https://runmatch.io/portal?strava=error');
    }
});

// Strava webhook verification (GET - required by Strava)
app.get('/strava/webhook', (req, res) => {
    const { 'hub.mode': mode, 'hub.challenge': challenge, 'hub.verify_token': verifyToken } = req.query;
    
    if (mode === 'subscribe' && verifyToken === STRAVA_VERIFY_TOKEN) {
        console.log('✅ Strava webhook verified');
        res.json({ 'hub.challenge': challenge });
    } else {
        console.log('❌ Strava webhook verification failed');
        res.sendStatus(403);
    }
});

// Strava webhook receiver (POST - receives activity events)
app.post('/strava/webhook', async (req, res) => {
    // Respond immediately (Strava requires fast response)
    res.sendStatus(200);
    
    try {
        const { object_type, aspect_type, object_id, owner_id } = req.body;
        
        console.log(`📩 Strava webhook: ${object_type} ${aspect_type} for athlete ${owner_id}`);
        
        // Handle athlete deauthorization (required by Strava API terms)
        if (object_type === 'athlete' && aspect_type === 'update') {
            const updates = req.body.updates;
            if (updates && updates.authorized === 'false') {
                console.log(`🔓 Strava deauthorization for athlete ${owner_id}`);
                
                // Find and remove the Strava connection
                const { data: conn } = await supabase
                    .from('strava_connections')
                    .select('id')
                    .eq('strava_user_id', owner_id)
                    .single();
                
                if (conn) {
                    // Unlink user from this Strava connection
                    await supabase
                        .from('users')
                        .update({ strava_connection_id: null })
                        .eq('strava_connection_id', conn.id);
                    
                    // Delete the connection record
                    await supabase
                        .from('strava_connections')
                        .delete()
                        .eq('id', conn.id);
                    
                    console.log(`✅ Strava connection removed for athlete ${owner_id}`);
                }
                return;
            }
        }
        
        if (object_type !== 'activity' || aspect_type !== 'create') {
            return; // Only process new activities
        }
        
        // Find strava connection by athlete ID
        const { data: stravaConn, error: connError } = await supabase
            .from('strava_connections')
            .select('*')
            .eq('strava_user_id', owner_id)
            .single();
        
        if (connError || !stravaConn) {
            console.log(`No Strava connection found for athlete ${owner_id}`);
            return;
        }
        
        // Find user linked to this Strava connection
        const { data: users, error: userError } = await supabase
            .from('users')
            .select('*')
            .eq('strava_connection_id', stravaConn.id)
            .limit(1);
        
        const user = users?.[0];
        if (userError || !user) {
            console.log(`No user found for Strava connection ${stravaConn.id}`);
            return;
        }
        
        // Check if user has an enabled run objective OR is in an active competition with run/both
        const { data: runObjective } = await supabase
            .from('user_objectives')
            .select('target_value, enabled')
            .eq('user_id', user.id)
            .eq('objective_type', 'run')
            .eq('enabled', true)
            .single();
        
        let inRunCompetition = false;
        if (!runObjective) {
            const { data: activeComps } = await supabase
                .from('competition_participants')
                .select('competition_id, competitions!inner(status, objective_type)')
                .eq('user_id', user.id)
                .eq('status', 'active');
            
            inRunCompetition = (activeComps || []).some(cp => {
                const comp = cp.competitions;
                return comp && comp.status === 'active' && (comp.objective_type === 'run' || comp.objective_type === 'both');
            });
        }
        
        if (!runObjective && !inRunCompetition) {
            console.log(`User ${user.id} has no run objective and no active run competition, skipping`);
            return;
        }
        
        // --- Strava Token Refresh ---
        // Strava access tokens expire after ~6 hours. Check and refresh if needed.
        let accessToken = stravaConn.access_token;
        const tokenExpiresAt = new Date(stravaConn.token_expires_at);
        const now = new Date();
        
        if (now >= tokenExpiresAt) {
            console.log(`🔄 Strava token expired for athlete ${owner_id}, refreshing...`);
            try {
                const refreshResponse = await fetch('https://www.strava.com/oauth/token', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        client_id: STRAVA_CLIENT_ID,
                        client_secret: STRAVA_CLIENT_SECRET,
                        grant_type: 'refresh_token',
                        refresh_token: stravaConn.refresh_token
                    })
                });
                
                const refreshData = await refreshResponse.json();
                
                if (!refreshData.access_token) {
                    console.error(`❌ Strava token refresh failed for athlete ${owner_id}:`, refreshData);
                    return;
                }
                
                accessToken = refreshData.access_token;
                
                // Update stored tokens in DB
                const { error: tokenUpdateError } = await supabase
                    .from('strava_connections')
                    .update({
                        access_token: refreshData.access_token,
                        refresh_token: refreshData.refresh_token,
                        token_expires_at: new Date(refreshData.expires_at * 1000).toISOString(),
                        updated_at: new Date().toISOString()
                    })
                    .eq('id', stravaConn.id);
                
                if (tokenUpdateError) {
                    console.error('Failed to update Strava tokens in DB:', tokenUpdateError);
                } else {
                    console.log(`✅ Strava token refreshed for athlete ${owner_id}`);
                }
            } catch (refreshErr) {
                console.error(`❌ Strava token refresh error for athlete ${owner_id}:`, refreshErr);
                return;
            }
        }
        
        // Fetch activity details from Strava (using fresh token)
        const activityResponse = await fetch(`https://www.strava.com/api/v3/activities/${object_id}`, {
            headers: { 'Authorization': `Bearer ${accessToken}` }
        });
        
        if (!activityResponse.ok) {
            console.error(`Failed to fetch Strava activity ${object_id} (HTTP ${activityResponse.status})`);
            return;
        }
        
        const activity = await activityResponse.json();
        
        // Only process runs
        if (activity.type !== 'Run') {
            console.log(`Activity ${object_id} is ${activity.type}, not a Run, skipping`);
            return;
        }
        
        // Reject manual entries - only GPS-tracked runs count
        if (activity.manual) {
            console.log(`🚫 Activity ${object_id} rejected: manual entry (only GPS-tracked runs accepted)`);
            return;
        }
        
        // Pace check: reject runs faster than 4:00/mile (likely driving/cheating)
        const distanceMeters = activity.distance || 0;
        const movingTimeSec = activity.moving_time || 0;
        if (distanceMeters > 0 && movingTimeSec > 0) {
            const paceMinPerMile = (movingTimeSec / 60) / (distanceMeters / 1609.34);
            if (paceMinPerMile < 4.0) {
                console.log(`🚫 Activity ${object_id} rejected: pace ${paceMinPerMile.toFixed(1)} min/mi is faster than 4:00/mi limit (likely not a real run)`);
                return;
            }
        }
        
        const distanceMiles = distanceMeters / 1609.34; // meters to miles
        const goalMiles = runObjective ? runObjective.target_value : 0; // 0 if only in competition (no individual goal)
        
        console.log(`🏃 Run detected: ${distanceMiles.toFixed(2)} miles (goal: ${goalMiles} miles)`);
        
        // Use user's timezone to determine "today"
        const today = getTodayForTimezone(user.timezone);
        const isComplete = distanceMiles >= goalMiles;
        const runMiles = parseFloat(distanceMiles.toFixed(2));
        
        // Check if a run session already exists for today
        // Note: completed_count stores raw miles (e.g. 5.23) — the app reads this directly as todayRunDistance
        const { data: existingRunSession } = await supabase
            .from('objective_sessions')
            .select('id, completed_count')
            .eq('user_id', user.id)
            .eq('session_date', today)
            .eq('objective_type', 'run')
            .single();
        
        let sessionError;
        if (existingRunSession) {
            // Accumulate distance from multiple runs in the same day
            const newCompleted = parseFloat((existingRunSession.completed_count || 0)) + runMiles;
            const newRounded = parseFloat(newCompleted.toFixed(2));
            const { error } = await supabase
                .from('objective_sessions')
                .update({
                    completed_count: newRounded,
                    status: goalMiles > 0 && newRounded >= goalMiles ? 'completed' : (goalMiles === 0 ? 'completed' : 'pending')
                })
                .eq('id', existingRunSession.id);
            sessionError = error;
        } else {
            // Insert new run session for today
            const { error } = await supabase
                .from('objective_sessions')
                .insert({
                    user_id: user.id,
                    session_date: today,
                    objective_type: 'run',
                    target_count: goalMiles,
                    completed_count: runMiles,
                    status: isComplete ? 'completed' : 'pending',
                    deadline: user.objective_deadline || '23:59:00',
                    payout_amount: user.missed_goal_payout || 0,
                    payout_triggered: false
                });
            sessionError = error;
        }
        
        if (sessionError) {
            console.error('Failed to save run session:', sessionError);
        } else if (isComplete) {
            console.log(`✅ Run objective met for user ${user.id}: ${distanceMiles.toFixed(2)} >= ${goalMiles} miles`);
        } else {
            console.log(`🏃 Run progress saved: ${distanceMiles.toFixed(2)}/${goalMiles} miles (not yet met)`);
        }
        
        // --- RACE MODE: Check if this user just won any active race ---
        try {
            const { data: raceParticipations } = await supabase
                .from('competition_participants')
                .select('competition_id, baseline_run, competitions!inner(id, name, status, scoring_type, run_target, buy_in_amount, start_date)')
                .eq('user_id', user.id)
                .eq('status', 'active');
            
            for (const rp of (raceParticipations || [])) {
                const comp = rp.competitions;
                if (!comp || comp.status !== 'active' || comp.scoring_type !== 'race') continue;
                
                const raceTarget = parseFloat(comp.run_target) || 0;
                if (raceTarget <= 0) continue;
                
                // Get this user's total run miles in the competition date range
                const { data: raceSessions } = await supabase
                    .from('objective_sessions')
                    .select('completed_count, session_date')
                    .eq('user_id', user.id)
                    .eq('objective_type', 'run')
                    .gte('session_date', comp.start_date);
                
                let totalMiles = 0;
                for (const rs of (raceSessions || [])) {
                    let miles = parseFloat(rs.completed_count) || 0;
                    if (rs.session_date === comp.start_date) {
                        miles = Math.max(0, miles - (rp.baseline_run || 0));
                    }
                    totalMiles += miles;
                }
                
                if (totalMiles >= raceTarget) {
                    console.log(`🏁 RACE WON! User ${user.id} hit ${totalMiles.toFixed(2)}/${raceTarget} miles in "${comp.name}"`);
                    
                    // Get all participants for payout
                    const { data: allParticipants } = await supabase
                        .from('competition_participants')
                        .select('user_id, buy_in_amount')
                        .eq('competition_id', comp.id)
                        .eq('status', 'active');
                    
                    const buyIn = parseFloat(comp.buy_in_amount) || 0;
                    const poolCents = Math.round(buyIn * 100) * (allParticipants?.length || 0);
                    
                    // Award pool to winner
                    if (poolCents > 0) {
                        const { data: winnerUser } = await supabase.from('users').select('balance_cents').eq('id', user.id).single();
                        const newBal = (winnerUser?.balance_cents || 0) + poolCents;
                        await supabase.from('users').update({ balance_cents: newBal }).eq('id', user.id);
                        console.log(`💰 Race payout: $${(poolCents/100).toFixed(2)} to ${user.id}`);
                    }
                    
                    // Mark competition completed
                    await supabase.from('competitions').update({
                        status: 'completed',
                        winner_user_id: user.id,
                        completed_at: new Date().toISOString(),
                        payout_completed: poolCents > 0
                    }).eq('id', comp.id);
                    
                    // Send race emails
                    const { data: winnerData } = await supabase.from('users').select('full_name').eq('id', user.id).single();
                    const winnerName = winnerData?.full_name || 'Unknown';
                    
                    for (const p of (allParticipants || [])) {
                        const { data: pUser } = await supabase.from('users').select('email, full_name').eq('id', p.user_id).single();
                        if (!pUser?.email) continue;
                        
                        const isWinner = p.user_id === user.id;
                        const subject = isWinner 
                            ? `🏁 You won the "${comp.name}" race!`
                            : `🏁 "${comp.name}" race is over`;
                        const body = isWinner
                            ? `Congratulations ${pUser.full_name || 'Champion'}! You finished first in "${comp.name}" with ${totalMiles.toFixed(1)} miles!${poolCents > 0 ? ` $${(poolCents/100).toFixed(2)} has been added to your RunMatch balance.` : ''}`
                            : `${winnerName} finished the "${comp.name}" race first with ${totalMiles.toFixed(1)}/${raceTarget} miles.${poolCents > 0 ? ` The $${(poolCents/100).toFixed(2)} pool has been awarded to the winner.` : ''}`;
                        
                        try {
                            await emailTransporter.sendMail({
                                from: `"RunMatch" <${process.env.SMTP_USER || 'connect@runmatch.io'}>`,
                                to: pUser.email,
                                subject,
                                text: body,
                                html: `<div style="font-family:sans-serif;max-width:500px;margin:0 auto;padding:20px"><h2 style="color:#d9a600">${subject}</h2><p>${body}</p><p style="color:#888;font-size:12px;margin-top:30px">— RunMatch | Bet on a Better You</p></div>`
                            });
                        } catch (emailErr) {
                            console.error('Race email error:', emailErr.message);
                        }
                    }
                }
            }
        } catch (raceErr) {
            console.error('Race check error (non-fatal):', raceErr.message);
        }
        
    } catch (error) {
        console.error('Strava webhook processing error:', error);
    }
});

// Check Strava connection status
app.get('/strava/status/:userId', optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: user } = await supabase
            .from('users')
            .select('strava_connection_id')
            .eq('id', userId)
            .single();
        
        if (!user?.strava_connection_id) {
            return res.json({ connected: false });
        }
        
        const { data: stravaConn } = await supabase
            .from('strava_connections')
            .select('athlete_name, connected_at')
            .eq('id', user.strava_connection_id)
            .single();
        
        res.json({
            connected: true,
            athleteName: stravaConn?.athlete_name || 'Connected',
            connectedAt: stravaConn?.connected_at
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Disconnect Strava
app.delete('/strava/disconnect/:userId', optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Find the user's strava connection to get the access token
        const { data: user } = await supabase
            .from('users')
            .select('strava_connection_id')
            .eq('id', userId)
      .single();
    
        if (user?.strava_connection_id) {
            // Get the connection record for the access token
            const { data: conn } = await supabase
                .from('strava_connections')
                .select('access_token, refresh_token, token_expires_at, strava_user_id')
                .eq('id', user.strava_connection_id)
                .single();
            
            if (conn) {
                // Refresh token if expired before deauthorizing
                let accessToken = conn.access_token;
                if (conn.token_expires_at && new Date(conn.token_expires_at * 1000) < new Date()) {
                    try {
                        const refreshResp = await fetch('https://www.strava.com/oauth/token', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                client_id: process.env.STRAVA_CLIENT_ID,
                                client_secret: process.env.STRAVA_CLIENT_SECRET,
                                grant_type: 'refresh_token',
                                refresh_token: conn.refresh_token
                            })
                        });
                        const refreshData = await refreshResp.json();
                        if (refreshData.access_token) {
                            accessToken = refreshData.access_token;
                        }
                    } catch (refreshErr) {
                        console.log('⚠️ Token refresh failed during deauth, proceeding with existing token');
                    }
                }
                
                // Revoke access at Strava's API (deauthorize)
                try {
                    await fetch('https://www.strava.com/oauth/deauthorize', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                        body: `access_token=${accessToken}`
                    });
                    console.log(`🔓 Strava access revoked for athlete ${conn.strava_user_id}`);
                } catch (deauthErr) {
                    console.log('⚠️ Strava deauthorize API call failed, cleaning up locally anyway');
                }
                
                // Delete the strava_connections record
                await supabase
                    .from('strava_connections')
                    .delete()
                    .eq('id', user.strava_connection_id);
            }
        }
        
        // Remove link from user
        await supabase
            .from('users')
            .update({ strava_connection_id: null })
            .eq('id', userId);
        
        console.log(`🔌 Strava disconnected for user ${userId}`);
        res.json({ success: true });
        
    } catch (error) {
        console.error('❌ Strava disconnect error:', error);
        res.status(500).json({ error: error.message });
    }
});

// (app.listen moved to end of file — all routes must be registered first)

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
        business_profile: { url: "https://runmatch.io" },
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
        refresh_url: `https://app.runmatch.io/invite?code=${inviteCode}`,
        return_url: `https://app.runmatch.io/invite?setup_complete=true`,
        type: 'account_onboarding',
      });
      
      res.json({ onboardingUrl: accountLink.url });
    } else {
      res.json({ success: true, message: 'Recipient already set up' });
    }
  } catch (err) {
    console.error('Error in recipient onboarding:', err);
    res.status(500).json({ error: 'Failed to complete onboarding' });
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
        // Step 1: Transfer from RunMatch platform to connected account
        const transfer = await stripe.transfers.create({
          amount: rule.fixed_amount_cents,
          currency: 'usd',
          destination: rule.recipient.stripe_connect_account_id,
          description: `RunMatch missed goal payout from ${rule.payer.name}`,
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
            description: 'RunMatch instant payout'
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
              description: 'RunMatch standard payout'
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
            body: `💰 You received $${amountFormatted} from ${rule.payer.name} for missing their RunMatch fitness goal. ${timeMessage}`
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
      business_profile: { url: "https://runmatch.io" },
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
          body: `✅ RunMatch setup complete! You will receive $${amountFormatted} to your ${payoutMethodName} each time ${payer?.full_name || "your partner"} misses their fitness goal.`
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
      error: "Failed to complete setup" 
    });
  }
});
// Debug database endpoint removed for security


// Manual trigger payout (for when objective is missed)
app.post("/users/:userId/trigger-payout", optionalAuth, async (req, res) => {
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
                        description: `RunMatch payout from ${user.email} - missed objective`,
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
            .update({ balance_cents: newBalance, active_balance_cents: newBalance })
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
app.post("/objectives/create-daily-sessions", requireCronSecret, async (req, res) => {
    try {
        // Get all users with committed payouts
        const { data: users, error: usersError } = await supabase
            .from("users")
            .select("id, timezone, objective_type, objective_count, objective_deadline, missed_goal_payout")
            .eq("payout_committed", true);
        
        if (usersError) {
            return res.status(400).json({ error: usersError.message });
        }
        
        const results = [];
        
        for (const user of users || []) {
            // Get ENABLED objectives from user_objectives table
            const { data: enabledObjectives } = await supabase
                .from("user_objectives")
                .select("objective_type, target_value")
                .eq("user_id", user.id)
                .eq("enabled", true);
            
            // Determine which objectives to create sessions for
            let objectivesToCreate = [];
            if (enabledObjectives && enabledObjectives.length > 0) {
                // Use user_objectives table (modern multi-objective)
                objectivesToCreate = enabledObjectives.map(obj => ({
                    type: obj.objective_type,
                    target: obj.target_value
                }));
            } else if (user.objective_count && user.objective_count > 0) {
                // Legacy fallback: no user_objectives rows, use users table
                objectivesToCreate = [{
                    type: user.objective_type || "pushups",
                    target: user.objective_count
                }];
            }
            
            if (objectivesToCreate.length === 0) continue;
            
            const today = getTodayForTimezone(user.timezone);
            
            // Check existing sessions for today
            const { data: existing } = await supabase
                .from("objective_sessions")
                .select("objective_type")
                .eq("user_id", user.id)
                .eq("session_date", today);
            
            const existingTypes = new Set((existing || []).map(s => s.objective_type));
            
            // Create sessions for each enabled objective that doesn't have one yet
            for (const obj of objectivesToCreate) {
                if (existingTypes.has(obj.type)) continue;
                
            const { data: session, error: sessionError } = await supabase
                .from("objective_sessions")
                .insert({
                    user_id: user.id,
                    session_date: today,
                        objective_type: obj.type,
                        target_count: obj.target,
                    completed_count: 0,
                        deadline: parseDeadlineTime(user.objective_deadline),
                    status: "pending",
                    payout_amount: user.missed_goal_payout || 0
                })
                .select()
                .single();
            
            if (!sessionError) {
                    results.push({ userId: user.id, sessionId: session.id, type: obj.type });
                }
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
app.get("/objectives/today/:userId", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Use user's timezone to determine "today"
        const { data: userData } = await supabase.from("users").select("timezone").eq("id", userId).single();
        const today = getTodayForTimezone(userData?.timezone);
        
        // Fetch ALL sessions for today (pushups + run can both exist)
        const { data: sessions, error } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today);
        
        if (error) {
            return res.status(400).json({ error: error.message });
        }
        
        // Return both the array and a single session for backwards compat
        res.json({ 
            session: sessions && sessions.length > 0 ? sessions[0] : null,
            sessions: sessions || [],
            date: today 
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Mark objective as completed
app.post("/objectives/complete/:userId", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        const { completedCount, objectiveType = "pushups" } = req.body;
        
        const { data: userData } = await supabase.from("users").select("timezone").eq("id", userId).single();
        const today = getTodayForTimezone(userData?.timezone);
        
        // Get today's session for this objective type
        let { data: session, error: getError } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today)
            .eq("objective_type", objectiveType)
            .single();
        
        // If no session for this type, try to create one
        if (getError && getError.code === "PGRST116") {
            // Get user's objective settings
            const { data: objective } = await supabase
                .from("user_objectives")
                .select("target_value")
                .eq("user_id", userId)
                .eq("objective_type", objectiveType)
                .eq("enabled", true)
                .single();
            
            const { data: user } = await supabase
                .from("users")
                .select("objective_deadline, missed_goal_payout")
                .eq("id", userId)
                .single();
            
            if (objective) {
                // Create session
                const { data: newSession } = await supabase
                    .from("objective_sessions")
                    .insert({
                        user_id: userId,
                        session_date: today,
                        objective_type: objectiveType,
                        target_count: objective.target_value,
                        completed_count: 0,
                        deadline: parseDeadlineTime(user?.objective_deadline),
                        status: "pending",
                        payout_amount: user?.missed_goal_payout || 0
                    })
                    .select()
                    .single();
                session = newSession;
            } else {
                return res.status(404).json({ error: `No enabled ${objectiveType} objective found` });
            }
        }
        
        // Validate: cap increment to prevent score manipulation
        const currentCount = session.completed_count || 0;
        const requestedCount = completedCount || 0;
        const delta = requestedCount - currentCount;
        if (delta > 200) {
            console.log(`🚫 Suspicious pushup delta: ${delta} for user ${userId} (current: ${currentCount}, requested: ${requestedCount})`);
            return res.status(400).json({ error: 'Invalid count — too large of an increase in one sync.' });
        }
        
        const newCount = Math.max(requestedCount, currentCount);
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
        
        console.log(`✅ ${objectiveType} progress: ${newCount}/${session.target_count} for user ${userId}`);
        
        res.json({ 
            success: true, 
            completed: isComplete,
            objectiveType: objectiveType,
            session: updated 
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Reset all sessions at midnight (mark missed ones, create new ones)
app.post("/objectives/midnight-reset", requireCronSecret, async (req, res) => {
    try {
        // Get all users with committed payouts
        const { data: users } = await supabase
            .from("users")
            .select("id, timezone, objective_type, objective_count, objective_deadline, missed_goal_payout")
            .eq("payout_committed", true);
        
        let missedCount = 0;
        const newSessions = [];
        
        for (const user of users || []) {
            const userTz = user.timezone || "America/New_York";
            const userToday = getTodayForTimezone(userTz);
            const userYesterday = new Date(new Date(userToday + "T12:00:00").getTime() - 86400000).toISOString().slice(0, 10);
            
            // Mark any pending sessions from user's yesterday as missed
            const { data: missed } = await supabase
                .from("objective_sessions")
                .update({ status: "missed" })
                .eq("user_id", user.id)
                .eq("session_date", userYesterday)
                .in("status", ["pending"])
                .select();
            missedCount += (missed?.length || 0);
            
            // Create new session for user's today if it doesn't exist
            const { data: existing } = await supabase
                .from("objective_sessions")
                .select("id")
                .eq("user_id", user.id)
                .eq("session_date", userToday)
                .limit(1);
            
            if (!existing || existing.length === 0) {
                const { data: newSession } = await supabase
                    .from("objective_sessions")
                    .insert({
                        user_id: user.id,
                        session_date: userToday,
                        objective_type: user.objective_type || "pushups",
                        target_count: user.objective_count || 50,
                        completed_count: 0,
                        deadline: parseDeadlineTime(user.objective_deadline),
                        status: "pending",
                        payout_amount: user.missed_goal_payout || 0
                    })
                    .select()
                    .single();
                
                if (newSession) newSessions.push(newSession.id);
            }
        }
        
        res.json({
            missedYesterday: missedCount,
            newSessionsCreated: newSessions.length,
            date: new Date().toISOString()
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== SIGN IN ENDPOINT ==========
app.post("/signin", authLimiter, async (req, res) => {
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

        // Fetch user's objectives from user_objectives table
        const { data: userObjectives } = await supabase
            .from("user_objectives")
            .select("objective_type, target_value, enabled")
            .eq("user_id", user.id);

        // Build objectives map
        const objectivesMap = {};
        if (userObjectives) {
            userObjectives.forEach(obj => {
                objectivesMap[obj.objective_type] = {
                    target: obj.target_value,
                    enabled: obj.enabled
                };
            });
        }

        // Fetch today's session progress
        const today = new Date().toISOString().split("T")[0];
        const { data: todaySessions } = await supabase
            .from("objective_sessions")
            .select("objective_type, completed_count, target_count, status")
            .eq("user_id", user.id)
            .eq("session_date", today);

        // Build today's progress
        let todayProgress = {};
        if (todaySessions && todaySessions.length > 0) {
            todaySessions.forEach(session => {
                todayProgress[session.objective_type] = {
                    completed: session.completed_count,
                    target: session.target_count,
                    status: session.status
                };
            });
        }

        // Check if Strava is connected
        const stravaConnected = !!user.strava_connection_id;

        // Generate auth token
        const token = generateToken(user.id, user.email);
        
        // Return full user data
        res.json({
            message: "Sign-in successful",
            token,
            user: {
                id: user.id,
                full_name: user.full_name,
                email: user.email,
                phone: user.phone,
                balance_cents: user.balance_cents,
                timezone: user.timezone,
                // Objective settings
                objective_type: user.objective_type || "pushups",
                objective_count: user.objective_count,
                objective_schedule: user.objective_schedule || "daily",
                objective_deadline: parseDeadlineTime(user.objective_deadline),
                // Multi-objective support (legacy fallback only if NO user_objectives rows exist)
                pushups_enabled: userObjectives && userObjectives.length > 0 
                    ? (objectivesMap.pushups?.enabled ?? false)
                    : (user.objective_count > 0),
                pushups_count: objectivesMap.pushups?.target ?? user.objective_count ?? 50,
                run_enabled: objectivesMap.run?.enabled ?? false,
                run_distance: objectivesMap.run?.target ?? 2.0,
                // Strava
                strava_connected: stravaConnected,
                strava_connection_id: user.strava_connection_id,
                // Payout settings
                missed_goal_payout: user.missed_goal_payout,
                payout_destination: user.payout_destination,
                payout_committed: user.payout_committed,
                destination_committed: user.destination_committed,
                committed_destination: user.committed_destination,
                custom_recipient_id: user.custom_recipient_id,
                // Lock status
                settings_locked_until: user.settings_locked_until,
                // Today's progress
                today_progress: todayProgress,
                // Stripe
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
            refresh_url: refreshUrl || "https://app.runmatch.io/invite?refresh=true",
            return_url: returnUrl || "https://app.runmatch.io/invite?success=true",
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
// Settings Lock - Get user's settings lock state
// -----------------------------------------------------------------------------
app.get("/users/:userId/settings-lock", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        const { data: user, error } = await supabase
            .from("users")
            .select("settings_locked_until")
            .eq("id", userId)
            .single();
        
        if (error) {
            return res.status(400).json({ error: error.message });
        }
        
        res.json({ 
            settings_locked_until: user?.settings_locked_until || null 
        });
    } catch (error) {
        console.error("Get settings lock error:", error);
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Objective Settings - Update user objective configuration
// -----------------------------------------------------------------------------
// GET objectives settings (using normalized user_objectives table)
app.get("/objectives/settings/:userId", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Get user settings (including legacy fields for fallback)
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("objective_schedule, objective_deadline, missed_goal_payout, timezone, settings_locked_until, objective_count, objective_type")
            .eq("id", userId)
            .single();
        
        if (userError) {
            console.error("Get user error:", userError);
            return res.status(400).json({ error: userError.message });
        }
        
        // Try to get objectives from new user_objectives table
        let objectives = [];
        try {
            const { data: objData, error: objError } = await supabase
                .from("user_objectives")
                .select("objective_type, target_value, enabled")
                .eq("user_id", userId);
            
            if (!objError && objData) {
                objectives = objData;
            }
        } catch (e) {
            // Table might not exist yet, that's ok - use legacy fallback
            console.log("user_objectives table not available, using legacy fallback");
        }
        
        // Build response with objectives array + individual flags for backwards compat
        const objMap = {};
        (objectives || []).forEach(obj => {
            objMap[obj.objective_type] = { target: obj.target_value, enabled: obj.enabled };
        });
        
        // Determine pushups state from user_objectives table
        // Legacy fallback ONLY applies if user has zero rows in user_objectives (never migrated)
        let pushupsEnabled = objMap.pushups?.enabled ?? false;
        let pushupsCount = objMap.pushups?.target ?? 50;
        
        const hasAnyObjectives = objectives && objectives.length > 0;
        if (!hasAnyObjectives && user.objective_count && user.objective_count > 0) {
            // User has NO rows in user_objectives at all — use legacy data
            pushupsEnabled = true;
            pushupsCount = user.objective_count;
            console.log(`Legacy fallback: user ${userId} has objective_count=${user.objective_count} (no user_objectives rows)`);
        }
        
        res.json({
            // New format: objectives array
            objectives: objectives || [],
            // Backwards compatible format (with legacy fallback)
            pushups_enabled: pushupsEnabled,
            pushups_count: pushupsCount,
            run_enabled: objMap.run?.enabled ?? false,
            run_distance: objMap.run?.target ?? 2.0,
            // Schedule settings (still on users table)
            objective_schedule: user.objective_schedule ?? "daily",
            objective_deadline: user.objective_deadline || null,
            missed_goal_payout: user.missed_goal_payout ?? 0,
            timezone: user.timezone,
            settings_locked_until: user.settings_locked_until
        });
    } catch (error) {
        console.error("Error getting settings:", error);
        res.status(500).json({ error: error.message });
    }
});

app.post("/objectives/settings/:userId", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        const { 
            // New multi-objective fields (using user_objectives table)
            pushups_enabled, pushups_count, run_enabled, run_distance,
            // Legacy fields (still supported on users table)
            objective_type, objective_count, 
            objective_schedule, objective_deadline, 
            missed_goal_payout, timezone, settings_locked_until 
        } = req.body;
        
        // Handle objective upserts to user_objectives table
        if (typeof pushups_enabled === "boolean" || typeof pushups_count === "number") {
            const targetValue = pushups_count ?? 50;
            const enabled = pushups_enabled ?? false;
            
            await supabase
                .from("user_objectives")
                .upsert({
                    user_id: userId,
                    objective_type: "pushups",
                    target_value: targetValue,
                    enabled: enabled,
                    updated_at: new Date().toISOString()
                }, { onConflict: "user_id,objective_type" });
            
            console.log(`Pushups ${enabled ? "enabled" : "disabled"}: ${targetValue} for user ${userId}`);
        }
        
        if (typeof run_enabled === "boolean" || typeof run_distance === "number") {
            const targetValue = run_distance ?? 2.0;
            const enabled = run_enabled ?? true;
            
            await supabase
                .from("user_objectives")
                .upsert({
                    user_id: userId,
                    objective_type: "run",
                    target_value: targetValue,
                    enabled: enabled,
                    updated_at: new Date().toISOString()
                }, { onConflict: "user_id,objective_type" });
            
            console.log(`Run ${enabled ? "enabled" : "disabled"}: ${targetValue} mi for user ${userId}`);
        }
        
        // Update user table for schedule/deadline/payout settings
        const updateData = {};
        if (objective_type) updateData.objective_type = objective_type;
        if (objective_count) updateData.objective_count = objective_count;
        if (objective_schedule) updateData.objective_schedule = objective_schedule;
        if ('objective_deadline' in req.body) updateData.objective_deadline = objective_deadline;
        if (typeof missed_goal_payout === "number") {
            // Cap payout to user's current balance
            const { data: balUser } = await supabase.from("users").select("balance_cents").eq("id", userId).single();
            const maxPayout = balUser ? (balUser.balance_cents || 0) / 100 : 0;
            const cappedPayout = Math.min(missed_goal_payout, maxPayout);
            updateData.missed_goal_payout = cappedPayout;
            if (cappedPayout > 0) updateData.payout_committed = true;
            if (missed_goal_payout > maxPayout && missed_goal_payout > 0) {
                console.log(`⚠️ Payout capped: requested $${missed_goal_payout}, max $${maxPayout} for user ${userId}`);
            }
        }
        if (timezone) updateData.timezone = timezone;
        // Handle settings_locked_until - allow null to clear the lock
        if ('settings_locked_until' in req.body) {
            updateData.settings_locked_until = settings_locked_until;  // Can be null to clear
        }
        
        // 1. Update user settings (only if there are user-level fields to update)
        let userData = null;
        if (Object.keys(updateData).length > 0) {
            const { data, error: userError } = await supabase
            .from("users")
            .update(updateData)
            .eq("id", userId)
            .select()
            .single();
        
        if (userError) {
            console.error("User update error:", userError);
            return res.status(400).json({ error: userError.message });
            }
            userData = data;
        } else {
            // No user-level changes (e.g. pushups/run only) — fetch current user data
            // so session logic below can still reference it
            const { data } = await supabase
                .from("users")
                .select()
                .eq("id", userId)
                .single();
            userData = data;
        }
        
        // If user doesn't exist at all, we're done (pushups/run still saved above)
        if (!userData) {
            return res.json({ success: true, user: null, session: null });
        }
        
        // 2. Update/create today's sessions for ENABLED objectives only
        const today = getTodayForTimezone(userData.timezone);
        const newDeadline = ('objective_deadline' in req.body) ? objective_deadline : (userData.objective_deadline || "09:00:00");
        const newPayoutAmount = (typeof missed_goal_payout === "number") ? missed_goal_payout : (userData.missed_goal_payout || 0);
        
        // Get all enabled objectives for this user
        const { data: enabledObjectives } = await supabase
            .from("user_objectives")
            .select("objective_type, target_value, enabled")
            .eq("user_id", userId)
            .eq("enabled", true);
        
        // Get all existing sessions for today
        const { data: existingSessions } = await supabase
            .from("objective_sessions")
            .select("id, objective_type, completed_count, status")
            .eq("user_id", userId)
            .eq("session_date", today);
        
        const existingByType = {};
        (existingSessions || []).forEach(s => { existingByType[s.objective_type] = s; });
        
        let sessionResults = [];
        for (const obj of (enabledObjectives || [])) {
            const existing = existingByType[obj.objective_type];
            if (existing) {
                // Update existing session with new deadline/payout (preserve completed_count)
                const { data: updated } = await supabase
                    .from("objective_sessions")
                    .update({
                        target_count: obj.target_value,
                        deadline: newDeadline,
                        payout_amount: newPayoutAmount
                    })
                    .eq("id", existing.id)
                    .select()
                    .single();
                if (updated) sessionResults.push(updated);
            } else {
                // Create new session for this objective type
                const { data: created } = await supabase
                .from("objective_sessions")
                .insert({
                    user_id: userId,
                    session_date: today,
                        objective_type: obj.objective_type,
                        target_count: obj.target_value,
                    deadline: newDeadline,
                    payout_amount: newPayoutAmount,
                    completed_count: 0,
                    status: "pending",
                    payout_triggered: false
                })
                .select()
                .single();
                if (created) sessionResults.push(created);
            }
        }
        
        // Grace period: if deadline already passed today, pre-mark sessions so cron won't deduct
        if (newDeadline && newDeadline !== "null") {
            const userTz = userData.timezone || "America/New_York";
            const currentTime = new Date().toLocaleTimeString("en-US", { 
                hour: "2-digit", minute: "2-digit", hour12: false, timeZone: userTz 
            }).replace(/^24:/, "00:");
            const deadlineHHMM = parseDeadlineTime(newDeadline);
            
            if (currentTime > deadlineHHMM) {
                for (const sess of sessionResults) {
                    if (!sess.payout_triggered && sess.status === "pending") {
                        await supabase.from("objective_sessions").update({
                            status: "grace",
                            payout_triggered: true
                        }).eq("id", sess.id);
                    }
                }
                console.log(`⏰ Deadline ${deadlineHHMM} already passed (now ${currentTime} in ${userTz}) — today's sessions marked as grace for user ${userId}`);
            }
        }
        
        console.log("Settings saved for user", userId, "- sessions:", sessionResults.length);
        res.json({ success: true, user: userData, session: sessionResults[0] || null, sessions: sessionResults });
        
    } catch (error) {
        console.error("Error in /objectives/settings:", error);
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Ensure Today Session - Create session for user if it does not exist
// -----------------------------------------------------------------------------
app.post("/objectives/ensure-session/:userId", optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Get user settings
        const { data: user, error: userError } = await supabase
            .from("users")
            .select("timezone, objective_deadline, missed_goal_payout")
            .eq("id", userId)
            .single();
        
        if (userError || !user) {
            return res.status(404).json({ error: "User not found" });
        }
        
        const today = getTodayForTimezone(user.timezone);
        
        // Get enabled objectives from user_objectives table
        const { data: enabledObjectives } = await supabase
            .from("user_objectives")
            .select("objective_type, target_value")
            .eq("user_id", userId)
            .eq("enabled", true);
        
        if (!enabledObjectives || enabledObjectives.length === 0) {
            return res.json({ sessions: [], created: false, message: "No enabled objectives" });
        }
        
        // Check existing sessions for today
        const { data: existingSessions } = await supabase
            .from("objective_sessions")
            .select("*")
            .eq("user_id", userId)
            .eq("session_date", today);
        
        const existingTypes = new Set((existingSessions || []).map(s => s.objective_type));
        const sessionsToCreate = [];
        
        // Create sessions for objectives that don't have one yet
        for (const obj of enabledObjectives) {
            if (!existingTypes.has(obj.objective_type)) {
                sessionsToCreate.push({
                user_id: userId,
                session_date: today,
                objective_type: obj.objective_type,
                target_count: obj.target_value,
                completed_count: 0,
                deadline: parseDeadlineTime(user.objective_deadline),
                status: "pending",
                payout_amount: user.missed_goal_payout || 0
                });
            }
        }
        
        let newSessions = [];
        if (sessionsToCreate.length > 0) {
            const { data: created, error: createError } = await supabase
                .from("objective_sessions")
                .insert(sessionsToCreate)
                .select();
            
            if (createError) {
                console.error("Session create error:", createError);
            }
            newSessions = created || [];
        }
        
        res.json({ 
            sessions: [...(existingSessions || []), ...newSessions], 
            created: newSessions.length > 0,
            newCount: newSessions.length
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Admin endpoint: Get charity payout totals
app.get("/admin/charity-totals", requireCronSecret, async (req, res) => {
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
app.post("/admin/charity-payout/:charityName", requireCronSecret, async (req, res) => {
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

// -----------------------------------------------------------------------------
// Competitions (Compete Feature)
// -----------------------------------------------------------------------------

// Create a competition (LOBBY — no money deducted, status = pending)
app.post('/compete/create', optionalAuth, async (req, res) => {
    try {
        const { userId, name, objectiveType, scoringType, durationDays, buyInAmount, targetValue, pushupTarget, runTarget } = req.body;
        
        if (!userId || !name || !objectiveType) {
            return res.status(400).json({ error: 'Missing required fields: userId, name, objectiveType' });
        }
        
        const isRace = scoringType === 'race';
        const buyIn = parseFloat(buyInAmount) || 0;
        const days = isRace ? null : (parseInt(durationDays) || 7);
        
        if (buyIn > 0) {
            const { data: creator } = await supabase
                .from('users').select('balance_cents').eq('id', userId).single();
            const creatorBalance = (creator?.balance_cents || 0) / 100;
            if (creatorBalance < buyIn) {
                return res.status(400).json({ error: `Insufficient balance. You have $${creatorBalance.toFixed(2)} but the buy-in is $${buyIn}. Deposit funds first.` });
            }
        }
        
        // Generate 6-char invite code
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let inviteCode = '';
        for (let i = 0; i < 6; i++) {
            inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        // Create in PENDING status — dates are placeholders, set properly on start
        const today = new Date();
        const startDate = today.toISOString().split('T')[0];
        const endDate = new Date(today.getTime() + days * 86400000).toISOString().split('T')[0];
        
        const { data: competition, error: createError } = await supabase
            .from('competitions')
            .insert({
                creator_user_id: userId,
                name: name.trim(),
                objective_type: isRace ? 'run' : objectiveType,
                scoring_type: scoringType || 'consistency',
                start_date: startDate,
                end_date: endDate,
                status: 'pending',
                invite_code: inviteCode,
                target_value: targetValue || 0,
                pushup_target: pushupTarget || 0,
                run_target: runTarget || 0,
                buy_in_amount: buyIn,
                duration_days: days
            })
            .select()
            .single();
        
        if (createError) {
            console.error('Competition create error:', createError);
            return res.status(500).json({ error: createError.message });
        }
        
        // Auto-join the creator as first participant (NO money deducted yet)
        await supabase
            .from('competition_participants')
            .insert({
                competition_id: competition.id,
                user_id: userId,
                status: 'active',
                buy_in_locked: false,
                buy_in_amount: buyIn
            });
        
        console.log(`🏆 Competition created (PENDING): "${name}" (${inviteCode}) by ${userId}`);
        
        const compType = isRace ? 'Race' : (scoringType === 'cumulative' ? 'Total Count' : 'Days Completed');
        const buyInLabel = buyIn > 0 ? `$${buyIn} buy-in` : 'Free';
        notifySlack(`🏆 *New Competition Created*\n• Name: ${name.trim()}\n• Type: ${compType} (${isRace ? 'run' : objectiveType})\n• Stakes: ${buyInLabel}\n• Code: ${inviteCode}`);
        
        res.json({ success: true, competition, inviteCode });
        
    } catch (error) {
        console.error('Competition create error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Verify/preview a competition by code (before joining)
app.get('/compete/verify/:code', async (req, res) => {
    try {
        const code = req.params.code.toUpperCase();
        
        const { data: competition, error } = await supabase
            .from('competitions')
            .select('*, creator:users!creator_user_id(full_name, email)')
            .eq('invite_code', code)
            .single();
        
        if (error || !competition) {
            return res.status(404).json({ error: 'Competition not found' });
        }
        
        // Get participant count
        const { count } = await supabase
            .from('competition_participants')
            .select('*', { count: 'exact', head: true })
            .eq('competition_id', competition.id)
            .eq('status', 'active');
        
        res.json({
            id: competition.id,
            name: competition.name,
            objectiveType: competition.objective_type,
            scoringType: competition.scoring_type,
            startDate: competition.start_date,
            endDate: competition.end_date,
            status: competition.status,
            targetValue: competition.target_value || 0,
            pushupTarget: competition.pushup_target || 0,
            runTarget: competition.run_target || 0,
            buyInAmount: competition.buy_in_amount,
            durationDays: competition.duration_days || 7,
            creatorUserId: competition.creator_user_id,
            creatorName: competition.creator?.full_name || 'Unknown',
            participantCount: count || 0
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Join a competition
app.post('/compete/join', optionalAuth, async (req, res) => {
    try {
        const { userId, code } = req.body;
        
        if (!userId || !code) {
            return res.status(400).json({ error: 'Missing userId or code' });
        }
        
        const { data: competition, error: findError } = await supabase
            .from('competitions')
            .select('*')
            .eq('invite_code', code.toUpperCase())
            .single();
        
        if (findError || !competition) {
            return res.status(404).json({ error: 'Competition not found' });
        }
        
        if (competition.status === 'completed') {
            return res.status(400).json({ error: 'This competition has already ended' });
        }
        
        if (competition.status === 'active') {
            return res.status(400).json({ error: 'This competition has already started. You can only join before it begins.' });
        }
        
        // Check if already joined
        const { data: existing } = await supabase
            .from('competition_participants')
            .select('id')
            .eq('competition_id', competition.id)
            .eq('user_id', userId)
            .single();
        
        if (existing) {
            return res.status(400).json({ error: 'You have already joined this competition' });
        }
        
        const buyIn = parseFloat(competition.buy_in_amount) || 0;
        
        if (buyIn > 0) {
            const { data: joiner } = await supabase
                .from('users').select('balance_cents').eq('id', userId).single();
            const joinerBalance = (joiner?.balance_cents || 0) / 100;
            if (joinerBalance < buyIn) {
                return res.status(400).json({ error: `Insufficient balance. You have $${joinerBalance.toFixed(2)} but the buy-in is $${buyIn}. Deposit funds first.` });
            }
        }
        
        // Join the LOBBY — NO money deducted yet (happens when creator starts)
        const { error: joinError } = await supabase
            .from('competition_participants')
            .insert({
                competition_id: competition.id,
                user_id: userId,
                status: 'active',
                buy_in_locked: false,
                buy_in_amount: buyIn
            });
        
        if (joinError) {
            console.error('Competition join error:', joinError);
            return res.status(500).json({ error: joinError.message });
        }
        
        console.log(`🏆 User ${userId} joined lobby for "${competition.name}" (${code})`);
        res.json({ success: true, competitionId: competition.id, name: competition.name });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// START a competition (creator only — deducts all balances, sets active, starts timer)
app.post('/compete/start', optionalAuth, async (req, res) => {
    try {
        const { userId, competitionId } = req.body;
        
        if (!userId || !competitionId) {
            return res.status(400).json({ error: 'Missing userId or competitionId' });
        }
        
        // Get competition
        const { data: comp, error: compErr } = await supabase
            .from('competitions')
            .select('*')
            .eq('id', competitionId)
            .single();
        
        if (compErr || !comp) {
            return res.status(404).json({ error: 'Competition not found' });
        }
        
        // Only the creator can start
        if (comp.creator_user_id !== userId) {
            return res.status(403).json({ error: 'Only the competition creator can start it' });
        }
        
        if (comp.status !== 'pending') {
            return res.status(400).json({ error: 'Competition has already been started' });
        }
        
        // Get all participants
        const { data: participants } = await supabase
            .from('competition_participants')
            .select('user_id, buy_in_amount')
            .eq('competition_id', competitionId)
            .eq('status', 'active');
        
        if (!participants || participants.length < 1) {
            return res.status(400).json({ error: 'No participants to start with' });
        }
        
        const buyIn = parseFloat(comp.buy_in_amount) || 0;
        
        // If paid competition, check ALL participants have sufficient balance
        if (buyIn > 0) {
            const insufficientUsers = [];
            for (const p of participants) {
                const { data: user } = await supabase
                    .from('users').select('balance_cents, full_name').eq('id', p.user_id).single();
                const balanceDollars = (user?.balance_cents || 0) / 100;
                if (balanceDollars < buyIn) {
                    insufficientUsers.push({
                        name: user?.full_name || 'Unknown',
                        userId: p.user_id,
                        balance: balanceDollars
                    });
                }
            }
            
            if (insufficientUsers.length > 0) {
                const names = insufficientUsers.map(u => u.name).join(', ');
                return res.status(400).json({
                    error: `Cannot start: ${names} ${insufficientUsers.length === 1 ? 'has' : 'have'} insufficient balance for the $${buyIn} buy-in.`,
                    insufficientUsers
                });
            }
            
            // Deduct buy-in from ALL participants
            for (const p of participants) {
                const buyInCents = Math.round(buyIn * 100);
                const { data: user } = await supabase
                    .from('users').select('balance_cents').eq('id', p.user_id).single();
                const newBalance = Math.max(0, (user?.balance_cents || 0) - buyInCents);
                await supabase.from('users').update({ balance_cents: newBalance }).eq('id', p.user_id);
                
                // Mark participant's buy-in as locked
                await supabase.from('competition_participants')
                    .update({ buy_in_locked: true })
                    .eq('competition_id', competitionId)
                    .eq('user_id', p.user_id);
                
                console.log(`🏆 Deducted $${buyIn} from ${p.user_id} (new: $${(newBalance/100).toFixed(2)})`);
            }
        }
        
        // Set start_date = today, end_date = today + duration_days, status = active
        const today = new Date();
        const isRaceComp = comp.scoring_type === 'race';
        const durationDays = comp.duration_days || (isRaceComp ? null : 7);
        const startDate = today.toISOString().split('T')[0];
        const endDate = durationDays ? new Date(today.getTime() + durationDays * 86400000).toISOString().split('T')[0] : null;
        
        const startedAt = new Date().toISOString();
        await supabase.from('competitions')
            .update({
                status: 'active',
                start_date: startDate,
                end_date: endDate,
                started_at: startedAt
            })
            .eq('id', competitionId);
        
        // Snapshot each participant's current-day counts as baselines
        for (const p of participants) {
            const { data: todaySessions } = await supabase
                .from('objective_sessions')
                .select('objective_type, completed_count')
                .eq('user_id', p.user_id)
                .eq('session_date', startDate);
            
            let bPushups = 0, bRun = 0;
            for (const s of (todaySessions || [])) {
                if (s.objective_type === 'pushups') bPushups = s.completed_count || 0;
                if (s.objective_type === 'run') bRun = parseFloat(s.completed_count) || 0;
            }
            
            await supabase.from('competition_participants')
                .update({ baseline_pushups: bPushups, baseline_run: bRun })
                .eq('competition_id', competitionId)
                .eq('user_id', p.user_id);
            
            if (bPushups > 0 || bRun > 0) {
                console.log(`📊 Baseline for ${p.user_id}: pushups=${bPushups}, run=${bRun}`);
            }
        }
        
        // Return updated balance for the requesting user
        const { data: updatedUser } = await supabase
            .from('users').select('balance_cents').eq('id', userId).single();
        
        const poolTotal = buyIn * participants.length;
        console.log(`🏆 Competition STARTED: "${comp.name}" | ${participants.length} players | Pool: $${poolTotal}`);
        
        res.json({
            success: true,
            startDate,
            endDate,
            participantCount: participants.length,
            poolTotal,
            newBalanceCents: updatedUser?.balance_cents ?? null
        });
        
    } catch (error) {
        console.error('Competition start error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Cancel/end a competition (creator only — refunds all participants)
app.post('/compete/cancel', optionalAuth, async (req, res) => {
    try {
        const { userId, competitionId } = req.body;
        
        if (!userId || !competitionId) {
            return res.status(400).json({ error: 'Missing userId or competitionId' });
        }
        
        const { data: comp, error: compErr } = await supabase
            .from('competitions')
            .select('*')
            .eq('id', competitionId)
            .single();
        
        if (compErr || !comp) {
            return res.status(404).json({ error: 'Competition not found' });
        }
        
        if (comp.creator_user_id !== userId) {
            return res.status(403).json({ error: 'Only the creator can cancel this competition' });
        }
        
        if (comp.status === 'completed') {
            return res.status(400).json({ error: 'Competition has already ended' });
        }
        
        // Refund all participants if buy-ins were locked (active competitions)
        if (comp.status === 'active') {
            const { data: participants } = await supabase
                .from('competition_participants')
                .select('user_id, buy_in_amount, buy_in_locked')
                .eq('competition_id', competitionId)
                .eq('status', 'active');
            
            for (const p of (participants || [])) {
                if (p.buy_in_locked && parseFloat(p.buy_in_amount) > 0) {
                    const refundCents = Math.round(parseFloat(p.buy_in_amount) * 100);
                    const { data: user } = await supabase
                        .from('users').select('balance_cents').eq('id', p.user_id).single();
                    const newBal = (user?.balance_cents || 0) + refundCents;
                    await supabase.from('users').update({ balance_cents: newBal }).eq('id', p.user_id);
                    console.log(`🏆 Refunded $${p.buy_in_amount} to ${p.user_id}`);
                }
            }
        }
        
        // Mark competition as cancelled
        await supabase.from('competitions')
            .update({ status: 'completed', completed_at: new Date().toISOString() })
            .eq('id', competitionId);
        
        console.log(`🏆 Competition "${comp.name}" cancelled by creator ${userId}`);
        
        // Email all participants about cancellation
        try {
            const { data: participants } = await supabase
                .from('competition_participants')
                .select('user_id')
                .eq('competition_id', competitionId)
                .eq('status', 'active');
            
            const buyIn = parseFloat(comp.buy_in_amount) || 0;
            
            for (const p of (participants || [])) {
                const { data: pUser } = await supabase
                    .from('users').select('email, full_name').eq('id', p.user_id).single();
                if (!pUser?.email) continue;
                
                const refundNote = buyIn > 0 && comp.status === 'active'
                    ? ` Your $${buyIn} entry has been refunded to your RunMatch balance.`
                    : '';
                
                await emailTransporter.sendMail({
                    from: `"RunMatch" <${process.env.SMTP_USER || 'connect@runmatch.io'}>`,
                    to: pUser.email,
                    subject: `Competition "${comp.name}" has been cancelled`,
                    text: `Hi ${pUser.full_name || 'there'}, the competition "${comp.name}" has been ended early by the creator.${refundNote} Thanks for participating!`,
                    html: `<div style="font-family:sans-serif;max-width:500px;margin:0 auto;padding:20px"><h2 style="color:#d9a600">Competition Cancelled</h2><p>Hi ${pUser.full_name || 'there'},</p><p>The competition <strong>"${comp.name}"</strong> has been ended early by the creator.${refundNote}</p><p>Thanks for participating!</p><p style="color:#888;font-size:12px;margin-top:30px">— RunMatch | Bet on a Better You</p></div>`
                });
                console.log(`📧 Cancellation email sent to ${pUser.email}`);
            }
        } catch (emailErr) {
            console.error('Cancellation email error (non-fatal):', emailErr.message);
        }
        
        res.json({ success: true });
        
    } catch (error) {
        console.error('Cancel competition error:', error);
        res.status(500).json({ error: error.message });
    }
});

// List competitions for a user
app.get('/compete/user/:userId', optionalAuth, async (req, res) => {
    try {
        const { userId } = req.params;
        
        // Get all competition IDs this user participates in
        const { data: participations, error: partError } = await supabase
            .from('competition_participants')
            .select('competition_id')
            .eq('user_id', userId)
            .eq('status', 'active');
        
        if (partError) {
            return res.status(500).json({ error: partError.message });
        }
        
        if (!participations || participations.length === 0) {
            return res.json({ competitions: [] });
        }
        
        const compIds = participations.map(p => p.competition_id);
        
        const { data: competitions, error: compError } = await supabase
            .from('competitions')
            .select('*, creator:users!creator_user_id(full_name)')
            .in('id', compIds)
            .order('created_at', { ascending: false });
        
        if (compError) {
            return res.status(500).json({ error: compError.message });
        }
        
        // For each competition, get participant count
        const results = [];
        for (const comp of (competitions || [])) {
            const { count } = await supabase
                .from('competition_participants')
                .select('*', { count: 'exact', head: true })
                .eq('competition_id', comp.id)
                .eq('status', 'active');
            
            results.push({
                id: comp.id,
                name: comp.name,
                objectiveType: comp.objective_type,
                scoringType: comp.scoring_type,
                startDate: comp.start_date,
                endDate: comp.end_date,
                status: comp.status,
                inviteCode: comp.invite_code,
                targetValue: comp.target_value || 0,
                pushupTarget: comp.pushup_target || 0,
                runTarget: comp.run_target || 0,
                buyInAmount: comp.buy_in_amount,
                durationDays: comp.duration_days,
                isRace: comp.scoring_type === 'race',
                creatorUserId: comp.creator_user_id,
                creatorName: comp.creator?.full_name || 'Unknown',
                participantCount: count || 0
            });
        }
        
        res.json({ competitions: results });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get leaderboard for a competition
app.get('/compete/:competitionId/leaderboard', async (req, res) => {
    try {
        const { competitionId } = req.params;
        const limit = parseInt(req.query.limit) || 0;
        
        // Get competition details
        const { data: competition, error: compError } = await supabase
            .from('competitions')
            .select('*')
            .eq('id', competitionId)
            .single();
        
        if (compError || !competition) {
            return res.status(404).json({ error: 'Competition not found' });
        }
        
        // Get all active participants with user info and baselines
        const { data: participants, error: partError } = await supabase
            .from('competition_participants')
            .select('user_id, baseline_pushups, baseline_run, users!user_id(full_name, email)')
            .eq('competition_id', competitionId)
            .eq('status', 'active');
        
        if (partError) {
            return res.status(500).json({ error: partError.message });
        }
        
        const leaderboard = [];
        
        // Batch-fetch all sessions for all participants in one query
        const userIds = (participants || []).map(p => p.user_id);
        let allSessionsQuery = supabase
            .from('objective_sessions')
            .select('user_id, status, completed_count, target_count, session_date, objective_type')
            .in('user_id', userIds)
            .gte('session_date', competition.start_date)
            .lte('session_date', competition.end_date);
        
        if (competition.objective_type !== 'both') {
            allSessionsQuery = allSessionsQuery.eq('objective_type', competition.objective_type);
        }
        
        const { data: allSessionsData } = await allSessionsQuery;
        
        // Group sessions by user_id
        const sessionsByUser = {};
        for (const s of (allSessionsData || [])) {
            if (!sessionsByUser[s.user_id]) sessionsByUser[s.user_id] = [];
            sessionsByUser[s.user_id].push(s);
        }
        
        for (const p of (participants || [])) {
            let score = 0;
            let daysCompleted = 0;
            let totalCount = 0;
            let currentStreak = 0;
            
            const allSessions = sessionsByUser[p.user_id] || [];
            const startDate = competition.start_date;
            const bPushups = p.baseline_pushups || 0;
            const bRun = p.baseline_run || 0;
            const compPushupTarget = competition.pushup_target || 0;
            const compRunTarget = competition.run_target || 0;
            
            // Helper: check if a session meets the COMPETITION target (not personal)
            function meetsCompTarget(s, adjustedCount) {
                let target;
                if (s.objective_type === 'pushups') target = compPushupTarget;
                else if (s.objective_type === 'run') target = compRunTarget;
                else target = competition.target_value || 0;
                return target > 0 ? adjustedCount >= target : adjustedCount > 0;
            }
            
            if (competition.objective_type === 'both') {
                const byDate = {};
                for (const s of allSessions) {
                    if (!byDate[s.session_date]) byDate[s.session_date] = {};
                    let count = parseFloat(s.completed_count) || 0;
                    if (s.session_date === startDate) {
                        if (s.objective_type === 'pushups') count = Math.max(0, count - bPushups);
                        if (s.objective_type === 'run') count = Math.max(0, count - bRun);
                    }
                    byDate[s.session_date][s.objective_type] = { ...s, _adjustedCount: count };
                    const pts = s.objective_type === 'run' ? count * 100 : count;
                    totalCount += pts;
                }
                const sortedDates = Object.keys(byDate).sort();
                for (const date of sortedDates) {
                    const dayEntries = byDate[date];
                    const allDone = Object.values(dayEntries).every(e => meetsCompTarget(e, e._adjustedCount));
                    if (allDone && Object.keys(dayEntries).length >= 2) {
                        daysCompleted++;
                        currentStreak++;
                    } else {
                        currentStreak = 0;
                    }
                }
            } else {
                const sorted = allSessions.sort((a, b) => a.session_date.localeCompare(b.session_date));
                for (const s of sorted) {
                    let count = parseFloat(s.completed_count) || 0;
                    if (s.session_date === startDate) {
                        if (s.objective_type === 'pushups') count = Math.max(0, count - bPushups);
                        if (s.objective_type === 'run') count = Math.max(0, count - bRun);
                    }
                    totalCount += count;
                    if (meetsCompTarget(s, count)) {
                        daysCompleted++;
                        currentStreak++;
                    } else {
                        currentStreak = 0;
                    }
                }
            }
            
            score = (competition.scoring_type === 'cumulative' || competition.scoring_type === 'race') ? totalCount : daysCompleted;
            
            // Extract today's progress, adjusted for baseline on start day
            const { data: pUserTz } = await supabase.from('users').select('timezone').eq('id', p.user_id).single();
            const todayStr = getTodayForTimezone(pUserTz?.timezone);
            const todaySessions = allSessions.filter(s => s.session_date === todayStr);
            const todayProgress = {};
            for (const s of todaySessions) {
                let completed = parseFloat(s.completed_count) || 0;
                if (s.session_date === startDate) {
                    if (s.objective_type === 'pushups') completed = Math.max(0, completed - bPushups);
                    if (s.objective_type === 'run') completed = Math.max(0, completed - bRun);
                }
                let compTarget;
                if (s.objective_type === 'pushups') compTarget = compPushupTarget;
                else if (s.objective_type === 'run') compTarget = compRunTarget;
                else compTarget = competition.target_value || 0;
                const adjustedStatus = compTarget > 0 && completed >= compTarget ? 'completed' : 'pending';
                todayProgress[s.objective_type] = {
                    completed,
                    target: compTarget,
                    status: adjustedStatus
                };
            }
            
            const entry = {
                userId: p.user_id,
                name: p.users?.full_name || p.users?.email || 'Unknown',
                score: Math.round(score * 100) / 100,
                daysCompleted,
                totalCount: Math.round(totalCount * 100) / 100,
                streak: currentStreak,
                todayProgress
            };
            if (competition.scoring_type === 'race') {
                entry.raceTarget = compRunTarget;
                entry.raceProgress = compRunTarget > 0 ? Math.min(1, totalCount / compRunTarget) : 0;
            }
            leaderboard.push(entry);
        }
        
        // Sort by score descending, then by streak as tiebreaker
        leaderboard.sort((a, b) => b.score - a.score || b.streak - a.streak);
        
        // Assign ranks
        leaderboard.forEach((entry, i) => { entry.rank = i + 1; });
        
        // Calculate total days and precise time remaining
        const isRaceComp = competition.scoring_type === 'race';
        const startedAt = competition.started_at ? new Date(competition.started_at) : new Date(competition.start_date);
        const now = new Date();
        const msElapsed = Math.max(0, now - startedAt);
        
        let totalDays, daysElapsed, daysRemaining, hoursRemaining, endsAt;
        if (isRaceComp || !competition.duration_days) {
            totalDays = null;
            daysElapsed = Math.ceil(msElapsed / 86400000);
            daysRemaining = null;
            hoursRemaining = null;
            endsAt = null;
        } else {
            const endAt = new Date(startedAt.getTime() + competition.duration_days * 86400000);
            const msRemaining = Math.max(0, endAt - now);
            totalDays = competition.duration_days;
            daysElapsed = Math.min(Math.ceil(msElapsed / 86400000), totalDays);
            daysRemaining = Math.max(0, Math.ceil(msRemaining / 86400000));
            hoursRemaining = Math.max(0, Math.floor(msRemaining / 3600000));
            endsAt = endAt.toISOString();
        }
        
        let compPushupTarget = competition.pushup_target ?? 0;
        let compRunTarget = competition.run_target ?? 0;
        
        res.json({
            competition: {
                id: competition.id,
                name: competition.name,
                objectiveType: competition.objective_type,
                scoringType: competition.scoring_type,
                startDate: competition.start_date,
                endDate: competition.end_date,
                status: competition.status,
                inviteCode: competition.invite_code,
                targetValue: competition.target_value || 0,
                pushupTarget: compPushupTarget,
                runTarget: compRunTarget,
                buyInAmount: competition.buy_in_amount,
                durationDays: competition.duration_days || 7,
                creatorUserId: competition.creator_user_id,
                totalDays,
                daysElapsed,
                daysRemaining,
                hoursRemaining,
                startedAt: competition.started_at || competition.start_date,
                endsAt,
                isRace: isRaceComp,
                totalParticipants: leaderboard.length
            },
            leaderboard: limit > 0 ? leaderboard.slice(0, limit) : leaderboard
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Cron: check and complete ended competitions, determine winners, pay out
app.post('/compete/check-completed', requireCronSecret, async (req, res) => {
    try {
        const now = new Date();
        const today = now.toISOString().split('T')[0];
        
        // Get all active competitions, then filter by precise end time
        const { data: activeComps, error } = await supabase
            .from('competitions')
            .select('*')
            .eq('status', 'active');
        
        const ended = (activeComps || []).filter(comp => {
            // Race comps end via Strava webhook, not time — but add 30-day safety timeout
            if (comp.scoring_type === 'race') {
                if (comp.started_at) {
                    const safetyEnd = new Date(new Date(comp.started_at).getTime() + 30 * 86400000);
                    return now >= safetyEnd;
                }
                return false;
            }
            if (comp.started_at) {
                const endAt = new Date(new Date(comp.started_at).getTime() + (comp.duration_days || 7) * 86400000);
                return now >= endAt;
            }
            return comp.end_date < today;
        });
        
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        
        let completed = 0;
        const payoutResults = [];
        
        for (const comp of (ended || [])) {
            // --- Determine the winner via leaderboard calculation ---
            const { data: participants } = await supabase
                .from('competition_participants')
                .select('user_id, buy_in_amount, baseline_pushups, baseline_run')
                .eq('competition_id', comp.id)
                .eq('status', 'active');
            
            if (!participants || participants.length === 0) {
                await supabase.from('competitions')
                    .update({ status: 'completed', completed_at: new Date().toISOString() })
                    .eq('id', comp.id);
                completed++;
                continue;
            }
            
            // Calculate scores for each participant
            const scores = [];
            for (const p of participants) {
                let sessionsQuery = supabase
                    .from('objective_sessions')
                    .select('status, completed_count, session_date, objective_type')
                    .eq('user_id', p.user_id)
                    .gte('session_date', comp.start_date)
                    .lte('session_date', comp.end_date);
                
                if (comp.objective_type !== 'both') {
                    sessionsQuery = sessionsQuery.eq('objective_type', comp.objective_type);
                }
                
                const { data: sessions } = await sessionsQuery;
                const allSessions = sessions || [];
                const startDate = comp.start_date;
                const bPushups = p.baseline_pushups || 0;
                const bRun = p.baseline_run || 0;
                
                let daysCompleted = 0;
                let totalCount = 0;
                const cPushTarget = comp.pushup_target || 0;
                const cRunTarget = comp.run_target || 0;
                
                function meetsTarget(objType, count) {
                    let target;
                    if (objType === 'pushups') target = cPushTarget;
                    else if (objType === 'run') target = cRunTarget;
                    else target = comp.target_value || 0;
                    return target > 0 ? count >= target : count > 0;
                }
                
                if (comp.objective_type === 'both') {
                    const byDate = {};
                    for (const s of allSessions) {
                        if (!byDate[s.session_date]) byDate[s.session_date] = {};
                        let count = parseFloat(s.completed_count) || 0;
                        if (s.session_date === startDate) {
                            if (s.objective_type === 'pushups') count = Math.max(0, count - bPushups);
                            if (s.objective_type === 'run') count = Math.max(0, count - bRun);
                        }
                        byDate[s.session_date][s.objective_type] = { ...s, _adj: count };
                        const pts = s.objective_type === 'run' ? count * 100 : count;
                        totalCount += pts;
                    }
                    for (const date of Object.keys(byDate)) {
                        const dayEntries = byDate[date];
                        const allDone = Object.values(dayEntries).every(e => meetsTarget(e.objective_type, e._adj));
                        if (allDone && Object.keys(dayEntries).length >= 2) {
                            daysCompleted++;
                        }
                    }
                } else {
                    for (const s of allSessions) {
                        let count = parseFloat(s.completed_count) || 0;
                        if (s.session_date === startDate) {
                            if (s.objective_type === 'pushups') count = Math.max(0, count - bPushups);
                            if (s.objective_type === 'run') count = Math.max(0, count - bRun);
                        }
                        totalCount += count;
                        if (meetsTarget(s.objective_type, count)) {
                            daysCompleted++;
                        }
                    }
                }
                
                const score = (comp.scoring_type === 'cumulative' || comp.scoring_type === 'race') ? totalCount : daysCompleted;
                const { data: scoreUser } = await supabase.from('users').select('full_name').eq('id', p.user_id).single();
                scores.push({ userId: p.user_id, score, buyInAmount: parseFloat(p.buy_in_amount) || 0, name: scoreUser?.full_name || 'Unknown' });
            }
            
            // Sort by score descending
            scores.sort((a, b) => b.score - a.score);
            const topScore = scores[0].score;
            const winners = scores.filter(s => s.score === topScore && s.score > 0);
            
            // --- Payout logic ---
            const buyIn = parseFloat(comp.buy_in_amount) || 0;
            const poolAmount = buyIn * participants.length;
            let payoutDone = false;
            
            if (poolAmount > 0 && winners.length > 0) {
                // Split pool among all tied winners
                const splitCents = Math.floor(Math.round(poolAmount * 100) / winners.length);
                
                for (const winner of winners) {
                    const { data: winnerUser } = await supabase
                        .from('users').select('balance_cents').eq('id', winner.userId).single();
                    const newBalance = (winnerUser?.balance_cents || 0) + splitCents;
                    await supabase.from('users').update({ balance_cents: newBalance }).eq('id', winner.userId);
                    
                    await supabase.from('competition_payouts').insert({
                        competition_id: comp.id,
                        winner_user_id: winner.userId,
                        pool_amount: splitCents / 100,
                        participant_count: participants.length
                    });
                    
                    console.log(`🏆 PAYOUT: $${(splitCents/100).toFixed(2)} to ${winner.name} (${winner.userId}) for "${comp.name}"${winners.length > 1 ? ` (split ${winners.length} ways)` : ''}`);
                }
                
                payoutDone = true;
            } else if (poolAmount > 0 && winners.length === 0) {
                // Nobody scored — refund all participants
                for (const p of participants) {
                    if (p.buy_in_amount > 0) {
                        const refundCents = Math.round(parseFloat(p.buy_in_amount) * 100);
                        const { data: refundUser } = await supabase
                            .from('users').select('balance_cents').eq('id', p.user_id).single();
                        const newBal = (refundUser?.balance_cents || 0) + refundCents;
                        await supabase.from('users').update({ balance_cents: newBal }).eq('id', p.user_id);
                    }
                }
                console.log(`🏆 REFUND: All participants refunded for "${comp.name}" (no one scored)`);
            }
            
            // Mark competition completed with winner(s)
            const winnerId = winners.length > 0 ? winners[0].userId : null;
            await supabase.from('competitions')
                .update({
                    status: 'completed',
                    winner_user_id: winnerId,
                    payout_completed: payoutDone,
                    completed_at: new Date().toISOString()
                })
                .eq('id', comp.id);
            
            payoutResults.push({
                competitionId: comp.id,
                name: comp.name,
                winnerId,
                winnerCount: winners.length,
                poolAmount,
                payoutDone,
                participantCount: participants.length
            });
            
            // Send completion emails to all participants
            try {
                const winnerIds = new Set(winners.map(w => w.userId));
                const winnerNames = winners.map(w => w.name).join(' & ');
                
                for (const p of participants) {
                    const { data: pUser } = await supabase
                        .from('users').select('email, full_name').eq('id', p.user_id).single();
                    if (!pUser?.email) continue;
                    
                    const isWinner = winnerIds.has(p.user_id);
                    let subject, body;
                    
                    if (winners.length === 0) {
                        subject = `Competition "${comp.name}" has ended — Draw`;
                        body = `"${comp.name}" has ended with no winner.${poolAmount > 0 ? ' All buy-ins have been refunded since no one scored.' : ' Better luck next time!'}`;
                    } else if (isWinner && winners.length === 1) {
                        subject = `🏆 You won "${comp.name}"!`;
                        body = `Congrats ${pUser.full_name || 'Champion'}! You won "${comp.name}" with a score of ${topScore}.${poolAmount > 0 ? ` $${poolAmount} has been added to your RunMatch balance.` : ''}`;
                    } else if (isWinner && winners.length > 1) {
                        const splitAmount = (Math.floor(Math.round(poolAmount * 100) / winners.length) / 100).toFixed(2);
                        subject = `🏆 You tied for first in "${comp.name}"!`;
                        body = `"${comp.name}" ended in a ${winners.length}-way tie! You and ${winnerNames.replace(pUser.full_name + ' & ', '').replace(' & ' + pUser.full_name, '')} each scored ${topScore}.${poolAmount > 0 ? ` The $${poolAmount} pool has been split — $${splitAmount} added to your balance.` : ''}`;
                    } else {
                        const winnerName = winnerNames;
                        subject = `Competition "${comp.name}" has ended`;
                        body = `"${comp.name}" has ended. ${winnerName} won with a score of ${topScore}.${poolAmount > 0 ? ` The $${poolAmount} pool has been awarded to the winner${winners.length > 1 ? 's' : ''}.` : ''}`;
                    }
                    
                    await emailTransporter.sendMail({
                        from: `"RunMatch" <${process.env.SMTP_USER || 'connect@runmatch.io'}>`,
                        to: pUser.email,
                        subject,
                        text: body,
                        html: `<div style="font-family:sans-serif;max-width:500px;margin:0 auto;padding:20px"><h2 style="color:#d9a600">${subject}</h2><p>${body}</p><p style="color:#888;font-size:12px;margin-top:30px">— RunMatch | Bet on a Better You</p></div>`
                    });
                    console.log(`📧 Competition email sent to ${pUser.email}`);
                }
            } catch (emailErr) {
                console.error('Competition email error (non-fatal):', emailErr.message);
            }
            
            completed++;
            console.log(`🏆 Competition completed: "${comp.name}" | Winner${winners.length > 1 ? 's' : ''}: ${winners.length > 0 ? winners.map(w => w.name).join(' & ') : 'none (refunded)'}`);
        }
        
        res.json({ success: true, completed, payouts: payoutResults });
        
    } catch (error) {
        console.error('Competition check-completed error:', error);
        res.status(500).json({ error: error.message });
    }
});

// -----------------------------------------------------------------------------
// Start server (must be after all route definitions)
// -----------------------------------------------------------------------------
app.listen(port, () => console.log(`RunMatch backend listening on port ${port}`));
