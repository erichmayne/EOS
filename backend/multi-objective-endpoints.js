// Multi-Objective Endpoints (Future Feature)
// Add these to server.js when ready to enable multi-objective support

// ========== MULTI-OBJECTIVE ENDPOINTS (FUTURE) ==========

// Get user's active objectives
app.get('/objectives/user/:userId/active', async (req, res) => {
    try {
        const { userId } = req.params;
        
        // For now, return current single objective format
        const { data: user } = await supabase
            .from('users')
            .select('objective_type, objective_count, objective_schedule, objective_deadline')
            .eq('id', userId)
            .single();
            
        if (!user) {
            return res.status(404).json({ detail: 'User not found' });
        }
        
        // Format as array for future compatibility
        const objectives = [{
            type: user.objective_type,
            target_value: user.objective_count,
            target_unit: 'reps',
            deadline: user.objective_deadline,
            schedule: user.objective_schedule
        }];
        
        res.json({ objectives, mode: 'single' }); // mode indicates single vs multi
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Create multi-objective session (future)
app.post('/objectives/sessions/multi/create', async (req, res) => {
    try {
        const { userId } = req.body;
        const today = new Date().toISOString().split('T')[0];
        
        // Check if multi-objectives are enabled for user
        const { data: objectives } = await supabase
            .from('user_objectives')
            .select('*')
            .eq('user_id', userId)
            .eq('active', true);
            
        if (!objectives || objectives.length === 0) {
            // Fall back to single objective system
            return res.json({ 
                message: 'No multi-objectives configured, use single objective endpoints',
                mode: 'single'
            });
        }
        
        // Create multi-objective session
        const objectivesData = {};
        let earliestDeadline = '23:59';
        let latestDeadline = '00:00';
        
        objectives.forEach(obj => {
            objectivesData[obj.objective_type] = {
                target: obj.target_value,
                unit: obj.target_unit,
                deadline: obj.deadline,
                completed: 0,
                status: 'pending'
            };
            
            // Track deadline range
            if (obj.deadline < earliestDeadline) earliestDeadline = obj.deadline;
            if (obj.deadline > latestDeadline) latestDeadline = obj.deadline;
        });
        
        // Get user's committed payout
        const { data: user } = await supabase
            .from('users')
            .select('missed_goal_payout')
            .eq('id', userId)
            .single();
        
        const { data: session, error } = await supabase
            .from('objective_sessions_v2')
            .insert({
                user_id: userId,
                session_date: today,
                objectives: objectivesData,
                overall_status: 'pending',
                payout_amount: user.missed_goal_payout,
                earliest_deadline: earliestDeadline,
                latest_deadline: latestDeadline
            })
            .select()
            .single();
            
        if (error) {
            return res.status(400).json({ detail: error.message });
        }
        
        res.json({ session, mode: 'multi' });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Log progress for specific objective type
app.post('/objectives/sessions/multi/log', async (req, res) => {
    try {
        const { userId, objectiveType, value } = req.body;
        const today = new Date().toISOString().split('T')[0];
        
        // Get multi-objective session
        const { data: session } = await supabase
            .from('objective_sessions_v2')
            .select('*')
            .eq('user_id', userId)
            .eq('session_date', today)
            .single();
            
        if (!session) {
            // Fall back to single objective
            return res.json({ 
                message: 'No multi-objective session, use single objective endpoints',
                mode: 'single'
            });
        }
        
        // Update specific objective
        const objectives = session.objectives;
        if (!objectives[objectiveType]) {
            return res.status(400).json({ detail: 'Objective type not found' });
        }
        
        // Update based on direction
        const objective = objectives[objectiveType];
        if (objectiveType === 'screen_time') {
            // Accumulate for "stay under" objectives
            objective.completed += value;
        } else {
            // Set for "meet or exceed" objectives
            objective.completed = value;
        }
        
        // Check if completed
        const isCompleted = checkObjectiveCompletion(objective);
        objective.status = isCompleted ? 'completed' : 'in_progress';
        
        // Check overall status
        let allCompleted = true;
        let anyMissed = false;
        
        Object.entries(objectives).forEach(([type, obj]) => {
            if (new Date(`2000-01-01 ${obj.deadline}`) < new Date(`2000-01-01 ${new Date().toTimeString().slice(0,5)}`)) {
                // Past deadline
                if (obj.status !== 'completed') {
                    obj.status = 'missed';
                    anyMissed = true;
                }
            }
            if (obj.status !== 'completed') {
                allCompleted = false;
            }
        });
        
        // Update session
        const overallStatus = anyMissed ? 'missed' : (allCompleted ? 'completed' : 'in_progress');
        
        const { data: updated, error } = await supabase
            .from('objective_sessions_v2')
            .update({
                objectives: objectives,
                overall_status: overallStatus,
                updated_at: new Date()
            })
            .eq('id', session.id)
            .select()
            .single();
            
        if (error) {
            return res.status(400).json({ detail: error.message });
        }
        
        res.json({
            session: updated,
            objective: objectives[objectiveType],
            message: getStatusMessage(objectiveType, objectives[objectiveType])
        });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Check multi-objective sessions for payouts
app.post('/objectives/multi/check-missed', async (req, res) => {
    try {
        const now = new Date();
        const currentTime = now.toTimeString().slice(0, 5);
        
        // Find sessions with objectives past their deadlines
        const { data: sessions } = await supabase
            .from('objective_sessions_v2')
            .select('*')
            .eq('session_date', now.toISOString().split('T')[0])
            .eq('overall_status', 'in_progress')
            .lte('earliest_deadline', currentTime);
            
        const results = [];
        
        for (const session of sessions || []) {
            let anyMissed = false;
            const objectives = session.objectives;
            
            // Check each objective
            Object.entries(objectives).forEach(([type, obj]) => {
                if (obj.deadline <= currentTime && obj.status !== 'completed') {
                    obj.status = 'missed';
                    anyMissed = true;
                }
            });
            
            if (anyMissed && !session.payout_triggered) {
                // Trigger single payout for all missed objectives
                const { data: transaction } = await supabase
                    .from('transactions')
                    .insert({
                        user_id: session.user_id,
                        type: 'payout',
                        amount_cents: Math.round(session.payout_amount * 100),
                        status: 'pending',
                        description: 'Missed daily objectives',
                        metadata: {
                            session_id: session.id,
                            objectives_missed: Object.entries(objectives)
                                .filter(([_, obj]) => obj.status === 'missed')
                                .map(([type, _]) => type)
                        }
                    })
                    .select()
                    .single();
                    
                // Update session
                await supabase
                    .from('objective_sessions_v2')
                    .update({
                        objectives: objectives,
                        overall_status: 'missed',
                        payout_triggered: true,
                        payout_transaction_id: transaction.id,
                        updated_at: new Date()
                    })
                    .eq('id', session.id);
                    
                results.push({
                    sessionId: session.id,
                    userId: session.user_id,
                    amount: session.payout_amount,
                    objectivesMissed: Object.entries(objectives)
                        .filter(([_, obj]) => obj.status === 'missed')
                        .map(([type, _]) => type)
                });
            }
        }
        
        res.json({
            sessionsChecked: sessions?.length || 0,
            payoutsTriggered: results
        });
    } catch (error) {
        res.status(500).json({ detail: error.message });
    }
});

// Helper functions
function checkObjectiveCompletion(objective) {
    // Logic depends on objective type and direction
    // For now, simple comparison
    return objective.completed >= objective.target;
}

function getStatusMessage(type, objective) {
    if (objective.status === 'completed') {
        return `✅ ${type} completed!`;
    }
    
    const remaining = objective.target - objective.completed;
    return `${objective.completed}/${objective.target} ${objective.unit} (${remaining} remaining)`;
}