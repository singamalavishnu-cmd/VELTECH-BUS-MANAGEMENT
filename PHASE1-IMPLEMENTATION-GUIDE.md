# Phase 1 Implementation Guide

## Step 1: Apply SQL Schema

1. **Go to your Supabase Dashboard**
   - Visit [supabase.com](https://supabase.com) and login
   - Select your Vel Tech Bus Management project

2. **Open SQL Editor**
   - Go to SQL Editor in the sidebar
   - Click "New Query"

3. **Copy and Execute the Schema**
   ```sql
   -- Copy the entire contents of supabase-schema-phase1.sql and paste it here
   -- Then click "Run" to execute
   ```

4. **Verify Tables Created**
   - Check the Table Editor to see all new Phase 1 tables
   - Verify RLS policies are applied

## Step 2: Update Supabase Configuration

Add these new RPC functions to your `supabase-config.js`:

```javascript
// Add to window.supabaseClient initialization
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
```

## Step 3: Next Steps After Schema Application

1. **Test Database Connection**
   - Verify all new tables are accessible
   - Test RPC functions work correctly

2. **Implement Frontend Features** (Starting now)
   - Emergency panic button
   - Push notification preferences
   - Seat reservation system

3. **Set Up Push Notifications**
   - Choose a service (Firebase, OneSignal, or native)
   - Implement device token management

Would you like me to proceed with implementing the emergency features in the student interface now?
