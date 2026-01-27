#!/bin/bash

echo "🔧 Updating server.js with objective tracking endpoints..."

SERVER="user@159.26.94.94"

ssh $SERVER << 'EOF'
cd ~/morning-would-payments

# Backup current server.js
cp server.js server.js.backup.objectives.$(date +%Y%m%d_%H%M%S)
echo "✅ Backed up server.js"

# Update the existing /users/profile endpoint
echo "📝 Updating /users/profile endpoint..."

# First, comment out the old /users/profile endpoint (if it exists)
sed -i.tmp '/app.post.*\/users\/profile.*{/,/^});/s/^/\/\/ /' server.js

# Add the updated profile endpoint
cat >> server.js << 'PROFILE_ENDPOINT'

// Updated user profile endpoint with objective tracking
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
PROFILE_ENDPOINT

# Add NEW objective tracking endpoints (these don't exist yet)
cat >> server.js << 'NEW_ENDPOINTS'

// === OBJECTIVE TRACKING ENDPOINTS ===

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

// Log objective progress
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
NEW_ENDPOINTS

echo "✅ Added objective tracking endpoints"

# Restart the server
echo "🔄 Restarting server..."
pm2 restart server 2>/dev/null || (pkill node && nohup node server.js > server.log 2>&1 &)

echo "✅ Server updated and restarted!"

# Test the endpoints
sleep 3
echo ""
echo "🧪 Testing endpoints..."
curl -s https://api.live-eos.com/debug/database | head -5

EOF

echo ""
echo "✅ Server updated successfully!"
echo ""
echo "The following changes were made:"
echo "  1. Updated /users/profile endpoint to save objective settings"
echo "  2. Added /objectives/today/:userId endpoint"
echo "  3. Added /objectives/sessions/start endpoint"
echo "  4. Added /objectives/sessions/log endpoint"
echo "  5. Added /objectives/check-missed endpoint"