# Sales review 2023: dashboards for a sales director and a sales manager

This project analyses 2023 veterinary clinic sales data (13,496 order lines, 5,991 orders, 20 ZIP territories, 7 sales agents) and feeds a dashboard with two views:

- **Sales director:** headline KPIs, monthly trend, regions, category mix and decisions.
- **Sales manager:** agent scorecard, revenue per ZIP, agent trends (monthly and weekly), category mix against the company, and ZIP territories.

**Headline:** net revenue was $1,457,538 (AOV $243.29), and it is flat (Jul–Nov is +2.5% on Jan–Jun). Peter and Gordon trail on revenue per ZIP because their orders are smaller, the Northeast is down 8%, and 5.3% of revenue (the Puerto Rico ZIP) has no agent. Full write-up: [`report.md`](report.md).

## Repository layout

| Path | What it holds |
|---|---|
| `raw/` | Source workbook (read only, never modified) |
| `work/01_clean.sql` | Cleaning layer: typed, trimmed and flagged tables plus the `fact_order_lines` join |
| `work/02_marts.sql` | Reporting views behind the dashboard (`dir_*` for the director, `mgr_*` for the manager) |
| `work/03_validate.sql` | Data validation checks |
| `work/run_pipeline.py` | Runs everything end to end: loads raw into SQLite, cleans, builds marts, validates and exports |
| `clean/` | Cleaned tables and view extracts (CSV, `marts.xlsx`) |
| `docs/` | `profile.md` (column profile), `cleaning-log.md`, `validation.md` (34/34 checks pass) |
| `charts/` | Report charts |
| `dashboard/index.html` | Dashboard page source (rendered with d3 inside a Claude dashboard) |
| `Sales_review_2023_data.xlsx` | One workbook with raw sheets, profile, cleaned data, cleaning log and validation |

## Reproduce

```bash
pip install pandas openpyxl
python3 work/run_pipeline.py .
```

This needs Python 3.10+ and uses SQLite (built in). The run rebuilds `work/sales.sqlite`, the CSVs in `clean/` and the validation results, and prints `ALL PASS` when every check holds.

## Metric definitions

- **Net revenue** is the sum of all lines, including "Fee Discounts & Client Returns". **Gross revenue** leaves that category out.
- **Orders** counts distinct `ORDER_ID`. **AOV** is net revenue ÷ orders.
- **Revenue per ZIP** is net revenue ÷ ZIP territories. Every ZIP has about 300 orders, so this is the fair way to compare agents.
- December 2023 is partial (data ends 6 Dec), so it is excluded from monthly comparisons.
