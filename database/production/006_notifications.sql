-- ============================================
-- VIBESLINX NOTIFICATIONS SYSTEM - PRODUCTION v1.0
-- User Notifications & Automated Triggers
-- ============================================
-- This migration creates the notifications system with automated
-- triggers for booking events, payment events, and reviews.
-- Includes all fixes from: 021_fix_trigger_and_notifications.sql
-- ============================================

-- ============================================
-- 1. CREATE NOTIFICATIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Notification Content
  type TEXT NOT NULL CHECK (type IN (
    'booking_request',
    'booking_confirmed', 
    'booking_cancelled',
    'booking_completed',
    'booking_declined',
    'payment_received',
    'payment_failed',
    'escrow_released',
    'escrow_refunded',
    'withdrawal_completed',
    'review_received',
    'system_message'
  )),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  
  -- Action
  action_url TEXT,
  action_label TEXT,
  
  -- Related Entities
  booking_id UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  
  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,
  
  -- Status
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Priority (for sorting)
  priority INTEGER DEFAULT 0
);

-- ============================================
-- 2. CREATE INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON public.notifications(type);

-- Composite index for unread notifications
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, created_at DESC) 
  WHERE is_read = FALSE;

-- ============================================
-- 3. CREATE NOTIFICATION FUNCTIONS
-- ============================================

-- Helper function to create notifications
CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_message TEXT,
  p_action_url TEXT DEFAULT NULL,
  p_booking_id UUID DEFAULT NULL,
  p_transaction_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  notification_id UUID;
BEGIN
  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    message,
    action_url,
    booking_id,
    transaction_id,
    metadata
  ) VALUES (
    p_user_id,
    p_type,
    p_title,
    p_message,
    p_action_url,
    p_booking_id,
    p_transaction_id,
    p_metadata
  )
  RETURNING id INTO notification_id;
  
  RETURN notification_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 4. CREATE TRIGGER FUNCTIONS FOR AUTO-NOTIFICATIONS
-- ============================================

-- Notify provider on new booking request
CREATE OR REPLACE FUNCTION public.notify_booking_request()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'pending' AND (OLD.id IS NULL) THEN
    PERFORM public.create_notification(
      NEW.provider_id,
      'booking_request',
      'New Booking Request',
      'You have a new booking request for ' || NEW.service_name,
      '/provider/bookings',
      NEW.id
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Notify client on booking status change
CREATE OR REPLACE FUNCTION public.notify_booking_status_change()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Booking confirmed
  IF NEW.status = 'confirmed' AND OLD.status = 'pending' THEN
    PERFORM public.create_notification(
      NEW.client_id,
      'booking_confirmed',
      'Booking Confirmed!',
      'Your booking for ' || NEW.service_name || ' has been confirmed',
      '/bookings',
      NEW.id
    );
    
  -- Booking declined
  ELSIF NEW.status = 'declined' AND OLD.status = 'pending' THEN
    PERFORM public.create_notification(
      NEW.client_id,
      'booking_declined',
      'Booking Declined',
      'Your booking request for ' || NEW.service_name || ' was declined',
      '/bookings',
      NEW.id
    );
    
  -- Booking cancelled
  ELSIF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    -- Notify the other party
    DECLARE
      current_user_id UUID;
    BEGIN
      current_user_id := auth.uid();
      
      IF current_user_id IS NULL OR current_user_id != NEW.provider_id THEN
        PERFORM public.create_notification(
          NEW.provider_id,
          'booking_cancelled',
          'Booking Cancelled',
          'A booking for ' || NEW.service_name || ' has been cancelled',
          '/provider/bookings',
          NEW.id
        );
      END IF;
      
      IF current_user_id IS NULL OR current_user_id != NEW.client_id THEN
        PERFORM public.create_notification(
          NEW.client_id,
          'booking_cancelled',
          'Booking Cancelled',
          'Your booking for ' || NEW.service_name || ' has been cancelled',
          '/bookings',
          NEW.id
        );
      END IF;
    END;
    
  -- Booking completed
  ELSIF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    PERFORM public.create_notification(
      NEW.client_id,
      'booking_completed',
      'Booking Completed',
      'Your booking for ' || NEW.service_name || ' is complete',
      '/bookings',
      NEW.id
    );
    
    PERFORM public.create_notification(
      NEW.provider_id,
      'booking_completed',
      'Booking Completed',
      'Booking for ' || NEW.service_name || ' is complete. Funds released to wallet.',
      '/provider/wallet',
      NEW.id
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Notify on payment events
CREATE OR REPLACE FUNCTION public.notify_payment_events()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    
    CASE NEW.type
      WHEN 'escrow_release' THEN
        PERFORM public.create_notification(
          NEW.user_id,
          'escrow_released',
          'Payment Released',
          'Escrow payment of ZMW ' || NEW.amount || ' has been released to your wallet',
          '/provider/wallet',
          NEW.booking_id,
          NEW.id
        );
        
      WHEN 'refund' THEN
        PERFORM public.create_notification(
          NEW.user_id,
          'escrow_refunded',
          'Refund Processed',
          'Your commitment fee of ZMW ' || NEW.amount || ' has been refunded',
          '/wallet',
          NEW.booking_id,
          NEW.id
        );
        
      WHEN 'withdrawal' THEN
        PERFORM public.create_notification(
          NEW.user_id,
          'withdrawal_completed',
          'Withdrawal Complete',
          'Your withdrawal of ZMW ' || ABS(NEW.amount) || ' has been processed',
          '/provider/wallet',
          NULL,
          NEW.id
        );
      ELSE
        NULL;
    END CASE;
    
  ELSIF NEW.status = 'failed' AND OLD.status != 'failed' THEN
    PERFORM public.create_notification(
      NEW.user_id,
      'payment_failed',
      'Payment Failed',
      'A payment transaction failed. Please try again.',
      '/wallet',
      NEW.booking_id,
      NEW.id
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Notify on new review
CREATE OR REPLACE FUNCTION public.notify_review_received()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  star_text TEXT;
BEGIN
  star_text := REPEAT('⭐', NEW.rating);
  
  PERFORM public.create_notification(
    NEW.reviewee_id,
    'review_received',
    'New Review Received',
    'You received a ' || star_text || ' review',
    '/provider/profile',
    NEW.booking_id
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. CREATE TRIGGERS
-- ============================================

DROP TRIGGER IF EXISTS notify_on_booking_request ON public.bookings;
CREATE TRIGGER notify_on_booking_request
  AFTER INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_booking_request();

DROP TRIGGER IF EXISTS notify_on_booking_status_change ON public.bookings;
CREATE TRIGGER notify_on_booking_status_change
  AFTER UPDATE ON public.bookings
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_booking_status_change();

DROP TRIGGER IF EXISTS notify_on_payment_events ON public.transactions;
CREATE TRIGGER notify_on_payment_events
  AFTER UPDATE ON public.transactions
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_payment_events();

DROP TRIGGER IF EXISTS notify_on_review_received ON public.reviews;
CREATE TRIGGER notify_on_review_received
  AFTER INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_review_received();

-- ============================================
-- 6. ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 7. CREATE RLS POLICIES
-- ============================================

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Service role can manage notifications" ON public.notifications;

CREATE POLICY "Users can view own notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Service role can manage notifications"
ON public.notifications
TO service_role
USING (true)
WITH CHECK (true);

-- ============================================
-- 8. GRANT PERMISSIONS
-- ============================================

GRANT SELECT, UPDATE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
GRANT EXECUTE ON FUNCTION public.create_notification TO service_role;

-- ============================================
-- NOTIFICATIONS SYSTEM COMPLETE
-- ============================================
