-- ====================================================================================================
-- EMERGENCY FUNCTIONALITY FIX - VEL TECH BUS MANAGEMENT
-- ====================================================================================================
-- This script creates the missing database functions and tables for emergency features

-- 1. Create Emergency Contacts table
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_type TEXT NOT NULL CHECK (contact_type IN ('police', 'hospital', 'fire', 'transport_office', 'admin')),
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    email TEXT,
    address TEXT,
    is_active BOOLEAN DEFAULT true,
    priority INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create Emergency Incidents table
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
    assigned_to TEXT,
    emergency_contacts_notified JSONB DEFAULT '[]',
    response_time INTEGER,
    resolution_time INTEGER,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

-- 3. Create Notifications table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('student', 'driver', 'parent', 'admin', 'all')),
    recipient_id TEXT,
    template_key TEXT,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    bus_no TEXT,
    route_id BIGINT REFERENCES public.bus_routes(id),
    notification_type TEXT NOT NULL CHECK (notification_type IN ('info', 'warning', 'emergency', 'success')),
    channels JSONB DEFAULT '["push"]',
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed')),
    scheduled_at TIMESTAMPTZ DEFAULT now(),
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Enable RLS and create policies (drop existing first if they exist)
DO $$
BEGIN
    -- Drop existing policies if they exist to avoid conflicts
    DROP POLICY IF EXISTS emergency_contacts_read ON public.emergency_contacts;
    DROP POLICY IF EXISTS emergency_incidents_read ON public.emergency_incidents;
    DROP POLICY IF EXISTS emergency_incidents_write ON public.emergency_incidents;
    DROP POLICY IF EXISTS notifications_read ON public.notifications;
    DROP POLICY IF EXISTS notifications_write ON public.notifications;

    -- Create fresh policies
    CREATE POLICY emergency_contacts_read ON public.emergency_contacts FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY emergency_incidents_read ON public.emergency_incidents FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY emergency_incidents_write ON public.emergency_incidents FOR ALL TO authenticated USING (true) WITH CHECK (true);
    CREATE POLICY notifications_read ON public.notifications FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY notifications_write ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);

EXCEPTION
    WHEN OTHERS THEN
        -- If policies don't exist, create them without dropping
        CREATE POLICY emergency_contacts_read ON public.emergency_contacts FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY emergency_incidents_read ON public.emergency_incidents FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY emergency_incidents_write ON public.emergency_incidents FOR ALL TO authenticated USING (true) WITH CHECK (true);
        CREATE POLICY notifications_read ON public.notifications FOR SELECT TO anon, authenticated USING (true);
        CREATE POLICY notifications_write ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);
END;
$$;

-- 5. Create the notification function
CREATE OR REPLACE FUNCTION public.send_notification(
    p_recipient_type TEXT,
    p_recipient_id TEXT,
    p_template_key TEXT,
    p_custom_title TEXT DEFAULT NULL,
    p_custom_message TEXT DEFAULT NULL,
    p_bus_no TEXT DEFAULT NULL,
    p_route_id BIGINT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
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
        COALESCE(p_custom_title, 'Notification'),
        COALESCE(p_custom_message, 'You have a new notification'),
        p_bus_no,
        p_route_id,
        'info',
        p_metadata
    ) RETURNING id INTO v_notification_id;

    RETURN v_notification_id;
END;
$$;

-- 6. Create the emergency incident function
CREATE OR REPLACE FUNCTION public.create_emergency_incident(
    p_incident_type TEXT,
    p_reported_by_type TEXT,
    p_reported_by_id TEXT,
    p_bus_no TEXT DEFAULT NULL,
    p_route_id BIGINT DEFAULT NULL,
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

    -- Send emergency notification to all active emergency contacts
    FOR contact_record IN
        SELECT phone, name FROM public.emergency_contacts
        WHERE is_active = true ORDER BY priority
    LOOP
        PERFORM public.send_notification(
            'admin', NULL, 'emergency_alert',
            'Emergency Alert',
            'Emergency incident reported: ' || COALESCE(p_description, 'No description') || ' Contact: ' || contact_record.name,
            p_bus_no,
            p_route_id,
            jsonb_build_object('incident_type', p_incident_type, 'severity', p_severity, 'contact_phone', contact_record.phone)
        );
    END LOOP;

    RETURN v_incident_id;
END;
$$;

-- 7. Grant permissions (safe approach)
DO $$
BEGIN
    -- Revoke existing permissions first
    REVOKE EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) FROM authenticated;

    -- Grant fresh permissions
    GRANT EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;

EXCEPTION
    WHEN OTHERS THEN
        -- If revoke fails (permissions don't exist), just grant them
        GRANT EXECUTE ON FUNCTION public.send_notification(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, JSONB) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.create_emergency_incident(TEXT, TEXT, TEXT, TEXT, BIGINT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;
END;
$$;

-- 8. Insert default emergency contacts
INSERT INTO public.emergency_contacts (contact_type, name, phone, priority) VALUES
('police', 'Local Police Station', '100', 1),
('hospital', 'Nearest Hospital', '108', 1),
('fire', 'Fire Department', '101', 2)
ON CONFLICT DO NOTHING;

-- 9. Enable realtime for emergency tables
DO $$
BEGIN
    -- Check if publication exists before adding tables
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        -- Add tables to realtime publication (ignore errors if tables already exist in publication)
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_incidents;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;

        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table might already be in publication, continue
                NULL;
        END;
    END IF;
END
$$;

-- ====================================================================================================
-- EMERGENCY FUNCTIONALITY SETUP COMPLETE
-- ====================================================================================================
