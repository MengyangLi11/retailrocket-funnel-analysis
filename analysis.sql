-- ============================================================
-- RetailRocket E-Commerce Funnel Analysis
-- Author: Gurmesh Singh
-- Data: ~2.75M user events (view / addtocart / transaction)
--        from an online retailer, May-Sep 2015 (RetailRocket, Kaggle)
-- Tool:  MySQL
--
-- Note on the data:
--   timestamp    = Unix time in MILLISECONDS (divide by 1000 to read as a date)
--   event        = 'view', 'addtocart', or 'transaction'
--   transactionid= only present on transaction rows (NULL otherwise)
-- ============================================================

USE retailrocket;


-- ============================================================
-- 1. SANITY CHECK: how many of each event exist?
-- These raw counts are the backbone of the funnel.
-- ============================================================
SELECT event, COUNT(*) AS cnt
FROM events
GROUP BY event;
-- view: 2,664,312 | addtocart: 69,332 | transaction: 22,457


-- ============================================================
-- 2. THE FUNNEL (unique-visitor level)
-- Raw event counts overstate reality because one visitor
-- views many items. The honest funnel counts UNIQUE visitors
-- who reached each stage at least once.
-- ============================================================
SELECT
  COUNT(DISTINCT CASE WHEN event = 'view'        THEN visitorid END) AS viewers,
  COUNT(DISTINCT CASE WHEN event = 'addtocart'   THEN visitorid END) AS carters,
  COUNT(DISTINCT CASE WHEN event = 'transaction' THEN visitorid END) AS buyers
FROM events;
-- viewers: 1,404,179 | carters: 37,722 | buyers: 11,719
-- => view->cart = 2.7%, cart->buy = 31.1%, view->buy = 0.83%
-- The big leak is view -> cart. Checkout (cart -> buy) is healthy.


-- ============================================================
-- 3. TIME-BASED ANALYSIS
-- ============================================================

-- 3a. What date range does the data cover?
SELECT
  FROM_UNIXTIME(MIN(timestamp) / 1000) AS first_event,
  FROM_UNIXTIME(MAX(timestamp) / 1000) AS last_event
FROM events;
-- 2015-05-03 to 2015-09-18 (~4.5 months)

-- 3b. Weekly Active Users: is the store growing or shrinking?
SELECT
  YEARWEEK(FROM_UNIXTIME(timestamp / 1000), 3) AS year_week,
  COUNT(DISTINCT visitorid)                    AS weekly_active_users
FROM events
GROUP BY year_week
ORDER BY year_week;
-- Stable at ~70k-95k/week (first & last weeks are partial). Traffic is not the problem.

-- 3c. Is the view->cart rate getting worse over time, or is it steady?
SELECT
  YEARWEEK(FROM_UNIXTIME(timestamp / 1000), 3)                                AS year_week,
  COUNT(DISTINCT CASE WHEN event = 'view'      THEN visitorid END)            AS viewers,
  COUNT(DISTINCT CASE WHEN event = 'addtocart' THEN visitorid END)            AS carters,
  ROUND(100 * COUNT(DISTINCT CASE WHEN event = 'addtocart' THEN visitorid END)
            / COUNT(DISTINCT CASE WHEN event = 'view'      THEN visitorid END), 2) AS view_to_cart_pct
FROM events
GROUP BY year_week
ORDER BY year_week;
-- Flat between 2.3% and 3.0% every week => the low conversion is STRUCTURAL,
-- not seasonal. The experience never self-corrects.


-- ============================================================
-- 4. BEHAVIOR-BASED ANALYSIS
-- What separates buyers from everyone else?
-- ============================================================

-- 4a. Do buyers browse more items than non-buyers?
SELECT
  CASE WHEN b.visitorid IS NOT NULL THEN 'buyer' ELSE 'non-buyer' END AS user_type,
  COUNT(*)                       AS num_visitors,
  ROUND(AVG(v.items_viewed), 2)  AS avg_items_viewed
FROM (
  -- distinct items each visitor viewed
  SELECT visitorid, COUNT(DISTINCT itemid) AS items_viewed
  FROM events
  WHERE event = 'view'
  GROUP BY visitorid
) v
LEFT JOIN (
  -- everyone who ever bought
  SELECT DISTINCT visitorid FROM events WHERE event = 'transaction'
) b ON v.visitorid = b.visitorid
GROUP BY user_type;
-- non-buyer avg: 1.45 items | buyer avg: 9.61 items
-- Buyers browse ~6.6x more. Browsing depth is the strongest buy signal.

-- 4b. How concentrated is the "one-and-done" problem?
SELECT
  CASE
    WHEN items_viewed = 1             THEN '1 item'
    WHEN items_viewed BETWEEN 2 AND 4 THEN '2-4 items'
    WHEN items_viewed BETWEEN 5 AND 9 THEN '5-9 items'
    ELSE '10+ items'
  END       AS bucket,
  COUNT(*)  AS visitors
FROM (
  SELECT visitorid, COUNT(DISTINCT itemid) AS items_viewed
  FROM events
  WHERE event = 'view'
  GROUP BY visitorid
) t
GROUP BY bucket
ORDER BY MIN(items_viewed);
-- 1 item: 1,118,109 (80%) | 2-4: 247,092 (18%) | 5-9: 29,769 (2%) | 10+: 9,209 (0.7%)
-- 80% of visitors view a single product and leave.


-- ============================================================
-- 5. RETENTION
-- ============================================================

-- 5a. How many visitors come back on a different day?
SELECT
  CASE WHEN active_days = 1 THEN 'one-time (1 day)'
       ELSE 'returning (2+ days)' END AS visitor_type,
  COUNT(*)                            AS visitors
FROM (
  SELECT visitorid,
         COUNT(DISTINCT DATE(FROM_UNIXTIME(timestamp / 1000))) AS active_days
  FROM events
  GROUP BY visitorid
) t
GROUP BY visitor_type;
-- one-time: 1,262,936 | returning: 144,644  => only ~10% ever return.

-- 5b. Of the people who bought, how many bought again?
SELECT
  CASE WHEN orders = 1 THEN 'one-time buyer' ELSE 'repeat buyer' END AS buyer_type,
  COUNT(*)                                                           AS buyers
FROM (
  SELECT visitorid, COUNT(DISTINCT transactionid) AS orders
  FROM events
  WHERE event = 'transaction'
  GROUP BY visitorid
) t
GROUP BY buyer_type;
-- one-time buyer: 10,656 | repeat buyer: 1,063  => only ~9% buy a second time.


-- ============================================================
-- SUMMARY OF FINDINGS
--   * view->cart is only 2.7% and flat every week (structural leak)
--   * cart->buy is a healthy 31% (checkout is fine)
--   * buyers view ~10 items, non-buyers ~1.5
--   * 80% of visitors view a single item and leave
--   * 90% of visitors never return; 91% of buyers never buy again
-- => Fix product DISCOVERY for one-item browsers. See README for the A/B test.
-- ============================================================
