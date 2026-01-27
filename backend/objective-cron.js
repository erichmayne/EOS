#!/usr/bin/env node

// Cron job to check for missed objectives and trigger payouts
// Run this every hour or at specific times (e.g., 10 minutes after each common deadline)

const { createClient } = require('@supabase/supabase-js');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// Initialize Supabase
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
);

async function checkMissedObjectives() {
    console.log(`[${new Date().toISOString()}] Checking for missed objectives...`);
    
    try {
        // Create daily sessions for active users
        await supabase.rpc('create_daily_objective_sessions');
        
        // Check for missed objectives
        const { data: missedSessions, error } = await supabase
            .rpc('check_missed_objectives');

        if (error) {
            console.error('Error checking missed objectives:', error);
            return;
        }

        if (!missedSessions || missedSessions.length === 0) {
            console.log('No missed objectives found');
            return;
        }

        console.log(`Found ${missedSessions.length} missed objectives`);

        // Process each missed objective
        for (const session of missedSessions) {
            await processPayout(session);
        }

    } catch (error) {
        console.error('Cron job error:', error);
    }
}

async function processPayout(session) {
    try {
        console.log(`Processing payout for user ${session.user_email}: $${session.payout_amount}`);

        if (session.payout_amount <= 0) {
            console.log('No payout amount set, skipping');
            return;
        }

        // Create transaction record
        const { data: transaction, error: txError } = await supabase
            .from('transactions')
            .insert({
                user_id: session.user_id,
                type: 'payout',
                amount_cents: Math.round(session.payout_amount * 100),
                status: 'pending',
                description: 'Missed objective payout',
                metadata: {
                    session_id: session.session_id,
                    destination: session.payout_destination,
                    objective_date: new Date().toISOString().split('T')[0]
                }
            })
            .select()
            .single();

        if (txError) {
            console.error('Transaction creation error:', txError);
            return;
        }

        // Process payout based on destination
        let payoutResult;
        if (session.payout_destination === 'charity') {
            // Process charity donation
            payoutResult = await processCharityDonation(session, transaction);
        } else if (session.payout_destination === 'custom') {
            // Process custom recipient payout
            payoutResult = await processCustomPayout(session, transaction);
        }

        // Update transaction status
        await supabase
            .from('transactions')
            .update({
                status: payoutResult.success ? 'completed' : 'failed',
                stripe_payment_id: payoutResult.paymentId,
                processed_at: new Date(),
                metadata: {
                    ...transaction.metadata,
                    result: payoutResult
                }
            })
            .eq('id', transaction.id);

        // Mark session payout as triggered
        await supabase
            .from('objective_sessions')
            .update({
                payout_triggered: true,
                payout_amount: session.payout_amount,
                payout_transaction_id: transaction.id,
                updated_at: new Date()
            })
            .eq('id', session.session_id);

        console.log(`Payout processed successfully for session ${session.session_id}`);

    } catch (error) {
        console.error(`Error processing payout for session ${session.session_id}:`, error);
    }
}

async function processCharityDonation(session, transaction) {
    try {
        // Get user's payment method
        const { data: user } = await supabase
            .from('users')
            .select('stripe_customer_id, stripe_payment_method_id')
            .eq('id', session.user_id)
            .single();

        if (!user?.stripe_customer_id || !user?.stripe_payment_method_id) {
            throw new Error('No payment method on file');
        }

        // Create Stripe payment intent for charity
        const paymentIntent = await stripe.paymentIntents.create({
            amount: transaction.amount_cents,
            currency: 'usd',
            customer: user.stripe_customer_id,
            payment_method: user.stripe_payment_method_id,
            off_session: true,
            confirm: true,
            description: 'EOS Charity Donation - Missed Objective',
            metadata: {
                type: 'charity_donation',
                user_id: session.user_id,
                session_id: session.session_id,
                transaction_id: transaction.id
            },
            // Transfer to charity's Stripe account
            // transfer_data: {
            //     destination: CHARITY_STRIPE_ACCOUNT_ID,
            // }
        });

        return {
            success: true,
            paymentId: paymentIntent.id,
            amount: paymentIntent.amount / 100
        };

    } catch (error) {
        console.error('Charity donation error:', error);
        return {
            success: false,
            error: error.message
        };
    }
}

async function processCustomPayout(session, transaction) {
    try {
        // Get recipient details
        const { data: recipient } = await supabase
            .from('recipients')
            .select('*')
            .eq('id', session.custom_recipient_id)
            .single();

        if (!recipient) {
            throw new Error('Recipient not found');
        }

        // Get user's payment method
        const { data: user } = await supabase
            .from('users')
            .select('stripe_customer_id, stripe_payment_method_id')
            .eq('id', session.user_id)
            .single();

        if (!user?.stripe_customer_id || !user?.stripe_payment_method_id) {
            throw new Error('No payment method on file');
        }

        // Create payment and transfer to recipient
        const paymentIntent = await stripe.paymentIntents.create({
            amount: transaction.amount_cents,
            currency: 'usd',
            customer: user.stripe_customer_id,
            payment_method: user.stripe_payment_method_id,
            off_session: true,
            confirm: true,
            description: `EOS Payout to ${recipient.full_name} - Missed Objective`,
            metadata: {
                type: 'custom_payout',
                user_id: session.user_id,
                recipient_id: recipient.id,
                session_id: session.session_id,
                transaction_id: transaction.id
            },
            // Transfer to recipient's connected account
            transfer_data: recipient.stripe_account_id ? {
                destination: recipient.stripe_account_id,
            } : undefined
        });

        // If recipient doesn't have Stripe account, send notification
        if (!recipient.stripe_account_id) {
            await sendPayoutNotification(recipient, transaction.amount_cents / 100);
        }

        return {
            success: true,
            paymentId: paymentIntent.id,
            amount: paymentIntent.amount / 100,
            recipient: recipient.full_name
        };

    } catch (error) {
        console.error('Custom payout error:', error);
        return {
            success: false,
            error: error.message
        };
    }
}

async function sendPayoutNotification(recipient, amount) {
    // Send SMS or email notification to recipient about pending payout
    console.log(`Notifying ${recipient.full_name} about $${amount} payout`);
    // Implement SMS/email notification here
}

// Run the check
if (require.main === module) {
    checkMissedObjectives()
        .then(() => {
            console.log('Objective check completed');
            process.exit(0);
        })
        .catch(error => {
            console.error('Fatal error:', error);
            process.exit(1);
        });
}

module.exports = { checkMissedObjectives };