// Complete Server.js Update for EOS
// This includes all existing endpoints + objective tracking system

const express = require('express');
const cors = require('cors');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const { createClient } = require('@supabase/supabase-js');
const twilio = require('twilio');

const app = express();
app.use(cors());
app.use(express.json());

// Initialize Supabase
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
);

// Initialize Twilio
const twilioClient = twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
);

// ========== EXISTING ENDPOINTS ==========

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date() });
});

// Debug database connectivity
app.get('/debug/database', async (req, res) => {
    try {
        const results = {};
        
        results.supabaseConnected = !!supabase;
        
        const { data: usersData, error: usersError } = await supabase
            .from('users')
            .select('count');
        results.usersTable = usersError ? { error: usersError.message } : { count: usersData?.length || 0 };
        
        const { data: recipientsData, error: recipientsError } = await supabase
            .from('recipients')
            .select('count');
        results.recipientsTable = recipientsError ? { error: recipientsError.message } : { count: recipientsData?.length || 0 };
        
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

// Send recipient invite SMS
async function sendRecipientInviteSMS(phone, inviteCode, payerName) {
    try {
        const message = await twilioClient.messages.create({
            body: `${payerName} has invited you to receive cash payouts through EOS. Set up your payout details at: https://app.live-eos.com/invite/${inviteCode}`,
            from: process.env.TWILIO_PHONE_NUMBER,
            to: phone
        });
        console.log('SMS sent:', message.sid);
        return message;
    } catch (error) {
        console.error('SMS error:', error);
        throw error;
    }
}

// Recipient invites endpoint
app.post('/recipient-invites', async (req, res) => {
    try {
        const { payerEmail, payerName, phone } = req.body;
        
        if (!payerEmail || !phone) {
            return res.status(400).json({ 
                detail: 'Missing required fields: payerEmail and phone are required' 
            });
        }
        
        // Look up payer user by email
        const { data: payerUser, error: userError } = await supabase
            .from('users')
            .select('*')
            .eq('email', payerEmail)
            .single();
        
        if (userError || !payerUser) {
            console.error('User lookup error:', userError);
            return res.status(404).json({ 
                detail: 'Payer user not found. Please create/update your profile first.' 
            });
        }
        
        // Check for existing pending invite
        const { data: existingInvite, error: inviteCheckError } = await supabase
            .from('recipient_invites')
            .select('*')
            .eq('payer_user_id', payerUser.id)
            .eq('phone', phone)
            .eq('status', 'pending')
            .single();
        
        if (existingInvite && !inviteCheckError) {
            // Resend the existing invite
            await sendRecipientInviteSMS(phone, existingInvite.invite_code, payerName || payerUser.full_name);
            return res.json({ 
                inviteCode: existingInvite.invite_code,
                message: 'Invite resent successfully' 
            });
        }
        
        // Generate new invite code
        const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();
        
        // Create new invite
        const { data: newInvite, error: insertError } = await supabase
            .from('recipient_invites')
            .insert({
                payer_user_id: payerUser.id,
                phone: phone,
                invite_code: inviteCode,
                status: 'pending'
            })
            .select()
            .single();
        
        if (insertError) {
            console.error('Insert error:', insertError);
            return res.status(500).json({ 
                detail: 'Failed to create invite: ' + insertError.message 
            });
        }
        
        // Send SMS
        await sendRecipientInviteSMS(phone, inviteCode, payerName || payerUser.full_name);
        
        res.json({ 
            inviteCode: inviteCode,
            message: 'Invite sent successfully' 
        });
        
    } catch (error) {
        console.error('Recipient invite error:', error);
        res.status(500).json({ 
            detail: error.message || 'Internal server error' 
        });
    }
});

// Generate invite code only (no SMS) - for manual sharing
app.post('/recipient-invites/code-only', async (req, res) => {
    try {
        const { payerEmail, payerName } = req.body;
        
        if (!payerEmail) {
            return res.status(400).json({ 
                detail: 'Missing required field: payerEmail' 
            });
        }
        
        // Look up payer user by email
        const { data: payerUser, error: userError } = await supabase
            .from('users')
            .select('*')
            .eq('email', payerEmail)
            .single();
        
        if (userError || !payerUser) {
            console.error('User lookup error:', userError);
            return res.status(404).json({ 
                detail: 'Payer user not found. Please save your profile first.' 
            });
        }
        
        // Generate new invite code (8 chars, no ambiguous chars)
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let inviteCode = '';
        for (let i = 0; i < 8; i++) {
            inviteCode += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        // Create new invite (phone is null for code-only invites)
        const { data: newInvite, error: insertError } = await supabase
            .from('recipient_invites')
            .insert({
                payer_user_id: payerUser.id,
                phone: null,
                invite_code: inviteCode,
                status: 'pending'
            })
            .select()
            .single();
        
        if (insertError) {
            console.error('Insert error:', insertError);
            return res.status(500).json({ 
                detail: 'Failed to create invite: ' + insertError.message 
            });
        }
        
        res.json({ 
            inviteCode: inviteCode,
            message: 'Invite code generated successfully. Share it manually.' 
        });
        
    } catch (error) {
        console.error('Code-only invite error:', error);
        res.status(500).json({ 
            detail: error.message || 'Internal server error' 
        });
    }
});

// Verify invite code
app.post('/verify-invite', async (req, res) => {
    try {
        const { inviteCode } = req.body;
        
        if (!inviteCode) {
            return res.status(400).json({ detail: 'Invite code is required' });
        }
        
        const { data: invite, error } = await supabase
            .from('recipient_invites')
            .select('*, payer:users(full_name, email)')
            .eq('invite_code', inviteCode.toUpperCase())
            .single();
        
        if (error || !invite) {
            return res.status(404).json({ detail: 'Invalid invite code' });
        }
        
        if (invite.status !== 'pending') {
            return res.status(400).json({ detail: 'Invite has already been used' });
        }
        
        res.json({ 
            inviteCode: invite.invite_code,
            payerName: invite.payer?.full_name || 'Unknown',
            payerEmail: invite.payer?.email
        });
    } catch (error) {
        console.error('Verify invite error:', error);
        res.status(500).json({ detail: error.message });
    }
});

// Recipient onboarding with Stripe Connect Custom account
app.post('/recipient-onboarding-custom', async (req, res) => {
    try {
        const {
            inviteCode,
            email,
            cardholderName,
            cardNumber,
            expiryMonth,
            expiryYear,
            cvc,
            zipCode
        } = req.body;

        // Verify invite
        const { data: invite, error: inviteError } = await supabase
            .from('recipient_invites')
            .select('*, payer:users(full_name)')
            .eq('invite_code', inviteCode.toUpperCase())
            .single();

        if (inviteError || !invite || invite.status !== 'pending') {
            return res.status(400).json({ 
                detail: 'Invalid or already used invite code' 
            });
        }

        // Create Stripe Custom Connect account
        const account = await stripe.accounts.create({
            type: 'custom',
            country: 'US',
            email: email,
            business_type: 'individual',
            individual: {
                email: email,
                first_name: cardholderName.split(' ')[0],
                last_name: cardholderName.split(' ').slice(1).join(' ') || 'User',
            },
            capabilities: {
                card_payments: { requested: true },
                transfers: { requested: true }
            },
            business_profile: {
                mcc: '7299',
                product_description: 'EOS recipient payouts'
            },
            settings: {
                payouts: {
                    statement_descriptor: 'EOS PAYOUT',
                },
            },
            tos_acceptance: {
                date: Math.floor(Date.now() / 1000),
                ip: req.ip
            }
        });

        // Create external account (debit card for payouts)
        const token = await stripe.tokens.create({
            card: {
                number: cardNumber,
                exp_month: expiryMonth,
                exp_year: expiryYear,
                cvc: cvc,
                currency: 'usd',
                name: cardholderName,
                address_zip: zipCode
            }
        });

        await stripe.accounts.createExternalAccount(
            account.id,
            { external_account: token.id }
        );

        // Create or update recipient record
        const { data: recipient, error: recipientError } = await supabase
            .from('recipients')
            .upsert({
                email: email,
                full_name: cardholderName,
                phone: invite.phone,
                stripe_account_id: account.id,
                onboarding_completed: true
            }, {
                onConflict: 'email'
            })
            .select()
            .single();

        if (recipientError) {
            throw new Error('Failed to save recipient: ' + recipientError.message);
        }

        // Update invite status
        await supabase
            .from('recipient_invites')
            .update({ 
                status: 'completed',
                recipient_id: recipient.id
            })
            .eq('id', invite.id);

        res.json({
            success: true,
            message: 'Setup completed successfully',
            recipientId: recipient.id
        });

    } catch (error) {
        console.error('Recipient onboarding error:', error);
        res.status(500).json({ 
            detail: error.message || 'Failed to complete setup' 
        });
    }
});

// ========== UPDATED USER PROFILE ENDPOINT WITH OBJECTIVE TRACKING ==========

app.post('/users/profile', async (req, res) => {
    try {
        const { 
            email, fullName, phone, password, balanceCents,
            objective_type, objective_count, objective_schedule, 
            objective_deadline, missed_goal_payout, payout_destination,
            committedPayoutAmount, payoutCommitted
        } = req.body;

        // Check if user exists
        const { data: existingUser } = await supabase
            .from('users')
            .select('id')
            .eq('email', email)
            .single();

        let userData = {
            email: email,
            full_name: fullName,
            phone: phone,
            balance_cents: balanceCents || 0,
            objective_type: objective_type || 'pushups',
            objective_count: objective_count || 50,
            objective_schedule: objective_schedule || 'daily',
            objective_deadline: objective_deadline || '09:00',
            missed_goal_payout: committedPayoutAmount || missed_goal_payout || 0,
            payout_destination: payout_destination || 'charity',
            payout_committed: payoutCommitted || false
        };

        // Only include password for new users
        if (!existingUser && password) {
            userData.password_hash = password; // In production, hash this!
        }

        const { data, error } = existingUser
            ? await supabase
                .from('users')
                .update(userData)
                .eq('id', existingUser.id)
                .select()
                .single()
            : await supabase
                .from('users')
                .insert(userData)
                .select()
                .single();

        if (error) {
            console.error('User save error:', error);
            return res.status(400).json({ detail: error.message });
        }

        res.json({ message: 'Profile saved successfully', userId: data.id });
    } catch (error) {
        console.error('Profile save error:', error);
        res.status(500).json({ detail: error.message });
    }
});

// ========== OBJECTIVE TRACKING ENDPOINTS ==========

// Get today's objective session
app.get('/objectives/today/:userId', async (req, res) => {
    try {
        const { userId } = req.params;

        // First, ensure today's session exists
        await supabase.rpc('create_daily_objective_sessions');

        // Get today's session
        const { data, error } = await supabase
            .from('objective_sessions')
            .select('*')
            .eq('user_id', userId)
            .eq('session_date', new Date().toISOString().split('T')[0])
            .single();

        if (error && error.code !== 'PGRST116') { // Not found is OK
            return res.status(400).json({ detail: error.message });
        }

        res.json(data || { message: 'No session for today' });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Start objective session
app.post('/objectives/sessions/start', async (req, res) => {
    try {
        const { userId } = req.body;
        const today = new Date().toISOString().split('T')[0];

        // Get or create today's session
        const { data: session } = await supabase
            .from('objective_sessions')
            .select('*')
            .eq('user_id', userId)
            .eq('session_date', today)
            .single();

        if (!session) {
            // Create session if it doesn't exist
            const { data: user } = await supabase
                .from('users')
                .select('objective_type, objective_count, objective_deadline')
                .eq('id', userId)
                .single();

            const { data: newSession, error: createError } = await supabase
                .from('objective_sessions')
                .insert({
                    user_id: userId,
                    session_date: today,
                    objective_type: user.objective_type,
                    objective_count: user.objective_count,
                    deadline_time: user.objective_deadline,
                    status: 'in_progress',
                    started_at: new Date()
                })
                .select()
                .single();

            if (createError) {
                return res.status(400).json({ detail: createError.message });
            }

            return res.json(newSession);
        }

        // Update existing session
        const { data: updatedSession, error } = await supabase
            .from('objective_sessions')
            .update({
                status: 'in_progress',
                started_at: session.started_at || new Date(),
                updated_at: new Date()
            })
            .eq('id', session.id)
            .select()
            .single();

        if (error) {
            return res.status(400).json({ detail: error.message });
        }

        res.json(updatedSession);
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Log objective progress (e.g., completing pushups)
app.post('/objectives/sessions/log', async (req, res) => {
    try {
        const { userId, repCount } = req.body;
        const today = new Date().toISOString().split('T')[0];

        // Get today's session
        const { data: session, error: sessionError } = await supabase
            .from('objective_sessions')
            .select('*')
            .eq('user_id', userId)
            .eq('session_date', today)
            .single();

        if (sessionError || !session) {
            return res.status(404).json({ detail: 'No active session found' });
        }

        // Update session completed count
        const newCompletedCount = (session.completed_count || 0) + repCount;
        const isCompleted = newCompletedCount >= session.objective_count;

        const { data: updatedSession, error: updateError } = await supabase
            .from('objective_sessions')
            .update({
                completed_count: newCompletedCount,
                status: isCompleted ? 'completed' : 'in_progress',
                completed_at: isCompleted ? new Date() : null,
                updated_at: new Date()
            })
            .eq('id', session.id)
            .select()
            .single();

        if (updateError) {
            return res.status(400).json({ detail: updateError.message });
        }

        res.json({
            session: updatedSession,
            message: isCompleted ? 'Objective completed! 🎉' : `Progress: ${newCompletedCount}/${session.objective_count}`
        });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Check for missed objectives and trigger payouts
app.post('/objectives/check-missed', async (req, res) => {
    try {
        // Call the database function to check missed objectives
        const { data: missedSessions, error } = await supabase
            .rpc('check_missed_objectives');

        if (error) {
            return res.status(400).json({ detail: error.message });
        }

        // Process payouts for missed objectives
        const payoutResults = [];
        for (const session of missedSessions || []) {
            if (session.payout_amount > 0) {
                try {
                    // Create transaction record
                    const { data: transaction } = await supabase
                        .from('transactions')
                        .insert({
                            user_id: session.user_id,
                            type: 'payout',
                            amount_cents: Math.round(session.payout_amount * 100),
                            status: 'pending',
                            description: 'Missed objective payout',
                            metadata: {
                                session_id: session.session_id,
                                destination: session.payout_destination
                            }
                        })
                        .select()
                        .single();

                    // Mark payout as triggered
                    await supabase
                        .from('objective_sessions')
                        .update({
                            payout_triggered: true,
                            payout_amount: session.payout_amount,
                            payout_transaction_id: transaction.id
                        })
                        .eq('id', session.session_id);

                    payoutResults.push({
                        sessionId: session.session_id,
                        userId: session.user_id,
                        amount: session.payout_amount,
                        status: 'triggered'
                    });
                } catch (payoutError) {
                    console.error('Payout error:', payoutError);
                    payoutResults.push({
                        sessionId: session.session_id,
                        error: payoutError.message
                    });
                }
            }
        }

        res.json({
            missedCount: missedSessions?.length || 0,
            payouts: payoutResults
        });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// ========== PAYMENT ENDPOINTS (Existing) ==========

// Create checkout session for deposits
app.post('/create-checkout-session', async (req, res) => {
    try {
        const { amount } = req.body;
        
        const session = await stripe.checkout.sessions.create({
            payment_method_types: ['card'],
            line_items: [
                {
                    price_data: {
                        currency: 'usd',
                        product_data: {
                            name: 'EOS Balance Deposit',
                        },
                        unit_amount: amount,
                    },
                    quantity: 1,
                },
            ],
            mode: 'payment',
            success_url: 'https://eos-app://deposit-success',
            cancel_url: 'https://eos-app://deposit-cancel',
        });

        res.json({ sessionId: session.id });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Create payment intent
app.post('/create-payment-intent', async (req, res) => {
    try {
        const { amount } = req.body;

        const paymentIntent = await stripe.paymentIntents.create({
            amount: amount,
            currency: 'usd',
            automatic_payment_methods: {
                enabled: true,
            },
        });

        res.json({ 
            clientSecret: paymentIntent.client_secret,
            paymentIntentId: paymentIntent.id 
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== SERVER STARTUP ==========

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`EOS server running on port ${PORT}`);
    console.log('Objective tracking system active');
});

module.exports = app;