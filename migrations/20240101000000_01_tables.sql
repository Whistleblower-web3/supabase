
-- ============================================
-- 1. boxes 表 (Box main table)
-- ============================================
-- Box table stores chain event data, MetadataBox data is stored as an independent associated table
-- Events:
--      Exchange contract: BoxListed, BoxPurchased, BidPlaced, CompleterAssigned, RequestDeadlineChanged, ReviewDeadlineChanged, RefundPermitChanged,
--      TruthBox contract: BoxCreated, BoxStatusChanged, PriceChanged, DeadlineChanged, PrivateKeyPublished
CREATE TABLE IF NOT EXISTS boxes (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  -- Basic identifier
  id NUMERIC(78, 0) NOT NULL, -- boxId 
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  token_id NUMERIC(78, 0) NOT NULL, -- NFT tokenId, same as boxId
  token_uri TEXT, -- NFT tokenURI (currently not written to this field, reserved for extension)
  
  -- Chain event data fields
  box_info_cid TEXT, -- CID (for associating MetadataBox) in BoxCreated event
  private_key TEXT, 
  price NUMERIC(78, 0) NOT NULL DEFAULT 0, 
  deadline NUMERIC(78, 0) NOT NULL DEFAULT 0, 
  
  -- User relationships
  minter_id NUMERIC(78, 0) NOT NULL, -- UserId
  owner_address TEXT NOT NULL, -- NFT owner address (wallet address)
  publisher_id NUMERIC(78, 0), -- UserId
  seller_id NUMERIC(78, 0), -- UserId
  buyer_id NUMERIC(78, 0), -- UserId
  completer_id NUMERIC(78, 0), -- UserId 
  
  -- Status and timestamps
  status TEXT NOT NULL CHECK (status IN (
    'Storing', 'Selling', 'Auctioning', 'Paid', 
    'Refunding', 'InSecrecy', 'Published', 'Blacklisted'
  )),
  
  -- Transaction related
  listed_mode TEXT CHECK (listed_mode IN ('Selling', 'Auctioning')), 
  accepted_token TEXT, 
  refund_permit BOOLEAN, 
  
  -- Timestamp fields
  create_timestamp NUMERIC(78, 0) NOT NULL, 
  publish_timestamp NUMERIC(78, 0), 
  listed_timestamp NUMERIC(78, 0), 
  purchase_timestamp NUMERIC(78, 0), 
  complete_timestamp NUMERIC(78, 0), 
  request_refund_deadline NUMERIC(78, 0), 
  review_deadline NUMERIC(78, 0) 
);

-- ============================================
-- 2. users table (User table - UserId)
-- Events: All events with userId are associated with this table
-- ============================================
CREATE TABLE IF NOT EXISTS users (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id NUMERIC(78, 0) NOT NULL, -- UserId 
  
  PRIMARY KEY (network, layer, id) -- Composite primary key contains network field
);


-- ============================================
-- 11. box_bidders table (Box bidder association table)
-- Events: BidPlaced
-- ============================================
CREATE TABLE IF NOT EXISTS box_bidders (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id NUMERIC(78, 0) NOT NULL, -- boxId
  bidder_id NUMERIC(78, 0) NOT NULL, -- UserId
  
  PRIMARY KEY (network, layer, id, bidder_id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, bidder_id) REFERENCES users(network, layer, id) ON DELETE CASCADE
);


-- ============================================
-- 3. user_addresses table (User address table - User2)
-- Events: Blacklist, Transfer(TruthNFT)
-- ============================================
CREATE TABLE IF NOT EXISTS user_addresses (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- userAddress (address)
  
  PRIMARY KEY (network, layer, id), 
  is_blacklisted BOOLEAN NOT NULL DEFAULT FALSE
);


-- ============================================
-- 4. metadata_boxes table (MetadataBox association table)
-- Events: BoxCreated
-- Can only insert, cannot update
-- ============================================
-- Store MetadataBox JSON data retrieved from IPFS, associated with boxes table via id (boxId)
CREATE TABLE IF NOT EXISTS metadata_boxes (
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id NUMERIC(78, 0) NOT NULL, -- boxId
  
  PRIMARY KEY (network, layer, id), 
  FOREIGN KEY (network, layer, id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  
  -- BoxInfo fields
  type_of_crime TEXT, 
  label TEXT[], 
  title TEXT, 
  nft_image TEXT, 
  box_image TEXT, 
  country TEXT, 
  state TEXT, 
  description TEXT, 
  event_date DATE, 
  create_date TIMESTAMP WITH TIME ZONE, 
  timestamp BIGINT, 
  mint_method TEXT CHECK (mint_method IN ('create', 'createAndPublish')),
  
  file_list TEXT[], 
  password TEXT, 
  
  encryption_slices_metadata_cid JSONB, -- { slicesMetadataCID_encryption, slicesMetadataCID_iv }
  encryption_file_cid JSONB[], -- [{ fileCID_encryption, fileCID_iv }, ...]
  encryption_passwords JSONB, -- { password_encryption, password_iv }
  public_key TEXT
);


-- ============================================
-- 5. payments table (Payment record table)
-- Events: OrderAmountPaid
-- Can only insert, cannot update
-- ============================================
CREATE TABLE IF NOT EXISTS payments (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- Transaction hash - log index
  box_id NUMERIC(78, 0) NOT NULL,
  user_id NUMERIC(78, 0) NOT NULL, -- UserId
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  token TEXT NOT NULL, 
  amount NUMERIC(78, 0) NOT NULL, 
  timestamp NUMERIC(78, 0) NOT NULL,
  transaction_hash BYTEA NOT NULL, 
  block_number NUMERIC(78, 0) NOT NULL
);

-- ============================================
-- 6. withdraws table (Withdraw record table)
-- Events: OrderAmountWithdraw, HelperRewrdsWithdraw, MinterRewardsWithdraw
-- Can only insert, cannot update
-- ============================================
CREATE TABLE IF NOT EXISTS withdraws (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- Transaction hash - log index
  token TEXT NOT NULL, 
  box_list NUMERIC(78, 0)[] NOT NULL, -- Box ID list
  user_id NUMERIC(78, 0) NOT NULL, -- UserId
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  withdraw_type TEXT NOT NULL CHECK (withdraw_type IN ('Order', 'Refund', 'Helper', 'Minter')),
  amount NUMERIC(78, 0) NOT NULL,
  timestamp NUMERIC(78, 0) NOT NULL,
  transaction_hash BYTEA NOT NULL,
  block_number NUMERIC(78, 0) NOT NULL
);

-- ============================================
-- 7. rewards_addeds table (Reward added event record table)
-- Events: RewardAmountAdded
-- Can only insert, cannot update
-- ============================================
-- Record each RewardAmountAdded event, for event tracking
-- Event sync script will write chain events to this table, triggers will listen to this table and update aggregate tables
CREATE TABLE IF NOT EXISTS rewards_addeds (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- Transaction hash - log index (for unique identification of each event)
  box_id NUMERIC(78, 0) NOT NULL, 
  token TEXT NOT NULL, -- Token address
  reward_type TEXT NOT NULL CHECK (reward_type IN ('Minter', 'Seller', 'Completer', 'Total')), -- Note: includes 'Total'
  amount NUMERIC(78, 0) NOT NULL,
  timestamp NUMERIC(78, 0) NOT NULL,
  transaction_hash BYTEA NOT NULL,
  block_number NUMERIC(78, 0) NOT NULL,
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE
);

-- ============================================
-- 8. box_rewards table (Box total reward amount aggregation table)
-- ============================================
-- Record the total reward amount of each type of reward for each box, for aggregate data
-- Listen to rewards_addeds table INSERT, automatically accumulated by triggers
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
CREATE TABLE IF NOT EXISTS box_rewards (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  id TEXT NOT NULL, -- box_id-reward_type-token composite key
  box_id NUMERIC(78, 0) NOT NULL,
  reward_type TEXT NOT NULL CHECK (reward_type IN ('Minter', 'Seller', 'Completer', 'Total')), 
  token TEXT NOT NULL, 
  PRIMARY KEY (network, layer, id),
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  UNIQUE(network, layer, box_id, reward_type, token)
);

-- ============================================
-- 9. user_rewards table (User reward amount detail table)
-- ============================================
-- Record the total reward amount of each type of reward for each user, for each token, for detail data
-- Listen to rewards_addeds table INSERT, automatically accumulated by triggers
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
CREATE TABLE IF NOT EXISTS user_rewards (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  id TEXT NOT NULL, -- user_id-reward_type-token composite key
  user_id NUMERIC(78, 0) NOT NULL, 
  reward_type TEXT NOT NULL CHECK (reward_type IN ('Minter', 'Seller', 'Completer')), 
  token TEXT NOT NULL, 
  PRIMARY KEY (network, layer, id),
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  UNIQUE(network, layer, user_id, reward_type, token)
);

-- ============================================
-- 10. user_withdraws table (User total withdrawal amount detail table)
-- ============================================
-- Record the total withdrawal amount of each type of withdrawal for each user, for each token, for detail data
-- Listen to withdraws table INSERT, automatically accumulated by triggers
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
CREATE TABLE IF NOT EXISTS user_withdraws (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  id TEXT NOT NULL, -- user_id-withdraw_type-token composite key
  user_id NUMERIC(78, 0) NOT NULL, 
  withdraw_type TEXT NOT NULL CHECK (withdraw_type IN ('Helper', 'Minter')), -- Withdraw type
  token TEXT NOT NULL, 
  PRIMARY KEY (network, layer, id),
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  UNIQUE(network, layer, user_id, withdraw_type, token)
);

-- ============================================
-- 12. box_user_order_amounts table (Box user (buyer/bidder) each token的资金状态表)
-- ============================================
-- Theoretically only one token, because box.accepted_token is unique
-- Listen to payments table INSERT, automatically accumulated by triggers
-- Listen to withdraws table INSERT, automatically accumulated by triggers
-- Listen to rewards_addeds table INSERT, automatically accumulated by triggers
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
CREATE TABLE IF NOT EXISTS box_user_order_amounts (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- user_id-box_id-token composite key
  user_id NUMERIC(78, 0) NOT NULL, -- UserId
  box_id NUMERIC(78, 0) NOT NULL, -- box_id
  token TEXT NOT NULL, 
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  
  -- Unique constraint: Each user has only one record for each token in each box
  UNIQUE(network, layer, user_id, box_id, token)
);

-- ============================================
-- 13. statistical_state table (Statistical state table - singleton)
-- Listen to boxes table, when status changes, accumulate and subtract
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
-- ============================================
CREATE TABLE IF NOT EXISTS statistical_state (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL DEFAULT 'statistical', -- Singleton ID
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  total_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  storing_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  selling_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  auctioning_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  paid_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  refunding_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  in_secrecy_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  published_supply NUMERIC(78, 0) NOT NULL DEFAULT 0,
  blacklisted_supply NUMERIC(78, 0) NOT NULL DEFAULT 0
);

-- ============================================
-- 14. fund_manager_state table (Fund manager state table - singleton)
-- ============================================
-- Note: It needs to be created before token_total_amounts, because of foreign key dependency
-- It has no practical function, but can be kept for future expansion
CREATE TABLE IF NOT EXISTS fund_manager_state (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL DEFAULT 'fundManager', -- Singleton ID
  
  PRIMARY KEY (network, layer, id) -- Composite primary key contains network field
);

-- ============================================
-- 15. token_total_amounts table (Token total amount table)
-- ============================================
-- Listen to payments and withdraws table INSERT, automatically accumulated by triggers
-- Listen to rewards_addeds table INSERT, automatically accumulated by triggers
-- ⚠️ Do not allow manual insertion/update, completely managed by triggers
CREATE TABLE IF NOT EXISTS token_total_amounts (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- tokenAddress-fundsType composite key
  token TEXT NOT NULL, 
  fund_manager_id TEXT NOT NULL DEFAULT 'fundManager',
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, fund_manager_id) REFERENCES fund_manager_state(network, layer, id) ON DELETE CASCADE,
  funds_type TEXT NOT NULL CHECK (funds_type IN (
    'OrderPaid',    
    'OrderWithdraw',   
    'RefundWithdraw',  
    'RewardsAdded',    
    'HelperRewardsWithdraw',  
    'MinterRewardsWithdraw'  
  )),
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  
  -- Unique constraint (contains network field)
  UNIQUE(network, layer, token, funds_type)
);

-- ============================================
-- 16. sync_status table (Sync status table - for event sync script)
-- ============================================
-- Each contract has independent sync status
CREATE TABLE IF NOT EXISTS sync_status (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  contract_name TEXT NOT NULL CHECK (contract_name IN ('TRUTH_BOX', 'EXCHANGE', 'FUND_MANAGER', 'TRUTH_NFT', 'USER_ID')),
  last_synced_block NUMERIC(78, 0) NOT NULL DEFAULT 0,
  last_synced_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  
  PRIMARY KEY (network, layer, contract_name) -- Composite primary key contains network field and contract name
);

-- Initialize sync_status records (create initial records for each network and each contract)
INSERT INTO sync_status (network, layer, contract_name, last_synced_block, last_synced_at)
VALUES 
  ('testnet', 'sapphire', 'TRUTH_BOX', 0, NOW()),
  ('testnet', 'sapphire', 'EXCHANGE', 0, NOW()),
  ('testnet', 'sapphire', 'FUND_MANAGER', 0, NOW()),
  ('testnet', 'sapphire', 'TRUTH_NFT', 0, NOW()),
  ('testnet', 'sapphire', 'USER_ID', 0, NOW()),
  ('mainnet', 'sapphire', 'TRUTH_BOX', 0, NOW()),
  ('mainnet', 'sapphire', 'EXCHANGE', 0, NOW()),
  ('mainnet', 'sapphire', 'FUND_MANAGER', 0, NOW()),
  ('mainnet', 'sapphire', 'TRUTH_NFT', 0, NOW()),
  ('mainnet', 'sapphire', 'USER_ID', 0, NOW())
ON CONFLICT (network, layer, contract_name) DO NOTHING;

