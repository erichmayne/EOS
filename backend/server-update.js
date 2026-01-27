// Add this endpoint to your server.js file on the remote server

// Custom recipient onboarding with direct card input
app.post('/recipient-onboarding-custom', async (req, res) => {
    try {
        const { inviteCode, email, cardDetails } = req.body;
        
        if (!inviteCode || !email || !cardDetails) {
            return res.status(400).json({ detail: 'Missing required fields' });
        }
        
        // Verify invite code
        const { data: invite, error: inviteError } = await supabase
            .from('recipient_invites')
            .select('*, payer:payer_user_id(full_name, email)')
            .eq('invite_code', inviteCode)
            .single();
        
        if (inviteError || !invite) {
            return res.status(404).json({ detail: 'Invalid invite code' });
        }
        
        if (invite.status !== 'pending') {
            return res.status(400).json({ detail: 'This invite has already been used' });
        }
        
        // Create Stripe Connect Custom account
        const account = await stripe.accounts.create({
            type: 'custom',
            country: 'US',
            email: email,
            capabilities: {
                card_payments: { requested: true },
                transfers: { requested: true },
            },
            business_type: 'individual',
            business_profile: {
                product_description: 'Receiving EOS fitness goal payouts',
            },
            settings: {
                payouts: {
                    statement_descriptor: 'EOS PAYOUT',
                },
            },
            tos_acceptance: {
                date: Math.floor(Date.now() / 1000),
                ip: req.ip,
            },
        });
        
        // Add card as external account
        const card = await stripe.accounts.createExternalAccount(account.id, {
            external_account: {
                object: 'card',
                name: cardDetails.name,
                number: cardDetails.number,
                exp_month: cardDetails.exp_month,
                exp_year: cardDetails.exp_year,
                cvc: cardDetails.cvc,
                currency: 'usd',
                address_zip: cardDetails.address_zip,
            },
            default_for_currency: true,
        });
        
        // Create or update recipient record
        const { data: recipient, error: recipientError } = await supabase
            .from('recipients')
            .upsert({
                phone: invite.phone,
                email: email,
                name: cardDetails.name,
                stripe_connect_account_id: account.id,
                type: 'individual',
            })
            .select()
            .single();
        
        if (recipientError) {
            // Clean up Stripe account if DB fails
            await stripe.accounts.del(account.id);
            throw recipientError;
        }
        
        // Update invite status
        await supabase
            .from('recipient_invites')
            .update({
                status: 'accepted',
                recipient_id: recipient.id,
            })
            .eq('invite_code', inviteCode);
        
        // Create payout rule
        const { data: payoutRule, error: ruleError } = await supabase
            .from('payout_rules')
            .insert({
                payer_user_id: invite.payer_user_id,
                recipient_id: recipient.id,
                fixed_amount_cents: 500, // Default $5, will be overridden by user's setting
                active: true,
            })
            .select()
            .single();
        
        res.json({
            success: true,
            recipientId: recipient.id,
            message: 'Payout method successfully configured',
        });
        
    } catch (error) {
        console.error('Recipient onboarding error:', error);
        res.status(500).json({ 
            detail: error.message || 'Failed to set up payout method' 
        });
    }
});
