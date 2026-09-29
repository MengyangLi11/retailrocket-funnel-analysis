-- ============================================================
-- 04  RETENTION: do visitors and buyers come back?
-- Context for the recommendation: if most visitors never return,
-- the first visit is the only chance to get them browsing.
-- ============================================================
USE retailrocket;

-- 4.1  Returning vs one-time visitors (distinct active days, UTC)
SELECT
  CASE WHEN active_days = 1 THEN 'one-time (1 day)' ELSE 'returning (2+ days)' END AS visitor_type,
  COUNT(*)                                          AS visitors,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct
FROM visitor_summary
GROUP BY visitor_type;
-- one-time 1,263,811 (89.8%) | returning 143,769 (10.2%)


-- 4.2  Repeat purchase among buyers --------------------------
SELECT
  CASE WHEN orders = 1 THEN 'one-time buyer' ELSE 'repeat buyer' END AS buyer_type,
  COUNT(*)                                          AS buyers,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct
FROM visitor_summary
WHERE bought = 1
GROUP BY buyer_type;
-- one-time 10,656 (90.9%) | repeat 1,063 (9.1%)
-- => ~90% of visitors get one visit. Discovery has to happen in session one.
