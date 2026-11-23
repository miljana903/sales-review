-- =====================================================================
-- 01_clean.sql  ·  Cleaning layer (SQLite 3.35+; ANSI-style, ports to
-- Postgres / SQL Server / Snowflake with minor function renames).
--
-- Inputs : raw_orders, raw_regions, raw_sales_agents  (loaded 1:1 from the
--          workbook sheets by work/run_pipeline.py; never modified)
-- Outputs: clean_sales_agents, clean_regions, clean_orders, fact_order_lines
--
-- Grain
--   clean_sales_agents : one row = one sales agent            (PK agent_id)
--   clean_regions      : one row = one ZIP code territory     (PK zipcode)
--   clean_orders       : one row = one revenue-category line of one order
--                        (PK order_id + order_category)
--   fact_order_lines   : same grain as clean_orders, enriched with territory
--                        and agent attributes (left joins, no row change)
-- Every step below is logged in docs/cleaning-log.md (step numbers match).
-- =====================================================================

DROP TABLE IF EXISTS clean_sales_agents;
DROP TABLE IF EXISTS clean_regions;
DROP TABLE IF EXISTS clean_orders;
DROP TABLE IF EXISTS fact_order_lines;

-- ---------------------------------------------------------------------
-- Sales agents (7 rows)
--   [C1] AGENT_ID stored as text -> INTEGER so it joins to Regions.AGENT_ID
--   [C2] SALES_TEAM case: 'team 1' / 'team 2' -> 'Team 1' / 'Team 2'
--   [C3] REGION trailing spaces trimmed (4 of 7 values)
-- ---------------------------------------------------------------------
CREATE TABLE clean_sales_agents AS
SELECT
    CAST(TRIM(AGENT_ID) AS INTEGER)                                AS agent_id,
    'Team ' || TRIM(SUBSTR(TRIM(SALES_TEAM), 5))                   AS sales_team,   -- normalises case of the 'Team' prefix
    TRIM(SALES_AGENT)                                              AS sales_agent,
    TRIM(REGION)                                                   AS agent_region
FROM raw_sales_agents;

-- ---------------------------------------------------------------------
-- Regions / territories (20 rows, one per ZIP)
--   [C4] ZIPCODE stored as number, leading zeros lost (965, 2554)
--        -> add zip5 text column '00965', '02554' (integer key kept for joins)
--   [C5] ZIP 965 (PR) has blank REGION and AGENT_ID -> labelled
--        'Unassigned (PR)' / agent NULL, row kept
--   [C6] Derived macro_region from the parenthesised parent in REGION
--        ('Mid-South (South)' -> 'South'); plain names map to themselves
-- ---------------------------------------------------------------------
CREATE TABLE clean_regions AS
SELECT
    CAST(ZIPCODE AS INTEGER)                                       AS zipcode,
    printf('%05d', CAST(ZIPCODE AS INTEGER))                       AS zip5,
    UPPER(TRIM(STATE))                                             AS state,
    COALESCE(NULLIF(TRIM(REGION), ''), 'Unassigned (PR)')          AS region,
    CASE
        WHEN NULLIF(TRIM(REGION), '') IS NULL THEN 'Unassigned (PR)'
        WHEN INSTR(REGION, '(') > 0
             THEN TRIM(SUBSTR(REGION, INSTR(REGION, '(') + 1,
                              INSTR(REGION, ')') - INSTR(REGION, '(') - 1))
        ELSE TRIM(REGION)
    END                                                            AS macro_region,
    CAST(AGENT_ID AS INTEGER)                                      AS agent_id      -- NULL stays NULL (unknown, not 0)
FROM raw_regions;

-- ---------------------------------------------------------------------
-- Orders (13,496 rows)
--   No duplicates (0 full-row, 0 on order_id+category) -> nothing removed.
--   [C7] revenue_type: 'Discount/Return' for the contra-revenue category,
--        'Revenue' otherwise. Net revenue = SUM(revenue) over all lines;
--        gross revenue = SUM(revenue) over 'Revenue' lines.
--   [C8] is_negative flag for negative lines outside the discount category
--        (refunds/reversals; kept, value unchanged)
--   [C9] is_zero flag (revenue = 0; kept, it is a recorded 0, not a blank)
--   [C10] is_outlier flag: |z| > 3 within its category (kept)
--   [C11] Derived month, ISO week start (Monday), weekday, partial-month flag
--        (data ends 2023-12-06, so December holds 4 business days only)
-- ---------------------------------------------------------------------
CREATE TABLE clean_orders AS
WITH typed AS (
    SELECT
        TRIM(ORDER_ID)                           AS order_id,
        TRIM(ORDER_CATEGORY)                     AS order_category,
        DATE(REPORTING_DATE)                     AS reporting_date,
        CAST(REVENUE AS REAL)                    AS revenue,
        CAST(ZIPCODE AS INTEGER)                 AS zipcode
    FROM raw_orders
),
cat_stats AS (                                   -- per-category mean / sd for the outlier flag
    SELECT order_category,
           AVG(revenue)                                                  AS mu,
           SQRT(AVG(revenue * revenue) - AVG(revenue) * AVG(revenue))    AS sd
    FROM typed
    GROUP BY order_category
),
max_date AS (SELECT MAX(reporting_date) AS d FROM typed)
SELECT
    t.order_id,
    t.order_category,
    REPLACE(t.order_category, ' Revenue', '')                            AS category_short,
    t.reporting_date,
    STRFTIME('%Y-%m', t.reporting_date)                                  AS month,
    DATE(t.reporting_date, '-' || ((CAST(STRFTIME('%w', t.reporting_date) AS INTEGER) + 6) % 7) || ' days')
                                                                         AS week_start,
    CAST(STRFTIME('%w', t.reporting_date) AS INTEGER)                    AS weekday_num,   -- 0 = Sunday
    t.revenue,
    t.zipcode,
    CASE WHEN t.order_category = 'Fee Discounts & Client Returns'
         THEN 'Discount/Return' ELSE 'Revenue' END                       AS revenue_type,
    CASE WHEN t.revenue < 0 AND t.order_category <> 'Fee Discounts & Client Returns'
         THEN 1 ELSE 0 END                                               AS is_negative,
    CASE WHEN t.revenue = 0 THEN 1 ELSE 0 END                            AS is_zero,
    CASE WHEN s.sd > 0 AND ABS(t.revenue - s.mu) / s.sd > 3
         THEN 1 ELSE 0 END                                               AS is_outlier,
    CASE WHEN STRFTIME('%Y-%m', t.reporting_date) = STRFTIME('%Y-%m', m.d)
         THEN 1 ELSE 0 END                                               AS is_partial_month
FROM typed t
JOIN cat_stats s USING (order_category)
CROSS JOIN max_date m;

CREATE UNIQUE INDEX ux_clean_orders ON clean_orders(order_id, order_category);
CREATE INDEX ix_clean_orders_zip   ON clean_orders(zipcode);
CREATE INDEX ix_clean_orders_month ON clean_orders(month);

-- ---------------------------------------------------------------------
-- Fact table: order lines + territory + agent.
--   LEFT JOINs keep every order line; reference tables proven unique per key
--   (see docs/validation.md). [C12] Lines whose ZIP has no agent show
--   'Unassigned (PR)' instead of disappearing.
-- ---------------------------------------------------------------------
CREATE TABLE fact_order_lines AS
SELECT
    o.*,
    r.zip5,
    r.state,
    COALESCE(r.region,       'Not found')                                AS region,
    COALESCE(r.macro_region, 'Not found')                                AS macro_region,
    r.agent_id,
    COALESCE(a.sales_agent, CASE WHEN r.zipcode IS NULL THEN 'Not found' ELSE 'Unassigned (PR)' END) AS sales_agent,
    COALESCE(a.sales_team,  CASE WHEN r.zipcode IS NULL THEN 'Not found' ELSE 'Unassigned (PR)' END) AS sales_team
FROM clean_orders o
LEFT JOIN clean_regions      r ON r.zipcode  = o.zipcode
LEFT JOIN clean_sales_agents a ON a.agent_id = r.agent_id;

CREATE INDEX ix_fact_agent ON fact_order_lines(sales_agent, month);
CREATE INDEX ix_fact_region ON fact_order_lines(macro_region, region, month);
