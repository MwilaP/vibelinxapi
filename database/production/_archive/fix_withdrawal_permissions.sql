-- Fix permissions for withdrawal_requests table
-- Run this in Supabase SQL Editor

-- Grant SELECT permission to authenticated users
GRANT SELECT ON public.withdrawal_requests TO authenticated;
GRANT SELECT ON public.withdrawal_requests TO anon;

-- Grant UPDATE permission for admin operations
GRANT UPDATE ON public.withdrawal_requests TO authenticated;

-- If the table doesn't exist, you may need to check the actual table name
-- Common variations:
-- - withdrawal_requests
-- - payout_requests
-- - withdrawals

-- Check if RLS is enabled and causing issues
-- You can temporarily disable RLS for testing:
-- ALTER TABLE public.withdrawal_requests DISABLE ROW LEVEL SECURITY;

-- Or create a policy that allows admins to view all withdrawal requests:
DROP POLICY IF EXISTS "Admin can view all withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Admin can view all withdrawal requests"
ON public.withdrawal_requests
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE admin_users.user_id = auth.uid()
    AND admin_users.status = 'active'
  )
);

DROP POLICY IF EXISTS "Admin can update withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Admin can update withdrawal requests"
ON public.withdrawal_requests
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE admin_users.user_id = auth.uid()
    AND admin_users.status = 'active'
  )
);

-- Grant permissions on related tables if they exist
GRANT SELECT ON public.wallets TO authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT UPDATE ON public.wallets TO authenticated;
GRANT INSERT ON public.wallet_transactions TO authenticated;

-- Verify the grants
SELECT 
    grantee, 
    table_name, 
    privilege_type 
FROM 
    information_schema.role_table_grants 
WHERE 
    table_name IN ('withdrawal_requests', 'wallets', 'wallet_transactions')
    AND grantee IN ('authenticated', 'anon');
