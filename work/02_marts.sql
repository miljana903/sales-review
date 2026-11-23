-- =====================================================================
-- 02_marts.sql  ·  Reporting layer feeding both dashboards.
-- Input : fact_order_lines (01_clean.sql)
--
-- Metric definitions (used everywhere)
--   Net revenue      = SUM(revenue) over all lines, incl. discounts/returns
--   Gross revenue    = SUM(revenue) over lines where revenue_type = 'Revenue'
--   Discounts        = SUM(revenue) over 'Fee Discounts & Client Returns' lines
--   Discount rate    = -Discounts / Gross revenue
--   Orders           = COUNT(DISTINCT order_id)
--   AOV              = Net revenue / Orders
--   Revenue per ZIP  = Net revenue / number of ZIP territories (each ZIP
--                      carries ~300 orders, so territory size drives totals)
--   Full months      = 2023-01 .. 2023-11 (2023-12 holds 4 days, flagged)
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_orders  ·  one row = one order (PK order_id). Aggregates lines once so
-- every order-level metric (AOV, order counts) is computed on one grain.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_orders;
CREATE VIEW v_orders AS
SELECT
    order_id,
    MIN(reporting_date)                                                  AS reporting_date,
    MIN(month)                                                           AS month,
    MIN(week_start)                                                      AS week_start,
    MIN(is_partial_month)                                                AS is_partial_month,
    MIN(zipcode)                                                         AS zipcode,
    MIN(zip5)                                                            AS zip5,
    MIN(state)                                                           AS state,
    MIN(region)                                                          AS region,
    MIN(macro_region)                                                    AS macro_region,
    MIN(sales_agent)                                                     AS sales_agent,
    MIN(sales_team)                                                      AS sales_team,
    COUNT(*)                                                             AS lines,
    SUM(revenue)                                                         AS net_revenue,
    SUM(CASE WHEN revenue_type = 'Revenue' THEN revenue ELSE 0 END)      AS gross_revenue,
    SUM(CASE WHEN revenue_type = 'Discount/Return' THEN revenue ELSE 0 END) AS discounts
FROM fact_order_lines
GROUP BY order_id;

-- ---------------------------------------------------------------------
-- Director 1 · headline KPIs (one row)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dir_kpis;
CREATE VIEW dir_kpis AS
SELECT
    ROUND(SUM(net_revenue), 2)                                           AS net_revenue,
    ROUND(SUM(gross_revenue), 2)                                         AS gross_revenue,
    ROUND(SUM(discounts), 2)                                             AS discounts,
    ROUND(-SUM(discounts) / SUM(gross_revenue), 4)                       AS discount_rate,
    COUNT(*)                                                             AS orders,
    ROUND(SUM(net_revenue) / COUNT(*), 2)                                AS aov,
    COUNT(DISTINCT zipcode)                                              AS zips,
    ROUND(SUM(net_revenue) / COUNT(DISTINCT zipcode), 2)                 AS revenue_per_zip,
    MIN(reporting_date)                                                  AS first_date,
    MAX(reporting_date)                                                  AS last_date,
    ROUND(SUM(CASE WHEN is_partial_month = 0 THEN net_revenue END)
          / COUNT(DISTINCT CASE WHEN is_partial_month = 0 THEN month END), 2) AS avg_full_month_revenue,
    ROUND(SUM(CASE WHEN month BETWEEN '2023-01' AND '2023-06' THEN net_revenue END) / 6.0, 2) AS h1_avg_month,
    ROUND(SUM(CASE WHEN month BETWEEN '2023-07' AND '2023-11' THEN net_revenue END) / 5.0, 2) AS h2_avg_month,
    ROUND((SUM(CASE WHEN month BETWEEN '2023-07' AND '2023-11' THEN net_revenue END) / 5.0)
        / (SUM(CASE WHEN month BETWEEN '2023-01' AND '2023-06' THEN net_revenue END) / 6.0) - 1, 4) AS h2_vs_h1,
    ROUND(SUM(CASE WHEN month = '2023-11' THEN net_revenue END), 2)     AS nov_revenue,
    ROUND(SUM(CASE WHEN month BETWEEN '2023-08' AND '2023-10' THEN net_revenue END) / 3.0, 2) AS aug_oct_avg,
    ROUND(SUM(CASE WHEN month = '2023-11' THEN net_revenue END)
        / (SUM(CASE WHEN month BETWEEN '2023-08' AND '2023-10' THEN net_revenue END) / 3.0) - 1, 4) AS nov_vs_aug_oct,
    ROUND(SUM(CASE WHEN sales_agent = 'Unassigned (PR)' THEN net_revenue END), 2) AS unassigned_revenue,
    ROUND(SUM(CASE WHEN sales_agent = 'Unassigned (PR)' THEN net_revenue END) / SUM(net_revenue), 4) AS unassigned_share
FROM v_orders;

-- ---------------------------------------------------------------------
-- Director 2 · monthly trend. Revenue per business day makes the partial
-- December comparable with full months.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dir_monthly;
CREATE VIEW dir_monthly AS
WITH m AS (
    SELECT month,
           MAX(is_partial_month)                     AS is_partial_month,
           COUNT(*)                                  AS orders,
           SUM(net_revenue)                          AS net_revenue,
           SUM(gross_revenue)                        AS gross_revenue,
           SUM(discounts)                            AS discounts,
           COUNT(DISTINCT reporting_date)            AS trading_days
    FROM v_orders
    GROUP BY month
)
SELECT month, is_partial_month, orders, trading_days,
       ROUND(net_revenue, 2)                                              AS net_revenue,
       ROUND(gross_revenue, 2)                                            AS gross_revenue,
       ROUND(discounts, 2)                                                AS discounts,
       ROUND(net_revenue / orders, 2)                                     AS aov,
       ROUND(net_revenue / trading_days, 2)                               AS revenue_per_trading_day,
       ROUND(net_revenue / LAG(net_revenue) OVER (ORDER BY month) - 1, 4) AS mom_growth
FROM m
ORDER BY month;

-- ---------------------------------------------------------------------
-- Director 3 · macro region x month (full months only for trend lines)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dir_macro_region_month;
CREATE VIEW dir_macro_region_month AS
SELECT macro_region, month, MAX(is_partial_month) AS is_partial_month,
       COUNT(*) AS orders, ROUND(SUM(net_revenue), 2) AS net_revenue
FROM v_orders
GROUP BY macro_region, month;

-- ---------------------------------------------------------------------
-- Director 4 · region scorecard: size, efficiency (per ZIP), AOV and the
-- change between H1 (Jan-Jun) and the Jul-Nov run rate (monthly averages).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dir_region;
CREATE VIEW dir_region AS
WITH r AS (
    SELECT macro_region, region,
           COUNT(DISTINCT zipcode)                                        AS zips,
           COUNT(*)                                                       AS orders,
           SUM(net_revenue)                                               AS net_revenue,
           SUM(gross_revenue)                                             AS gross_revenue,
           SUM(discounts)                                                 AS discounts,
           SUM(CASE WHEN month BETWEEN '2023-01' AND '2023-06' THEN net_revenue END) / 6.0 AS h1_avg_month,
           SUM(CASE WHEN month BETWEEN '2023-07' AND '2023-11' THEN net_revenue END) / 5.0 AS h2_avg_month
    FROM v_orders
    GROUP BY macro_region, region
)
SELECT macro_region, region, zips, orders,
       ROUND(net_revenue, 2)                                              AS net_revenue,
       ROUND(net_revenue / SUM(net_revenue) OVER (), 4)                   AS revenue_share,
       ROUND(net_revenue / zips, 2)                                       AS revenue_per_zip,
       ROUND(net_revenue / orders, 2)                                     AS aov,
       ROUND(-discounts / gross_revenue, 4)                               AS discount_rate,
       ROUND(h1_avg_month, 2)                                             AS h1_avg_month,
       ROUND(h2_avg_month, 2)                                             AS h2_avg_month,
       ROUND(h2_avg_month / h1_avg_month - 1, 4)                          AS h2_vs_h1
FROM r
ORDER BY net_revenue DESC;

-- ---------------------------------------------------------------------
-- Director 5 · category mix (line grain is the right grain here)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dir_category;
CREATE VIEW dir_category AS
SELECT order_category, category_short, revenue_type,
       COUNT(*)                                                           AS lines,
       COUNT(DISTINCT order_id)                                           AS orders_with_category,
       ROUND(SUM(revenue), 2)                                             AS net_revenue,
       ROUND(SUM(revenue) / SUM(SUM(revenue)) OVER (), 4)                 AS share_of_net,
       ROUND(AVG(revenue), 2)                                             AS avg_line_revenue,
       SUM(is_zero)                                                       AS zero_lines,
       ROUND(SUM(CASE WHEN month BETWEEN '2023-07' AND '2023-11' THEN revenue END) / 5.0
           / (SUM(CASE WHEN month BETWEEN '2023-01' AND '2023-06' THEN revenue END) / 6.0) - 1, 4) AS h2_vs_h1
FROM fact_order_lines
GROUP BY order_category, category_short, revenue_type
ORDER BY net_revenue DESC;

-- ---------------------------------------------------------------------
-- Manager 1 · agent scorecard
--   last_full_month = 2023-11; baseline = average of Aug-Oct
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_agent;
CREATE VIEW mgr_agent AS
WITH o AS (
    SELECT sales_team, sales_agent,
           MIN(region)                                                    AS region,
           MIN(macro_region)                                              AS macro_region,
           COUNT(DISTINCT zipcode)                                        AS zips,
           COUNT(*)                                                       AS orders,
           SUM(lines)                                                     AS lines,
           SUM(net_revenue)                                               AS net_revenue,
           SUM(gross_revenue)                                             AS gross_revenue,
           SUM(discounts)                                                 AS discounts,
           SUM(CASE WHEN net_revenue <= 0 THEN 1 ELSE 0 END)              AS orders_zero_or_negative,
           SUM(CASE WHEN month = '2023-11' THEN net_revenue END)          AS nov_revenue,
           SUM(CASE WHEN month BETWEEN '2023-08' AND '2023-10' THEN net_revenue END) / 3.0 AS aug_oct_avg
    FROM v_orders
    GROUP BY sales_team, sales_agent
),
l AS (
    SELECT sales_agent,
           SUM(is_negative)                                               AS refund_lines,
           ROUND(SUM(CASE WHEN is_negative = 1 THEN revenue ELSE 0 END), 2) AS refund_value,
           SUM(is_outlier)                                                AS outlier_lines,
           SUM(is_zero)                                                   AS zero_lines
    FROM fact_order_lines
    GROUP BY sales_agent
)
SELECT o.sales_team, o.sales_agent, o.region, o.macro_region, o.zips, o.orders,
       ROUND(o.net_revenue, 2)                                            AS net_revenue,
       ROUND(o.net_revenue / SUM(o.net_revenue) OVER (), 4)               AS revenue_share,
       ROUND(o.net_revenue / o.zips, 2)                                   AS revenue_per_zip,
       ROUND(o.net_revenue / o.orders, 2)                                 AS aov,
       ROUND(1.0 * o.lines / o.orders, 2)                                 AS lines_per_order,
       ROUND(-o.discounts / o.gross_revenue, 4)                           AS discount_rate,
       ROUND(1.0 * o.orders_zero_or_negative / o.orders, 4)               AS share_orders_zero_or_negative,
       l.refund_lines, l.refund_value, l.outlier_lines, l.zero_lines,
       ROUND(o.nov_revenue, 2)                                            AS nov_revenue,
       ROUND(o.aug_oct_avg, 2)                                            AS aug_oct_avg,
       ROUND(o.nov_revenue / o.aug_oct_avg - 1, 4)                        AS nov_vs_aug_oct
FROM o JOIN l USING (sales_agent)
ORDER BY revenue_per_zip DESC;

-- ---------------------------------------------------------------------
-- Manager 2 · agent x month
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_agent_month;
CREATE VIEW mgr_agent_month AS
-- includes an 'All agents' row per month (company baseline); do not sum across sales_agent
WITH base AS (
    SELECT sales_team, sales_agent, month, is_partial_month, zipcode, net_revenue FROM v_orders
    UNION ALL
    SELECT 'All', 'All agents', month, is_partial_month, zipcode, net_revenue FROM v_orders
)
SELECT sales_team, sales_agent, month, MAX(is_partial_month) AS is_partial_month,
       COUNT(DISTINCT zipcode) AS zips, COUNT(*) AS orders,
       ROUND(SUM(net_revenue), 2) AS net_revenue,
       ROUND(SUM(net_revenue) / COUNT(*), 2) AS aov,
       ROUND(SUM(net_revenue) / COUNT(DISTINCT zipcode), 2) AS revenue_per_zip
FROM base
GROUP BY sales_team, sales_agent, month;

-- ---------------------------------------------------------------------
-- Manager 3 · agent x category (mix vs company average share)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_agent_category;
CREATE VIEW mgr_agent_category AS
-- includes 'All agents' rows (company mix); do not sum across sales_agent
WITH base AS (
    SELECT sales_agent, category_short, revenue FROM fact_order_lines
    UNION ALL
    SELECT 'All agents', category_short, revenue FROM fact_order_lines
),
ac AS (SELECT sales_agent, category_short, SUM(revenue) AS rev, COUNT(*) AS lines
       FROM base GROUP BY sales_agent, category_short),
tot AS (SELECT category_short, SUM(revenue) AS rev FROM fact_order_lines GROUP BY category_short)
SELECT ac.sales_agent, ac.category_short, ac.lines,
       ROUND(ac.rev, 2)                                                   AS net_revenue,
       ROUND(ac.rev / SUM(ac.rev) OVER (PARTITION BY ac.sales_agent), 4)  AS agent_share,
       ROUND(t.rev / (SELECT SUM(rev) FROM tot), 4)                       AS company_share
FROM ac JOIN tot t USING (category_short);

-- ---------------------------------------------------------------------
-- Manager 4 · ZIP territory scorecard
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_zip;
CREATE VIEW mgr_zip AS
SELECT sales_team, sales_agent, region, zip5, state,
       COUNT(*)                                                           AS orders,
       ROUND(SUM(net_revenue), 2)                                         AS net_revenue,
       ROUND(SUM(net_revenue) / COUNT(*), 2)                              AS aov,
       ROUND(-SUM(discounts) / SUM(gross_revenue), 4)                     AS discount_rate,
       ROUND(SUM(CASE WHEN month BETWEEN '2023-07' AND '2023-11' THEN net_revenue END) / 5.0
           / (SUM(CASE WHEN month BETWEEN '2023-01' AND '2023-06' THEN net_revenue END) / 6.0) - 1, 4) AS h2_vs_h1
FROM v_orders
GROUP BY sales_team, sales_agent, region, zip5, state
ORDER BY net_revenue DESC;

-- ---------------------------------------------------------------------
-- Manager 5 · weekly revenue per agent (operational cadence)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_agent_week;
CREATE VIEW mgr_agent_week AS
-- includes 'All agents' rows; revenue_per_zip makes agents with 1-6 ZIPs comparable
WITH base AS (
    SELECT sales_agent, week_start, zipcode, net_revenue FROM v_orders
    UNION ALL
    SELECT 'All agents', week_start, zipcode, net_revenue FROM v_orders
),
z AS (SELECT sales_agent, COUNT(DISTINCT zipcode) AS zips FROM base GROUP BY sales_agent)
SELECT b.sales_agent, b.week_start, COUNT(*) AS orders, ROUND(SUM(b.net_revenue), 2) AS net_revenue,
       ROUND(SUM(b.net_revenue) / z.zips, 2) AS revenue_per_zip
FROM base b JOIN z USING (sales_agent)
GROUP BY b.sales_agent, b.week_start, z.zips;

-- ---------------------------------------------------------------------
-- Manager 6 · team roll-up
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS mgr_team;
CREATE VIEW mgr_team AS
SELECT sales_team,
       COUNT(DISTINCT sales_agent)                                        AS agents,
       COUNT(DISTINCT zipcode)                                            AS zips,
       COUNT(*)                                                           AS orders,
       ROUND(SUM(net_revenue), 2)                                         AS net_revenue,
       ROUND(SUM(net_revenue) / COUNT(DISTINCT zipcode), 2)               AS revenue_per_zip,
       ROUND(SUM(net_revenue) / COUNT(*), 2)                              AS aov
FROM v_orders
GROUP BY sales_team
ORDER BY net_revenue DESC;
