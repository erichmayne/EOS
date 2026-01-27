-- EOS Database Schema for Supabase
-- Run this in your Supabase SQL Editor to create all necessary tables

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing tables if they exist (be careful with this in production!)
-- Uncomment these lines if you want to reset the database
-- DROP TABLE IF EXISTS payout_events CASCADE;
-- DROP TABLE IF EXISTS payout_rules CASCADE;
-- DROP TABLE IF EXISTS recipient_invites CASCADE;
-- DROP TABLE IF EXISTS recipients CASCADE;
-- DROP TABLE IF EXISTS users CASCADE;

-- Create users table
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stripe_customer_id TEXT UNIQUE,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    phone TEXT,
    password_hash TEXT NOT NULL,
    active_balance_cents INTEGER NOT NULL DEFAULT 0,
    is_signed_in BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for email lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_stripe_customer_id ON public.users(stripe_customer_id);

-- Create recipients table
CREATE TABLE IF NOT EXISTS public.recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL CHECK (type IN ('individual', 'charity')),
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    stripe_connect_account_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for stripe account lookups
CREATE INDEX IF NOT EXISTS idx_recipients_stripe_account ON public.recipients(stripe_connect_account_id);
CREATE INDEX IF NOT EXISTS idx_recipients_phone ON public.recipients(phone);

-- Create recipient_invites table
CREATE TABLE IF NOT EXISTS public.recipient_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payer_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    phone TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired')),
    recipient_id UUID REFERENCES public.recipients(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for invite lookups
CREATE INDEX IF NOT EXISTS idx_recipient_invites_code ON public.recipient_invites(invite_code);
CREATE INDEX IF NOT EXISTS idx_recipient_invites_payer ON public.recipient_invites(payer_user_id);
CREATE INDEX IF NOT EXISTS idx_recipient_invites_status ON public.recipient_invites(status);
CREATE INDEX IF NOT EXISTS idx_recipient_invites_phone ON public.recipient_invites(phone);

-- Create payout_rules table
CREATE TABLE IF NOT EXISTS public.payout_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payer_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES public.recipients(id) ON DELETE CASCADE,
    fixed_amount_cents INTEGER NOT NULL CHECK (fixed_amount_cents > 0),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for payout rules
CREATE INDEX IF NOT EXISTS idx_payout_rules_payer ON public.payout_rules(payer_user_id);
CREATE INDEX IF NOT EXISTS idx_payout_rules_recipient ON public.payout_rules(recipient_id);
CREATE INDEX IF NOT EXISTS idx_payout_rules_active ON public.payout_rules(active);

-- Create payout_events table
CREATE TABLE IF NOT EXISTS public.payout_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payer_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES public.recipients(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    goal_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'processing', 'paid', 'failed')),
    stripe_transfer_id TEXT,
    stripe_payout_id TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for payout events
CREATE INDEX IF NOT EXISTS idx_payout_events_status ON public.payout_events(status);
CREATE INDEX IF NOT EXISTS idx_payout_events_goal_date ON public.payout_events(goal_date);
CREATE INDEX IF NOT EXISTS idx_payout_events_payer ON public.payout_events(payer_user_id);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add updated_at triggers to all tables
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_recipients_updated_at ON public.recipients;
CREATE TRIGGER update_recipients_updated_at BEFORE UPDATE ON public.recipients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_recipient_invites_updated_at ON public.recipient_invites;
CREATE TRIGGER update_recipient_invites_updated_at BEFORE UPDATE ON public.recipient_invites
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_payout_rules_updated_at ON public.payout_rules;
CREATE TRIGGER update_payout_rules_updated_at BEFORE UPDATE ON public.payout_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_payout_events_updated_at ON public.payout_events;
CREATE TRIGGER update_payout_events_updated_at BEFORE UPDATE ON public.payout_events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions (adjust based on your Supabase setup)
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres;

-- Optional: Enable Row Level Security (RLS) if needed
-- ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.recipients ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.recipient_invites ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.payout_rules ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.payout_events ENABLE ROW LEVEL SECURITY;

-- Test query to verify tables exist
SELECT 
    'users' as table_name, 
    COUNT(*) as row_count 
FROM public.users
UNION ALL
SELECT 
    'recipients', 
    COUNT(*) 
FROM public.recipients
UNION ALL
SELECT 
    'recipient_invites', 
    COUNT(*) 
FROM public.recipient_invites
UNION ALL
SELECT 
    'payout_rules', 
    COUNT(*) 
FROM public.payout_rules
UNION ALL
SELECT 
    'payout_events', 
    COUNT(*) 
FROM public.payout_events;