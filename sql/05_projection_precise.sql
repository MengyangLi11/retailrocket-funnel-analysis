-- ============================================================
-- 05  A/B TEST INPUTS: baseline, traffic, and the lift projection
-- Feeds experiment/ab_test_plan.md and experiment/power_and_projection.py
-- ============================================================
USE retailrocket;
SET time_zone = '+00:00';


-- 5.1  Baseline for the primary metric -----------------------
SELECT
  SUM(has_view)                              AS viewers,
  SUM(carted)                                AS carters,
  ROUND(100 * SUM(carted) / SUM(has_view), 3) AS baseline_view_to_cart_pct   -- 2.686
FROM visitor_summary;


-- 5.2  Traffic available to the test: NEW viewers per full week
-- (conservative: returning visitors would add more)
WITH wk AS (
  SELECT YEARWEEK(first_seen_date, 3) AS iso_week,
         COUNT(DISTINCT first_seen_date) AS days,
         SUM(has_view) AS new_viewers
  FROM visitor_summary
  GROUP BY iso_week
)
SELECT COUNT(*) AS full_weeks,
       ROUND(AVG(new_viewers)) AS avg_new_viewers_per_week,
       MIN(new_viewers) AS min_week, MAX(new_viewers) AS max_week
FROM wk
WHERE days = 7;
-- ~71,800 new viewers per week (62k - 88k)


-- 5.3  Lift projection (scenario model) ----------------------
-- Mechanism: the "You may also like" strip pulls a share (reach) of
-- single-item visitors into browsing more. Those visitors are assumed
-- to convert like today's 2-4-item browsers, discounted by a causal
-- factor (browsers self-select, so not all of the observed gap is causal).
--
--   extra_carters  = single_item_viewers x reach x causal x (rate_2to4 - rate_1)
--   relative_lift  = extra_carters / current_carters
WITH base AS (
  SELECT
    SUM(has_view)                                          AS viewers,
    SUM(carted)                                            AS carters,
    SUM(items_viewed = 1)                                  AS n_single,
    CAST(SUM(carted AND items_viewed = 1) AS DECIMAL(30,12))
      / NULLIF(SUM(items_viewed = 1), 0) AS rate_1,
    CAST(SUM(carted AND items_viewed BETWEEN 2 AND 4) AS DECIMAL(30,12))
      / NULLIF(SUM(items_viewed BETWEEN 2 AND 4), 0) AS rate_2to4
  FROM visitor_summary
),
scenarios AS (
            SELECT 'Conservative' AS scenario, 0.17 AS reach, 0.5 AS causal
  UNION ALL SELECT 'Central',                  0.17,          1.0
  UNION ALL SELECT 'Low reach',                0.10,          1.0
  UNION ALL SELECT 'High reach',               0.25,          1.0
)
SELECT
  s.scenario, s.reach, s.causal,
  ROUND(b.n_single * s.reach * s.causal * (b.rate_2to4 - b.rate_1))                     AS extra_carters,
  ROUND(100 * b.n_single * s.reach * s.causal * (b.rate_2to4 - b.rate_1) / b.carters, 1) AS relative_lift_pct,
  ROUND(100 * b.carters / b.viewers, 2)                                                  AS baseline_pct,
  ROUND(100 * (b.carters + b.n_single * s.reach * s.causal * (b.rate_2to4 - b.rate_1)) / b.viewers, 2) AS projected_pct
FROM base b CROSS JOIN scenarios s
ORDER BY relative_lift_pct;
-- Low reach     10% x 1.0 ->  +11.0%  (2.69% -> 2.98%)
-- Conservative  17% x 0.5 ->   +9.4%  (2.69% -> 2.94%)
-- Central       17% x 1.0 ->  +18.7%  (2.69% -> 3.19%)   <- the ~19% projection
-- High reach    25% x 1.0 ->  +27.5%  (2.69% -> 3.43%)
