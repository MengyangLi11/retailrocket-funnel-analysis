-- ============================================================
-- 03  WHAT DRIVES THE LOW VIEW-TO-CART RATE?
-- Hypothesis: the 2.7% is dragged down by the ~80% of visitors who
-- look at a single product and leave ("single-item bounce").
-- Uses visitor_summary from 00_setup.sql. Viewers only (has_view = 1).
-- ============================================================
USE retailrocket;


-- 3.1  How many viewers see only one item? --------------------
SELECT
  depth_bucket,
  COUNT(*)                                          AS viewers,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_viewers
FROM visitor_summary
WHERE has_view = 1
GROUP BY depth_bucket
ORDER BY MIN(items_viewed);
-- 1 item 1,118,109 (79.6%) | 2-4 247,092 (17.6%) | 5-9 29,769 (2.1%) | 10+ 9,209 (0.7%)


-- 3.2  Are they really bouncing? -----------------------------
SELECT
  COUNT(*)                                             AS single_item_viewers,
  ROUND(100 * AVG(view_events = 1), 1)                 AS pct_one_single_pageview,
  ROUND(100 * AVG(active_days = 1), 1)                 AS pct_active_one_day_only
FROM visitor_summary
WHERE has_view = 1 AND items_viewed = 1;
-- 90.1% had exactly one product view event, 97.4% were seen on a single day:
-- the typical single-item visitor lands on one product page and leaves.


-- 3.3  THE KEY TABLE: add-to-cart rate by browsing depth ------
SELECT
  depth_bucket,
  COUNT(*)                                             AS viewers,
  SUM(carted)                                          AS carters,
  ROUND(100 * AVG(carted), 2)                          AS view_to_cart_pct,
  ROUND(100 * SUM(carted) / SUM(SUM(carted)) OVER (), 1) AS pct_of_all_carters
FROM visitor_summary
WHERE has_view = 1
GROUP BY depth_bucket
ORDER BY MIN(items_viewed);
-- 1 item     1.32%   (43.0% of carters)
-- 2-4 items  5.04%
-- 5-9 items 14.55%
-- 10+ items 30.69%
-- Conversion rises steeply with every extra item viewed.


-- 3.4  Same curve, one row per item count (feeds the dashboard)
SELECT
  LEAST(items_viewed, 10)           AS items_viewed_capped,   -- 10 = "10+"
  COUNT(*)                          AS viewers,
  ROUND(100 * AVG(carted), 2)       AS view_to_cart_pct
FROM visitor_summary
WHERE has_view = 1
GROUP BY items_viewed_capped
ORDER BY items_viewed_capped;
-- 1: 1.32% | 2: 3.92% | 3: 6.75% | 4: 9.22% | 5: 11.72% ... 10+: 30.69%


-- 3.5  Decomposition: how much of the gap is the single-item group?
-- Blended rate = (share single x rate single) + (share multi x rate multi)
WITH seg AS (
  SELECT
    CASE WHEN items_viewed = 1 THEN 'single' ELSE 'multi' END AS seg,
    COUNT(*)      AS viewers,
    SUM(carted)   AS carters
  FROM visitor_summary
  WHERE has_view = 1
  GROUP BY seg
)
SELECT
  ROUND(100 * MAX(CASE WHEN seg = 'single' THEN viewers END) / SUM(viewers), 1) AS single_share_pct,
  ROUND(100 * MAX(CASE WHEN seg = 'single' THEN carters / viewers END), 2)      AS single_v2c_pct,
  ROUND(100 * MAX(CASE WHEN seg = 'multi'  THEN carters / viewers END), 2)      AS multi_v2c_pct,
  ROUND(100 * SUM(carters) / SUM(viewers), 2)                                   AS blended_v2c_pct
FROM seg;
-- single share 79.6% | single 1.32% | multi (2+ items) 6.85% | blended 2.45%
-- Visitors who view 2+ items add to cart at 6.85%, ~5x the single-item rate.
-- Because 4 out of 5 viewers are single-item, the blend collapses to ~2.5%.
-- => The low view-to-cart rate is a MIX problem, driven by single-item bounce.


-- 3.6  Where do the lost visitors sit? -----------------------
SELECT
  ROUND(100 * SUM(items_viewed = 1 AND carted = 0) / SUM(carted = 0), 1)
    AS pct_of_non_carters_who_viewed_one_item
FROM visitor_summary
WHERE has_view = 1;
-- 80.5% of all viewers who never add to cart saw exactly one product.


-- 3.7  Buyers vs non-buyers: browsing depth ------------------
SELECT
  CASE WHEN bought = 1 THEN 'buyer' ELSE 'non-buyer' END AS visitor_type,
  COUNT(*)                         AS viewers,
  ROUND(AVG(items_viewed), 2)      AS avg_items_viewed
FROM visitor_summary
WHERE has_view = 1
GROUP BY visitor_type;
-- buyers 9.61 items vs non-buyers 1.45 items (~6.6x)
