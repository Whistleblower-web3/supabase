
-- ============================================
-- Security Policies (RLS)
-- ============================================

-- This file defines Row Level Security (RLS) policies for all tables.
-- General Strategy:
-- 1. Anonymous and authenticated users: Read-only access to all public data.
-- 2. service_role (used by sync scripts): Full access (Insert, Update, Delete).

-- Note: Table-level RLS activation is done in 00_tables.sql

-- ============================================
-- Helper Function: Check if requester is service_role
-- ============================================
-- In Supabase, the 'service_role' key bypasses RLS by default.
-- However, we explicitly define policies to be clear and robust.

-- ============================================
-- 1. boxes
-- ============================================
CREATE POLICY "Public read access for boxes" ON boxes FOR SELECT USING (true);

-- ============================================
-- 2. metadata_boxes
-- ============================================
CREATE POLICY "Public read access for metadata_boxes" ON metadata_boxes FOR SELECT USING (true);

-- ============================================
-- 3. users
-- ============================================
CREATE POLICY "Public read access for users" ON users FOR SELECT USING (true);

-- ============================================
-- 4. user_addresses
-- ============================================
CREATE POLICY "Public read access for user_addresses" ON user_addresses FOR SELECT USING (true);

-- ============================================
-- 5. payments
-- ============================================
CREATE POLICY "Public read access for payments" ON payments FOR SELECT USING (true);

-- ============================================
-- 6. withdraws
-- ============================================
CREATE POLICY "Public read access for withdraws" ON withdraws FOR SELECT USING (true);

-- ============================================
-- 7. rewards_addeds
-- ============================================
CREATE POLICY "Public read access for rewards_addeds" ON rewards_addeds FOR SELECT USING (true);

-- ============================================
-- 8. box_rewards
-- ============================================
CREATE POLICY "Public read access for box_rewards" ON box_rewards FOR SELECT USING (true);

-- ============================================
-- 9. user_rewards
-- ============================================
CREATE POLICY "Public read access for user_rewards" ON user_rewards FOR SELECT USING (true);

-- ============================================
-- 10. user_withdraws
-- ============================================
CREATE POLICY "Public read access for user_withdraws" ON user_withdraws FOR SELECT USING (true);

-- ============================================
-- 11. box_bidders
-- ============================================
CREATE POLICY "Public read access for box_bidders" ON box_bidders FOR SELECT USING (true);

-- ============================================
-- 12. box_user_order_amounts
-- ============================================
CREATE POLICY "Public read access for box_user_order_amounts" ON box_user_order_amounts FOR SELECT USING (true);

-- ============================================
-- 13. statistical_state
-- ============================================
CREATE POLICY "Public read access for statistical_state" ON statistical_state FOR SELECT USING (true);

-- ============================================
-- 14. fund_manager_state
-- ============================================
CREATE POLICY "Public read access for fund_manager_state" ON fund_manager_state FOR SELECT USING (true);

-- ============================================
-- 15. token_total_amounts
-- ============================================
CREATE POLICY "Public read access for token_total_amounts" ON token_total_amounts FOR SELECT USING (true);

-- ============================================
-- 16. sync_status
-- ============================================
CREATE POLICY "Public read access for sync_status" ON sync_status FOR SELECT USING (true);
