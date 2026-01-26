-- ============================================
-- Increment Migration: Update search_boxes return fields
-- Migration Date: 2026-01-26
-- ============================================

-- IMPORTANT: Use CASCADE to drop all existing overloads and dependent objects (if any)
-- This ensures no "duplicate function" or "return type mismatch" errors.
DROP FUNCTION IF EXISTS search_boxes CASCADE;

-- ============================================
-- Full text search function: search_boxes (Enhanced)
-- ============================================
CREATE OR REPLACE FUNCTION search_boxes(
  network_filter TEXT DEFAULT NULL,
  layer_filter TEXT DEFAULT 'sapphire',
  search_query TEXT DEFAULT NULL,
  status_filter SMALLINT[] DEFAULT NULL,
  type_of_crime_filter TEXT[] DEFAULT NULL,
  country_filter TEXT[] DEFAULT NULL,
  label_filter TEXT[] DEFAULT NULL,
  accepted_token_filter TEXT[] DEFAULT NULL,
  listed_mode_filter SMALLINT[] DEFAULT NULL,
  min_price NUMERIC DEFAULT NULL,
  max_price NUMERIC DEFAULT NULL,
  min_timestamp NUMERIC DEFAULT NULL,
  max_timestamp NUMERIC DEFAULT NULL,
  sort_by TEXT DEFAULT 'relevance',
  sort_direction TEXT DEFAULT 'desc',
  limit_count INTEGER DEFAULT 20,
  offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
  id NUMERIC(78, 0),
  title TEXT,
  description TEXT,
  type_of_crime TEXT,
  country TEXT,
  state TEXT,
  label TEXT[],
  status SMALLINT,
  listed_mode SMALLINT,
  price NUMERIC,
  deadline NUMERIC(78, 0),  -- Added
  buyer_id NUMERIC(78, 0), -- Added
  nft_image TEXT,
  box_image TEXT,
  event_date DATE,
  create_timestamp NUMERIC,
  accepted_token TEXT,
  relevance REAL
) AS $$
BEGIN
  -- Parameter validation
  IF network_filter IS NULL THEN
    RAISE EXCEPTION 'network_filter cannot be NULL';
  END IF;
  IF network_filter NOT IN ('testnet', 'mainnet') THEN
    RAISE EXCEPTION 'network_filter must be ''testnet'' or ''mainnet''';
  END IF;
  IF layer_filter IS NOT NULL AND layer_filter != 'sapphire' THEN
    RAISE EXCEPTION 'layer_filter must be ''sapphire''';
  END IF;

  -- Safety cap: max 200 records
  limit_count := LEAST(limit_count, 200);
  
  -- Validate sort parameters
  IF sort_by NOT IN ('relevance', 'price', 'event_date', 'box_id') THEN
    RAISE EXCEPTION 'sort_by must be ''relevance'', ''price'', ''event_date'', or ''box_id''';
  END IF;
  IF sort_direction NOT IN ('asc', 'desc') THEN
    RAISE EXCEPTION 'sort_direction must be ''asc'' or ''desc''';
  END IF;
  
  RETURN QUERY
  SELECT 
    b.id,
    mb.title,
    mb.description,
    mb.type_of_crime,
    mb.country,
    mb.state,
    mb.label,
    b.status,
    b.listed_mode,
    b.price,
    b.deadline,  -- Added
    b.buyer_id,  -- Added
    mb.nft_image,
    mb.box_image,
    mb.event_date,
    b.create_timestamp,
    b.accepted_token,
    CASE 
      WHEN search_query IS NOT NULL THEN
        -- Weighted relevance score
        (
          -- Exact match boxId (highest priority)
          CASE WHEN b.id::TEXT = search_query THEN 10.0 ELSE 0 END +
          -- Full text search relevance (title and description)
          ts_rank(
            to_tsvector('english', COALESCE(mb.title, '') || ' ' || COALESCE(mb.description, '')),
            plainto_tsquery('english', search_query)
          ) * 5.0 +
          -- title fuzzy matching
          CASE WHEN mb.title ILIKE '%' || search_query || '%' THEN 3.0 ELSE 0 END +
          -- description fuzzy matching
          CASE WHEN mb.description ILIKE '%' || search_query || '%' THEN 2.0 ELSE 0 END +
          -- type_of_crime fuzzy matching
          CASE WHEN mb.type_of_crime ILIKE '%' || search_query || '%' THEN 2.0 ELSE 0 END +
          -- country fuzzy matching
          CASE WHEN mb.country ILIKE '%' || search_query || '%' THEN 1.5 ELSE 0 END +
          -- state fuzzy matching
          CASE WHEN mb.state ILIKE '%' || search_query || '%' THEN 1.5 ELSE 0 END +
          -- label matching
          CASE WHEN mb.label IS NOT NULL AND search_query = ANY(mb.label) THEN 2.0 ELSE 0 END
        )::REAL
      ELSE 0::REAL
    END AS relevance
  FROM boxes b
  LEFT JOIN metadata_boxes mb ON mb.network = b.network AND mb.layer = b.layer AND mb.id = b.id
  WHERE 
    b.network = network_filter
    AND b.layer = layer_filter
    AND (
      -- If there is no search query, return all results
      search_query IS NULL OR
      search_query = '' OR
      -- Exact match: boxId
      b.id::TEXT = search_query OR
      -- Full text search: title and description
      (mb.title IS NOT NULL OR mb.description IS NOT NULL) AND
      to_tsvector('english', COALESCE(mb.title, '') || ' ' || COALESCE(mb.description, '')) 
      @@ plainto_tsquery('english', search_query) OR
      -- title fuzzy matching
      (mb.title IS NOT NULL AND mb.title ILIKE '%' || search_query || '%') OR
      -- description fuzzy matching
      (mb.description IS NOT NULL AND mb.description ILIKE '%' || search_query || '%') OR
      -- type_of_crime fuzzy matching
      (mb.type_of_crime IS NOT NULL AND mb.type_of_crime ILIKE '%' || search_query || '%') OR
      -- country fuzzy matching
      (mb.country IS NOT NULL AND mb.country ILIKE '%' || search_query || '%') OR
      -- state fuzzy matching
      (mb.state IS NOT NULL AND mb.state ILIKE '%' || search_query || '%') OR
      -- label matching
      (mb.label IS NOT NULL AND search_query = ANY(mb.label))
    )
    AND (status_filter IS NULL OR b.status = ANY(status_filter))
    AND (type_of_crime_filter IS NULL OR (mb.type_of_crime IS NOT NULL AND mb.type_of_crime = ANY(type_of_crime_filter)))
    AND (country_filter IS NULL OR (mb.country IS NOT NULL AND mb.country = ANY(country_filter)))
    AND (label_filter IS NULL OR (mb.label IS NOT NULL AND mb.label && label_filter)) 
    AND (accepted_token_filter IS NULL OR b.accepted_token = ANY(accepted_token_filter))
    AND (listed_mode_filter IS NULL OR b.listed_mode = ANY(listed_mode_filter))
    AND (min_price IS NULL OR b.price >= min_price)
    AND (max_price IS NULL OR b.price <= max_price)
    AND (min_timestamp IS NULL OR b.create_timestamp >= min_timestamp)
    AND (max_timestamp IS NULL OR b.create_timestamp <= max_timestamp)
  ORDER BY 
    CASE 
      WHEN search_query IS NOT NULL AND sort_by = 'relevance' THEN
        CASE WHEN sort_direction = 'desc' THEN relevance::NUMERIC ELSE -relevance::NUMERIC END
      WHEN sort_by = 'price' THEN
        CASE WHEN sort_direction = 'desc' THEN b.price ELSE -b.price END
      WHEN sort_by = 'event_date' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN 
            CASE WHEN mb.event_date IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM mb.event_date) END
          ELSE 
            CASE WHEN mb.event_date IS NULL THEN 9999999999 ELSE -EXTRACT(EPOCH FROM mb.event_date) END
        END
      WHEN sort_by = 'box_id' THEN
        CASE 
          WHEN sort_direction = 'desc' THEN b.id::NUMERIC
          ELSE -b.id::NUMERIC
        END
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
