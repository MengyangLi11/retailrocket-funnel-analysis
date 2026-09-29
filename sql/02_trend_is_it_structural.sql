-- ============================================================
-- 02  IS THE 2.7% A BAD PATCH OR STRUCTURAL?
-- If view-to-cart is flat week after week while traffic moves,
-- the problem is the experience itself, not seasonality.
-- ============================================================
USE retailrocket;
SET time_zone = '+00:00';

-- 2.1  Weekly traffic and view-to-cart (ISO weeks, Mon-Sun, UTC)
SELECT
  YEARWEEK(FROM_UNIXTIME(timestamp / 1000), 3)                      AS iso_year_week,
  MIN(DATE(FROM_UNIXTIME(timestamp / 1000)))                        AS week_start,
  COUNT(DISTINCT visitorid)                                         AS weekly_active_visitors,
  COUNT(DISTINCT CASE WHEN event = 'view'        THEN visitorid END) AS viewers,
  COUNT(DISTINCT CASE WHEN event = 'addtocart'   THEN visitorid END) AS carters,
  COUNT(DISTINCT CASE WHEN event = 'transaction' THEN visitorid END) AS buyers,
  ROUND(100 * COUNT(DISTINCT CASE WHEN event = 'addtocart' THEN visitorid END)
            / COUNT(DISTINCT CASE WHEN event = 'view'      THEN visitorid END), 2) AS view_to_cart_pct
FROM events
GROUP BY iso_year_week
ORDER BY iso_year_week;
-- Full weeks: 70k-98k active visitors, view-to-cart between 2.29% and 2.96%.
-- (First and last weeks are partial and excluded from the range.)


-- 2.2  Summary of the weekly band (full weeks only) -----------
WITH weekly AS (
  SELECT
    YEARWEEK(FROM_UNIXTIME(timestamp / 1000), 3) AS wk,
    COUNT(DISTINCT DATE(FROM_UNIXTIME(timestamp / 1000))) AS days_in_week,
    COUNT(DISTINCT CASE WHEN event = 'view'      THEN visitorid END) AS viewers,
    COUNT(DISTINCT CASE WHEN event = 'addtocart' THEN visitorid END) AS carters
  FROM events
  GROUP BY wk
)
SELECT
  COUNT(*)                                          AS full_weeks,
  ROUND(MIN(100 * carters / viewers), 2)            AS min_v2c_pct,
  ROUND(MAX(100 * carters / viewers), 2)            AS max_v2c_pct,
  ROUND(AVG(100 * carters / viewers), 2)            AS avg_v2c_pct,
  ROUND(STDDEV_SAMP(100 * carters / viewers), 2)    AS sd_v2c_pct,
  MIN(viewers)                                      AS min_weekly_viewers,
  MAX(viewers)                                      AS max_weekly_viewers
FROM weekly
WHERE days_in_week = 7;
-- 19 full weeks | 2.29% - 2.96% | mean 2.58%, sd ~0.18pp
-- Weekly viewers swing by ~27k (70k -> 97k) but the rate barely moves:
-- the leak is structural, which is why a product change (not a campaign)
-- is the right response.
