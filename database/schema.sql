-- GoaGuide Database Schema for Supabase
-- Run this in Supabase SQL Editor

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types
CREATE TYPE trip_status AS ENUM ('planning', 'ready', 'booked', 'completed', 'cancelled');
CREATE TYPE booking_status AS ENUM ('hold', 'confirmed', 'cancelled', 'refunded');
CREATE TYPE gender_type AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');
CREATE TYPE trip_type AS ENUM ('family', 'solo', 'couple', 'friends', 'business', 'adventure');
CREATE TYPE age_bracket AS ENUM ('18-25', '26-35', '36-45', '46-55', '55+');
CREATE TYPE budget_bracket AS ENUM ('budget', 'mid_range', 'luxury');

-- Trips table
CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    destination VARCHAR(100) NOT NULL DEFAULT 'Goa',
    status trip_status DEFAULT 'planning',
    input_text TEXT,
    
    -- Anonymized profile (privacy-first)
    age_bracket age_bracket,
    gender gender_type,
    party_size INTEGER DEFAULT 1,
    trip_type trip_type,
    budget_bracket budget_bracket,
    budget_per_person DECIMAL(10,2),
    
    -- Questionnaire responses
    questionnaire_responses JSONB DEFAULT '{}',
    
    -- Consent management
    consent_tokens JSONB DEFAULT '{}',
    pii_shared BOOLEAN DEFAULT FALSE,
    
    -- Metadata
    feature_flags_snapshot JSONB DEFAULT '{}',
    trace_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Consent records for audit trail
CREATE TABLE consent_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    consent_token VARCHAR(255) UNIQUE NOT NULL,
    pii_categories TEXT[] NOT NULL,
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    trace_id VARCHAR(255)
);

-- Points of Interest with spatial data
CREATE TABLE pois (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL,
    location GEOMETRY(POINT, 4326) NOT NULL,
    address TEXT,
    opening_hours JSONB,
    price_range VARCHAR(20),
    rating DECIMAL(3,2) DEFAULT 0.00,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Events with spatial and temporal data
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(50),
    location GEOMETRY(POINT, 4326) NOT NULL,
    address TEXT,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE,
    
    -- Event metadata
    source VARCHAR(100),
    confidence_score DECIMAL(3,2) DEFAULT 0.00,
    requires_curation BOOLEAN DEFAULT TRUE,
    curator_approved BOOLEAN DEFAULT FALSE,
    capacity INTEGER,
    current_bookings INTEGER DEFAULT 0,
    
    -- Pricing
    price DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'INR',
    
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Providers/Vendors
CREATE TABLE providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    location GEOMETRY(POINT, 4326),
    
    -- KYC and verification
    kyc_status VARCHAR(20) DEFAULT 'pending',
    kyc_documents JSONB DEFAULT '{}',
    verification_date TIMESTAMP WITH TIME ZONE,
    
    -- Business metrics
    rating DECIMAL(3,2) DEFAULT 0.00,
    total_bookings INTEGER DEFAULT 0,
    active BOOLEAN DEFAULT TRUE,
    
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RFPs (Request for Proposals)
CREATE TABLE rfps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    
    -- Anonymized requirements only
    anonymized_requirements JSONB NOT NULL,
    budget_range JSONB NOT NULL,
    
    -- RFP lifecycle
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    
    -- Audit
    trace_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Provider offers
CREATE TABLE offers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfp_id UUID REFERENCES rfps(id) ON DELETE CASCADE,
    provider_id UUID REFERENCES providers(id) ON DELETE CASCADE,
    
    -- Offer details
    price DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    description TEXT,
    inclusions JSONB DEFAULT '{}',
    
    -- Offer lifecycle
    validity_hours INTEGER DEFAULT 24,
    status VARCHAR(20) DEFAULT 'active',
    expires_at TIMESTAMP WITH TIME ZONE,
    
    -- Audit
    trace_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Bookings
CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    offer_id UUID REFERENCES offers(id),
    user_id UUID NOT NULL,
    provider_id UUID REFERENCES providers(id),
    
    -- Booking details
    status booking_status DEFAULT 'hold',
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'INR',
    
    -- Payment
    payment_token VARCHAR(255),
    payment_method VARCHAR(50),
    
    -- Booking lifecycle
    hold_expires_at TIMESTAMP WITH TIME ZONE,
    confirmed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    
    -- Refunds
    refund_amount DECIMAL(10,2),
    refund_status VARCHAR(20),
    refund_processed_at TIMESTAMP WITH TIME ZONE,
    
    -- Audit
    trace_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Idempotency for booking operations
CREATE TABLE booking_idempotency (
    idempotency_key VARCHAR(255) PRIMARY KEY,
    booking_id UUID REFERENCES bookings(id),
    response_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() + INTERVAL '24 hours'
);

-- Photo verification
CREATE TABLE photo_verifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID REFERENCES trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    
    -- Photo data
    photo_url VARCHAR(500) NOT NULL,
    photo_hash VARCHAR(64),
    
    -- EXIF data
    exif_data JSONB,
    gps_coordinates GEOMETRY(POINT, 4326),
    timestamp_taken TIMESTAMP WITH TIME ZONE,
    
    -- Verification results
    verification_status VARCHAR(20) DEFAULT 'pending',
    confidence_score DECIMAL(3,2),
    manual_review_required BOOLEAN DEFAULT FALSE,
    approved_by UUID,
    approved_at TIMESTAMP WITH TIME ZONE,
    
    -- Device attestation
    device_attestation JSONB,
    
    -- Audit
    trace_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Audit log (immutable)
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Event identification
    event_type VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    
    -- User context
    user_id UUID,
    session_id VARCHAR(255),
    
    -- Request context
    trace_id VARCHAR(255),
    request_id VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    
    -- Event data
    event_data JSONB NOT NULL,
    before_state JSONB,
    after_state JSONB,
    
    -- Feature flags snapshot
    feature_flags_snapshot JSONB,
    
    -- Consent snapshot
    consent_snapshot JSONB,
    
    -- Metadata
    service_name VARCHAR(50),
    service_version VARCHAR(20),
    
    -- Immutable timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Feature flags
CREATE TABLE feature_flags (
    name VARCHAR(100) PRIMARY KEY,
    enabled BOOLEAN DEFAULT FALSE,
    rollout_percentage INTEGER DEFAULT 0 CHECK (rollout_percentage >= 0 AND rollout_percentage <= 100),
    user_segments TEXT[] DEFAULT '{}',
    description TEXT,
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create spatial indexes
CREATE INDEX idx_pois_location ON pois USING GIST(location);
CREATE INDEX idx_events_location ON events USING GIST(location);
CREATE INDEX idx_events_date_range ON events (start_date, end_date);
CREATE INDEX idx_providers_location ON providers USING GIST(location);
CREATE INDEX idx_photo_gps ON photo_verifications USING GIST(gps_coordinates);

-- Create regular indexes
CREATE INDEX idx_trips_user_id ON trips(user_id);
CREATE INDEX idx_trips_status ON trips(status);
CREATE INDEX idx_trips_created_at ON trips(created_at);
CREATE INDEX idx_bookings_trip_id ON bookings(trip_id);
CREATE INDEX idx_bookings_user_id ON bookings(user_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_audit_log_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);
CREATE INDEX idx_audit_log_trace ON audit_log(trace_id);
CREATE INDEX idx_audit_log_created_at ON audit_log(created_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON trips
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pois_updated_at BEFORE UPDATE ON pois
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_providers_updated_at BEFORE UPDATE ON providers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default feature flags
INSERT INTO feature_flags (name, enabled, description) VALUES
('trip_creation_enabled', true, 'Enable trip creation functionality'),
('questionnaire_flow', true, 'Enable dynamic questionnaire'),
('events_ingest', true, 'Enable event ingestion from external sources'),
('provider_rfp', true, 'Enable RFP system for providers'),
('auto_book', false, 'Enable automatic booking confirmation'),
('adventure_validator', false, 'Enable adventure activity validation'),
('photo_verification', true, 'Enable photo verification for activities'),
('llm_orchestrator', true, 'Enable LLM-powered features'),
('real_time_pricing', false, 'Enable dynamic pricing algorithms'),
('ml_recommendations', false, 'Enable ML-based recommendations');

-- Insert sample POIs for Goa
INSERT INTO pois (name, description, category, location, address, price_range) VALUES
('Baga Beach', 'Popular beach with water sports and nightlife', 'beach', ST_GeomFromText('POINT(73.7519 15.5557)', 4326), 'Baga, Goa', 'free'),
('Fort Aguada', 'Historic Portuguese fort with lighthouse', 'historical', ST_GeomFromText('POINT(73.7736 15.4909)', 4326), 'Candolim, Goa', 'budget'),
('Dudhsagar Falls', 'Spectacular four-tiered waterfall', 'nature', ST_GeomFromText('POINT(74.3144 15.3142)', 4326), 'Mollem, Goa', 'budget'),
('Basilica of Bom Jesus', 'UNESCO World Heritage church', 'religious', ST_GeomFromText('POINT(73.9115 15.5007)', 4326), 'Old Goa', 'free'),
('Anjuna Beach', 'Famous for flea market and trance parties', 'beach', ST_GeomFromText('POINT(73.7407 15.5735)', 4326), 'Anjuna, Goa', 'free'),
('Spice Plantation', 'Organic spice plantation tour', 'nature', ST_GeomFromText('POINT(74.1240 15.2993)', 4326), 'Ponda, Goa', 'mid_range'),
('Casino Royale', 'Floating casino on Mandovi River', 'entertainment', ST_GeomFromText('POINT(73.8370 15.4989)', 4326), 'Panaji, Goa', 'luxury'),
('Calangute Beach', 'Queen of beaches with water sports', 'beach', ST_GeomFromText('POINT(73.7553 15.5430)', 4326), 'Calangute, Goa', 'budget');

-- Insert sample events
INSERT INTO events (title, description, category, location, address, start_date, end_date, price, confidence_score, curator_approved) VALUES
('Sunburn Festival', 'Asia largest music festival', 'festival', ST_GeomFromText('POINT(73.7519 15.5557)', 4326), 'Vagator Beach, Goa', '2024-12-28 18:00:00+05:30', '2024-12-31 06:00:00+05:30', 5000.00, 0.95, true),
('Saturday Night Market', 'Weekly flea market with local crafts', 'market', ST_GeomFromText('POINT(73.7407 15.5735)', 4326), 'Anjuna Beach, Goa', '2024-02-17 18:00:00+05:30', '2024-02-18 02:00:00+05:30', 0.00, 0.90, true),
('Goa Carnival', 'Traditional Portuguese carnival celebration', 'cultural', ST_GeomFromText('POINT(73.8370 15.4989)', 4326), 'Panaji, Goa', '2024-02-10 16:00:00+05:30', '2024-02-13 22:00:00+05:30', 0.00, 0.98, true),
('Shigmo Festival', 'Hindu spring festival with parades', 'festival', ST_GeomFromText('POINT(73.8370 15.4989)', 4326), 'Panaji, Goa', '2024-03-25 10:00:00+05:30', '2024-03-25 20:00:00+05:30', 0.00, 0.92, true);

-- Row Level Security (RLS) policies
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE photo_verifications ENABLE ROW LEVEL SECURITY;

-- Users can only access their own trips
CREATE POLICY "Users can view own trips" ON trips
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own trips" ON trips
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own trips" ON trips
    FOR UPDATE USING (auth.uid() = user_id);

-- Users can only access their own bookings
CREATE POLICY "Users can view own bookings" ON bookings
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own bookings" ON bookings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can only access their own photo verifications
CREATE POLICY "Users can view own photos" ON photo_verifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can upload own photos" ON photo_verifications
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Public read access for POIs and events
CREATE POLICY "Anyone can view POIs" ON pois FOR SELECT USING (true);
CREATE POLICY "Anyone can view approved events" ON events FOR SELECT USING (curator_approved = true);

-- Create a function to log audit events
CREATE OR REPLACE FUNCTION log_audit_event(
    p_event_type VARCHAR,
    p_entity_type VARCHAR,
    p_entity_id UUID,
    p_event_data JSONB,
    p_before_state JSONB DEFAULT NULL,
    p_after_state JSONB DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    audit_id UUID;
BEGIN
    INSERT INTO audit_log (
        event_type,
        entity_type,
        entity_id,
        user_id,
        trace_id,
        event_data,
        before_state,
        after_state,
        service_name
    ) VALUES (
        p_event_type,
        p_entity_type,
        p_entity_id,
        auth.uid(),
        current_setting('app.trace_id', true),
        p_event_data,
        p_before_state,
        p_after_state,
        'goaguide-api'
    ) RETURNING id INTO audit_id;
    
    RETURN audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
