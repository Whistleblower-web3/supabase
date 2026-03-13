
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
  minter_id TEXT NOT NULL, -- UserId (bytes32 hex)
  owner_address TEXT NOT NULL, -- NFT owner address (wallet address)
  publisher_id TEXT, -- UserId (bytes32 hex)
  seller_id TEXT, -- UserId (bytes32 hex)
  buyer_id TEXT, -- UserId (bytes32 hex)
  completer_id TEXT, -- UserId (bytes32 hex)
  
  -- Status and timestamps
  -- Status values: 0=Storing, 1=Selling, 2=Auctioning, 3=Paid, 4=Refunding, 5=Delaying, 6=Published, 7=Blacklisted
  status SMALLINT NOT NULL CHECK (status BETWEEN 0 AND 7),
  
  -- Transaction related
  -- listed_mode values: NULL=Not Listed, 1=Selling, 2=Auctioning
  listed_mode SMALLINT CHECK (listed_mode BETWEEN 1 AND 2), 
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

ALTER TABLE boxes ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 2. users table (User table - UserId)
-- Events: All events with userId are associated with this table
-- ============================================
CREATE TABLE IF NOT EXISTS users (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- UserId (bytes32 hex)
  
  PRIMARY KEY (network, layer, id) -- Composite primary key contains network field
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;


-- ============================================
-- 11. box_bidders table (Box bidder association table)
-- Events: BidPlaced
-- ============================================
CREATE TABLE IF NOT EXISTS box_bidders (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- boxId-UserId 
  box_id NUMERIC(78, 0) NOT NULL, -- boxId
  bidder_id TEXT NOT NULL, -- UserId (bytes32 hex)
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, bidder_id) REFERENCES users(network, layer, id) ON DELETE CASCADE
);

ALTER TABLE box_bidders ENABLE ROW LEVEL SECURITY;


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

ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;


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
  
  encryption_slices_metadata_cid JSONB, -- { encryption_data, encryption_iv }
  encryption_file_cid JSONB[], -- [{ encryption_data, encryption_iv }, ...]
  encryption_passwords JSONB, -- { encryption_data, encryption_iv }
  public_key TEXT
);

ALTER TABLE metadata_boxes ENABLE ROW LEVEL SECURITY;


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
  user_id TEXT NOT NULL, -- UserId (bytes32 hex)
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  token TEXT NOT NULL, 
  amount NUMERIC(78, 0) NOT NULL, 
  timestamp NUMERIC(78, 0) NOT NULL,
  transaction_hash BYTEA NOT NULL, 
  block_number NUMERIC(78, 0) NOT NULL
);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. withdraws table (Withdraw record table)
-- Events: OrderAmountWithdraw, HelperRewrdsWithdraw, MinterRewardsWithdraw
-- Can only insert, cannot update
-- ============================================
CREATE TABLE IF NOT EXISTS withdraws (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL, -- eventName-withdrawType-Transaction hash 
  token TEXT NOT NULL, 
  box_list NUMERIC(78, 0)[] NOT NULL, -- Box ID list
  user_id TEXT NOT NULL, -- UserId (bytes32 hex)
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  withdraw_type TEXT NOT NULL CHECK (withdraw_type IN ('Order', 'Refund', 'Reward')),
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
  
  id TEXT NOT NULL, -- eventName-rewardType-Transaction hash 
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

ALTER TABLE rewards_addeds ENABLE ROW LEVEL SECURITY;

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

ALTER TABLE box_rewards ENABLE ROW LEVEL SECURITY;

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
  user_id TEXT NOT NULL, 
  reward_type TEXT NOT NULL CHECK (reward_type IN ('Minter', 'Seller', 'Completer')), 
  token TEXT NOT NULL, 
  PRIMARY KEY (network, layer, id),
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  UNIQUE(network, layer, user_id, reward_type, token)
);

ALTER TABLE user_rewards ENABLE ROW LEVEL SECURITY;

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
  user_id TEXT NOT NULL, 
  withdraw_type TEXT NOT NULL CHECK (withdraw_type IN ('Reward')), -- Withdraw type
  token TEXT NOT NULL, 
  PRIMARY KEY (network, layer, id),
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  UNIQUE(network, layer, user_id, withdraw_type, token)
);

ALTER TABLE user_withdraws ENABLE ROW LEVEL SECURITY;

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
  user_id TEXT NOT NULL, -- UserId (bytes32 hex)
  box_id NUMERIC(78, 0) NOT NULL, -- box_id
  token TEXT NOT NULL, 
  
  PRIMARY KEY (network, layer, id), -- Composite primary key contains network field
  FOREIGN KEY (network, layer, user_id) REFERENCES users(network, layer, id) ON DELETE CASCADE,
  FOREIGN KEY (network, layer, box_id) REFERENCES boxes(network, layer, id) ON DELETE CASCADE,
  
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  
  -- Unique constraint: Each user has only one record for each token in each box
  UNIQUE(network, layer, user_id, box_id, token)
);

ALTER TABLE box_user_order_amounts ENABLE ROW LEVEL SECURITY;

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
  status_0_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Storing
  status_1_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Selling
  status_2_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Auctioning
  status_3_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Paid
  status_4_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Refunding
  status_5_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Delaying
  status_6_supply NUMERIC(78, 0) NOT NULL DEFAULT 0, -- Published
  status_7_supply NUMERIC(78, 0) NOT NULL DEFAULT 0  -- Blacklisted
);

ALTER TABLE statistical_state ENABLE ROW LEVEL SECURITY;

-- Initialize statistical_state
INSERT INTO statistical_state (network, layer, id)
VALUES 
  ('testnet', 'sapphire', 'statistical'),
  ('mainnet', 'sapphire', 'statistical')
ON CONFLICT DO NOTHING;

-- ============================================
-- 14. fund_manager_state table (Fund manager state table - singleton)
-- ============================================
-- Note: It needs to be created before token_total_amounts, because of foreign key dependency
-- It has no practical function, but can be kept for future expansion
CREATE TABLE IF NOT EXISTS fund_manager_state (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL DEFAULT 'fundManager', -- Singleton ID
  paused BOOLEAN NOT NULL DEFAULT FALSE,
  
  PRIMARY KEY (network, layer, id) -- Composite primary key contains network field
);

ALTER TABLE fund_manager_state ENABLE ROW LEVEL SECURITY;

-- Initialize fund_manager_state
INSERT INTO fund_manager_state (network, layer, id)
VALUES 
  ('testnet', 'sapphire', 'fundManager'),
  ('mainnet', 'sapphire', 'fundManager')
ON CONFLICT DO NOTHING;

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
    'RewardsWithdraw'  
  )),
  amount NUMERIC(78, 0) NOT NULL DEFAULT 0,
  
  -- Unique constraint (contains network field)
  UNIQUE(network, layer, token, funds_type)
);

ALTER TABLE token_total_amounts ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 17. forwarder_state table (Forwarder status table - singleton)
-- ============================================
CREATE TABLE IF NOT EXISTS forwarder_state (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  id TEXT NOT NULL DEFAULT 'forwarder', -- Singleton ID
  paused BOOLEAN NOT NULL DEFAULT FALSE,
  
  PRIMARY KEY (network, layer, id) -- Composite primary key contains network field
);

ALTER TABLE forwarder_state ENABLE ROW LEVEL SECURITY;

-- Initialize forwarder_state
INSERT INTO forwarder_state (network, layer, id)
VALUES 
  ('testnet', 'sapphire', 'forwarder'),
  ('mainnet', 'sapphire', 'forwarder')
ON CONFLICT DO NOTHING;

-- ============================================
-- 16. sync_status table (Sync status table - for event sync script)
-- ============================================
-- Each contract has independent sync status
CREATE TABLE IF NOT EXISTS sync_status (
  
  network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
  layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
  
  contract_name TEXT NOT NULL CHECK (contract_name IN ('TRUTH_BOX', 'EXCHANGE', 'FUND_MANAGER', 'TRUTH_NFT', 'USER_MANAGER', 'FORWARDER')),
  last_synced_block NUMERIC(78, 0) NOT NULL DEFAULT 0,
  last_synced_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  
  PRIMARY KEY (network, layer, contract_name) -- Composite primary key contains network field and contract name
);

ALTER TABLE sync_status ENABLE ROW LEVEL SECURITY;

-- Initialize sync_status records (create initial records for each network and each contract)
INSERT INTO sync_status (network, layer, contract_name, last_synced_block, last_synced_at)
VALUES 
  ('testnet', 'sapphire', 'TRUTH_BOX', 0, NOW()),
  ('testnet', 'sapphire', 'EXCHANGE', 0, NOW()),
  ('testnet', 'sapphire', 'FUND_MANAGER', 0, NOW()),
  ('testnet', 'sapphire', 'TRUTH_NFT', 0, NOW()),
  ('testnet', 'sapphire', 'USER_MANAGER', 0, NOW()),
  ('testnet', 'sapphire', 'FORWARDER', 0, NOW()),
  ('mainnet', 'sapphire', 'TRUTH_BOX', 0, NOW()),
  ('mainnet', 'sapphire', 'EXCHANGE', 0, NOW()),
  ('mainnet', 'sapphire', 'FUND_MANAGER', 0, NOW()),
  ('mainnet', 'sapphire', 'TRUTH_NFT', 0, NOW()),
  ('mainnet', 'sapphire', 'USER_MANAGER', 0, NOW()),
  ('mainnet', 'sapphire', 'FORWARDER', 0, NOW())
ON CONFLICT (network, layer, contract_name) DO NOTHING;

