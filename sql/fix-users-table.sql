-- Fix Users Table - Add Missing Columns
-- Run this in Supabase SQL Editor

-- Add missing columns to users table (will ignore if they already exist)
DO $$ 
BEGIN
    -- Core user fields
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'full_name') THEN
        ALTER TABLE users ADD COLUMN full_name VARCHAR(255);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'phone') THEN
        ALTER TABLE users ADD COLUMN phone VARCHAR(50);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'password_hash') THEN
        ALTER TABLE users ADD COLUMN password_hash VARCHAR(255);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'balance_cents') THEN
        ALTER TABLE users ADD COLUMN balance_cents INTEGER DEFAULT 0;
    END IF;
    
    -- Stripe fields
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'stripe_customer_id') THEN
        ALTER TABLE users ADD COLUMN stripe_customer_id VARCHAR(255);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'stripe_payment_method_id') THEN
        ALTER TABLE users ADD COLUMN stripe_payment_method_id VARCHAR(255);
    END IF;
    
    -- Objective fields
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'objective_type') THEN
        ALTER TABLE users ADD COLUMN objective_type VARCHAR(50) DEFAULT 'pushups';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'objective_count') THEN
        ALTER TABLE users ADD COLUMN objective_count INTEGER DEFAULT 50;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'objective_schedule') THEN
        ALTER TABLE users ADD COLUMN objective_schedule VARCHAR(20) DEFAULT 'daily';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'objective_deadline') THEN
        ALTER TABLE users ADD COLUMN objective_deadline TIME DEFAULT '09:00';
    END IF;
    
    -- Payout fields
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'missed_goal_payout') THEN
        ALTER TABLE users ADD COLUMN missed_goal_payout DECIMAL(10,2) DEFAULT 0.00;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'payout_destination') THEN
        ALTER TABLE users ADD COLUMN payout_destination VARCHAR(20) DEFAULT 'charity';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'payout_committed') THEN
        ALTER TABLE users ADD COLUMN payout_committed BOOLEAN DEFAULT FALSE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'custom_recipient_id') THEN
        ALTER TABLE users ADD COLUMN custom_recipient_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'timezone') THEN
        ALTER TABLE users ADD COLUMN timezone VARCHAR(50) DEFAULT 'America/New_York';
    END IF;
    
    -- Timestamps
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'created_at') THEN
        ALTER TABLE users ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'updated_at') THEN
        ALTER TABLE users ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Verify the columns were added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'users' 
ORDER BY ordinal_position;
