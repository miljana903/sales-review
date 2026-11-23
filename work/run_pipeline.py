"""Reproducible pipeline: raw workbook -> SQLite raw tables -> clean (01) -> marts (02)
-> validation (03 + independent pandas checks) -> clean CSVs + dashboard JSON + profile.

Usage:  python3 -I work/run_pipeline.py <project_dir>
Raw workbook is only read, never written.
"""
import json, sqlite3, sys
from pathlib import Path
import pandas as pd

ROOT = Path(sys.argv[1])
RAW = ROOT / "raw" / "sales_data_2023.xlsx"
DB = ROOT / "work" / "sales.sqlite"
if DB.exists():
    DB.unlink()
con = sqlite3.connect(DB)

# ---- load raw sheets 1:1 (dtype=object keeps ints as ints, blanks as NULL) ----
sheets = {"Orders": "raw_orders", "Regions": "raw_regions", "Sales_agents": "raw_sales_agents"}
raw = {}
for sheet, table in sheets.items():
    df = pd.read_excel(RAW, sheet_name=sheet, dtype=object)
    df = df.astype(object).where(df.notna(), None)
    if sheet == "Orders":
        df["REPORTING_DATE"] = pd.to_datetime(df["REPORTING_DATE"]).dt.strftime("%Y-%m-%d %H:%M:%S")
    raw[sheet] = df
    df.to_sql(table, con, index=False)

for f in ["01_clean.sql", "02_marts.sql"]:
    con.executescript((ROOT / "work" / f).read_text())

q = lambda sql: pd.read_sql_query(sql, con)

# ---- profile (every value computed) ----
def profile(df, name, expected):
    rows = []
    for c in df.columns:
        s = df[c]
        nb = s.dropna()
        types = nb.map(lambda x: type(x).__name__).value_counts().to_dict()
        num = pd.to_numeric(nb, errors="coerce") if all(t in ("int", "float") for t in types) else None
        mn = mx = ""
        if num is not None and len(num):
            mn, mx = num.min(), num.max()
        elif len(nb) and all(t in ("datetime", "Timestamp", "str") for t in types) and "DATE" in c:
            mn, mx = nb.min(), nb.max()
        top = ", ".join(f"{repr(k)} ({v})" for k, v in nb.value_counts().head(5).items())
        sp = sum(1 for v in nb if isinstance(v, str) and v != v.strip())
        rows.append(dict(Table=name, Column=c, Expected=expected.get(c, ""), Actual="/".join(types),
                         Example=repr(nb.iloc[0]) if len(nb) else "", Rows=len(s), Blanks=int(s.isna().sum()),
                         NonBlanks=len(nb), Distinct=nb.nunique(), Min=mn, Max=mx, Top5=top, SpacePadded=sp))
    return rows

prof = []
prof += profile(raw["Orders"], "Orders", dict(ORDER_ID="text", ORDER_CATEGORY="text", REPORTING_DATE="date", REVENUE="decimal", ZIPCODE="5-digit text"))
prof += profile(raw["Regions"], "Regions", dict(ZIPCODE="5-digit text", REGION="text", STATE="text", AGENT_ID="integer"))
prof += profile(raw["Sales_agents"], "Sales_agents", dict(AGENT_ID="integer", SALES_TEAM="text", SALES_AGENT="text", REGION="text"))
pd.DataFrame(prof).to_csv(ROOT / "work" / "profile_raw.csv", index=False)

# ---- validation: SQL checks + independent pandas second numbers ----
val = q((ROOT / "work" / "03_validate.sql").read_text())
o = raw["Orders"].copy()
o["REVENUE"] = o["REVENUE"].astype(float)
o["REPORTING_DATE"] = pd.to_datetime(o["REPORTING_DATE"])
reg = raw["Regions"].copy()
ag = raw["Sales_agents"].copy()
ag["AGENT_ID"] = ag["AGENT_ID"].astype(int)
reg["AGENT_ID"] = pd.to_numeric(reg["AGENT_ID"])
m = o.merge(reg[["ZIPCODE", "AGENT_ID", "REGION"]], on="ZIPCODE", how="left", validate="many_to_one") \
     .merge(ag[["AGENT_ID", "SALES_AGENT"]], on="AGENT_ID", how="left", validate="many_to_one")
two = []
k = q("select * from dir_kpis").iloc[0]
two.append(("Two methods: net revenue (SQL dir_kpis vs pandas sum of raw)", round(o.REVENUE.sum(), 2), k.net_revenue))
two.append(("Two methods: orders (SQL vs pandas nunique)", o.ORDER_ID.nunique(), k.orders))
gross = o.loc[o.ORDER_CATEGORY != "Fee Discounts & Client Returns", "REVENUE"].sum()
two.append(("Two methods: gross revenue (SQL vs pandas filter)", round(gross, 2), k.gross_revenue))
ma = q("select sales_agent, net_revenue, orders from mgr_agent")
pa = m.assign(SALES_AGENT=m.SALES_AGENT.fillna("Unassigned (PR)")).groupby("SALES_AGENT").agg(rev=("REVENUE", "sum"), orders=("ORDER_ID", "nunique"))
diff = sum(abs(round(pa.loc[r.sales_agent, "rev"], 2) - r.net_revenue) > 0.005 or pa.loc[r.sales_agent, "orders"] != r.orders for r in ma.itertuples())
two.append(("Two methods: per-agent revenue & orders, SQL groupby vs pandas merge+groupby (agents differing)", 0, diff))
dm = q("select month, net_revenue from dir_monthly")
pm = o.groupby(o.REPORTING_DATE.dt.strftime("%Y-%m")).REVENUE.sum().round(2)
two.append(("Two methods: monthly revenue SQL vs pandas (months differing)", 0, int(sum(abs(pm[r.month] - r.net_revenue) > 0.005 for r in dm.itertuples()))))
nov = o[(o.REPORTING_DATE >= "2023-11-01") & (o.REPORTING_DATE < "2023-12-01")]
two.append(("Date range: Nov revenue by >= 2023-11-01 and < 2023-12-01 vs SQL month='2023-11'", round(nov.REVENUE.sum(), 2),
            float(dm.set_index("month").loc["2023-11", "net_revenue"])))
val = pd.concat([val, pd.DataFrame(two, columns=["chk", "expected", "got"])], ignore_index=True)
val["pass"] = [abs(float(e) - float(g)) < 0.006 for e, g in zip(val.expected, val.got)]
val.to_csv(ROOT / "work" / "validation_results.csv", index=False)

# spot checks (hand-verifiable rows)
spots = q("""select order_id, order_category, reporting_date, revenue, zip5, region, macro_region, sales_agent, sales_team,
             is_negative, is_zero, is_outlier, is_partial_month from fact_order_lines
             where (order_id='197716-2603' and order_category='Grooming Revenue')
                or (order_id in (select order_id from fact_order_lines where zipcode=965 limit 1) and zipcode=965)
                or revenue=(select max(revenue) from fact_order_lines)
                or revenue=(select min(revenue) from fact_order_lines)
             limit 8""")
spots.to_csv(ROOT / "work" / "spot_checks.csv", index=False)

# ---- clean outputs ----
for t in ["clean_orders", "clean_regions", "clean_sales_agents", "fact_order_lines"]:
    q(f"select * from {t}").to_csv(ROOT / "clean" / f"{t}.csv", index=False)

# ---- dashboard data ----
views = ["dir_kpis", "dir_monthly", "dir_macro_region_month", "dir_region", "dir_category",
         "mgr_agent", "mgr_agent_month", "mgr_agent_category", "mgr_zip", "mgr_agent_week", "mgr_team"]
data = {v: q(f"select * from {v}").to_dict(orient="records") for v in views}
(ROOT / "work" / "dashboard_data.json").write_text(json.dumps(data, default=float))
with pd.ExcelWriter(ROOT / "clean" / "marts.xlsx") as xw:
    for v in views:
        q(f"select * from {v}").to_excel(xw, sheet_name=v[:31], index=False)

print(val.to_string())
print("ALL PASS" if val["pass"].all() else "FAILURES")
print(spots.to_string())
