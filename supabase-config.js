// supabase-config.js
// Updated with your provided credentials

const SUPABASE_URL = 'https://nlzneuelzgbrkevcbcxw.supabase.co'; 
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5sem5ldWVsemdicmtldmNiY3h3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg4MTU2MDIsImV4cCI6MjA3NDM5MTYwMn0.iEdXK9g3_gsL-HyGNhmL69_huo0R3PFm-zU4qYM-9XM';

// Initialize the Supabase Client
window.supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Verification: You can uncomment the line below to check if the connection object is created
// console.log('Supabase Client Initialized:', !!window.supabaseClient);

// =========================================
// PHASE 1 ENHANCEMENTS - RPC FUNCTIONS
// =========================================

// Function to send push notification
window.sendNotification = async (recipientType, recipientId, templateKey, customTitle, customMessage, busNo, routeId, metadata) => {
    try {
        const { data, error } = await window.supabaseClient.rpc('send_notification', {
            p_recipient_type: recipientType,
            p_recipient_id: recipientId,
            p_template_key: templateKey,
            p_custom_title: customTitle,
            p_custom_message: customMessage,
            p_bus_no: busNo,
            p_route_id: routeId,
            p_metadata: metadata
        });
        return { data, error };
    } catch (err) {
        console.error('Send notification error:', err);
        return { data: null, error: err };
    }
};

// Function to create emergency incident
window.createEmergencyIncident = async (incidentType, reportedByType, reportedById, busNo, routeId, lat, lng, description, severity) => {
    try {
        const { data, error } = await window.supabaseClient.rpc('create_emergency_incident', {
            p_incident_type: incidentType,
            p_reported_by_type: reportedByType,
            p_reported_by_id: reportedById,
            p_bus_no: busNo,
            p_route_id: routeId,
            p_location_lat: lat,
            p_location_lng: lng,
            p_description: description,
            p_severity: severity
        });
        return { data, error };
    } catch (err) {
        console.error('Create emergency incident error:', err);
        return { data: null, error: err };
    }
};

// Function to book seat reservation
window.bookSeat = async (tripId, studentId, seatNumber, specialRequirements) => {
    try {
        const { data, error } = await window.supabaseClient.rpc('book_seat', {
            p_trip_id: tripId,
            p_student_id: studentId,
            p_seat_number: seatNumber,
            p_special_requirements: specialRequirements
        });
        return { data, error };
    } catch (err) {
        console.error('Book seat error:', err);
        return { data: null, error: err };
    }
};

// Function to update trip status and send notifications
window.updateTripStatus = async (tripId, status, delayMinutes, delayReason) => {
    try {
        const { error } = await window.supabaseClient.rpc('update_trip_status', {
            p_trip_id: tripId,
            p_status: status,
            p_delay_minutes: delayMinutes,
            p_delay_reason: delayReason
        });
        return { error };
    } catch (err) {
        console.error('Update trip status error:', err);
        return { error: err };
    }
};

// =========================================
// UTILITY FUNCTIONS
// =========================================

// Function to get current user location
window.getCurrentLocation = () => {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            resolve(null);
            return;
        }

        navigator.geolocation.getCurrentPosition(
            (position) => {
                resolve({
                    lat: position.coords.latitude,
                    lng: position.coords.longitude
                });
            },
            (error) => {
                console.log('Geolocation error:', error);
                resolve(null);
            },
            {
                enableHighAccuracy: true,
                timeout: 10000,
                maximumAge: 300000
            }
        );
    });
};

// Function to check if user is authenticated
window.isAuthenticated = () => {
    try {
        return localStorage.getItem('vt_student_authed') === 'true';
    } catch (e) {
        return false;
    }
};

// Function to get current student ID
window.getCurrentStudentId = () => {
    try {
        return localStorage.getItem('vt_student_id') || 'unknown';
    } catch (e) {
        return 'unknown';
    }
};
