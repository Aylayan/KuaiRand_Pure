-- ============================================================
-- KuaiRand-Pure：创建 Power BI 稳定指标视图
--
-- 目标：
--   1. 将 06_sql_core_metrics_reconciliation.sql 中已核对的口径封装为视图；
--   2. 为 Power BI 提供总体、时间、用户、内容和推荐方式指标入口；
--   3. 避免在 Power BI 中重复编写复杂的清洗和聚合逻辑。
--
-- 使用说明：
--   1. 必须先保证 05 已执行成功，且 06 的核心核对结果均为 PASS；
--   2. 在 DBeaver 中使用 Alt + X 完整执行；
--   3. CREATE OR REPLACE VIEW 可重复执行，只更新视图定义；
--   4. 本脚本不会修改四张基础表或两个分析明细视图中的数据；
--   5. 本项目暂不单独建立指标视图质量核验脚本。
--
-- Power BI 使用建议：
--   - 比率字段统一以 *_rate_pct 命名，数值 46.4 表示 46.4%；
--   - 在 Power BI 中将 *_rate_pct 显示为小数，不要再次乘以 100；
--   - 视图保留完整计算精度，显示小数位由 Power BI 控制；
--   - 标准推荐是主分析，随机推荐只用于同期描述性比较。
-- ============================================================

USE kuairand_analytics;


-- ------------------------------------------------------------
-- 1. 标准推荐总体核心指标
-- 一行代表标准推荐整体表现，可用于 Power BI 首页 KPI 卡片。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_overall_standard AS
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
play_medians AS
(
    SELECT
        (
            SELECT AVG(play_time_seconds)
            FROM ranked_play_time
            WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
        ) AS median_play_time_seconds,
        (
            SELECT AVG(play_ratio_raw)
            FROM ranked_play_ratio
            WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))
        ) AS median_play_ratio
)
SELECT
    'standard' AS recommendation_method,
    MIN(d.date_clean) AS min_date,
    MAX(d.date_clean) AS max_date,
    COUNT(*) AS recommendation_records,
    COUNT(DISTINCT d.user_id) AS unique_users,
    COUNT(DISTINCT d.video_id) AS unique_videos,
    COUNT(d.is_complete_play) AS valid_duration_records,
    SUM(d.is_complete_play IS NULL) AS missing_duration_records,
    AVG(d.is_click) * 100.0 AS click_rate_pct,
    AVG(d.long_view) * 100.0 AS long_view_rate_pct,
    AVG(d.is_complete_play) * 100.0 AS complete_play_rate_pct,
    AVG(d.is_like) * 100.0 AS like_rate_pct,
    AVG(d.is_comment) * 100.0 AS comment_rate_pct,
    AVG(d.is_follow) * 100.0 AS follow_rate_pct,
    AVG(d.is_forward) * 100.0 AS forward_rate_pct,
    AVG(d.has_interaction) * 100.0 AS interaction_rate_pct,
    MAX(m.median_play_time_seconds) AS median_play_time_seconds,
    AVG(d.play_time_seconds) AS mean_play_time_seconds,
    MAX(m.median_play_ratio) AS median_play_ratio,
    AVG(d.play_ratio_raw) AS mean_play_ratio,
    AVG(d.play_ratio_raw >= 1) * 100.0 AS ratio_ge_1_pct
FROM vw_standard_analysis_detail AS d
CROSS JOIN play_medians AS m;


-- ------------------------------------------------------------
-- 2. 标准推荐每日指标
-- 一行代表一天，用于推荐量与行为率趋势图。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_daily_standard AS
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
    d.click_rate_pct,
    d.long_view_rate_pct,
    d.complete_play_rate_pct,
    d.like_rate_pct,
    d.comment_rate_pct,
    d.follow_rate_pct,
    d.forward_rate_pct,
    d.interaction_rate_pct,
    m.median_play_time_seconds
FROM daily_agg AS d
LEFT JOIN play_time_median AS m
    ON d.date_clean = m.date_clean;


-- ------------------------------------------------------------
-- 3. 标准推荐小时指标
-- 一行代表一个小时档位，用于 24 小时趋势图。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_hourly_standard AS
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
        COUNT(DISTINCT video_id) AS unique_videos,
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
    h.unique_videos,
    h.click_rate_pct,
    h.long_view_rate_pct,
    h.complete_play_rate_pct,
    h.interaction_rate_pct,
    m.median_play_time_seconds
FROM hourly_agg AS h
LEFT JOIN play_time_median AS m
    ON h.hour = m.hour;


-- ------------------------------------------------------------
-- 4. 标准推荐用户分层指标
-- 长表结构便于 Power BI 使用 segment_type 和 segment_value 作为切片器。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_user_segments_standard AS
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
    s.click_rate_pct,
    s.long_view_rate_pct,
    s.complete_play_rate_pct,
    s.interaction_rate_pct,
    m.median_play_time_seconds
FROM segment_agg AS s
LEFT JOIN play_time_median AS m
    ON s.segment_type = m.segment_type
   AND s.segment_value = m.segment_value;


-- ------------------------------------------------------------
-- 5. 标准推荐内容分层指标
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_content_segments_standard AS
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
    s.click_rate_pct,
    s.long_view_rate_pct,
    s.complete_play_rate_pct,
    s.interaction_rate_pct,
    m.median_play_time_seconds
FROM segment_agg AS s
LEFT JOIN play_time_median AS m
    ON s.segment_type = m.segment_type
   AND s.segment_value = m.segment_value;


-- ------------------------------------------------------------
-- 6. 同期标准推荐与随机推荐对比指标
-- 一行代表一种推荐方式，时间范围固定为 2022-04-22 至 2022-05-08。
-- 该视图只支持描述性比较，不支持因果或 A/B 实验结论。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_recommendation_comparison AS
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
comparison_agg AS
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
)
SELECT
    c.recommendation_method,
    c.min_date,
    c.max_date,
    c.recommendation_records,
    c.unique_users,
    c.unique_videos,
    c.click_rate_pct,
    c.long_view_rate_pct,
    c.complete_play_rate_pct,
    c.like_rate_pct,
    c.comment_rate_pct,
    c.follow_rate_pct,
    c.forward_rate_pct,
    c.interaction_rate_pct,
    pt.median_play_time_seconds,
    c.mean_play_time_seconds,
    pr.median_play_ratio,
    c.mean_play_ratio,
    c.ratio_ge_1_pct
FROM comparison_agg AS c
LEFT JOIN play_time_median AS pt
    ON c.recommendation_method = pt.recommendation_method
LEFT JOIN play_ratio_median AS pr
    ON c.recommendation_method = pr.recommendation_method;


-- ------------------------------------------------------------
-- 7. 创建结果清单
-- 这里只列出视图是否已经创建，不执行独立的指标质量核验。
-- ------------------------------------------------------------
SELECT
    table_name AS metric_view_name
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name IN
  (
      'vw_metric_overall_standard',
      'vw_metric_daily_standard',
      'vw_metric_hourly_standard',
      'vw_metric_user_segments_standard',
      'vw_metric_content_segments_standard',
      'vw_metric_recommendation_comparison'
  )
ORDER BY table_name;


-- ============================================================
-- 执行完成后，Power BI 主要连接以上六个 vw_metric_* 视图。
-- 如需查看明细或增加新的分组口径，仍可连接：
--   vw_standard_analysis_detail
--   vw_random_analysis_detail
--
-- 本项目当前不执行独立的指标视图质量核验；
-- 若后续修改 05、06 或 07 中任一指标口径，应重新执行 SQL-Python 核对。
-- ============================================================
