-- WikiTruth Supabase 数据库迁移文件
-- 07_drop_sell_timestamp.sql - 删除 boxes 表中的 sell_timestamp 字段
-- 
-- 说明：sell_timestamp 字段已不再使用，移除该字段
-- 如果表不存在或字段不存在，此迁移会安全地跳过

-- 删除 sell_timestamp 字段（如果存在）
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'boxes' 
        AND column_name = 'sell_timestamp'
    ) THEN
        ALTER TABLE boxes DROP COLUMN sell_timestamp;
    END IF;
END $$;

