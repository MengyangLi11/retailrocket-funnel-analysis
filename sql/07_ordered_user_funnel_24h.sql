USE retailrocket;
SET time_zone = '+00:00';

-- 时间戳单位为毫秒；观察结束时间取最后一条事件时间
SET @window_ms = 24 * 60 * 60 * 1000;
SET @end_ms = (SELECT MAX(`timestamp`) FROM events);

-- 重建本次新增的有序漏斗明细表
DROP TABLE IF EXISTS funnel_user_24h;

CREATE TABLE funnel_user_24h AS
WITH first_view AS (
    -- 每名用户首次被记录到的浏览
    SELECT
        visitorid,
        MIN(`timestamp`) AS view_ts
    FROM events
    WHERE event = 'view'
    GROUP BY visitorid
),
cohort AS (
    -- 只纳入具有完整24小时观察期的用户
    SELECT
        visitorid,
        view_ts,
        view_ts + @window_ms AS deadline_ts
    FROM first_view
    WHERE view_ts + @window_ms <= @end_ms
),
first_cart AS (
    -- 找到浏览之后、窗口以内的第一次加购
    SELECT
        c.visitorid,
        MIN(e.`timestamp`) AS cart_ts
    FROM cohort c
    JOIN events e
      ON e.visitorid = c.visitorid
     AND e.event = 'addtocart'
     AND e.`timestamp` > c.view_ts
     AND e.`timestamp` <= c.deadline_ts
    GROUP BY c.visitorid
),
first_buy AS (
    -- 找到合格加购之后、窗口以内的第一次购买
    SELECT
        c.visitorid,
        MIN(e.`timestamp`) AS buy_ts
    FROM cohort c
    JOIN first_cart a
      ON a.visitorid = c.visitorid
    JOIN events e
      ON e.visitorid = c.visitorid
     AND e.event = 'transaction'
     AND e.`timestamp` > a.cart_ts
     AND e.`timestamp` <= c.deadline_ts
    GROUP BY c.visitorid
)
SELECT
    c.visitorid,
    c.view_ts,
    c.deadline_ts,
    a.cart_ts,
    b.buy_ts
FROM cohort c
LEFT JOIN first_cart a ON a.visitorid = c.visitorid
LEFT JOIN first_buy b ON b.visitorid = c.visitorid;

-- 结果一：观察期筛选前后的人数
SELECT
    (SELECT COUNT(*) FROM visitor_summary WHERE has_view = 1)
        AS all_viewers,
    COUNT(*) AS eligible_viewers,
    (SELECT COUNT(*) FROM visitor_summary WHERE has_view = 1)
        - COUNT(*) AS excluded_tail_viewers
FROM funnel_user_24h;

-- 结果二：有序漏斗及转化比例
SELECT
    COUNT(*) AS viewers,
    COUNT(cart_ts) AS ordered_carters,
    COUNT(buy_ts) AS ordered_buyers,
    ROUND(
        100.0 * COUNT(cart_ts) / NULLIF(COUNT(*), 0), 4
    ) AS view_to_cart_pct,
    ROUND(
        100.0 * COUNT(buy_ts) / NULLIF(COUNT(cart_ts), 0), 4
    ) AS cart_to_buy_pct,
    ROUND(
        100.0 * COUNT(buy_ts) / NULLIF(COUNT(*), 0), 4
    ) AS view_to_buy_pct
FROM funnel_user_24h;

-- 结果三：检查是否存在不符合时间顺序或窗口的路径
SELECT COUNT(*) AS invalid_paths
FROM funnel_user_24h
WHERE
    (
        cart_ts IS NOT NULL
        AND (cart_ts <= view_ts OR cart_ts > deadline_ts)
    )
    OR
    (
        buy_ts IS NOT NULL
        AND (
            cart_ts IS NULL
            OR buy_ts <= cart_ts
            OR buy_ts > deadline_ts
        )
    );