-- Step 1: Check if table exists, if not create (compatibility processing)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sync_status') THEN
        -- If table does not exist, create table with new structure
        CREATE TABLE sync_status (
            network TEXT NOT NULL CHECK (network IN ('testnet', 'mainnet')),
            layer TEXT NOT NULL DEFAULT 'sapphire' CHECK (layer = 'sapphire'),
            contract_name TEXT NOT NULL CHECK (contract_name IN ('TRUTH_BOX', 'EXCHANGE', 'FUND_MANAGER', 'TRUTH_NFT', 'USER_ID')),
            last_synced_block NUMERIC(78, 0) NOT NULL DEFAULT 0,
            last_synced_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            PRIMARY KEY (network, layer, contract_name)
        );
        RETURN;
    END IF;
END $$;

-- Step 2: Create temporary table to backup old data (only when table has old structure)
DO $$
DECLARE
    v_network TEXT;
    v_layer TEXT;
    v_last_synced_block NUMERIC(78, 0);
    v_last_synced_at TIMESTAMP WITH TIME ZONE;
    v_contract_name TEXT;
    v_has_id_column BOOLEAN;
BEGIN
    -- Check if id column exists
    SELECT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public'
        AND table_name = 'sync_status' 
        AND column_name = 'id'
    ) INTO v_has_id_column;
    
    IF v_has_id_column THEN
        -- Backup old data
        DROP TABLE IF EXISTS sync_status_backup;
        CREATE TABLE sync_status_backup AS
        SELECT * FROM sync_status;
        
        -- Step 3: Drop old primary key constraint
        ALTER TABLE sync_status DROP CONSTRAINT IF EXISTS sync_status_pkey;
        
        -- Step 4: Clear old data (because primary key structure will change, need to re-insert)
        DELETE FROM sync_status;
        
        -- Step 5: Add new contract_name column
        ALTER TABLE sync_status ADD COLUMN IF NOT EXISTS contract_name TEXT;
        
        -- Step 6: Migrate data: copy the record with id=1 to each contract
        -- Create 5 records for each network/layer combination (corresponding to 5 contracts)
        FOR v_network, v_layer, v_last_synced_block, v_last_synced_at IN
            SELECT DISTINCT network, layer, last_synced_block, last_synced_at
            FROM sync_status_backup
            WHERE id = 1
        LOOP
            -- Create record for each contract
            FOREACH v_contract_name IN ARRAY ARRAY['TRUTH_BOX', 'EXCHANGE', 'FUND_MANAGER', 'TRUTH_NFT', 'USER_ID']
            LOOP
                INSERT INTO sync_status (network, layer, contract_name, last_synced_block, last_synced_at)
                VALUES (v_network, v_layer, v_contract_name, v_last_synced_block, v_last_synced_at);
            END LOOP;
        END LOOP;
        
        -- Step 7: Drop old id column
        ALTER TABLE sync_status DROP COLUMN IF EXISTS id;
        
        -- Step 8: Add NOT NULL constraint to contract_name
        ALTER TABLE sync_status ALTER COLUMN contract_name SET NOT NULL;
        
        -- Step 9: Add CHECK constraint (if not exists)
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'sync_status_contract_name_check'
        ) THEN
            ALTER TABLE sync_status ADD CONSTRAINT sync_status_contract_name_check 
                CHECK (contract_name IN ('TRUTH_BOX', 'EXCHANGE', 'FUND_MANAGER', 'TRUTH_NFT', 'USER_ID'));
        END IF;
        
        -- Step 10: Add new primary key constraint
        ALTER TABLE sync_status ADD CONSTRAINT sync_status_pkey 
            PRIMARY KEY (network, layer, contract_name);
    ELSE
        -- If table is already new structure, only ensure all records exist
        RAISE NOTICE 'sync_status table is already new structure, skip migration';
    END IF;
END $$;

-- Step 10: Ensure all networks and contracts have initial records (if some records are missing after migration)
INSERT INTO sync_status (network, layer, contract_name, last_synced_block, last_synced_at)
SELECT 
    n.network,
    n.layer,
    c.contract_name,
    0,
    NOW()
FROM 
    (SELECT DISTINCT network, layer FROM sync_status) n
CROSS JOIN 
    (VALUES 
        ('TRUTH_BOX'),
        ('EXCHANGE'),
        ('FUND_MANAGER'),
        ('TRUTH_NFT'),
        ('USER_ID')
    ) AS c(contract_name)
WHERE NOT EXISTS (
    SELECT 1 
    FROM sync_status s 
    WHERE s.network = n.network 
    AND s.layer = n.layer 
    AND s.contract_name = c.contract_name
)
ON CONFLICT (network, layer, contract_name) DO NOTHING;

-- Step 11: Clean up temporary table (optional, recommended to keep for verification)
-- DROP TABLE IF EXISTS sync_status_backup;