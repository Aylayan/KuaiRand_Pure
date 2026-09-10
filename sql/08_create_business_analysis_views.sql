-- ============================================================
-- KuaiRand-Pure：业务深化分析视图
--
-- 目标：
--   1. 固定 2022-04-22 至 2022-05-08 的同期比较口径；
--   2. 建立“曝光层 + 点击后质量”的推荐质量链；
--   3. 支持用户/内容分层比较；
--   4. 支持共同用户的等权配对验证。
--
-- 边界：
--   - 本脚本只创建或更新视图，不修改四张基础表；
--   - 标准推荐与随机推荐不是用户级随机 A/B 实验；
--   - 结果只能解释为同期历史样本中的观察性关联。
-- ============================================================

USE kuairand_analytics;


-- ------------------------------------------------------------
-- 1. 同期业务分析明细视图
-- 一行代表一条推荐记录；两种推荐方式保持独立标签。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_business_same_period_detail AS
SELECT
    record_id,
    user_id,
    video_id,
    date_clean,
    'standard' AS recommendation_method,
    is_click,
    long_view,
    is_complete_play,
    has_interaction,
    is_hate,
    is_profile_enter,
    play_time_seconds,
    play_ratio_raw,
    user_active_degree,
    register_days_group,
    duration_group,
    video_type,
    upload_type,
    screen_orientation
FROM vw_standard_analysis_detail
WHERE log_source = 'standard_0422_0508'
  AND date_clean BETWEEN DATE('2022-04-22') AND DATE('2022-05-08')

UNION ALL

SELECT
    record_id,
    user_id,
    video_id,
    date_clean,
    'random' AS recommendation_method,
    is_click,
    long_view,
    is_complete_play,
    has_interaction,
    is_hate,
    is_profile_enter,
    play_time_seconds,
    play_ratio_raw,
    user_active_degree,
    register_days_group,
    duration_group,
    video_type,
    upload_type,
    screen_orientation
FROM vw_random_analysis_detail
WHERE date_clean BETWEEN DATE('2022-04-22') AND DATE('2022-05-08');


-- ------------------------------------------------------------
-- 2. 推荐质量链
-- 曝光层指标与点击后条件指标并列，避免构造不成立的线性漏斗。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_business_quality_chain AS
SELECT
    recommendation_method,
    COUNT(*) AS recommendation_records,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT video_id) AS unique_videos,

    AVG(is_click) * 100.0 AS click_rate_pct,
    AVG(long_view) * 100.0 AS long_view_rate_pct,
    AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
    AVG(has_interaction) * 100.0 AS interaction_rate_pct,
    AVG(is_hate) * 100.0 AS hate_rate_pct,
    AVG(is_profile_enter) * 100.0 AS profile_enter_rate_pct,

    SUM(is_click = 1 AND long_view = 1)
        / NULLIF(SUM(is_click = 1), 0) * 100.0
        AS long_view_given_click_pct,

    SUM(is_click = 1 AND is_complete_play = 1)
        / NULLIF(SUM(is_click = 1 AND is_complete_play IS NOT NULL), 0)
        * 100.0 AS complete_play_given_click_pct,

    SUM(is_click = 1 AND has_interaction = 1)
        / NULLIF(SUM(is_click = 1), 0) * 100.0
        AS interaction_given_click_pct,

    SUM(is_click = 1 AND is_hate = 1)
        / NULLIF(SUM(is_click = 1), 0) * 100.0
        AS hate_given_click_pct
FROM vw_business_same_period_detail
GROUP BY recommendation_method;


-- ------------------------------------------------------------
-- 3. 用户与内容分层长表
-- 每行代表一种推荐方式 × 一个分层维度 × 一个分组。
-- stable_within_method 只表示该方法内部样本达到门槛；
-- 正式比较时，两种方法的对应分组都应为 1。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_business_segments AS
WITH segment_base AS
(
    SELECT
        recommendation_method,
        user_id,
        video_id,
        '用户活跃度' AS segment_dimension,
        COALESCE(CAST(user_active_degree AS CHAR), '缺失') AS segment_value,
        is_click,
        long_view,
        is_complete_play,
        has_interaction,
        is_hate
    FROM vw_business_same_period_detail

    UNION ALL

    SELECT
        recommendation_method,
        user_id,
        video_id,
        '注册时长',
        COALESCE(register_days_group, '缺失'),
        is_click,
        long_view,
        is_complete_play,
        has_interaction,
        is_hate
    FROM vw_business_same_period_detail

    UNION ALL

    SELECT
        recommendation_method,
        user_id,
        video_id,
        '视频时长',
        COALESCE(duration_group, '缺失'),
        is_click,
        long_view,
        is_complete_play,
        has_interaction,
        is_hate
    FROM vw_business_same_period_detail

    UNION ALL

    SELECT
        recommendation_method,
        user_id,
        video_id,
        '视频类型',
        COALESCE(CAST(video_type AS CHAR), '缺失'),
        is_click,
        long_view,
        is_complete_play,
        has_interaction,
        is_hate
    FROM vw_business_same_period_detail

    UNION ALL

    SELECT
        recommendation_method,
        user_id,
        video_id,
        '画面方向',
        COALESCE(screen_orientation, '缺失'),
        is_click,
        long_view,
        is_complete_play,
        has_interaction,
        is_hate
    FROM vw_business_same_period_detail
)
SELECT
    recommendation_method,
    segment_dimension,
    segment_value,
    COUNT(*) AS recommendation_records,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT video_id) AS unique_videos,
    AVG(is_click) * 100.0 AS click_rate_pct,
    AVG(long_view) * 100.0 AS long_view_rate_pct,
    AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
    AVG(has_interaction) * 100.0 AS interaction_rate_pct,
    AVG(is_hate) * 100.0 AS hate_rate_pct,
    CASE
        WHEN COUNT(*) >= 1000
         AND COUNT(DISTINCT user_id) >= 100
        THEN 1
        ELSE 0
    END AS stable_within_method
FROM segment_base
GROUP BY
    recommendation_method,
    segment_dimension,
    segment_value;


-- ------------------------------------------------------------
-- 4. 共同用户配对明细
-- 一行代表一个同时出现在标准推荐和随机推荐中的用户。
-- Python 使用该粒度进行用户级 Bootstrap 置信区间计算。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_business_user_paired AS
WITH user_method_rate AS
(
    SELECT
        recommendation_method,
        user_id,
        COUNT(*) AS recommendation_records,
        AVG(is_click) * 100.0 AS click_rate_pct,
        AVG(long_view) * 100.0 AS long_view_rate_pct,
        AVG(is_complete_play) * 100.0 AS complete_play_rate_pct,
        AVG(has_interaction) * 100.0 AS interaction_rate_pct,
        AVG(is_hate) * 100.0 AS hate_rate_pct
    FROM vw_business_same_period_detail
    GROUP BY recommendation_method, user_id
),
standard_user AS
(
    SELECT *
    FROM user_method_rate
    WHERE recommendation_method = 'standard'
),
random_user AS
(
    SELECT *
    FROM user_method_rate
    WHERE recommendation_method = 'random'
)
SELECT
    s.user_id,
    s.recommendation_records AS standard_records,
    r.recommendation_records AS random_records,
    s.click_rate_pct AS standard_click_rate_pct,
    r.click_rate_pct AS random_click_rate_pct,
    s.click_rate_pct - r.click_rate_pct AS click_gap_pp,
    s.long_view_rate_pct AS standard_long_view_rate_pct,
    r.long_view_rate_pct AS random_long_view_rate_pct,
    s.long_view_rate_pct - r.long_view_rate_pct AS long_view_gap_pp,
    s.complete_play_rate_pct AS standard_complete_play_rate_pct,
    r.complete_play_rate_pct AS random_complete_play_rate_pct,
    s.complete_play_rate_pct - r.complete_play_rate_pct AS complete_play_gap_pp,
    s.interaction_rate_pct AS standard_interaction_rate_pct,
    r.interaction_rate_pct AS random_interaction_rate_pct,
    s.interaction_rate_pct - r.interaction_rate_pct AS interaction_gap_pp,
    s.hate_rate_pct AS standard_hate_rate_pct,
    r.hate_rate_pct AS random_hate_rate_pct,
    s.hate_rate_pct - r.hate_rate_pct AS hate_gap_pp
FROM standard_user AS s
INNER JOIN random_user AS r
    ON s.user_id = r.user_id;


-- ------------------------------------------------------------
-- 5. 创建后核验
-- 预期同期明细 1,475,168 行，共同用户 25,877 人。
-- ------------------------------------------------------------
SELECT
    recommendation_method,
    COUNT(*) AS recommendation_records,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT video_id) AS unique_videos
FROM vw_business_same_period_detail
GROUP BY recommendation_method;

SELECT
    COUNT(*) AS paired_users,
    CASE
        WHEN COUNT(*) = 25877 THEN 'PASS'
        ELSE 'CHECK'
    END AS paired_user_check
FROM vw_metric_business_user_paired;

SELECT
    table_name AS business_view_name
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name IN
  (
      'vw_business_same_period_detail',
      'vw_metric_business_quality_chain',
      'vw_metric_business_segments',
      'vw_metric_business_user_paired'
  )
ORDER BY table_name;

