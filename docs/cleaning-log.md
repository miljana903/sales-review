# Cleaning log

Raw workbook is never modified. `work/run_pipeline.py` loads each sheet 1:1 into SQLite tables `raw_orders`, `raw_regions`, `raw_sales_agents`, then `work/01_clean.sql` builds the clean tables. Step numbers match the `[C#]` comments in the SQL. Import: dates are read as Excel date cells (no text parsing, so no locale ambiguity); revenue is numeric in all 13,496 cells.

| # | Problem | Rows (ids/count) | Fix (what changed, where) | Reason (effect on numbers) | Rows before → after |
|---|---|---|---|---|---|
| C1 | Sales_agents.AGENT_ID stored as text, Regions.AGENT_ID as number | 7 agent rows | `clean_sales_agents.agent_id` = CAST(TRIM(AGENT_ID) AS INTEGER) | Without it the ZIP→agent join matches 0 of 19 ZIPs and all $1,457,538 lands in "no agent" | 7 → 7 |
| C2 | SALES_TEAM case variants | agents 2 (Peter, "team 1") and 4 (Sally, "team 2") | `sales_team` = 'Team ' + number | Teams count 5 instead of 7; Team 1 = $281,394 (not $153,600 + $127,794), Team 2 = $524,393 (not $444,702 + $79,691) | 7 → 7 |
| C3 | Trailing spaces in Sales_agents.REGION | agents 1, 2, 3, 6 | TRIM into `agent_region` | Agent region = ZIP region for all 19 assigned ZIPs (14 ZIPs mismatched before) | 7 → 7 |
| C4 | ZIP codes stored as numbers lose leading zeros | ZIP 965 (647 lines), 2554 (687 lines) | Added `zip5` text column ('00965', '02554'); integer `zipcode` kept as join key | 1,334 lines would show invalid 3–4 digit ZIPs | 20 → 20 |
| C5 | ZIP 965 (PR) has blank REGION and AGENT_ID | 1 region row; 647 order lines, 299 orders, $76,608.13 | `region`/`macro_region` = 'Unassigned (PR)', `agent_id` stays NULL; fact shows agent/team 'Unassigned (PR)' | Keeps 5.3% of revenue visible instead of losing it in an inner join or inventing an owner | 20 → 20 |
| C6 | Region names nest a parent region in brackets | 5 region rows ("Mid-South (South)" etc.) | Derived `macro_region` (South, Midwest, Northeast, West) | Gives the director a 4-region roll-up: South $577,210, Midwest $524,393, Northeast $146,765, West $132,562 | 20 → 20 |
| C7 | Contra-revenue category mixed with revenue | 444 lines "Fee Discounts & Client Returns" (−$15,295.20) | `revenue_type` = 'Discount/Return' vs 'Revenue' | Net $1,457,538.49 vs gross $1,472,833.69; discount rate 1.04% | 13,496 → 13,496 |
| C8 | Negative lines in revenue categories (refunds/reversals) | 121 lines, −$12,936.73 | `is_negative` flag; values unchanged | Kept: dropping them would overstate net revenue by $12,936.73 (0.9%) | 13,496 → 13,496 |
| C9 | Zero-revenue lines | 2,367 lines (17.5%); e.g. 745 Professional Services, 464 Laboratory | `is_zero` flag; recorded 0 kept (not a blank) | Lines/order and category line counts include them; revenue unaffected | 13,496 → 13,496 |
| C10 | Extreme line values | 246 lines with \|z\| > 3 within their category, $114,556.82 | `is_outlier` flag; nothing removed | Removing them would cut net revenue 7.9%; they look like real high-value services (e.g. Boarding $2,184) | 13,496 → 13,496 |
| C11 | December is partial (data ends 2023-12-06) | 217 lines, 95 orders, $22,508.29 | `is_partial_month` flag; derived `month`, `week_start` (Monday), `weekday_num`, `category_short` | December would read as −83% vs November; it is excluded from monthly comparisons | 13,496 → 13,496 |
| C12 | Joins to reference tables | all lines | LEFT JOIN regions then agents into `fact_order_lines` after proving both unique per key | Row count 13,496 before and after; 0 'Not found'; 647 'Unassigned (PR)' | 13,496 → 13,496 |
| — | Duplicates | 0 full-row duplicates, 0 repeated (order_id, category) | Nothing removed | Totals unchanged | 13,496 → 13,496 |

Totals after cleaning: 13,496 lines, 5,991 orders, net revenue $1,457,538.49 — identical to raw (see `validation.md`).
