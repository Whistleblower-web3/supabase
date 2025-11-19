-- WikiTruth Supabase 数据库迁移文件
-- 03_functions.sql - 创建全文搜索函数
-- 注意：函数创建在表和索引之后
-- 所有函数都支持网络过滤，用于区分不同网络的数据

-- ============================================
-- 全文搜索函数：search_boxes
-- ============================================
-- 支持全文搜索、精确筛选和复合查询
-- 关联 metadata_boxes 表获取元数据信息
-- 必须指定网络参数以区分不同网络的数据
CREATE OR REPLACE FUNCTION search_boxes(
  network_filter TEXT DEFAULT NULL,
  layer_filter TEXT DEFAULT 'sapphire',
  search_query TEXT DEFAULT NULL,
  status_filter TEXT[] DEFAULT NULL,
  type_of_crime_filter TEXT[] DEFAULT NULL,
  country_filter TEXT[] DEFAULT NULL,
  label_filter TEXT[] DEFAULT NULL,
  min_price NUMERIC DEFAULT NULL,
  max_price NUMERIC DEFAULT NULL,
  min_timestamp NUMERIC DEFAULT NULL,
  max_timestamp NUMERIC DEFAULT NULL,
  sort_by TEXT DEFAULT 'relevance',  -- 排序字段：'relevance' | 'price' | 'event_date' | 'box_id'
  sort_direction TEXT DEFAULT 'desc',  -- 排序方向：'asc' | 'desc'
  limit_count INTEGER DEFAULT 20,
  offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
  id BIGINT,
  token_id BIGINT,
  title TEXT,
  description TEXT,
  type_of_crime TEXT,
  country TEXT,
  state TEXT,
  label TEXT[],
  status TEXT,
  price NUMERIC,
  nft_image TEXT,
  box_image TEXT,
  create_timestamp NUMERIC,
  relevance REAL
) AS $$
BEGIN
  -- 参数验证
  IF network_filter IS NULL THEN
    RAISE EXCEPTION 'network_filter cannot be NULL';
  END IF;
  IF network_filter NOT IN ('testnet', 'mainnet') THEN
    RAISE EXCEPTION 'network_filter must be ''testnet'' or ''mainnet''';
  END IF;
  IF layer_filter IS NOT NULL AND layer_filter != 'sapphire' THEN
    RAISE EXCEPTION 'layer_filter must be ''sapphire''';
  END IF;
  
  -- 验证排序参数
  IF sort_by NOT IN ('relevance', 'price', 'event_date', 'box_id') THEN
    RAISE EXCEPTION 'sort_by must be ''relevance'', ''price'', ''event_date'', or ''box_id''';
  END IF;
  IF sort_direction NOT IN ('asc', 'desc') THEN
    RAISE EXCEPTION 'sort_direction must be ''asc'' or ''desc''';
  END IF;
  
  RETURN QUERY
  SELECT 
    b.id,
    b.token_id,
    mb.title,
    mb.description,
    mb.type_of_crime,
    mb.country,
    mb.state,
    mb.label,
    b.status,
    b.price,
    mb.nft_image,
    mb.box_image,
    b.create_timestamp,
    CASE 
      WHEN search_query IS NOT NULL THEN
        -- 加权相关性评分
        (
          -- 精确匹配 boxId（最高优先级）
          CASE WHEN b.id::TEXT = search_query THEN 10.0 ELSE 0 END +
          -- 精确匹配 tokenId
          CASE WHEN b.token_id::TEXT = search_query THEN 9.0 ELSE 0 END +
          -- 全文搜索相关性（title 和 description）
          ts_rank(
            to_tsvector('english', COALESCE(mb.title, '') || ' ' || COALESCE(mb.description, '')),
            plainto_tsquery('english', search_query)
          ) * 5.0 +
          -- title 模糊匹配
          CASE WHEN mb.title ILIKE '%' || search_query || '%' THEN 3.0 ELSE 0 END +
          -- description 模糊匹配
          CASE WHEN mb.description ILIKE '%' || search_query || '%' THEN 2.0 ELSE 0 END +
          -- type_of_crime 模糊匹配
          CASE WHEN mb.type_of_crime ILIKE '%' || search_query || '%' THEN 2.0 ELSE 0 END +
          -- country 模糊匹配
          CASE WHEN mb.country ILIKE '%' || search_query || '%' THEN 1.5 ELSE 0 END +
          -- state 模糊匹配
          CASE WHEN mb.state ILIKE '%' || search_query || '%' THEN 1.5 ELSE 0 END +
          -- label 匹配
          CASE WHEN mb.label IS NOT NULL AND search_query = ANY(mb.label) THEN 2.0 ELSE 0 END +
          -- status 模糊匹配
          CASE WHEN b.status ILIKE '%' || search_query || '%' THEN 1.0 ELSE 0 END
        )::REAL
      ELSE 0::REAL
    END AS relevance
  FROM boxes b
  LEFT JOIN metadata_boxes mb ON mb.network = b.network AND mb.layer = b.layer AND mb.id = b.id
  WHERE 
    b.network = network_filter
    AND b.layer = layer_filter
    AND (
      -- 如果没有搜索查询，返回所有结果
      search_query IS NULL OR
      -- 全文搜索：title 和 description
      to_tsvector('english', COALESCE(mb.title, '') || ' ' || COALESCE(mb.description, '')) 
      @@ plainto_tsquery('english', search_query) OR
      -- 精确匹配：boxId（支持文本和数字）
      b.id::TEXT = search_query OR
      b.token_id::TEXT = search_query OR
      -- 模糊匹配：title
      mb.title ILIKE '%' || search_query || '%' OR
      -- 模糊匹配：description
      mb.description ILIKE '%' || search_query || '%' OR
      -- 模糊匹配：type_of_crime
      mb.type_of_crime ILIKE '%' || search_query || '%' OR
      -- 模糊匹配：country
      mb.country ILIKE '%' || search_query || '%' OR
      -- 模糊匹配：state
      mb.state ILIKE '%' || search_query || '%' OR
      -- 标签匹配
      (mb.label IS NOT NULL AND search_query = ANY(mb.label)) OR
      -- status 匹配
      b.status ILIKE '%' || search_query || '%'
    )
    AND (status_filter IS NULL OR b.status = ANY(status_filter))
    AND (type_of_crime_filter IS NULL OR mb.type_of_crime = ANY(type_of_crime_filter))
    AND (country_filter IS NULL OR mb.country = ANY(country_filter))
    AND (label_filter IS NULL OR mb.label && label_filter) -- 数组交集
    AND (min_price IS NULL OR b.price >= min_price)
    AND (max_price IS NULL OR b.price <= max_price)
    AND (min_timestamp IS NULL OR b.create_timestamp >= min_timestamp)
    AND (max_timestamp IS NULL OR b.create_timestamp <= max_timestamp)
  ORDER BY 
    -- 动态排序逻辑（所有值转换为 NUMERIC 以统一类型）
    CASE 
      -- 如果有搜索查询且排序字段为 relevance，优先按相关性排序
      WHEN search_query IS NOT NULL AND sort_by = 'relevance' THEN
        CASE WHEN sort_direction = 'desc' THEN relevance::NUMERIC ELSE -relevance::NUMERIC END
      -- 如果排序字段为 price
      WHEN sort_by = 'price' THEN
        CASE WHEN sort_direction = 'desc' THEN b.price ELSE -b.price END
      -- 如果排序字段为 event_date（来自 metadata_boxes，转换为时间戳）
      WHEN sort_by = 'event_date' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN 
            CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
          ELSE 
            CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
        END
      -- 如果排序字段为 box_id（即 id，直接使用数字排序）
      WHEN sort_by = 'box_id' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN b.id::NUMERIC
          ELSE -b.id::NUMERIC
        END
      -- 默认情况：如果有搜索查询，按相关性排序；否则按事件日期排序
      ELSE
        CASE 
          WHEN search_query IS NOT NULL THEN
            CASE WHEN sort_direction = 'desc' THEN relevance::NUMERIC ELSE -relevance::NUMERIC END
          ELSE
            CASE 
              WHEN sort_direction = 'desc' THEN 
                CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
              ELSE 
                CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
            END
        END
    END DESC,
    -- 次要排序：确保结果稳定（当主要排序字段值相同时，统一使用 NUMERIC 类型）
    CASE 
      WHEN sort_by = 'relevance' OR (search_query IS NOT NULL AND sort_by = 'relevance') THEN
        CASE 
          WHEN sort_direction = 'desc' THEN 
            CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
          ELSE 
            CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
        END
      WHEN sort_by = 'price' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN 
            CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
          ELSE 
            CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
        END
      WHEN sort_by = 'event_date' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN b.id::NUMERIC
          ELSE -b.id::NUMERIC
        END
      WHEN sort_by = 'box_id' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN 
            CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
          ELSE 
            CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
        END
      ELSE
        CASE 
          WHEN sort_direction = 'desc' THEN b.id::NUMERIC
          ELSE -b.id::NUMERIC
        END
    END DESC
  LIMIT limit_count
  OFFSET offset_count;
END;
$$ LANGUAGE plpgsql;

