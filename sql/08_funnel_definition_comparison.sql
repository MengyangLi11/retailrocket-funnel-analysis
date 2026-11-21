USE retailrocket;
SET time_zone = '+00:00';

WITH all_counts AS (
    -- 全量用户：原版人数，以及浏览与加购的交集人数
    SELECT
        SUM(has_view) AS viewers,
        SUM(carted) AS all_carters,
        SUM(has_view AND carted) AS nested_carters
    FROM visitor_summary
),
mature_counts AS (
    -- 固定为07脚本中的完整观察期人群
    SELECT
        COUNT(*) AS viewers,
        SUM(s.carted) AS carters
    FROM funnel_user_24h f
    JOIN visitor_summary s
      ON s.visitorid = f.visitorid
),
ordered_full AS (
    -- 同一人群，要求加购晚于首次浏览
    -- 此处允许加购发生在24小时之后，直至数据结束
    SELECT
        COUNT(DISTINCT e.visitorid) AS carters
    FROM funnel_user_24h f
    JOIN events e
      ON e.visitorid = f.visitorid
     AND e.event = 'addtocart'
     AND e.`timestamp` > f.view_ts
),
comparison AS (
    SELECT
        1 AS seq,
        'original_stage_ratio' AS definition,
        viewers,
        all_carters AS carters
    FROM all_counts

    UNION ALL

    SELECT
        2, 'view_cart_intersection',
        viewers, nested_carters
    FROM all_counts

    UNION ALL

    SELECT
        3, 'mature_unordered_full',
        viewers, carters
    FROM mature_counts

    UNION ALL

    SELECT
        4, 'mature_ordered_full',
        m.viewers, o.carters
    FROM mature_counts m
    CROSS JOIN ordered_full o

    UNION ALL

    SELECT
        5, 'mature_ordered_24h',
        COUNT(*), COUNT(cart_ts)
    FROM funnel_user_24h
),
rates AS (
    -- 先保留计算精度，最后再四舍五入
    SELECT
        seq,
        definition,
        viewers,
        carters,
        CAST(100 AS DECIMAL(20,10)) * carters
            / NULLIF(viewers, 0) AS rate_pct
    FROM comparison
)
SELECT
    seq,
    definition,
    viewers,
    carters,
    ROUND(rate_pct, 4) AS view_to_cart_pct,
    ROUND(
        rate_pct - LAG(rate_pct) OVER (ORDER BY seq),
        4
    ) AS delta_pp
FROM rates
ORDER BY seq;