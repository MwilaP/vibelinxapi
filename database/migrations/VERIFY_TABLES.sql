-- Run this in Supabase SQL Editor to verify tables exist
-- This will show you if the tables were created

SELECT 
  table_name,
  table_schema
FROM information_schema.tables 
WHERE table_name IN ('wallets', 'wallet_transactions', 'escrow_transactions', 'withdrawal_requests')
ORDER BY table_name;

-- Also check what schema they're in
SELECT 
  schemaname,
  tablename,
  tableowner
FROM pg_tables 
WHERE tablename IN ('wallets', 'wallet_transactions', 'escrow_transactions', 'withdrawal_requests');
