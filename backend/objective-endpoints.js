// Backend endpoints for objective tracking - add to server.js

// Update user profile endpoint to save objective settings
app.post('/users/profile', async (req, res) => {
    try {
        const { 
            email, fullName, phone, password, balanceCents,
            objective_type, objective_count, objective_schedule, 
            objective_deadline, missed_goal_payout, payout_destination 
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
            missed_goal_payout: missed_goal_payout || 0,
            payout_destination: payout_destination || 'charity'
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

// Get today's objective session
app.get('/objectives/today/:userId', async (req, res) => {
    try {
        const { userId } = req.params;

        // First, ensure today's session exists
        await supabase.rpc('create_daily_objective_sessions');

        // Get today's session
        const { data, error } = await supabase
            .from('objective_sessions')
            .select(`
                *,
                user:users(
                    full_name,
                    objective_type,
                    objective_count,
                    objective_deadline
                )
            `)
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
        const { userId, repCount, videoUrl } = req.body;
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

        // Log the reps
        const { data: log, error: logError } = await supabase
            .from('objective_logs')
            .insert({
                session_id: session.id,
                rep_count: repCount,
                video_url: videoUrl
            })
            .select()
            .single();

        if (logError) {
            return res.status(400).json({ detail: logError.message });
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
                video_proof_url: videoUrl || session.video_proof_url,
                updated_at: new Date()
            })
            .eq('id', session.id)
            .select()
            .single();

        if (updateError) {
            return res.status(400).json({ detail: updateError.message });
        }

        res.json({
            log: log,
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
                    // Here you would integrate with Stripe to process the payout
                    // For now, we'll just record it
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

// Get user's objective history
app.get('/objectives/history/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const { limit = 30 } = req.query;

        const { data, error } = await supabase
            .from('objective_sessions')
            .select(`
                *,
                logs:objective_logs(count)
            `)
            .eq('user_id', userId)
            .order('session_date', { ascending: false })
            .limit(parseInt(limit));

        if (error) {
            return res.status(400).json({ detail: error.message });
        }

        res.json(data);
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Get leaderboard
app.get('/objectives/leaderboard', async (req, res) => {
    try {
        const { period = 'week' } = req.query;
        
        let dateFilter = new Date();
        if (period === 'week') {
            dateFilter.setDate(dateFilter.getDate() - 7);
        } else if (period === 'month') {
            dateFilter.setMonth(dateFilter.getMonth() - 1);
        }

        const { data, error } = await supabase
            .from('objective_sessions')
            .select(`
                user_id,
                users!inner(full_name),
                completed_count,
                status
            `)
            .gte('session_date', dateFilter.toISOString().split('T')[0])
            .eq('status', 'completed')
            .order('completed_count', { ascending: false });

        if (error) {
            return res.status(400).json({ detail: error.message });
        }

        // Aggregate by user
        const leaderboard = {};
        data.forEach(session => {
            const userId = session.user_id;
            if (!leaderboard[userId]) {
                leaderboard[userId] = {
                    userId: userId,
                    name: session.users.full_name,
                    totalCompleted: 0,
                    sessionsCompleted: 0
                };
            }
            leaderboard[userId].totalCompleted += session.completed_count;
            leaderboard[userId].sessionsCompleted += 1;
        });

        const sortedLeaderboard = Object.values(leaderboard)
            .sort((a, b) => b.totalCompleted - a.totalCompleted)
            .slice(0, 10);

        res.json(sortedLeaderboard);
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});