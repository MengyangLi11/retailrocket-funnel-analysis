-- ============================================================
-- 01  DATA PROFILE + THE PURCHASE FUNNEL
-- Question: where is the biggest leak on the path to purchase?
-- ============================================================
USE retailrocket;
SET time_zone = '+00:00';


-- 1.1  Scale of the data -------------------------------------
SELECT
  COUNT(*)                                 AS total_events,
  COUNT(DISTINCT visitorid)                AS unique_visitors,
  COUNT(DISTINCT itemid)                   AS unique_items,
  FROM_UNIXTIME(MIN(timestamp) / 1000)     AS first_event_utc,
  FROM_UNIXTIME(MAX(timestamp) / 1000)     AS last_event_utc
FROM events;
-- 2,756,101 events | 1,407,580 visitors | 235,061 items
-- 2015-05-03 03:00 -> 2015-09-18 02:59 UTC (~4.5 months)


-- 1.2  Events by type ----------------------------------------
SELECT event, COUNT(*) AS events,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_events
FROM events
GROUP BY event
ORDER BY events DESC;
-- view 2,664,312 (96.7%) | addtocart 69,332 (2.5%) | transaction 22,457 (0.8%)


-- 1.3  The funnel at the UNIQUE-VISITOR level ----------------
-- Raw event counts overstate reality (one visitor views many items),
-- so each stage counts visitors who reached it at least once.
WITH stages AS (
  SELECT
    COUNT(DISTINCT CASE WHEN event = 'view'        THEN visitorid END) AS viewers,
    COUNT(DISTINCT CASE WHEN event = 'addtocart'   THEN visitorid END) AS carters,
    COUNT(DISTINCT CASE WHEN event = 'transaction' THEN visitorid END) AS buyers
  FROM events
)
SELECT
  viewers, carters, buyers,
  ROUND(100 * carters / viewers, 2) AS view_to_cart_pct,   -- 2.69
  ROUND(100 * buyers  / carters, 2) AS cart_to_buy_pct,    -- 31.07
  ROUND(100 * buyers  / viewers, 2) AS view_to_buy_pct     -- 0.83
FROM stages;
-- viewers 1,404,179 | carters 37,722 | buyers 11,719
-- => The leak is VIEW -> CART (97.3% never add anything).
--    Checkout (cart -> buy, 31%) is comparatively healthy.


-- 1.4  Data-quality check: strict (sequential) funnel ---------
-- Some visitors add to cart without a logged view (tracking gaps
-- or views before the data window). The strict version counts only
-- carters who ALSO have a logged view.
SELECT
  SUM(has_view)                           AS viewers,
  SUM(carted)                             AS all_carters,
  SUM(carted AND NOT has_view)            AS carters_without_logged_view,
  SUM(carted AND has_view)                AS carters_with_view,
  ROUND(100 * SUM(carted) / SUM(has_view), 2)             AS stage_ratio_pct,   -- 2.69
  ROUND(100 * SUM(carted AND has_view) / SUM(has_view), 2) AS strict_rate_pct   -- 2.45
FROM visitor_summary;
-- 3,321 carters have no logged view. Headline uses the stage ratio (2.7%);
-- the strict rate (2.45%) is used for the visitor-level driver analysis in 03.
-- Either way the conclusion is the same: ~97% of viewers never add to cart.
