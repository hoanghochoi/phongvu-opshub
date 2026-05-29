CREATE OR REPLACE FUNCTION map_vietin_order_code_is_valid(code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  order_year INTEGER;
  order_month INTEGER;
  order_day INTEGER;
  parsed_date DATE;
BEGIN
  IF code !~ '^[0-9]{14}$' THEN
    RETURN FALSE;
  END IF;

  order_year := 2000 + substring(code FROM 1 FOR 2)::INTEGER;
  order_month := substring(code FROM 3 FOR 2)::INTEGER;
  order_day := substring(code FROM 5 FOR 2)::INTEGER;

  IF order_month < 1 OR order_month > 12 OR order_day < 1 OR order_day > 31 THEN
    RETURN FALSE;
  END IF;

  BEGIN
    parsed_date := make_date(order_year, order_month, order_day);
  EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
  END;

  RETURN EXTRACT(YEAR FROM parsed_date)::INTEGER = order_year
    AND EXTRACT(MONTH FROM parsed_date)::INTEGER = order_month
    AND EXTRACT(DAY FROM parsed_date)::INTEGER = order_day;
END;
$$;

CREATE OR REPLACE FUNCTION map_vietin_extract_order_codes(content TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  output TEXT[] := ARRAY[]::TEXT[];
  content_length INTEGER;
  current_index INTEGER;
  candidate TEXT;
  previous_char TEXT;
  next_char TEXT;
BEGIN
  IF content IS NULL OR content = '' THEN
    RETURN output;
  END IF;

  content_length := char_length(content);
  IF content_length < 14 THEN
    RETURN output;
  END IF;

  FOR current_index IN 1..(content_length - 13) LOOP
    candidate := substring(content FROM current_index FOR 14);

    IF candidate ~ '^[0-9]{14}$' THEN
      previous_char := CASE
        WHEN current_index = 1 THEN ''
        ELSE substring(content FROM current_index - 1 FOR 1)
      END;
      next_char := CASE
        WHEN current_index + 14 > content_length THEN ''
        ELSE substring(content FROM current_index + 14 FOR 1)
      END;

      IF (current_index = 1 OR previous_char !~ '^[0-9]$')
        AND (current_index + 14 > content_length OR next_char !~ '^[0-9]$')
        AND map_vietin_order_code_is_valid(candidate)
        AND NOT candidate = ANY(output) THEN
        output := array_append(output, candidate);
      END IF;
    END IF;
  END LOOP;

  RETURN output;
END;
$$;

WITH extracted AS (
  SELECT
    id,
    map_vietin_extract_order_codes(content) AS new_orders
  FROM "MapVietinTransaction"
  WHERE COALESCE(array_length("orders", 1), 0) = 0
    AND COALESCE("orderSource", '') <> 'MANUAL'
)
UPDATE "MapVietinTransaction" AS tx
SET
  "orders" = extracted.new_orders,
  "orderSource" = 'AUTO',
  "updatedAt" = NOW()
FROM extracted
WHERE tx.id = extracted.id
  AND COALESCE(array_length(extracted.new_orders, 1), 0) > 0;

DROP FUNCTION map_vietin_extract_order_codes(TEXT);
DROP FUNCTION map_vietin_order_code_is_valid(TEXT);
