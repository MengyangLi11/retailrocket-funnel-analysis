USE retailrocket;
SET time_zone = '+00:00';

DROP TABLE IF EXISTS funnel_item_24h;

CREATE TABLE funnel_item_24h AS
WITH item_views AS (
    -- 沿用07的人群与截止时间，找到窗口内各商品的首次浏览
    SELECT
        f.visitorid,
        e.itemid,
        MIN(e.`timestamp`) AS item_view_ts,
        MAX(f.deadline_ts) AS deadline_ts
    FROM funnel_user_24h f
    JOIN events e
      ON e.visitorid = f.visitorid
     AND e.event = 'view'
     AND e.`timestamp` >= f.view_ts
     AND e.`timestamp` <= f.deadline_ts
    GROUP BY f.visitorid, e.itemid
),
item_carts AS (
    -- 同一用户、同一商品：浏览之后的合格加购
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
    -- 同一用户、同一商品：合格加购之后的购买
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

ALTER TABLE funnel_item_24h
ADD PRIMARY KEY (visitorid, itemid);

-- 结果一：相同人群、相同窗口下的两种链路定义
WITH counts AS (
    SELECT
        1 AS seq,
        'cross_item_allowed' AS definition,
        COUNT(*) AS viewers,
        COUNT(cart_ts) AS carters,
        COUNT(buy_ts) AS buyers
    FROM funnel_user_24h

    UNION ALL

    SELECT
        2,
        'same_item_required',
        COUNT(DISTINCT visitorid),
        COUNT(DISTINCT CASE
            WHEN cart_ts IS NOT NULL THEN visitorid END),
        COUNT(DISTINCT CASE
            WHEN buy_ts IS NOT NULL THEN visitorid END)
    FROM funnel_item_24h
)
SELECT
    definition,
    viewers,
    carters,
    buyers,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * carters
        / NULLIF(viewers, 0), 4
    ) AS view_to_cart_pct,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * buyers
        / NULLIF(carters, 0), 4
    ) AS cart_to_buy_pct,
    ROUND(
        CAST(100 AS DECIMAL(20,10)) * buyers
        / NULLIF(viewers, 0), 4
    ) AS view_to_buy_pct
FROM counts
ORDER BY seq;

-- 结果二：明细规模、用户覆盖与时间规则检查
SELECT
    COUNT(*) AS user_item_pairs,
    COUNT(DISTINCT visitorid) AS covered_viewers,
    SUM(
        (
            cart_ts IS NOT NULL
            AND (
                cart_ts <= item_view_ts
                OR cart_ts > deadline_ts
            )
        )
        OR
        (
            buy_ts IS NOT NULL
            AND (
                cart_ts IS NULL
                OR buy_ts <= cart_ts
                OR buy_ts > deadline_ts
            )
        )
    ) AS invalid_paths
FROM funnel_item_24h;