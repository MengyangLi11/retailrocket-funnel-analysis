"""
Rebuild every number in this project from events.csv, without MySQL.

Loads events.csv into an in-memory SQLite database, runs the same logic as
the files in sql/, checks the headline numbers, and writes the Power BI
extracts to powerbi/data/.

Usage:
    pip install pandas
    python scripts/build_outputs.py /path/to/events.csv

All dates are UTC (same as the MySQL scripts, which SET time_zone = '+00:00').
"""
import json
import sqlite3
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "powerbi" / "data"


def load(csv_path: str) -> sqlite3.Connection:
    df = pd.read_csv(csv_path)
    con = sqlite3.connect(":memory:")
    df.to_sql("events", con, index=False)
    con.executescript(
        """
        CREATE INDEX ix_v ON events(visitorid);
        CREATE TABLE visitor_summary AS
        SELECT
          visitorid,
          date(MIN(timestamp)/1000, 'unixepoch')                     AS first_seen_date,
          COUNT(DISTINCT CASE WHEN event='view' THEN itemid END)     AS items_viewed,
          SUM(event='view')                                          AS view_events,
          MAX(event='view')                                          AS has_view,
          MAX(event='addtocart')                                     AS carted,
          MAX(event='transaction')                                   AS bought,
          COUNT(DISTINCT transactionid)                              AS orders,
          COUNT(DISTINCT date(timestamp/1000, 'unixepoch'))          AS active_days
        FROM events GROUP BY visitorid;
        ALTER TABLE visitor_summary ADD COLUMN depth_bucket TEXT;
        UPDATE visitor_summary SET depth_bucket = CASE
          WHEN items_viewed = 0 THEN '0 (no view)'
          WHEN items_viewed = 1 THEN '1 item'
          WHEN items_viewed <= 4 THEN '2-4 items'
          WHEN items_viewed <= 9 THEN '5-9 items'
          ELSE '10+ items' END;
        """
    )
    return con


def one(con, sql):
    return con.execute(sql).fetchone()


def main(csv_path: str) -> None:
    con = load(csv_path)
    q = lambda sql: pd.read_sql(sql, con)
    k = {}

    # ---- 01 funnel ------------------------------------------------------
    k["events"], k["visitors"] = one(con, "SELECT COUNT(*), COUNT(DISTINCT visitorid) FROM events")
    k["viewers"], k["carters"], k["buyers"] = one(con, """
        SELECT COUNT(DISTINCT CASE WHEN event='view' THEN visitorid END),
               COUNT(DISTINCT CASE WHEN event='addtocart' THEN visitorid END),
               COUNT(DISTINCT CASE WHEN event='transaction' THEN visitorid END) FROM events""")
    k["view_to_cart_pct"] = 100 * k["carters"] / k["viewers"]
    k["cart_to_buy_pct"] = 100 * k["buyers"] / k["carters"]
    k["view_to_buy_pct"] = 100 * k["buyers"] / k["viewers"]
    k["carters_without_logged_view"], k["strict_v2c_pct"] = one(con, """
        SELECT SUM(carted AND NOT has_view), 100.0*SUM(carted AND has_view)/SUM(has_view)
        FROM visitor_summary""")

    # ---- 02 weekly trend ------------------------------------------------
    weekly = q("""
        SELECT MIN(date(timestamp/1000,'unixepoch')) AS week_start,
               COUNT(DISTINCT date(timestamp/1000,'unixepoch')) AS days_in_week,
               COUNT(DISTINCT visitorid) AS active_visitors,
               COUNT(DISTINCT CASE WHEN event='view' THEN visitorid END) AS viewers,
               COUNT(DISTINCT CASE WHEN event='addtocart' THEN visitorid END) AS carters,
               COUNT(DISTINCT CASE WHEN event='transaction' THEN visitorid END) AS buyers
        FROM events
        GROUP BY strftime('%Y-%W', timestamp/1000, 'unixepoch') ORDER BY week_start""")
    full = weekly[weekly.days_in_week == 7]
    rate = 100 * full.carters / full.viewers
    k["full_weeks"] = int(len(full))
    k["weekly_v2c_min_pct"], k["weekly_v2c_max_pct"] = rate.min(), rate.max()
    k["weekly_v2c_mean_pct"], k["weekly_v2c_sd_pp"] = rate.mean(), rate.std()
    k["weekly_active_min"], k["weekly_active_max"] = int(full.active_visitors.min()), int(full.active_visitors.max())

    # ---- 03 driver: browse depth -----------------------------------------
    depth = q("""
        SELECT depth_bucket, COUNT(*) AS viewers, SUM(carted) AS carters,
               100.0*AVG(carted) AS view_to_cart_pct
        FROM visitor_summary WHERE has_view = 1
        GROUP BY depth_bucket ORDER BY MIN(items_viewed)""")
    depth["pct_of_viewers"] = 100 * depth.viewers / depth.viewers.sum()
    depth["pct_of_carters"] = 100 * depth.carters / depth.carters.sum()
    k["depth_table"] = depth.round(2).to_dict("records")
    s = depth.set_index("depth_bucket")
    k["single_item_share_pct"] = s.loc["1 item", "pct_of_viewers"]
    k["single_item_v2c_pct"] = s.loc["1 item", "view_to_cart_pct"]
    multi = depth[depth.depth_bucket != "1 item"]
    k["multi_item_v2c_pct"] = 100 * multi.carters.sum() / multi.viewers.sum()
    k["pct_single_one_pageview"], k["pct_single_one_day"] = one(con, """
        SELECT 100.0*AVG(view_events=1), 100.0*AVG(active_days=1)
        FROM visitor_summary WHERE has_view=1 AND items_viewed=1""")
    k["pct_non_carters_single_item"] = one(con, """
        SELECT 100.0*SUM(items_viewed=1 AND carted=0)/SUM(carted=0)
        FROM visitor_summary WHERE has_view=1""")[0]
    k["avg_items_per_viewer"] = one(con, "SELECT AVG(items_viewed) FROM visitor_summary WHERE has_view=1")[0]
    k["buyer_avg_items"], k["nonbuyer_avg_items"] = one(con, """
        SELECT AVG(CASE WHEN bought=1 THEN items_viewed END),
               AVG(CASE WHEN bought=0 THEN items_viewed END)
        FROM visitor_summary WHERE has_view=1""")

    # ---- 04 retention ----------------------------------------------------
    k["pct_one_time_visitors"] = one(con, "SELECT 100.0*AVG(active_days=1) FROM visitor_summary")[0]
    k["pct_repeat_buyers"] = one(con, "SELECT 100.0*AVG(orders>1) FROM visitor_summary WHERE bought=1")[0]

    # ---- 05 experiment inputs -------------------------------------------
    new_wk = q("""
        SELECT strftime('%Y-%W', first_seen_date) AS wk,
               COUNT(DISTINCT first_seen_date) AS days, SUM(has_view) AS new_viewers
        FROM visitor_summary GROUP BY wk""")
    k["new_viewers_per_week"] = float(new_wk[new_wk.days == 7].new_viewers.mean())

    n1 = int(s.loc["1 item", "viewers"])
    r1 = s.loc["1 item", "view_to_cart_pct"] / 100
    r24 = s.loc["2-4 items", "view_to_cart_pct"] / 100
    scen = pd.DataFrame(
        [("Low reach", 0.10, 1.0), ("Conservative", 0.17, 0.5),
         ("Central", 0.17, 1.0), ("High reach", 0.25, 1.0)],
        columns=["scenario", "reach", "causal_share"])
    scen["extra_carters"] = n1 * scen.reach * scen.causal_share * (r24 - r1)
    scen["relative_lift_pct"] = 100 * scen.extra_carters / k["carters"]
    scen["baseline_pct"] = k["view_to_cart_pct"]
    scen["projected_pct"] = 100 * (k["carters"] + scen.extra_carters) / k["viewers"]
    k["scenarios"] = scen.round(4).to_dict("records")
    k["model_inputs"] = {"single_item_viewers": n1, "rate_1": r1, "rate_2to4": r24}

    # ---- Power BI extracts ----------------------------------------------
    OUT.mkdir(parents=True, exist_ok=True)
    q("""
        SELECT first_seen_date,
               MIN(items_viewed, 10) AS items_viewed_capped,
               depth_bucket,
               CASE WHEN active_days > 1 THEN 1 ELSE 0 END AS is_returning,
               COUNT(*) AS visitors, SUM(has_view) AS viewers, SUM(carted) AS carters,
               SUM(carted AND has_view) AS carters_with_view, SUM(bought) AS buyers,
               SUM(orders > 1) AS repeat_buyers, SUM(items_viewed) AS items_viewed_total
        FROM visitor_summary
        GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 4""").to_csv(OUT / "fact_visitor_cohort.csv", index=False)
    weekly.to_csv(OUT / "weekly_funnel.csv", index=False)
    q("""SELECT date(timestamp/1000,'unixepoch') AS event_date, event, COUNT(*) AS events
         FROM events GROUP BY 1, 2 ORDER BY 1, 2""").to_csv(OUT / "daily_events.csv", index=False)
    scen.round(4).to_csv(OUT / "ab_scenarios.csv", index=False)

    # ---- sanity checks against the numbers quoted in the README ----------
    assert k["events"] == 2_756_101
    assert (k["viewers"], k["carters"], k["buyers"]) == (1_404_179, 37_722, 11_719)
    assert round(k["view_to_cart_pct"], 1) == 2.7
    assert round(k["single_item_share_pct"]) == 80
    assert 18.5 <= scen.loc[scen.scenario == "Central", "relative_lift_pct"].item() <= 19.5

    (ROOT / "experiment" / "key_numbers.json").write_text(
        json.dumps(k, indent=2, default=lambda o: round(float(o), 4)))
    print(json.dumps({x: k[x] for x in k if x not in ("depth_table", "scenarios")},
                     indent=2, default=lambda o: round(float(o), 3)))
    print(depth.round(2).to_string(index=False))
    print(scen.round(2).to_string(index=False))
    print("\nAll checks passed. Extracts written to", OUT)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "events.csv")
