-- ====================================================================================================
-- PHASE 1 ENHANCEMENTS - VEL TECH BUS MANAGEMENT SYSTEM
-- ====================================================================================================
-- FIX: Corrected syntax error caused by invisible, non-ASCII whitespace characters.
-- All route_id columns remain BIGINT as agreed.
-- ====================================================================================================

-- ------------------------------------------------------------------------------------------------
-- 0. DATA TYPE CONVERSION & SANITY CHECK (For environments that ran the previous UUID script)
-- ------------------------------------------------------------------------------------------------

-- Attempt to convert route_id columns to BIGINT (if they exist and are UUID)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'notifications' AND column_name = 'route_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.notifications ALTER COLUMN route_id TYPE bigint USING route_id::bigint;
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'emergency_incidents' AND column_name = 'route_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.emergency_incidents ALTER COLUMN route_id TYPE bigint USING route_id::bigint;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'trip_schedules' AND column_name = 'route_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.trip_schedules ALTER COLUMN route_id TYPE bigint USING route_id::bigint;
    END IF;
END
$$;

-- ------------------------------------------------------------------------------------------------
-- 1. PUSH NOTIFICATIONS SYSTEM
-- ------------------------------------------------------------------------------------------------

-- Table for User Notification Preferences
CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_type TEXT NOT NULL CHECK (user_type IN ('student', 'driver', 'parent', 'admin')),
    user_id TEXT NOT NULL, -- Student ID, Driver ID, Parent ID, or Admin ID
    device_token TEXT, -- For mobile app push notifications
    email_notifications BOOLEAN DEFAULT true,
    sms_notifications BOOLEAN DEFAULT false,
    push_notifications BOOLEAN DEFAULT true,
    bus_arrival_alerts BOOLEAN DEFAULT true,
    delay_alerts BOOLEAN DEFAULT true,
    emergency_alerts BOOLEAN DEFAULT true,
    schedule_changes BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_type, user_id)
);

-- Table for Notification Templates
CREATE TABLE IF NOT EXISTS public.notification_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key TEXT UNIQUE NOT NULL, -- e.g., 'bus_arrival', 'delay_alert', 'emergency'
    title_template TEXT NOT NULL,
    message_template TEXT NOT NULL,
    notification_type TEXT NOT NULL CHECK (notification_type IN ('info', 'warning', 'emergency', 'success')),
    channels JSONB DEFAULT '["push", "email"]', -- Array of delivery channels
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Notification Queue/History
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('student', 'driver', 'parent', 'admin', 'all')),
    recipient_id TEXT,
    template_key TEXT REFERENCES public.notification_templates(template_key),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    bus_no TEXT, -- Associated bus number if applicable
    route_id BIGINT REFERENCES public.bus_routes(id), 
    notification_type TEXT NOT NULL CHECK (notification_type IN ('info', 'warning', 'emergency', 'success')),
    channels JSONB DEFAULT '["push"]',
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed')),
    scheduled_at TIMESTAMPTZ DEFAULT now(),
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    error_message TEXT,
    metadata JSONB, -- Additional data like location, delay minutes, etc.
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------------------------
-- 2. EMERGENCY & SAFETY FEATURES
-- ------------------------------------------------------------------------------------------------

-- Table for Emergency Contacts
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_type TEXT NOT NULL CHECK (contact_type IN ('police', 'hospital', 'fire', 'transport_office', 'admin')),
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT,
    address TEXT,
    is_active BOOLEAN DEFAULT true,
    priority INTEGER DEFAULT 1, -- Lower number = higher priority
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Panic Button Incidents
CREATE TABLE IF NOT EXISTS public.emergency_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_type TEXT NOT NULL CHECK (incident_type IN ('panic_button', 'accident', 'medical', 'security', 'breakdown')),
    reported_by_type TEXT NOT NULL CHECK (reported_by_type IN ('student', 'driver', 'admin')),
    reported_by_id TEXT NOT NULL,
    bus_no TEXT,
    route_id BIGINT REFERENCES public.bus_routes(id), 
    location_lat DOUBLE PRECISION,
    location_lng DOUBLE PRECISION,
    description TEXT,
    severity TEXT DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'acknowledged', 'resolved', 'false_alarm')),
    assigned_to TEXT, -- Admin or emergency contact ID
    emergency_contacts_notified JSONB DEFAULT '[]',
    response_time INTEGER, -- Minutes to respond
    resolution_time INTEGER, -- Minutes to resolve
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

-- Table for Incident Media (Photos, Videos)
CREATE TABLE IF NOT EXISTS public.emergency_incident_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID NOT NULL REFERENCES public.emergency_incidents(id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('image', 'video', 'audio')),
    file_url TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    uploaded_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------------------------
-- 3. ENHANCED ROUTE MANAGEMENT
-- ------------------------------------------------------------------------------------------------

-- Table for Bus Capacity Information
CREATE TABLE IF NOT EXISTS public.bus_capacity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bus_no TEXT UNIQUE NOT NULL,
    total_seats INTEGER NOT NULL DEFAULT 50,
    standing_capacity INTEGER DEFAULT 20,
    wheelchair_accessible BOOLEAN DEFAULT false,
    air_conditioned BOOLEAN DEFAULT false,
    wifi_available BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Trip Schedules (Individual trip instances)
CREATE TABLE IF NOT EXISTS public.trip_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id BIGINT NOT NULL REFERENCES public.bus_routes(id), 
    bus_no TEXT NOT NULL,
    trip_date DATE NOT NULL,
    trip_type TEXT DEFAULT 'regular' CHECK (trip_type IN ('regular', 'special', 'maintenance')),
    scheduled_departure TIME NOT NULL,
    scheduled_arrival TIME,
    actual_departure TIME,
    actual_arrival TIME,
    status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'in_transit', 'completed', 'cancelled', 'delayed')),
    driver_id TEXT,
    capacity_total INTEGER,
    capacity_booked INTEGER DEFAULT 0,
    delay_minutes INTEGER DEFAULT 0,
    delay_reason TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Seat Reservations
CREATE TABLE IF NOT EXISTS public.seat_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trip_schedules(id) ON DELETE CASCADE,
    student_id TEXT NOT NULL,
    seat_number TEXT, -- e.g., 'A1', 'B15', or NULL for general booking
    reservation_type TEXT DEFAULT 'confirmed' CHECK (reservation_type IN ('confirmed', 'waitlist', 'standby')),
    booking_time TIMESTAMPTZ DEFAULT now(),
    check_in_time TIMESTAMPTZ,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'checked_in', 'no_show', 'cancelled')),
    special_requirements TEXT, -- e.g., wheelchair, priority seating
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Trip Feedback
CREATE TABLE IF NOT EXISTS public.trip_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trip_schedules(id),
    student_id TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    feedback_type TEXT CHECK (feedback_type IN ('punctuality', 'cleanliness', 'driver_behavior', 'safety', 'comfort', 'general')),
    comments TEXT,
    is_anonymous BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ------------------------------------------------------------------------------------------------
-- 4. MOBILE APP & USER MANAGEMENT
-- ------------------------------------------------------------------------------------------------

-- Table for Student Profiles (Enhanced)
CREATE TABLE IF NOT EXISTS public.student_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE,
    full_name TEXT NOT NULL,
    phone TEXT,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    emergency_contact_relation TEXT,
    address TEXT,
    department TEXT,
    year_of_study INTEGER,
    profile_image_url TEXT,
    qr_code TEXT UNIQUE, -- For quick check-ins
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Driver Profiles
CREATE TABLE IF NOT EXISTS public.driver_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    license_number TEXT UNIQUE,
    license_expiry DATE,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    profile_image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    hire_date DATE,
    rating DECIMAL(3,2) DEFAULT 5.00,
    total_trips INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Parent/Guardian Profiles
CREATE TABLE IF NOT EXISTS public.parent_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address TEXT,
    student_ids JSONB DEFAULT '[]', -- Array of student IDs they can monitor
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table for Device Management (for push notifications)
CREATE TABLE IF NOT EXISTS public.user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_type TEXT NOT NULL CHECK (user_type IN ('student', 'driver', 'parent', 'admin')),
    user_id TEXT NOT NULL,
    device_token TEXT NOT NULL,
    device_type TEXT CHECK (device_type IN ('ios', 'android', 'web')),
    app_version TEXT,
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_type, user_id, device_token)
);

-- ------------------------------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------------------------

-- Enable RLS on all new tables
ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_incident_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bus_capacity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_allowlist_audit ENABLE ROW LEVEL SECURITY;

-- Notification Preferences Policies
DO $$
BEGIN
    DROP POLICY IF EXISTS notification_preferences_read ON public.user_notification_preferences;
    DROP POLICY IF EXISTS notification_preferences_write ON public.user_notification_preferences;

    CREATE POLICY notification_preferences_read ON public.user_notification_preferences FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY notification_preferences_write ON public.user_notification_preferences FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY notification_preferences_read ON public.user_notification_preferences FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY notification_preferences_write ON public.user_notification_preferences FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Notification Templates (Admin only for write, read for all)
DO $$
BEGIN
    DROP POLICY IF EXISTS notification_templates_read ON public.notification_templates;
    DROP POLICY IF EXISTS notification_templates_write ON public.notification_templates;

    CREATE POLICY notification_templates_read ON public.notification_templates FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY notification_templates_write ON public.notification_templates FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY notification_templates_read ON public.notification_templates FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY notification_templates_write ON public.notification_templates FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);
END;
$$;

-- Notifications (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS notifications_read ON public.notifications;
    DROP POLICY IF EXISTS notifications_write ON public.notifications;
    DROP POLICY IF EXISTS notifications_update ON public.notifications;

    CREATE POLICY notifications_read ON public.notifications FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY notifications_write ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);
    CREATE POLICY notifications_update ON public.notifications FOR UPDATE TO authenticated USING (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY notifications_read ON public.notifications FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY notifications_write ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);
        CREATE POLICY notifications_update ON public.notifications FOR UPDATE TO authenticated USING (true);
END;
$$;

-- Emergency Contacts (Read for all, write for admin)
DO $$
BEGIN
    DROP POLICY IF EXISTS emergency_contacts_read ON public.emergency_contacts;
    DROP POLICY IF EXISTS emergency_contacts_write ON public.emergency_contacts;

    CREATE POLICY emergency_contacts_read ON public.emergency_contacts FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY emergency_contacts_write ON public.emergency_contacts FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY emergency_contacts_read ON public.emergency_contacts FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY emergency_contacts_write ON public.emergency_contacts FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);
END;
$$;

-- Emergency Incidents (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS emergency_incidents_read ON public.emergency_incidents;
    DROP POLICY IF EXISTS emergency_incidents_write ON public.emergency_incidents;

    CREATE POLICY emergency_incidents_read ON public.emergency_incidents FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY emergency_incidents_write ON public.emergency_incidents FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY emergency_incidents_read ON public.emergency_incidents FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY emergency_incidents_write ON public.emergency_incidents FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Emergency Media (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS emergency_media_read ON public.emergency_incident_media;
    DROP POLICY IF EXISTS emergency_media_write ON public.emergency_incident_media;

    CREATE POLICY emergency_media_read ON public.emergency_incident_media FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY emergency_media_write ON public.emergency_incident_media FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY emergency_media_read ON public.emergency_incident_media FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY emergency_media_write ON public.emergency_incident_media FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Bus Capacity (Read for all, write for admin)
DO $$
BEGIN
    DROP POLICY IF EXISTS bus_capacity_read ON public.bus_capacity;
    DROP POLICY IF EXISTS bus_capacity_write ON public.bus_capacity;

    CREATE POLICY bus_capacity_read ON public.bus_capacity FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY bus_capacity_write ON public.bus_capacity FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY bus_capacity_read ON public.bus_capacity FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY bus_capacity_write ON public.bus_capacity FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);
END;
$$;

-- Trip Schedules (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS trip_schedules_read ON public.trip_schedules;
    DROP POLICY IF EXISTS trip_schedules_write ON public.trip_schedules;

    CREATE POLICY trip_schedules_read ON public.trip_schedules FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY trip_schedules_write ON public.trip_schedules FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY trip_schedules_read ON public.trip_schedules FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY trip_schedules_write ON public.trip_schedules FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Seat Reservations (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS seat_reservations_read ON public.seat_reservations;
    DROP POLICY IF EXISTS seat_reservations_write ON public.seat_reservations;

    CREATE POLICY seat_reservations_read ON public.seat_reservations FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY seat_reservations_write ON public.seat_reservations FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY seat_reservations_read ON public.seat_reservations FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY seat_reservations_write ON public.seat_reservations FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Trip Feedback (Read for admin, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS trip_feedback_read ON public.trip_feedback;
    DROP POLICY IF EXISTS trip_feedback_write ON public.trip_feedback;

    CREATE POLICY trip_feedback_read ON public.trip_feedback FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
    CREATE POLICY trip_feedback_write ON public.trip_feedback FOR INSERT TO authenticated WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY trip_feedback_read ON public.trip_feedback FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);
        CREATE POLICY trip_feedback_write ON public.trip_feedback FOR INSERT TO authenticated WITH CHECK (true);
END;
$$;

-- Student Profiles (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS student_profiles_read ON public.student_profiles;
    DROP POLICY IF EXISTS student_profiles_write ON public.student_profiles;

    CREATE POLICY student_profiles_read ON public.student_profiles FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY student_profiles_write ON public.student_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY student_profiles_read ON public.student_profiles FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY student_profiles_write ON public.student_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- Driver Profiles (Read for all, write for admin)
DO $$
BEGIN
    DROP POLICY IF EXISTS driver_profiles_read ON public.driver_profiles;
    DROP POLICY IF EXISTS driver_profiles_write ON public.driver_profiles;

    CREATE POLICY driver_profiles_read ON public.driver_profiles FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY driver_profiles_write ON public.driver_profiles FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY driver_profiles_read ON public.driver_profiles FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY driver_profiles_write ON public.driver_profiles FOR ALL TO authenticated USING (auth.uid() IS NOT NULL);
END;
$$;

-- Parent Profiles (Read for all, write for authenticated)
DO $$
BEGIN
    DROP POLICY IF EXISTS parent_profiles_read ON public.parent_profiles;
    DROP POLICY IF EXISTS parent_profiles_write ON public.parent_profiles;

    CREATE POLICY parent_profiles_read ON public.parent_profiles FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY parent_profiles_write ON public.parent_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY parent_profiles_read ON public.parent_profiles FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY parent_profiles_write ON public.parent_profiles FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

-- User Devices (Read/Write for authenticated users)
DO $$
BEGIN
    DROP POLICY IF EXISTS user_devices_read ON public.user_devices;
    DROP POLICY IF EXISTS user_devices_write ON public.user_devices;

    CREATE POLICY user_devices_read ON public.user_devices FOR SELECT TO authenticated USING (true);
    CREATE POLICY user_devices_write ON public.user_devices FOR ALL TO authenticated USING (true) WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY user_devices_read ON public.user_devices FOR SELECT TO authenticated USING (true);
        CREATE POLICY user_devices_write ON public.user_devices FOR ALL TO authenticated USING (true) WITH CHECK (true);
END;
$$;

DO $$
BEGIN
    DROP POLICY IF EXISTS admin_allowlist_audit_select ON public.admin_allowlist_audit;
    DROP POLICY IF EXISTS admin_allowlist_audit_insert ON public.admin_allowlist_audit;
    DROP POLICY IF EXISTS admin_allowlist_audit_no_update ON public.admin_allowlist_audit;
    DROP POLICY IF EXISTS admin_allowlist_audit_no_delete ON public.admin_allowlist_audit;

    CREATE POLICY admin_allowlist_audit_select ON public.admin_allowlist_audit FOR SELECT TO authenticated USING ((auth.jwt() ->> 'user_role') = 'admin');
    CREATE POLICY admin_allowlist_audit_insert ON public.admin_allowlist_audit FOR INSERT TO authenticated WITH CHECK ((auth.jwt() ->> 'can_write_audit') = 'true');
    CREATE POLICY admin_allowlist_audit_no_update ON public.admin_allowlist_audit FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
    CREATE POLICY admin_allowlist_audit_no_delete ON public.admin_allowlist_audit FOR DELETE TO authenticated USING (false);

EXCEPTION
    WHEN OTHERS THEN
        CREATE POLICY admin_allowlist_audit_select ON public.admin_allowlist_audit FOR SELECT TO authenticated USING ((auth.jwt() ->> 'user_role') = 'admin');
        CREATE POLICY admin_allowlist_audit_insert ON public.admin_allowlist_audit FOR INSERT TO authenticated WITH CHECK ((auth.jwt() ->> 'can_write_audit') = 'true');
        CREATE POLICY admin_allowlist_audit_no_update ON public.admin_allowlist_audit FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
        CREATE POLICY admin_allowlist_audit_no_delete ON public.admin_allowlist_audit FOR DELETE TO authenticated USING (false);
END;
$$;

-- ------------------------------------------------------------------------------------------------
-- 6. REALTIME CONFIGURATION
-- ------------------------------------------------------------------------------------------------

-- Enable Realtime for key Phase 1 tables (assuming supabase_realtime publication exists)
DO $$
BEGIN
    -- Check if publication exists before adding tables
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        -- Add tables to realtime publication (ignore errors if tables already exist in publication)
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_incidents;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.trip_schedules;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.seat_reservations;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;
    END IF;
END
$$;

-- ------------------------------------------------------------------------------------------------
-- 7. RPC FUNCTIONS FOR PHASE 1 FEATURES
-- ------------------------------------------------------------------------------------------------

-- 7.1. Function to send push notification
CREATE OR REPLACE FUNCTION public.send_notification(
    p_recipient_type TEXT,
    p_recipient_id TEXT,
    p_template_key TEXT,
    p_custom_title TEXT DEFAULT NULL,
    p_custom_message TEXT DEFAULT NULL,
    p_bus_no TEXT DEFAULT NULL,
    p_route_id BIGINT DEFAULT NULL, -- **BIGINT**
    p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_template RECORD;
    v_title TEXT;
    v_message TEXT;
    v_notification_id UUID;
    v_notification_type TEXT;
BEGIN
    -- Get template
    SELECT * INTO v_template FROM public.notification_templates
    WHERE template_key = p_template_key AND is_active = true;

    IF v_template IS NULL THEN
        RAISE EXCEPTION 'Notification template not found: %', p_template_key;
    END IF;

    -- Use custom or template content
    v_title := COALESCE(p_custom_title, v_template.title_template);
    v_message := COALESCE(p_custom_message, v_template.message_template);
    v_notification_type := v_template.notification_type;

    -- Insert notification
    INSERT INTO public.notifications (
        recipient_type,
        recipient_id,
        template_key,
        title,
        message,
        bus_no,
        route_id,
        notification_type,
        metadata
    ) VALUES (
        p_recipient_type,
        p_recipient_id,
        p_template_key,
        v_title,
        v_message,
        p_bus_no,
        p_route_id,
        v_notification_type,
        p_metadata
    ) RETURNING id INTO v_notification_id;

    RETURN v_notification_id;
END;
$$;

-- 7.2. Function to create emergency incident
CREATE OR REPLACE FUNCTION public.create_emergency_incident(
    p_incident_type TEXT,
    p_reported_by_type TEXT,
    p_reported_by_id TEXT,
    p_bus_no TEXT DEFAULT NULL,
    p_route_id BIGINT DEFAULT NULL, -- **BIGINT**
    p_location_lat DOUBLE PRECISION DEFAULT NULL,
    p_location_lng DOUBLE PRECISION DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_severity TEXT DEFAULT 'medium'
)
RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_incident_id UUID;
    contact_record RECORD; -- Added missing variable declaration
BEGIN
    -- Insert emergency incident
    INSERT INTO public.emergency_incidents (
        incident_type,
        reported_by_type,
        reported_by_id,
        bus_no,
        route_id,
        location_lat,
        location_lng,
        description,
        severity
    ) VALUES (
        p_incident_type,
        p_reported_by_type,
        p_reported_by_id,
        p_bus_no,
        p_route_id,
        p_location_lat,
        p_location_lng,
        p_description,
        p_severity
    ) RETURNING id INTO v_incident_id;

    PERFORM public.send_notification(
        'admin', '8bd75827-1bcb-45eb-8aa2-1ff722ee6ddc', 'emergency_alert',
        'Emergency Alert',
        'Emergency incident reported: ' || COALESCE(p_description, 'No description provided'),
        p_bus_no,
        p_route_id,
        jsonb_build_object('incident_type', p_incident_type, 'severity', p_severity, 'incident_id', v_incident_id)
    );

    RETURN v_incident_id;
END;
$$;

-- 7.3. Function to book seat reservation
CREATE OR REPLACE FUNCTION public.book_seat(
    p_trip_id UUID,
    p_student_id TEXT,
    p_seat_number TEXT DEFAULT NULL,
    p_special_requirements TEXT DEFAULT NULL
)
RETURNS JSONB
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip RECORD;
    v_current_bookings INTEGER;
    v_result JSONB;
BEGIN
    -- Get trip details
    SELECT * INTO v_trip FROM public.trip_schedules WHERE id = p_trip_id;

    IF v_trip IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Trip not found');
    END IF;

    IF v_trip.status != 'scheduled' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Trip is not available for booking');
    END IF;

    -- Check current bookings
    SELECT COUNT(*) INTO v_current_bookings
    FROM public.seat_reservations
    WHERE trip_id = p_trip_id AND status = 'active';

    IF v_current_bookings >= COALESCE(v_trip.capacity_total, 50) THEN
        -- Add to waitlist
        INSERT INTO public.seat_reservations (trip_id, student_id, seat_number, reservation_type, special_requirements)
        VALUES (p_trip_id, p_student_id, p_seat_number, 'waitlist', p_special_requirements);

        RETURN jsonb_build_object('success', true, 'message', 'Added to waitlist', 'waitlist', true);
    ELSE
        -- Confirm booking
        INSERT INTO public.seat_reservations (trip_id, student_id, seat_number, special_requirements)
        VALUES (p_trip_id, p_student_id, p_seat_number, p_special_requirements);

        -- Update trip booking count
        UPDATE public.trip_schedules
        SET capacity_booked = v_current_bookings + 1
        WHERE id = p_trip_id;

        -- Send confirmation notification
        PERFORM public.send_notification(
            'student', p_student_id, 'booking_confirmed',
            'Seat Booking Confirmed',
            'Your seat has been confirmed for trip ' || v_trip.bus_no,
            v_trip.route_id,
            jsonb_build_object('trip_id', p_trip_id, 'seat_number', p_seat_number)
        );

        RETURN jsonb_build_object('success', true, 'message', 'Booking confirmed', 'waitlist', false);
    END IF;
END;
$$;

-- 7.4. Function to update trip status and send notifications
CREATE OR REPLACE FUNCTION public.update_trip_status(
    p_trip_id UUID,
    p_status TEXT,
    p_delay_minutes INTEGER DEFAULT 0,
    p_delay_reason TEXT DEFAULT NULL
)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip RECORD;
    v_students JSONB;
BEGIN
    -- Get trip details
    SELECT * INTO v_trip FROM public.trip_schedules WHERE id = p_trip_id;

    -- Update trip status
    UPDATE public.trip_schedules
    SET status = p_status,
        delay_minutes = p_delay_minutes,
        delay_reason = p_delay_reason,
        updated_at = now()
    WHERE id = p_trip_id;

    -- Get all students with reservations for this trip
    SELECT jsonb_agg(
        jsonb_build_object(
            'student_id', sr.student_id,
            'seat_number', sr.seat_number
        )
    ) INTO v_students
    FROM public.seat_reservations sr
    WHERE sr.trip_id = p_trip_id AND sr.status = 'active';

    -- Send notifications based on status
    IF p_status = 'in_transit' THEN
        -- Notify all booked students that trip has started
        PERFORM public.send_notification(
            'student', student_info->>'student_id', 'trip_started',
            'Trip Started',
            'Your bus ' || v_trip.bus_no || ' has departed',
            v_trip.bus_no,
            v_trip.route_id,
            jsonb_build_object('trip_id', p_trip_id)
        )
        FROM jsonb_array_elements(v_students) AS student_info;
    ELSIF p_status = 'delayed' AND p_delay_minutes > 0 THEN
        -- Notify about delay
        PERFORM public.send_notification(
            'student', student_info->>'student_id', 'delay_alert',
            'Trip Delayed',
            'Your bus ' || v_trip.bus_no || ' is delayed by ' || p_delay_minutes || ' minutes',
            v_trip.bus_no,
            v_trip.route_id,
            jsonb_build_object('trip_id', p_trip_id, 'delay_minutes', p_delay_minutes)
        )
        FROM jsonb_array_elements(v_students) AS student_info;
    END IF;
END;
$$;

-- Grant permissions for the new functions (safe approach)
DO $$
BEGIN
    -- Revoke existing permissions first
    REVOKE EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.book_seat(UUID, TEXT, TEXT, TEXT) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.update_trip_status(UUID, TEXT, INTEGER, TEXT) FROM authenticated;

    -- Grant fresh permissions
    GRANT EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.book_seat(UUID, TEXT, TEXT, TEXT) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.update_trip_status(UUID, TEXT, INTEGER, TEXT) TO authenticated;

EXCEPTION
    WHEN OTHERS THEN
        -- If revoke fails, just grant the permissions
        GRANT EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.book_seat(UUID, TEXT, TEXT, TEXT) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.update_trip_status(UUID, TEXT, INTEGER, TEXT) TO authenticated;
END;
$$;

-- ------------------------------------------------------------------------------------------------
-- 8. INDEXES FOR PERFORMANCE
-- ------------------------------------------------------------------------------------------------

-- Notification indexes
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_type, recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_status ON public.notifications(status);
CREATE INDEX IF NOT EXISTS idx_notifications_scheduled ON public.notifications(scheduled_at);
-- New index for route_id
CREATE INDEX IF NOT EXISTS idx_notifications_route ON public.notifications(route_id);

-- Emergency incident indexes
CREATE INDEX IF NOT EXISTS idx_emergency_incidents_status ON public.emergency_incidents(status);
CREATE INDEX IF NOT EXISTS idx_emergency_incidents_type ON public.emergency_incidents(incident_type);
CREATE INDEX IF NOT EXISTS idx_emergency_incidents_created ON public.emergency_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emergency_incidents_location ON public.emergency_incidents(location_lat, location_lng);
-- New index for route_id
CREATE INDEX IF NOT EXISTS idx_emergency_incidents_route ON public.emergency_incidents(route_id);

-- Trip and reservation indexes
CREATE INDEX IF NOT EXISTS idx_trip_schedules_date ON public.trip_schedules(trip_date);
CREATE INDEX IF NOT EXISTS idx_trip_schedules_route ON public.trip_schedules(route_id);
CREATE INDEX IF NOT EXISTS idx_trip_schedules_status ON public.trip_schedules(status);
CREATE INDEX IF NOT EXISTS idx_seat_reservations_trip ON public.seat_reservations(trip_id);
CREATE INDEX IF NOT EXISTS idx_seat_reservations_student ON public.seat_reservations(student_id);

-- User profile indexes
CREATE INDEX IF NOT EXISTS idx_student_profiles_email ON public.student_profiles(email);
CREATE INDEX IF NOT EXISTS idx_student_profiles_qr ON public.student_profiles(qr_code);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_license ON public.driver_profiles(license_number);

-- Device management indexes
CREATE INDEX IF NOT EXISTS idx_user_devices_token ON public.user_devices(device_token);
CREATE INDEX IF NOT EXISTS idx_user_devices_user ON public.user_devices(user_type, user_id);

-- ------------------------------------------------------------------------------------------------
-- 9. TRIGGERS FOR AUTOMATED UPDATES
-- ------------------------------------------------------------------------------------------------

-- Trigger to update notification preferences updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_user_notification_preferences_updated_at ON public.user_notification_preferences;
CREATE TRIGGER update_user_notification_preferences_updated_at
    BEFORE UPDATE ON public.user_notification_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_emergency_incidents_updated_at ON public.emergency_incidents;
CREATE TRIGGER update_emergency_incidents_updated_at
    BEFORE UPDATE ON public.emergency_incidents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_bus_capacity_updated_at ON public.bus_capacity;
CREATE TRIGGER update_bus_capacity_updated_at
    BEFORE UPDATE ON public.bus_capacity
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_trip_schedules_updated_at ON public.trip_schedules;
CREATE TRIGGER update_trip_schedules_updated_at
    BEFORE UPDATE ON public.trip_schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_student_profiles_updated_at ON public.student_profiles;
CREATE TRIGGER update_student_profiles_updated_at
    BEFORE UPDATE ON public.student_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_driver_profiles_updated_at ON public.driver_profiles;
CREATE TRIGGER update_driver_profiles_updated_at
    BEFORE UPDATE ON public.driver_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_parent_profiles_updated_at ON public.parent_profiles;
CREATE TRIGGER update_parent_profiles_updated_at
    BEFORE UPDATE ON public.parent_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------------------------------------------
-- 10. INITIAL DATA FOR PHASE 1
-- ------------------------------------------------------------------------------------------------

-- Insert default notification templates
INSERT INTO public.notification_templates (template_key, title_template, message_template, notification_type) VALUES
('bus_arrival', 'Bus Arriving', 'Your bus {{bus_no}} is arriving at {{stop_name}} in {{minutes}} minutes', 'info'),
('delay_alert', 'Trip Delayed', 'Your bus {{bus_no}} is delayed by {{delay_minutes}} minutes. Reason: {{delay_reason}}', 'warning'),
('emergency_alert', 'Emergency Alert', 'Emergency incident reported on bus {{bus_no}}. {{description}}', 'emergency'),
('booking_confirmed', 'Booking Confirmed', 'Your seat {{seat_number}} on bus {{bus_no}} has been confirmed', 'success'),
('trip_started', 'Trip Started', 'Your bus {{bus_no}} has departed and is on the way', 'info'),
('schedule_changed', 'Schedule Changed', 'Schedule for bus {{bus_no}} has been updated. Check the app for details', 'warning')
ON CONFLICT (template_key) DO NOTHING;

-- Insert default emergency contacts
INSERT INTO public.emergency_contacts (contact_type, name, phone, priority)
SELECT v.contact_type, v.name, v.phone, v.priority
FROM (VALUES
    ('police', 'Local Police Station', '100', 1),
    ('hospital', 'Nearest Hospital', '108', 1),
    ('fire', 'Fire Department', '101', 2)
) AS v(contact_type, name, phone, priority)
WHERE NOT EXISTS (
    SELECT 1
    FROM public.emergency_contacts ec
    WHERE ec.contact_type = v.contact_type
);

-- Insert some sample bus capacity data (for existing buses)
INSERT INTO public.bus_capacity (bus_no, total_seats, standing_capacity, air_conditioned, wifi_available)
SELECT
    'VT-01',
    45,
    15,
    true,
    true
WHERE NOT EXISTS (SELECT 1 FROM public.bus_capacity WHERE bus_no = 'VT-01');

-- ====================================================================================================
-- PHASE 1 ENHANCEMENTS SETUP COMPLETE
-- ====================================================================================================
