# Validation

Run by `work/run_pipeline.py`: SQL checks in `work/03_validate.sql`, independent pandas recomputations in the script. Format: Check · Expected · Got · Pass. Results file: `work/validation_results.csv`.

| # | Check | Expected | Got | Pass |
|---|---|---|---|---|
| 1 | Row reconciliation: raw order lines - removed (0) = clean lines | 13,496 | 13,496 | ✅ |
| 2 | Row count unchanged by joins (clean_orders = fact_order_lines) | 13,496 | 13,496 | ✅ |
| 3 | Distinct orders raw = clean | 5,991 | 5,991 | ✅ |
| 4 | Total reconciliation: raw revenue x100 = clean revenue x100 (cents) | 145,753,849 | 145,753,849 | ✅ |
| 5 | Grain: clean lines = distinct (order_id, category) | 13,496 | 13,496 | ✅ |
| 6 | Grain: one date and one ZIP per order (orders with >1) | 0 | 0 | ✅ |
| 7 | Reference unique: regions rows = distinct zipcode | 20 | 20 | ✅ |
| 8 | Reference unique: agents rows = distinct agent_id | 7 | 7 | ✅ |
| 9 | Joins: order lines with ZIP not in Regions (Not found) | 0 | 0 | ✅ |
| 10 | Joins: Regions.agent_id not in Sales_agents (excluding logged NULL) | 0 | 0 | ✅ |
| 11 | Joins: lines labelled Unassigned (PR) = raw lines for ZIP 965 (logged C5) | 647 | 647 | ✅ |
| 12 | Consistency: agent region = ZIP region for every assigned ZIP (mismatches) | 0 | 0 | ✅ |
| 13 | Nulls: blank revenue / date / category / ZIP in clean_orders | 0 | 0 | ✅ |
| 14 | Nulls: NULL agent_id in fact = lines of ZIP 965 only | 647 | 647 | ✅ |
| 15 | Types: numeric revenue count = non-blank count | 13,496 | 13,496 | ✅ |
| 16 | Types: valid ISO dates (date() round-trips) | 13,496 | 13,496 | ✅ |
| 17 | Domains: sales_team values not of form Team N | 0 | 0 | ✅ |
| 18 | Domains: distinct sales teams after case fix | 5 | 5 | ✅ |
| 19 | Domains: values with leading/trailing spaces (agents+regions) | 0 | 0 | ✅ |
| 20 | Domains: dates outside 2023-01-01..2023-12-31 | 0 | 0 | ✅ |
| 21 | Flags: is_negative = negative lines outside discount category | 121 | 121 | ✅ |
| 22 | Flags: is_zero = raw zero lines | 2,367 | 2,367 | ✅ |
| 23 | Flags: is_partial_month = raw lines dated December 2023 | 217 | 217 | ✅ |
| 24 | Group totals: sum of agent revenue x100 = grand total x100 | 145,753,849 | 145,753,849 | ✅ |
| 25 | Group totals: sum of region revenue x100 = grand total x100 | 145,753,849 | 145,753,849 | ✅ |
| 26 | Group totals: sum of monthly revenue x100 = grand total x100 | 145,753,849 | 145,753,849 | ✅ |
| 27 | Group totals: sum of category revenue x100 = grand total x100 | 145,753,849 | 145,753,849 | ✅ |
| 28 | Group totals: sum of agent orders = total orders | 5,991 | 5,991 | ✅ |
| 29 | Two methods: net revenue (SQL dir_kpis vs pandas sum of raw) | 1,457,538.49 | 1,457,538.49 | ✅ |
| 30 | Two methods: orders (SQL vs pandas nunique) | 5,991 | 5,991 | ✅ |
| 31 | Two methods: gross revenue (SQL vs pandas filter) | 1,472,833.69 | 1,472,833.69 | ✅ |
| 32 | Two methods: per-agent revenue & orders, SQL groupby vs pandas merge+groupby (agents differing) | 0 | 0 | ✅ |
| 33 | Two methods: monthly revenue SQL vs pandas (months differing) | 0 | 0 | ✅ |
| 34 | Date range: Nov revenue by >= 2023-11-01 and < 2023-12-01 vs SQL month='2023-11' | 132,139.44 | 132,139.44 | ✅ |

**34 of 34 checks pass.** Revenue checks compare cents (×100) to avoid float noise; 145,753,849 cents = $1,457,538.49.

## Spot checks (rows read by hand against the raw workbook)

| order_id    | order_category                | reporting_date   |   revenue |   zip5 | region            | macro_region    | sales_agent     | sales_team      |   is_negative |   is_zero |   is_outlier |   is_partial_month |
|:------------|:------------------------------|:-----------------|----------:|-------:|:------------------|:----------------|:----------------|:----------------|--------------:|----------:|-------------:|-------------------:|
| 197716-2603 | Grooming Revenue              | 2023-12-06       |      74   |  50667 | Midwest           | Midwest         | Jan             | Team 2          |             0 |         0 |            0 |                  1 |
| 197479-2603 | Professional Services Revenue | 2023-11-20       |       0   |  00965 | Unassigned (PR)   | Unassigned (PR) | Unassigned (PR) | Unassigned (PR) |             0 |         1 |            0 |                  0 |
| 197479-2603 | Anesthesia Revenue            | 2023-11-20       |     292   |  00965 | Unassigned (PR)   | Unassigned (PR) | Unassigned (PR) | Unassigned (PR) |             0 |         0 |            0 |                  0 |
| 197479-2603 | Pharmacy Revenue              | 2023-11-20       |     101.8 |  00965 | Unassigned (PR)   | Unassigned (PR) | Unassigned (PR) | Unassigned (PR) |             0 |         0 |            0 |                  0 |
| 197479-2603 | Imaging Revenue               | 2023-11-20       |      57   |  00965 | Unassigned (PR)   | Unassigned (PR) | Unassigned (PR) | Unassigned (PR) |             0 |         0 |            0 |                  0 |
| 196077-2603 | Boarding Revenue              | 2023-09-04       |    2184   |  77964 | South             | South           | Sarah           | Team 4          |             0 |         0 |            1 |                  0 |
| 197479-2603 | Surgery Revenue               | 2023-11-20       |      50   |  00965 | Unassigned (PR)   | Unassigned (PR) | Unassigned (PR) | Unassigned (PR) |             0 |         0 |            0 |                  0 |
| 195166-2603 | Surgery Revenue               | 2023-07-12       |    -894   |  41015 | Mid-South (South) | South           | Peter           | Team 1          |             1 |         0 |            1 |                  0 |

- `197716-2603` Grooming, 2023-12-06, 74.00, ZIP 50667 → Midwest / Jan / Team 2; December flagged partial. Matches raw row 2 of Orders and Regions row for 50667 (agent 3 = Jan).
- `197479-2603` (ZIP 965): four lines kept, region and agent shown as "Unassigned (PR)", no value changed; the 0.00 line is flagged zero, not dropped.
- Max line 2,184.00 (Boarding, ZIP 77964, Sarah) flagged outlier (|z| > 3 within Boarding) and kept.
- Edge of date range: November revenue computed with `>= 2023-11-01 and < 2023-12-01` equals the SQL month bucket (check 34).

## Results validation (stage 6)
- Group totals: agents, regions, months and categories each sum to the grand total to the cent (checks 24–27); agent orders sum to 5,991 (check 28).
- Headline numbers computed two ways: net revenue, gross revenue, orders, per-agent revenue/orders and monthly revenue (checks 29–33).
- Sanity: all rates between 0 and 100% (discount rate 0.69%–1.33% by region); AOV $212.99–$265.64.
