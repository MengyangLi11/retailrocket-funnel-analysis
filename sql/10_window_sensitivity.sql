USE retailrocket;
SET time_zone = '+00:00';

SET @max_window_ms = 7 * 24 * 60 * 60 * 1000;
SET @end_ms = (SELECT MAX(`timestamp`) FROM events);

DROP TABLE IF EXISTS funnel_item_7d;

CREATE TABLE funnel_item_7d AS
WITH cohort AS (
    -- 三个窗口使用相同的完整7日观察期人群
    SELECT
        visitorid,
        view_ts,
        view_ts + @max_window_ms AS deadline_ts
    FROM funnel_user_24h
    WHERE view_ts + @max_window_ms <= @end_ms
),
item_views AS (
    SELECT
        f.visitorid,
        e.itemid,
        MAX(f.view_ts) AS user_view_ts,
        MIN(e.`timestamp`) AS item_view_ts,
        MAX(f.deadline_ts) AS deadline_ts
    FROM cohort f
    JOIN events e
      ON e.visitorid = f.visitorid
     AND e.event = 'view'
     AND e.`timestamp` >= f.view_ts
     AND e.`timestamp` <= f.deadline_ts
    GROUP BY f.visitorid, e.itemid
),
item_carts AS (
    SELECT
        v.visitorid,
        v.itemid,
        MIN(e.`timestamp`) AS cart_ts
    FROM item_views v
    JOIN events e
      ON e.visitorid = v.visitorid
     AND e.itemid = v.itemid
     AND e.event = 'addtocart'
     AND e.`timestamp` > v.item_view_ts
     AND e.`timestamp` <= v.deadline_ts
    GROUP BY v.visitorid, v.itemid
),
item_buys AS (
    SELECT
        v.visitorid,
        v.itemid,
        MIN(e.`timestamp`) AS buy_ts
    FROM item_views v
    JOIN item_carts c
      ON c.visitorid = v.visitorid
     AND c.itemid = v.itemid
    JOIN events e
      ON e.visitorid = v.visitorid
     AND e.itemid = v.itemid
     AND e.event = 'transaction'
     AND e.`timestamp` > c.cart_ts
     AND e.`timestamp` <= v.deadline_ts
    GROUP BY v.visitorid, v.itemid
)
SELECT
    v.visitorid,
    v.itemid,
    v.user_view_ts,
    v.item_view_ts,
    v.deadline_ts,
    c.cart_ts,
    b.buy_ts
FROM item_views v
LEFT JOIN item_carts c
  ON c.visitorid = v.visitorid
 AND c.itemid = v.itemid
LEFT JOIN item_buys b
  ON b.visitorid = v.visitorid
 AND b.itemid = v.itemid;

ALTER TABLE funnel_item_7d
ADD PRIMARY KEY (visitorid, itemid);

-- 保存汇总查询，方便后续导出
CREATE OR REPLACE VIEW funnel_window_sensitivity AS
WITH user_times AS (
    -- 先验证同商品链路，再取得每名用户的最早合格时间
    SELECT
        visitorid,
        MIN(user_view_ts) AS user_view_ts,
        MIN(cart_ts) AS valid_cart_ts,
        MIN(buy_ts) AS valid_buy_ts
    FROM funnel_item_7d
    GROUP BY visitorid
),
window_options AS (
    SELECT 1 AS window_hours, 3600000 AS window_ms
    UNION ALL SELECT 24, 86400000
    UNION ALL SELECT 168, 604800000
),
counts AS (
    SELECT
        w.window_hours,
        COUNT(u.visitorid) AS viewers,
        SUM(CASE
            WHEN u.valid_cart_ts <= u.user_view_ts + w.window_ms
            THEN 1 ELSE 0 END) AS carters,
        SUM(CASE
            WHEN u.valid_buy_ts <= u.user_view_ts + w.window_ms
            THEN 1 ELSE 0 END) AS buyers
    FROM window_options w
    LEFT JOIN user_times u ON 1 = 1
    GROUP BY w.window_hours, w.window_ms
)
SELECT
    window_hours,
    viewers,
    carters,
    buyers,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * carters
        / NULLIF(viewers, 0), 4
    ) AS view_to_cart_pct,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * buyers
        / NULLIF(viewers, 0), 4
    ) AS view_to_buy_pct,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * buyers
        / NULLIF(
            MAX(CASE WHEN window_hours = 168
                     THEN buyers END) OVER (),
            0
        ), 4
    ) AS buyer_coverage_7d_pct
FROM counts;

-- 结果一：三个窗口的对照
SELECT *
FROM funnel_window_sensitivity
ORDER BY window_hours;

-- 结果二：明细规模及规则检查
SELECT
    COUNT(*) AS user_item_pairs,
    COUNT(DISTINCT visitorid) AS covered_viewers,
    SUM(
        item_view_ts < user_view_ts
        OR item_view_ts > deadline_ts
        OR deadline_ts > @end_ms
        OR (
            cart_ts IS NOT NULL
            AND (
                cart_ts <= item_view_ts
                OR cart_ts > deadline_ts
            )
        )
        OR (
            buy_ts IS NOT NULL
            AND (
                cart_ts IS NULL
                OR buy_ts <= cart_ts
                OR buy_ts > deadline_ts
            )
        )
    ) AS invalid_paths
FROM funnel_item_7d;