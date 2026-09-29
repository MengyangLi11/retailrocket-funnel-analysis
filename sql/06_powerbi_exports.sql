-- ============================================================
-- 06  EXPORTS FOR THE POWER BI DASHBOARD
-- Each query below produces one CSV in powerbi/data/.
-- In MySQL Workbench: run the query, then Export result -> CSV.
-- (Or run scripts/build_outputs.py, which builds the same files
--  straight from events.csv with Python.)
-- ============================================================
USE retailrocket;
SET time_zone = '+00:00';


-- 6.1  fact_visitor_cohort.csv  (main fact table, additive)
-- One row per first-seen date x browse depth x returning flag.
-- Each visitor is counted exactly once, so SUMs are always correct
-- under any slicer.
SELECT
  first_seen_date,
  LEAST(items_viewed, 10)                         AS items_viewed_capped,
  depth_bucket,
  CASE WHEN active_days > 1 THEN 1 ELSE 0 END     AS is_returning,
  COUNT(*)                                        AS visitors,
  SUM(has_view)                                   AS viewers,
  SUM(carted)                                     AS carters,
  SUM(carted AND has_view)                        AS carters_with_view,
  SUM(bought)                                     AS buyers,
  SUM(orders > 1)                                 AS repeat_buyers,
  SUM(items_viewed)                               AS items_viewed_total
FROM visitor_summary
GROUP BY first_seen_date, items_viewed_capped, depth_bucket, is_returning
ORDER BY first_seen_date, items_viewed_capped, is_returning;


-- 6.2  weekly_funnel.csv  (activity-based weekly trend)
SELECT
  MIN(DATE(FROM_UNIXTIME(timestamp / 1000)))                         AS week_start,
  COUNT(DISTINCT DATE(FROM_UNIXTIME(timestamp / 1000)))              AS days_in_week,
  COUNT(DISTINCT visitorid)                                          AS active_visitors,
  COUNT(DISTINCT CASE WHEN event = 'view'        THEN visitorid END) AS viewers,
  COUNT(DISTINCT CASE WHEN event = 'addtocart'   THEN visitorid END) AS carters,
  COUNT(DISTINCT CASE WHEN event = 'transaction' THEN visitorid END) AS buyers
FROM events
GROUP BY YEARWEEK(FROM_UNIXTIME(timestamp / 1000), 3)
ORDER BY week_start;


-- 6.3  daily_events.csv  (event volume by day and type)
SELECT
  DATE(FROM_UNIXTIME(timestamp / 1000)) AS event_date,
  event,
  COUNT(*)                              AS events
FROM events
GROUP BY event_date, event
ORDER BY event_date, event;

-- 6.4  ab_scenarios.csv is produced by 05_experiment_baseline_and_projection.sql (5.3)
