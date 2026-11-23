-- =====================================================================
-- 03_validate.sql · Stage 3 checks on the cleaned data. Each row returns
-- check, expected, got. run_pipeline.py marks pass/fail and adds an
-- independent pandas recomputation for the two-methods check.
-- =====================================================================
SELECT 'Row reconciliation: raw order lines - removed (0) = clean lines' AS chk,
       (SELECT COUNT(*) FROM raw_orders) - 0 AS expected, (SELECT COUNT(*) FROM clean_orders) AS got
UNION ALL SELECT 'Row count unchanged by joins (clean_orders = fact_order_lines)',
       (SELECT COUNT(*) FROM clean_orders), (SELECT COUNT(*) FROM fact_order_lines)
UNION ALL SELECT 'Distinct orders raw = clean',
       (SELECT COUNT(DISTINCT ORDER_ID) FROM raw_orders), (SELECT COUNT(*) FROM v_orders)
UNION ALL SELECT 'Total reconciliation: raw revenue x100 = clean revenue x100 (cents)',
       (SELECT CAST(ROUND(SUM(REVENUE)*100) AS INTEGER) FROM raw_orders),
       (SELECT CAST(ROUND(SUM(revenue)*100) AS INTEGER) FROM fact_order_lines)
UNION ALL SELECT 'Grain: clean lines = distinct (order_id, category)',
       (SELECT COUNT(*) FROM clean_orders),
       (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_category FROM clean_orders))
UNION ALL SELECT 'Grain: one date and one ZIP per order (orders with >1)', 0,
       (SELECT COUNT(*) FROM (SELECT order_id FROM clean_orders GROUP BY order_id
                              HAVING COUNT(DISTINCT reporting_date) > 1 OR COUNT(DISTINCT zipcode) > 1))
UNION ALL SELECT 'Reference unique: regions rows = distinct zipcode',
       (SELECT COUNT(*) FROM clean_regions), (SELECT COUNT(DISTINCT zipcode) FROM clean_regions)
UNION ALL SELECT 'Reference unique: agents rows = distinct agent_id',
       (SELECT COUNT(*) FROM clean_sales_agents), (SELECT COUNT(DISTINCT agent_id) FROM clean_sales_agents)
UNION ALL SELECT 'Joins: order lines with ZIP not in Regions (Not found)', 0,
       (SELECT COUNT(*) FROM fact_order_lines WHERE region = 'Not found')
UNION ALL SELECT 'Joins: Regions.agent_id not in Sales_agents (excluding logged NULL)', 0,
       (SELECT COUNT(*) FROM clean_regions r LEFT JOIN clean_sales_agents a USING (agent_id)
        WHERE r.agent_id IS NOT NULL AND a.agent_id IS NULL)
UNION ALL SELECT 'Joins: lines labelled Unassigned (PR) = raw lines for ZIP 965 (logged C5)',
       (SELECT COUNT(*) FROM raw_orders WHERE ZIPCODE = 965),
       (SELECT COUNT(*) FROM fact_order_lines WHERE sales_agent = 'Unassigned (PR)')
UNION ALL SELECT 'Consistency: agent region = ZIP region for every assigned ZIP (mismatches)', 0,
       (SELECT COUNT(*) FROM clean_regions r JOIN clean_sales_agents a USING (agent_id)
        WHERE r.region <> a.agent_region)
UNION ALL SELECT 'Nulls: blank revenue / date / category / ZIP in clean_orders', 0,
       (SELECT COUNT(*) FROM clean_orders WHERE revenue IS NULL OR reporting_date IS NULL
              OR order_category IS NULL OR zipcode IS NULL)
UNION ALL SELECT 'Nulls: NULL agent_id in fact = lines of ZIP 965 only',
       (SELECT COUNT(*) FROM raw_orders WHERE ZIPCODE = 965),
       (SELECT COUNT(*) FROM fact_order_lines WHERE agent_id IS NULL)
UNION ALL SELECT 'Types: numeric revenue count = non-blank count',
       (SELECT COUNT(revenue) FROM clean_orders),
       (SELECT COUNT(*) FROM clean_orders WHERE typeof(revenue) = 'real')
UNION ALL SELECT 'Types: valid ISO dates (date() round-trips)',
       (SELECT COUNT(*) FROM clean_orders),
       (SELECT COUNT(*) FROM clean_orders WHERE DATE(reporting_date) = reporting_date)
UNION ALL SELECT 'Domains: sales_team values not of form Team N', 0,
       (SELECT COUNT(*) FROM clean_sales_agents WHERE sales_team NOT GLOB 'Team [0-9]')
UNION ALL SELECT 'Domains: distinct sales teams after case fix', 5,
       (SELECT COUNT(DISTINCT sales_team) FROM clean_sales_agents)
UNION ALL SELECT 'Domains: values with leading/trailing spaces (agents+regions)', 0,
       (SELECT COUNT(*) FROM clean_sales_agents WHERE agent_region <> TRIM(agent_region) OR sales_team <> TRIM(sales_team))
     + (SELECT COUNT(*) FROM clean_regions WHERE region <> TRIM(region))
UNION ALL SELECT 'Domains: dates outside 2023-01-01..2023-12-31', 0,
       (SELECT COUNT(*) FROM clean_orders WHERE reporting_date < '2023-01-01' OR reporting_date >= '2024-01-01')
UNION ALL SELECT 'Flags: is_negative = negative lines outside discount category',
       (SELECT COUNT(*) FROM raw_orders WHERE REVENUE < 0 AND ORDER_CATEGORY <> 'Fee Discounts & Client Returns'),
       (SELECT SUM(is_negative) FROM clean_orders)
UNION ALL SELECT 'Flags: is_zero = raw zero lines',
       (SELECT COUNT(*) FROM raw_orders WHERE REVENUE = 0), (SELECT SUM(is_zero) FROM clean_orders)
UNION ALL SELECT 'Flags: is_partial_month = raw lines dated December 2023',
       (SELECT COUNT(*) FROM raw_orders WHERE REPORTING_DATE >= '2023-12-01'),
       (SELECT SUM(is_partial_month) FROM clean_orders)
UNION ALL SELECT 'Group totals: sum of agent revenue x100 = grand total x100',
       (SELECT CAST(ROUND(SUM(revenue)*100) AS INTEGER) FROM fact_order_lines),
       (SELECT CAST(ROUND(SUM(net_revenue)*100) AS INTEGER) FROM mgr_agent)
UNION ALL SELECT 'Group totals: sum of region revenue x100 = grand total x100',
       (SELECT CAST(ROUND(SUM(revenue)*100) AS INTEGER) FROM fact_order_lines),
       (SELECT CAST(ROUND(SUM(net_revenue)*100) AS INTEGER) FROM dir_region)
UNION ALL SELECT 'Group totals: sum of monthly revenue x100 = grand total x100',
       (SELECT CAST(ROUND(SUM(revenue)*100) AS INTEGER) FROM fact_order_lines),
       (SELECT CAST(ROUND(SUM(net_revenue)*100) AS INTEGER) FROM dir_monthly)
UNION ALL SELECT 'Group totals: sum of category revenue x100 = grand total x100',
       (SELECT CAST(ROUND(SUM(revenue)*100) AS INTEGER) FROM fact_order_lines),
       (SELECT CAST(ROUND(SUM(net_revenue)*100) AS INTEGER) FROM dir_category)
UNION ALL SELECT 'Group totals: sum of agent orders = total orders',
       (SELECT COUNT(*) FROM v_orders), (SELECT SUM(orders) FROM mgr_agent);
