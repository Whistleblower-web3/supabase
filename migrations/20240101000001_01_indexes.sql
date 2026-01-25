
-- ============================================
-- boxes indexes
-- ============================================
-- Network field index (for quick network filtering)
CREATE INDEX IF NOT EXISTS idx_boxes_network_layer ON boxes(network, layer);
CREATE INDEX IF NOT EXISTS idx_boxes_token_id ON boxes(network, layer, token_id);
CREATE INDEX IF NOT EXISTS idx_boxes_status ON boxes(network, layer, status);
CREATE INDEX IF NOT EXISTS idx_boxes_minter_id ON boxes(network, layer, minter_id);
CREATE INDEX IF NOT EXISTS idx_boxes_owner_address ON boxes(network, layer, owner_address);
CREATE INDEX IF NOT EXISTS idx_boxes_publisher_id ON boxes(network, layer, publisher_id);
CREATE INDEX IF NOT EXISTS idx_boxes_seller_id ON boxes(network, layer, seller_id);
CREATE INDEX IF NOT EXISTS idx_boxes_buyer_id ON boxes(network, layer, buyer_id);
CREATE INDEX IF NOT EXISTS idx_boxes_completer_id ON boxes(network, layer, completer_id);
CREATE INDEX IF NOT EXISTS idx_boxes_create_timestamp ON boxes(network, layer, create_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_boxes_price ON boxes(network, layer, price);
CREATE INDEX IF NOT EXISTS idx_boxes_box_info_cid ON boxes(network, layer, box_info_cid);
CREATE INDEX IF NOT EXISTS idx_boxes_listed_mode ON boxes(network, layer, listed_mode);

-- boxes composite indexes
CREATE INDEX IF NOT EXISTS idx_boxes_status_price ON boxes(network, layer, status, price);
CREATE INDEX IF NOT EXISTS idx_boxes_status_create_timestamp ON boxes(network, layer, status, create_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_boxes_status_listed_mode ON boxes(network, layer, status, listed_mode);

-- ============================================
-- metadata_boxes indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_network_layer ON metadata_boxes(network, layer);
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_type_of_crime ON metadata_boxes(network, layer, type_of_crime);
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_country ON metadata_boxes(network, layer, country);
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_state ON metadata_boxes(network, layer, state);
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_event_date ON metadata_boxes(network, layer, event_date);
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_mint_method ON metadata_boxes(network, layer, mint_method);

-- metadata_boxes full text search indexes (GIN indexes)
-- Note: Full text search indexes do not need to contain the network field, because the network is filtered first when querying
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_title_gin ON metadata_boxes USING gin(to_tsvector('english', COALESCE(title, '')));
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_description_gin ON metadata_boxes USING gin(to_tsvector('english', COALESCE(description, '')));
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_label_gin ON metadata_boxes USING gin(label);

-- metadata_boxes composite indexes
CREATE INDEX IF NOT EXISTS idx_metadata_boxes_type_country ON metadata_boxes(network, layer, type_of_crime, country);

-- ============================================
-- users indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_users_network_layer ON users(network, layer);

-- ============================================
-- user_addresses indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_user_addresses_network_layer ON user_addresses(network, layer);
CREATE INDEX IF NOT EXISTS idx_user_addresses_is_blacklisted ON user_addresses(network, layer, is_blacklisted);

-- ============================================
-- payments indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_payments_network_layer ON payments(network, layer);
CREATE INDEX IF NOT EXISTS idx_payments_box_id ON payments(network, layer, box_id);
CREATE INDEX IF NOT EXISTS idx_payments_user_id ON payments(network, layer, user_id);
CREATE INDEX IF NOT EXISTS idx_payments_token ON payments(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_payments_timestamp ON payments(network, layer, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_payments_block_number ON payments(network, layer, block_number);

-- ============================================
-- withdraws indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_withdraws_network_layer ON withdraws(network, layer);
CREATE INDEX IF NOT EXISTS idx_withdraws_user_id ON withdraws(network, layer, user_id);
CREATE INDEX IF NOT EXISTS idx_withdraws_token ON withdraws(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_withdraws_timestamp ON withdraws(network, layer, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_withdraws_withdraw_type ON withdraws(network, layer, withdraw_type);
CREATE INDEX IF NOT EXISTS idx_withdraws_block_number ON withdraws(network, layer, block_number);

-- ============================================
-- rewards_addeds indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_network_layer ON rewards_addeds(network, layer);
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_box_id ON rewards_addeds(network, layer, box_id);
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_reward_type ON rewards_addeds(network, layer, reward_type);
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_token ON rewards_addeds(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_timestamp ON rewards_addeds(network, layer, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_rewards_addeds_block_number ON rewards_addeds(network, layer, block_number);

-- ============================================
-- box_rewards indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_box_rewards_network_layer ON box_rewards(network, layer);
CREATE INDEX IF NOT EXISTS idx_box_rewards_box_id ON box_rewards(network, layer, box_id);
CREATE INDEX IF NOT EXISTS idx_box_rewards_reward_type ON box_rewards(network, layer, reward_type);
CREATE INDEX IF NOT EXISTS idx_box_rewards_token ON box_rewards(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_box_rewards_id ON box_rewards(network, layer, id);

-- ============================================
-- user_rewards indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_user_reward_amounts_network_layer ON user_rewards(network, layer);
CREATE INDEX IF NOT EXISTS idx_user_reward_amounts_user_id ON user_rewards(network, layer, user_id);
CREATE INDEX IF NOT EXISTS idx_user_reward_amounts_reward_type ON user_rewards(network, layer, reward_type);
CREATE INDEX IF NOT EXISTS idx_user_reward_amounts_token ON user_rewards(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_user_reward_amounts_user_reward_type ON user_rewards(network, layer, user_id, reward_type);

-- ============================================
-- user_withdraws indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_user_withdraw_amounts_network_layer ON user_withdraws(network, layer);
CREATE INDEX IF NOT EXISTS idx_user_withdraw_amounts_user_id ON user_withdraws(network, layer, user_id);
CREATE INDEX IF NOT EXISTS idx_user_withdraw_amounts_withdraw_type ON user_withdraws(network, layer, withdraw_type);
CREATE INDEX IF NOT EXISTS idx_user_withdraw_amounts_token ON user_withdraws(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_user_withdraw_amounts_user_withdraw_type ON user_withdraws(network, layer, user_id, withdraw_type);

-- ============================================
-- box_bidders indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_box_bidders_network_layer ON box_bidders(network, layer);
CREATE INDEX IF NOT EXISTS idx_box_bidders_id ON box_bidders(network, layer, id); -- id is boxId-UserId
CREATE INDEX IF NOT EXISTS idx_box_bidders_box_id ON box_bidders(network, layer, box_id);
CREATE INDEX IF NOT EXISTS idx_box_bidders_bidder_id ON box_bidders(network, layer, bidder_id);

-- ============================================
-- box_user_order_amounts indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_network_layer ON box_user_order_amounts(network, layer);
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_user_id ON box_user_order_amounts(network, layer, user_id);
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_box_id ON box_user_order_amounts(network, layer, box_id);
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_token ON box_user_order_amounts(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_user_box ON box_user_order_amounts(network, layer, user_id, box_id);
CREATE INDEX IF NOT EXISTS idx_box_user_order_amounts_user_box_token ON box_user_order_amounts(network, layer, user_id, box_id, token);

-- ============================================
-- token_total_amounts indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_token_total_amounts_network_layer ON token_total_amounts(network, layer);
CREATE INDEX IF NOT EXISTS idx_token_total_amounts_token ON token_total_amounts(network, layer, token);
CREATE INDEX IF NOT EXISTS idx_token_total_amounts_funds_type ON token_total_amounts(network, layer, funds_type);
CREATE INDEX IF NOT EXISTS idx_token_total_amounts_fund_manager_id ON token_total_amounts(network, layer, fund_manager_id);

