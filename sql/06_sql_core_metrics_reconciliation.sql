-- ============================================================
-- KuaiRand-Pure：SQL 核心指标复算与 Python 结果核对
--
-- 目标：
--   1. 使用 05_create_analysis_views.sql 创建的分析明细视图复算指标；
--   2. 核对 SQL 与《3 Python定义核心指标+探索性分析.ipynb》的核心结果；
--   3. 输出日期、小时、用户、内容和推荐方式的分析结果；
--   4. 为 07_create_metric_views.sql 提供经过核对的指标口径。
--
-- 使用说明：
--   1. 必须先完整执行 05_create_analysis_views.sql；
--   2. 在 DBeaver 中使用 Alt + X 执行本脚本；
--   3. 第 1～3、8 部分含 Python 基准值与 PASS / FAIL；
--   4. 第 4～7 部分用于查看 SQL 分组结果，与 Notebook 对照阅读；
--   5. 本脚本只有 SELECT / WITH / SHOW，不修改任何数据库对象或数据。
--
-- 核验原则：
--   数量指标必须精确相等；
--   百分比按业务展示精度保留 4 位小数后比较；
--   播放时长（秒）保留 3 位小数后比较；
--   播放进度保留 6 位小数后比较。
--   第 4～7 部分不再与 Python 逐行自动对账，避免为浮点尾差投入过多成本。
--
-- 指标单位：
--   *_rate_pct 均为百分比，例如 46.3981 表示 46.3981%；
--   *_seconds 均为秒；play_ratio 为比例值，1 表示播放进度 100%。
-- ============================================================

USE kuairand_analytics;


-- ------------------------------------------------------------
-- 0. 前置检查：确认两个分析明细视图已经存在
-- 预期返回 2 行。
-- ------------------------------------------------------------
SELECT
    table_name AS analysis_view,
    is_updatable
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name IN (
      'vw_standard_analysis_detail',
      'vw_random_analysis_detail'
  )
ORDER BY table_name;


-- ------------------------------------------------------------
-- 1. 标准推荐：规模指标与 Python 核对
-- Python 基准来自当前四张清洗后 Parquet 表。
-- ------------------------------------------------------------
WITH sql_metrics AS
(
    SELECT
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        COUNT(DISTINCT video_id) AS unique_videos,
        COUNT(is_complete_play) AS valid_duration_records,
        SUM(is_complete_play IS NULL) AS missing_duration_records
    FROM vw_standard_analysis_detail
),
metric_rows AS
(
    SELECT '推荐记录数' AS metric_name,
           recommendation_records * 1.0 AS sql_value,
           1414622.0 AS python_value
    FROM sql_metrics

    UNION ALL
    SELECT '覆盖用户数', unique_users * 1.0, 27077.0
    FROM sql_metrics

    UNION ALL
    SELECT '覆盖视频数', unique_videos * 1.0, 7551.0
    FROM sql_metrics

    UNION ALL
    SELECT '有效视频时长记录数', valid_duration_records * 1.0, 1385762.0
    FROM sql_metrics

    UNION ALL
    SELECT '视频时长缺失记录数', missing_duration_records * 1.0, 28860.0
    FROM sql_metrics
)
SELECT
    metric_name,
    sql_value,
    python_value,
    (sql_value - python_value) AS difference,
    CASE
        WHEN sql_value = python_value THEN 'PASS'
        ELSE 'FAIL'
    END AS check_result
FROM metric_rows;


-- ------------------------------------------------------------
-- 2. 标准推荐：核心行为率与 Python 核对
-- AVG(0/1字段) = 发生次数 / 统计记录数。
-- AVG(is_complete_play) 会自动忽略 NULL，与 Pandas mean() 口径一致。
-- SQL 与 Python 均先保留 4 位小数，再比较最终业务展示值。
-- ------------------------------------------------------------
WITH sql_metrics AS
(
    SELECT
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(is_like) * 100.0 AS like_rate_pct,
        AVG(is_comment) * 100.0 AS comment_rate_pct,
        AVG(is_follow) * 100.0 AS follow_rate_pct,
        AVG(is_forward) * 100.0 AS forward_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct
    FROM vw_standard_analysis_detail
),
metric_rows AS
(
    SELECT '有效播放/点击率(%)' AS metric_name,
           click_rate_pct AS sql_value,
           46.3981 AS python_value
    FROM sql_metrics

    UNION ALL
    SELECT '长播率(%)', long_view_rate_pct, 33.5572
    FROM sql_metrics

    UNION ALL
    SELECT '完整播放率(%)', complete_play_rate_pct, 15.4330
    FROM sql_metrics

    UNION ALL
    SELECT '点赞率(%)', like_rate_pct, 1.8644
    FROM sql_metrics

    UNION ALL
    SELECT '评论率(%)', comment_rate_pct, 0.2571
    FROM sql_metrics

    UNION ALL
    SELECT '关注率(%)', follow_rate_pct, 0.1072
    FROM sql_metrics

    UNION ALL
    SELECT '转发率(%)', forward_rate_pct, 0.0971
    FROM sql_metrics

    UNION ALL
    SELECT '综合互动率(%)', interaction_rate_pct, 2.2229
    FROM sql_metrics
)
SELECT
    metric_name,
    ROUND(sql_value, 4) AS sql_value,
    ROUND(python_value, 4) AS python_value,
    ROUND(ROUND(sql_value, 4) - ROUND(python_value, 4), 4) AS difference,
    CASE
        WHEN ROUND(sql_value, 4) = ROUND(python_value, 4) THEN 'PASS'
        ELSE 'FAIL'
    END AS check_result
FROM metric_rows;


-- ------------------------------------------------------------
-- 3. 标准推荐：播放时长与播放进度指标核对
--
-- MySQL 没有通用 MEDIAN() 聚合函数，因此按以下方式求中位数：
--   1. ROW_NUMBER() 排序并编号；
--   2. COUNT(*) OVER() 得到总行数；
--   3. 奇数取中间一项，偶数取中间两项平均值。
-- ------------------------------------------------------------
WITH ranked_play_time AS
(
    SELECT
        play_time_seconds,
        ROW_NUMBER() OVER (ORDER BY play_time_seconds) AS rn,
        COUNT(*) OVER () AS n
    FROM vw_standard_analysis_detail
    WHERE play_time_seconds IS NOT NULL
),
ranked_play_ratio AS
(
    SELECT
        play_ratio_raw,
        ROW_NUMBER() OVER (ORDER BY play_ratio_raw) AS rn,
        COUNT(*) OVER () AS n
    FROM vw_standard_analysis_detail
    WHERE play_ratio_raw IS NOT NULL
),
sql_metrics AS
(
    SELECT
        (
            SELECT AVG(play_time_seconds)
            FROM ranked_play_time
            WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
        ) AS median_play_time_seconds,
        (
            SELECT AVG(play_time_seconds)
            FROM vw_standard_analysis_detail
        ) AS mean_play_time_seconds,
        (
            SELECT AVG(play_ratio_raw)
            FROM ranked_play_ratio
            WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
        ) AS median_play_ratio,
        (
            SELECT AVG(play_ratio_raw)
            FROM vw_standard_analysis_detail
        ) AS mean_play_ratio,
        (
            SELECT AVG(play_ratio_raw >= 1) * 100.0
            FROM vw_standard_analysis_detail
            WHERE play_ratio_raw IS NOT NULL
        ) AS ratio_ge_1_pct
),
metric_rows AS
(
    SELECT '播放时长中位数(秒)' AS metric_name,
           median_play_time_seconds AS sql_value,
           5.007 AS python_value,
           3 AS decimal_places
    FROM sql_metrics

    UNION ALL
    SELECT '播放时长平均数(秒)', mean_play_time_seconds, 23.143, 3
    FROM sql_metrics

    UNION ALL
    SELECT '播放进度中位数', median_play_ratio, 0.101347, 6
    FROM sql_metrics

    UNION ALL
    SELECT '播放进度平均数', mean_play_ratio, 0.369201, 6
    FROM sql_metrics

    UNION ALL
    SELECT '播放进度达到100%的比例(%)', ratio_ge_1_pct, 15.4330, 4
    FROM sql_metrics
)
SELECT
    metric_name,
    ROUND(sql_value, decimal_places) AS sql_value,
    ROUND(python_value, decimal_places) AS python_value,
    ROUND(
        ROUND(sql_value, decimal_places)
        - ROUND(python_value, decimal_places),
        decimal_places
    ) AS difference,
    decimal_places,
    CASE
        WHEN ROUND(sql_value, decimal_places)
             = ROUND(python_value, decimal_places)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS check_result
FROM metric_rows;


-- ------------------------------------------------------------
-- 4. 标准推荐：每日指标
-- 一行代表一天。观察推荐量时，应同时观察行为率，避免只看比例波动。
-- ------------------------------------------------------------
WITH ranked_play_time AS
(
    SELECT
        date_clean,
        play_time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY date_clean
            ORDER BY play_time_seconds
        ) AS rn,
        COUNT(*) OVER (PARTITION BY date_clean) AS n
    FROM vw_standard_analysis_detail
    WHERE play_time_seconds IS NOT NULL
),
play_time_median AS
(
    SELECT
        date_clean,
        AVG(play_time_seconds) AS median_play_time_seconds
    FROM ranked_play_time
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY date_clean
),
daily_agg AS
(
    SELECT
        date_clean,
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        COUNT(DISTINCT video_id) AS unique_videos,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(is_like) * 100.0 AS like_rate_pct,
        AVG(is_comment) * 100.0 AS comment_rate_pct,
        AVG(is_follow) * 100.0 AS follow_rate_pct,
        AVG(is_forward) * 100.0 AS forward_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct
    FROM vw_standard_analysis_detail
    GROUP BY date_clean
)
SELECT
    d.date_clean,
    d.recommendation_records,
    d.unique_users,
    d.unique_videos,
    ROUND(d.click_rate_pct, 4) AS click_rate_pct,
    ROUND(d.long_view_rate_pct, 4) AS long_view_rate_pct,
    ROUND(d.complete_play_rate_pct, 4) AS complete_play_rate_pct,
    ROUND(d.like_rate_pct, 4) AS like_rate_pct,
    ROUND(d.comment_rate_pct, 4) AS comment_rate_pct,
    ROUND(d.follow_rate_pct, 4) AS follow_rate_pct,
    ROUND(d.forward_rate_pct, 4) AS forward_rate_pct,
    ROUND(d.interaction_rate_pct, 4) AS interaction_rate_pct,
    ROUND(m.median_play_time_seconds, 4) AS median_play_time_seconds
FROM daily_agg AS d
LEFT JOIN play_time_median AS m
    ON d.date_clean = m.date_clean
ORDER BY d.date_clean;


-- ------------------------------------------------------------
-- 5. 标准推荐：小时指标
-- 一行代表一个小时档位。解释比例时必须同时关注 recommendation_records。
-- ------------------------------------------------------------
WITH ranked_play_time AS
(
    SELECT
        hour,
        play_time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY hour
            ORDER BY play_time_seconds
        ) AS rn,
        COUNT(*) OVER (PARTITION BY hour) AS n
    FROM vw_standard_analysis_detail
    WHERE play_time_seconds IS NOT NULL
),
play_time_median AS
(
    SELECT
        hour,
        AVG(play_time_seconds) AS median_play_time_seconds
    FROM ranked_play_time
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY hour
),
hourly_agg AS
(
    SELECT
        hour,
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct
    FROM vw_standard_analysis_detail
    GROUP BY hour
)
SELECT
    h.hour,
    h.recommendation_records,
    h.unique_users,
    ROUND(h.click_rate_pct, 4) AS click_rate_pct,
    ROUND(h.long_view_rate_pct, 4) AS long_view_rate_pct,
    ROUND(h.complete_play_rate_pct, 4) AS complete_play_rate_pct,
    ROUND(h.interaction_rate_pct, 4) AS interaction_rate_pct,
    ROUND(m.median_play_time_seconds, 4) AS median_play_time_seconds
FROM hourly_agg AS h
LEFT JOIN play_time_median AS m
    ON h.hour = m.hour
ORDER BY h.hour;


-- ------------------------------------------------------------
-- 6. 标准推荐：用户分层指标（长表结构）
-- segment_type 表示按什么分组，segment_value 表示具体类别。
-- NULL 统一显示为“缺失”，对应 Pandas groupby(dropna=False)。
-- ------------------------------------------------------------
WITH segment_base AS
(
    SELECT
        '用户活跃度' AS segment_type,
        COALESCE(CAST(user_active_degree AS CHAR), '缺失') AS segment_value,
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '是否视频创作者',
        COALESCE(CAST(is_video_author AS CHAR), '缺失'),
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '注册时长分组',
        COALESCE(register_days_group, '缺失'),
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '粉丝规模分组',
        COALESCE(CAST(fans_user_num_range AS CHAR), '缺失'),
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail
),
ranked_play_time AS
(
    SELECT
        segment_type,
        segment_value,
        play_time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY segment_type, segment_value
            ORDER BY play_time_seconds
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY segment_type, segment_value
        ) AS n
    FROM segment_base
    WHERE play_time_seconds IS NOT NULL
),
play_time_median AS
(
    SELECT
        segment_type,
        segment_value,
        AVG(play_time_seconds) AS median_play_time_seconds
    FROM ranked_play_time
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY segment_type, segment_value
),
segment_agg AS
(
    SELECT
        segment_type,
        segment_value,
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        COUNT(DISTINCT video_id) AS unique_videos,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct
    FROM segment_base
    GROUP BY segment_type, segment_value
)
SELECT
    s.segment_type,
    s.segment_value,
    s.recommendation_records,
    s.unique_users,
    s.unique_videos,
    ROUND(s.click_rate_pct, 4) AS click_rate_pct,
    ROUND(s.long_view_rate_pct, 4) AS long_view_rate_pct,
    ROUND(s.complete_play_rate_pct, 4) AS complete_play_rate_pct,
    ROUND(s.interaction_rate_pct, 4) AS interaction_rate_pct,
    ROUND(m.median_play_time_seconds, 4) AS median_play_time_seconds
FROM segment_agg AS s
LEFT JOIN play_time_median AS m
    ON s.segment_type = m.segment_type
   AND s.segment_value = m.segment_value
ORDER BY
    FIELD(
        s.segment_type,
        '用户活跃度', '是否视频创作者', '注册时长分组', '粉丝规模分组'
    ),
    s.recommendation_records DESC;


-- ------------------------------------------------------------
-- 7. 标准推荐：内容分层指标（长表结构）
-- ------------------------------------------------------------
WITH segment_base AS
(
    SELECT
        '视频类型' AS segment_type,
        COALESCE(CAST(video_type AS CHAR), '缺失') AS segment_value,
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '上传方式',
        COALESCE(CAST(upload_type AS CHAR), '缺失'),
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '视频时长分组',
        CASE
            WHEN duration_group = '120秒及以上' THEN '120秒以上'
            ELSE COALESCE(duration_group, '缺失')
        END,
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        '屏幕方向',
        CASE
            WHEN screen_orientation = '方屏' THEN '方形'
            ELSE COALESCE(screen_orientation, '缺失')
        END,
        user_id, video_id, is_click, long_view, is_complete_play,
        has_interaction, play_time_seconds
    FROM vw_standard_analysis_detail
),
ranked_play_time AS
(
    SELECT
        segment_type,
        segment_value,
        play_time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY segment_type, segment_value
            ORDER BY play_time_seconds
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY segment_type, segment_value
        ) AS n
    FROM segment_base
    WHERE play_time_seconds IS NOT NULL
),
play_time_median AS
(
    SELECT
        segment_type,
        segment_value,
        AVG(play_time_seconds) AS median_play_time_seconds
    FROM ranked_play_time
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY segment_type, segment_value
),
segment_agg AS
(
    SELECT
        segment_type,
        segment_value,
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        COUNT(DISTINCT video_id) AS unique_videos,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct
    FROM segment_base
    GROUP BY segment_type, segment_value
)
SELECT
    s.segment_type,
    s.segment_value,
    s.recommendation_records,
    s.unique_users,
    s.unique_videos,
    ROUND(s.click_rate_pct, 4) AS click_rate_pct,
    ROUND(s.long_view_rate_pct, 4) AS long_view_rate_pct,
    ROUND(s.complete_play_rate_pct, 4) AS complete_play_rate_pct,
    ROUND(s.interaction_rate_pct, 4) AS interaction_rate_pct,
    ROUND(m.median_play_time_seconds, 4) AS median_play_time_seconds
FROM segment_agg AS s
LEFT JOIN play_time_median AS m
    ON s.segment_type = m.segment_type
   AND s.segment_value = m.segment_value
ORDER BY
    FIELD(
        s.segment_type,
        '视频类型', '上传方式', '视频时长分组', '屏幕方向'
    ),
    s.recommendation_records DESC;


-- ------------------------------------------------------------
-- 8. 同期标准推荐与随机推荐：SQL 复算并与 Python 核对
--
-- 可比时间范围：2022-04-22 至 2022-05-08。
-- 标准推荐只取 log_source = standard_0422_0508；随机推荐取同期全量。
-- 注意：这只是描述性比较，不是用户随机分流的 A/B 实验，不能解释为因果提升。
-- 数量指标精确比较；百分比保留 4 位、播放时长保留 3 位、播放进度保留 6 位。
-- ------------------------------------------------------------
-- 将同期的两张表找出来，再合并在一起
WITH same_period_base AS
(
    SELECT
        user_id,
        video_id,
        date_clean,
        recommendation_method,
        is_click,
        long_view,
        is_complete_play,
        is_like,
        is_comment,
        is_follow,
        is_forward,
        has_interaction,
        play_time_seconds,
        play_ratio_raw
    FROM vw_standard_analysis_detail
    WHERE log_source = 'standard_0422_0508'
      AND date_clean BETWEEN DATE('2022-04-22') AND DATE('2022-05-08')

    UNION ALL

    SELECT
        user_id,
        video_id,
        date_clean,
        recommendation_method,
        is_click,
        long_view,
        is_complete_play,
        is_like,
        is_comment,
        is_follow,
        is_forward,
        has_interaction,
        play_time_seconds,
        play_ratio_raw
    FROM vw_random_analysis_detail
    WHERE date_clean BETWEEN DATE('2022-04-22') AND DATE('2022-05-08')
),
-- 查询观看时长中位数
ranked_play_time AS
(
    SELECT
        recommendation_method,
        play_time_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY recommendation_method
            ORDER BY play_time_seconds
        ) AS rn,
        COUNT(*) OVER (PARTITION BY recommendation_method) AS n
    FROM same_period_base
    WHERE play_time_seconds IS NOT NULL
),
play_time_median AS
(
    SELECT
        recommendation_method,
        AVG(play_time_seconds) AS median_play_time_seconds
    FROM ranked_play_time
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY recommendation_method
),
-- 查询播放进度中位数
ranked_play_ratio AS
(
    SELECT
        recommendation_method,
        play_ratio_raw,
        ROW_NUMBER() OVER (
            PARTITION BY recommendation_method
            ORDER BY play_ratio_raw
        ) AS rn,
        COUNT(*) OVER (PARTITION BY recommendation_method) AS n
    FROM same_period_base
    WHERE play_ratio_raw IS NOT NULL
),
play_ratio_median AS
(
    SELECT
        recommendation_method,
        AVG(play_ratio_raw) AS median_play_ratio
    FROM ranked_play_ratio
    WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
    GROUP BY recommendation_method
),
-- 相对指标 SQL
actual_metrics AS
(
    SELECT
        recommendation_method,
        MIN(date_clean) AS min_date,
        MAX(date_clean) AS max_date,
        COUNT(*) AS recommendation_records,
        COUNT(DISTINCT user_id) AS unique_users,
        COUNT(DISTINCT video_id) AS unique_videos,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(is_like) * 100.0 AS like_rate_pct,
        AVG(is_comment) * 100.0 AS comment_rate_pct,
        AVG(is_follow) * 100.0 AS follow_rate_pct,
        AVG(is_forward) * 100.0 AS forward_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct,
        AVG(play_time_seconds) AS mean_play_time_seconds,
        AVG(play_ratio_raw) AS mean_play_ratio,
        AVG(play_ratio_raw >= 1) * 100.0 AS ratio_ge_1_pct
    FROM same_period_base
    GROUP BY recommendation_method
),
-- 相对指标 python对应值
python_baseline AS
(
    SELECT
        'standard' AS recommendation_method,
        289119 AS recommendation_records,
        25877 AS unique_users,
        6618 AS unique_videos,
        45.1171 AS click_rate_pct,
        31.8329 AS long_view_rate_pct,
        14.3247 AS complete_play_rate_pct,
        2.1431 AS interaction_rate_pct,
        4.831 AS median_play_time_seconds,
        0.095467 AS median_play_ratio,
        14.3247 AS ratio_ge_1_pct

    UNION ALL

    SELECT
        'random',
        1186049,
        27285,
        7583,
        17.6160,
        8.4962,
        3.3187,
        0.5574,
        2.091,
        0.034799,
        3.3187
)
SELECT
    a.recommendation_method,
    a.min_date,
    a.max_date,
    a.recommendation_records,
    a.unique_users,
    a.unique_videos,
    ROUND(a.click_rate_pct, 4) AS click_rate_pct,
    ROUND(a.long_view_rate_pct, 4) AS long_view_rate_pct,
    ROUND(a.complete_play_rate_pct, 4) AS complete_play_rate_pct,
    ROUND(a.like_rate_pct, 4) AS like_rate_pct,
    ROUND(a.comment_rate_pct, 4) AS comment_rate_pct,
    ROUND(a.follow_rate_pct, 4) AS follow_rate_pct,
    ROUND(a.forward_rate_pct, 4) AS forward_rate_pct,
    ROUND(a.interaction_rate_pct, 4) AS interaction_rate_pct,
    ROUND(pt.median_play_time_seconds, 3) AS median_play_time_seconds,
    ROUND(a.mean_play_time_seconds, 3) AS mean_play_time_seconds,
    ROUND(pr.median_play_ratio, 6) AS median_play_ratio,
    ROUND(a.mean_play_ratio, 6) AS mean_play_ratio,
    ROUND(a.ratio_ge_1_pct, 4) AS ratio_ge_1_pct,
    CASE
        WHEN a.recommendation_records = p.recommendation_records
         AND a.unique_users = p.unique_users
         AND a.unique_videos = p.unique_videos
         AND ROUND(a.click_rate_pct, 4) = ROUND(p.click_rate_pct, 4)
         AND ROUND(a.long_view_rate_pct, 4) = ROUND(p.long_view_rate_pct, 4)
         AND ROUND(a.complete_play_rate_pct, 4) = ROUND(p.complete_play_rate_pct, 4)
         AND ROUND(a.interaction_rate_pct, 4) = ROUND(p.interaction_rate_pct, 4)
         AND ROUND(pt.median_play_time_seconds, 3)
             = ROUND(p.median_play_time_seconds, 3)
         AND ROUND(pr.median_play_ratio, 6) = ROUND(p.median_play_ratio, 6)
         AND ROUND(a.ratio_ge_1_pct, 4) = ROUND(p.ratio_ge_1_pct, 4)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS python_reconciliation_result
FROM actual_metrics AS a
LEFT JOIN play_time_median AS pt
    ON a.recommendation_method = pt.recommendation_method
LEFT JOIN play_ratio_median AS pr
    ON a.recommendation_method = pr.recommendation_method
LEFT JOIN python_baseline AS p
    ON a.recommendation_method = p.recommendation_method
ORDER BY FIELD(a.recommendation_method, 'standard', 'random');


-- ============================================================
-- 完成标准：
--   1. 第 0 部分返回两个分析明细视图；
--   2. 第 1、2、3 部分按约定业务精度核验，check_result 全部为 PASS；
--   3. 第 8 部分两种推荐方式的 python_reconciliation_result 均为 PASS；
--   4. 第 4～7 部分用于 SQL 分组分析，不要求与 Python 逐行重复核验；
--   5. 标准推荐与随机推荐的差异仅作描述性解释，不得写成因果结论。
-- ============================================================
