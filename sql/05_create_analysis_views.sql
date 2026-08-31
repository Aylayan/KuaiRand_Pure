-- ============================================================
-- KuaiRand-Pure：创建 SQL 分析视图
--
-- 目标：
--   1. 将事实表与用户、视频维度表进行多对一 LEFT JOIN；
--   2. 将 Python Notebook 中的常用分析字段统一翻译为 SQL；
--   3. 为后续 SQL 指标复算和 Power BI 提供稳定的数据入口。
--
-- 重要说明：
--   1. VIEW 是保存好的查询，不会复制四张基础表的数据；
--   2. 标准推荐和随机推荐继续建立为两个独立视图；
--   3. 两种推荐机制抽样方式不同，不能无条件合并计算总体指标；
--   4. CREATE OR REPLACE VIEW 可重复执行，只会更新视图定义；
--   5. 本脚本不会修改四张基础表中的任何一行数据。
-- 
-- 对象	           存储数据？	    vw/dim/fact 前缀
-- 物理表 (table)	   ✅           存真实数据，占用磁盘	dim_、fact_
-- 视图 (view)	   ❌           只存 SELECT 语句，实时计算vw_
-- ============================================================

USE kuairand_analytics;


-- ------------------------------------------------------------
-- 1. 创建标准推荐分析明细视图
-- 一行仍代表一条标准推荐行为记录。
-- LEFT JOIN 保留全部事实记录，不会因维度信息缺失而静默丢行。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_standard_analysis_detail AS
SELECT
    -- 记录标识与时间
    f.record_id,
    f.user_id,
    f.video_id,
    f.date_clean,
    f.hourmin,
    (f.hourmin DIV 100) AS hour,
    f.log_source,
    f.tab,
    f.is_rand,
    'standard' AS recommendation_method,

    -- 行为标记
    f.is_click,
    f.is_like,
    f.is_follow,
    f.is_comment,
    f.is_forward,
    f.is_hate,
    f.long_view,
    f.is_profile_enter,
    CASE
        WHEN f.is_like = 1
          OR f.is_comment = 1
          OR f.is_follow = 1
          OR f.is_forward = 1
        THEN 1
        ELSE 0
    END AS has_interaction,

    -- 播放与停留
    f.play_time_ms,
    (f.play_time_ms / 1000.0) AS play_time_seconds,
    f.duration_ms,
    f.is_duration_missing AS fact_is_duration_missing,
    f.duration_ms_clean,
    f.play_ratio_raw,
    f.is_complete_play,
    f.profile_stay_time,
    f.comment_stay_time,

    -- 用户维度
    u.user_active_degree,
    u.is_lowactive_period,
    u.is_live_streamer_clean,
    u.is_video_author,
    u.follow_user_num,
    u.follow_user_num_range,
    u.fans_user_num,
    u.fans_user_num_range,
    u.friend_user_num,
    u.friend_user_num_range,
    u.register_days,
    u.register_days_range,
    CASE
        WHEN u.register_days >= 0
         AND u.register_days < 180 THEN '半年以内'
        WHEN u.register_days >= 180
         AND u.register_days < 365 THEN '半年-1年'
        WHEN u.register_days >= 365
         AND u.register_days < 730 THEN '1-2年'
        WHEN u.register_days >= 730
         AND u.register_days < 1460 THEN '2-4年'
        WHEN u.register_days >= 1460 THEN '4年以上'
        ELSE NULL
    END AS register_days_group,

    -- 视频维度
    v.author_id,
    v.video_type,
    v.upload_date_clean,
    v.upload_type,
    v.visible_status,
    v.is_duration_missing AS video_is_duration_missing,
    v.video_duration_seconds,
    CASE
        WHEN v.video_duration_seconds >= 0
         AND v.video_duration_seconds < 15 THEN '0-15秒'
        WHEN v.video_duration_seconds >= 15
         AND v.video_duration_seconds < 30 THEN '15-30秒'
        WHEN v.video_duration_seconds >= 30
         AND v.video_duration_seconds < 60 THEN '30-60秒'
        WHEN v.video_duration_seconds >= 60
         AND v.video_duration_seconds < 120 THEN '60-120秒'
        WHEN v.video_duration_seconds >= 120 THEN '120秒及以上'
        ELSE NULL
    END AS duration_group,
    v.server_width,
    v.server_height,
    CASE
        WHEN v.server_width > v.server_height THEN '横屏'
        WHEN v.server_width < v.server_height THEN '竖屏'
        WHEN v.server_width = v.server_height THEN '方屏'
        ELSE NULL
    END AS screen_orientation,
    v.music_type_clean,
    v.tag_clean
FROM fact_standard_behavior AS f
LEFT JOIN dim_user AS u
    ON f.user_id = u.user_id
LEFT JOIN dim_video AS v
    ON f.video_id = v.video_id;


-- ------------------------------------------------------------
-- 2. 创建随机推荐分析明细视图
-- 字段和标准推荐视图保持同构，但数据来源仍然完全独立。
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_random_analysis_detail AS
SELECT
    -- 记录标识与时间
    f.record_id,
    f.user_id,
    f.video_id,
    f.date_clean,
    f.hourmin,
    (f.hourmin DIV 100) AS hour,
    f.log_source,
    'random' AS recommendation_method,
    f.tab,
    f.is_rand,

    -- 行为标记
    f.is_click,
    f.is_like,
    f.is_follow,
    f.is_comment,
    f.is_forward,
    f.is_hate,
    f.long_view,
    f.is_profile_enter,
    CASE
        WHEN f.is_like = 1
          OR f.is_comment = 1
          OR f.is_follow = 1
          OR f.is_forward = 1
        THEN 1
        ELSE 0
    END AS has_interaction,

    -- 播放与停留
    f.play_time_ms,
    (f.play_time_ms / 1000.0) AS play_time_seconds,
    f.duration_ms,
    f.is_duration_missing AS fact_is_duration_missing,
    f.duration_ms_clean,
    f.play_ratio_raw,
    f.is_complete_play,
    f.profile_stay_time,
    f.comment_stay_time,

    -- 用户维度
    u.user_active_degree,
    u.is_lowactive_period,
    u.is_live_streamer_clean,
    u.is_video_author,
    u.follow_user_num,
    u.follow_user_num_range,
    u.fans_user_num,
    u.fans_user_num_range,
    u.friend_user_num,
    u.friend_user_num_range,
    u.register_days,
    u.register_days_range,
    CASE
        WHEN u.register_days >= 0
         AND u.register_days < 180 THEN '半年以内'
        WHEN u.register_days >= 180
         AND u.register_days < 365 THEN '半年-1年'
        WHEN u.register_days >= 365
         AND u.register_days < 730 THEN '1-2年'
        WHEN u.register_days >= 730
         AND u.register_days < 1460 THEN '2-4年'
        WHEN u.register_days >= 1460 THEN '4年以上'
        ELSE NULL
    END AS register_days_group,

    -- 视频维度
    v.author_id,
    v.video_type,
    v.upload_date_clean,
    v.upload_type,
    v.visible_status,
    v.is_duration_missing AS video_is_duration_missing,
    v.video_duration_seconds,
    CASE
        WHEN v.video_duration_seconds >= 0
         AND v.video_duration_seconds < 15 THEN '0-15秒'
        WHEN v.video_duration_seconds >= 15
         AND v.video_duration_seconds < 30 THEN '15-30秒'
        WHEN v.video_duration_seconds >= 30
         AND v.video_duration_seconds < 60 THEN '30-60秒'
        WHEN v.video_duration_seconds >= 60
         AND v.video_duration_seconds < 120 THEN '60-120秒'
        WHEN v.video_duration_seconds >= 120 THEN '120秒及以上'
        ELSE NULL
    END AS duration_group,
    v.server_width,
    v.server_height,
    CASE
        WHEN v.server_width > v.server_height THEN '横屏'
        WHEN v.server_width < v.server_height THEN '竖屏'
        WHEN v.server_width = v.server_height THEN '方屏'
        ELSE NULL
    END AS screen_orientation,
    v.music_type_clean,
    v.tag_clean
FROM fact_random_behavior AS f
LEFT JOIN dim_user AS u
    ON f.user_id = u.user_id
LEFT JOIN dim_video AS v
    ON f.video_id = v.video_id;


-- ------------------------------------------------------------
-- 3. 视图创建后：结构与行数核验
-- 两个视图的行数必须与各自事实表完全一致。
-- ------------------------------------------------------------
SELECT
    view_name,
    view_rows,
    fact_rows,
    CASE WHEN view_rows = fact_rows THEN 'PASS' ELSE 'FAIL' END AS check_result
FROM
(
    SELECT
        'vw_standard_analysis_detail' AS view_name,
        (SELECT COUNT(*) FROM vw_standard_analysis_detail) AS view_rows,
        (SELECT COUNT(*) FROM fact_standard_behavior) AS fact_rows

    UNION ALL

    SELECT
        'vw_random_analysis_detail',
        (SELECT COUNT(*) FROM vw_random_analysis_detail),
        (SELECT COUNT(*) FROM fact_random_behavior)
) AS view_row_check;


-- ------------------------------------------------------------
-- 4. 视图创建后：派生字段逻辑核验
-- 所有 invalid 或 mismatch 字段都应为 0。

-- =：只要一边是NULL，结果直接返回NULL（判断失效）
-- <=>：可以正常比较 NULL，返回 1 (真) /0 (假)，不会得到 NULL.
-- ------------------------------------------------------------
SELECT
    view_name,
    invalid_hour_rows,
    invalid_interaction_rows,
    interaction_mismatch_rows,
    register_group_mismatch_rows,
    duration_group_mismatch_rows,
    orientation_mismatch_rows,
    CASE
        WHEN invalid_hour_rows = 0
         AND invalid_interaction_rows = 0
         AND interaction_mismatch_rows = 0
         AND register_group_mismatch_rows = 0
         AND duration_group_mismatch_rows = 0
         AND orientation_mismatch_rows = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS check_result
FROM
(
    SELECT
        'vw_standard_analysis_detail' AS view_name,
        SUM(hour NOT BETWEEN 0 AND 23) AS invalid_hour_rows,
        SUM(has_interaction NOT IN (0, 1)) AS invalid_interaction_rows,
        SUM(
            has_interaction
            <> (is_like = 1 OR is_comment = 1 OR is_follow = 1 OR is_forward = 1)
        ) AS interaction_mismatch_rows,
        SUM(
            NOT (
                register_days_group <=> CASE
                    WHEN register_days >= 0 AND register_days < 180 THEN '半年以内'
                    WHEN register_days >= 180 AND register_days < 365 THEN '半年-1年'
                    WHEN register_days >= 365 AND register_days < 730 THEN '1-2年'
                    WHEN register_days >= 730 AND register_days < 1460 THEN '2-4年'
                    WHEN register_days >= 1460 THEN '4年以上'
                    ELSE NULL
                END
            )
        ) AS register_group_mismatch_rows,
        SUM(
            NOT (
                duration_group <=> CASE
                    WHEN video_duration_seconds >= 0 AND video_duration_seconds < 15 THEN '0-15秒'
                    WHEN video_duration_seconds >= 15 AND video_duration_seconds < 30 THEN '15-30秒'
                    WHEN video_duration_seconds >= 30 AND video_duration_seconds < 60 THEN '30-60秒'
                    WHEN video_duration_seconds >= 60 AND video_duration_seconds < 120 THEN '60-120秒'
                    WHEN video_duration_seconds >= 120 THEN '120秒及以上'
                    ELSE NULL
                END
            )
        ) AS duration_group_mismatch_rows,
        SUM(
            NOT (
                screen_orientation <=> CASE
                    WHEN server_width > server_height THEN '横屏'
                    WHEN server_width < server_height THEN '竖屏'
                    WHEN server_width = server_height THEN '方屏'
                    ELSE NULL
                END
            )
        ) AS orientation_mismatch_rows
    FROM vw_standard_analysis_detail

    UNION ALL

    SELECT
        'vw_random_analysis_detail',
        SUM(hour NOT BETWEEN 0 AND 23),
        SUM(has_interaction NOT IN (0, 1)),
        SUM(
            has_interaction
            <> (is_like = 1 OR is_comment = 1 OR is_follow = 1 OR is_forward = 1)
        ),
        SUM(
            NOT (
                register_days_group <=> CASE
                    WHEN register_days >= 0 AND register_days < 180 THEN '半年以内'
                    WHEN register_days >= 180 AND register_days < 365 THEN '半年-1年'
                    WHEN register_days >= 365 AND register_days < 730 THEN '1-2年'
                    WHEN register_days >= 730 AND register_days < 1460 THEN '2-4年'
                    WHEN register_days >= 1460 THEN '4年以上'
                    ELSE NULL
                END
            )
        ),
        SUM(
            NOT (
                duration_group <=> CASE
                    WHEN video_duration_seconds >= 0 AND video_duration_seconds < 15 THEN '0-15秒'
                    WHEN video_duration_seconds >= 15 AND video_duration_seconds < 30 THEN '15-30秒'
                    WHEN video_duration_seconds >= 30 AND video_duration_seconds < 60 THEN '30-60秒'
                    WHEN video_duration_seconds >= 60 AND video_duration_seconds < 120 THEN '60-120秒'
                    WHEN video_duration_seconds >= 120 THEN '120秒及以上'
                    ELSE NULL
                END
            )
        ),
        SUM(
            NOT (
                screen_orientation <=> CASE
                    WHEN server_width > server_height THEN '横屏'
                    WHEN server_width < server_height THEN '竖屏'
                    WHEN server_width = server_height THEN '方屏'
                    ELSE NULL
                END
            )
        )
    FROM vw_random_analysis_detail
) AS derived_field_check;


-- ------------------------------------------------------------
-- 5. 查看视图字段结构和少量样例
-- LIMIT 5 只用于人工抽查，不代表统计结论。
-- ------------------------------------------------------------
SHOW FULL COLUMNS FROM vw_standard_analysis_detail;
SHOW FULL COLUMNS FROM vw_random_analysis_detail;

SELECT *
FROM vw_standard_analysis_detail
ORDER BY record_id
LIMIT 5;

SELECT *
FROM vw_random_analysis_detail
ORDER BY record_id
LIMIT 5;



-- ============================================================
-- 完成标准
--   1. 第3部分两个视图的行数检查均为 PASS；
--   2. 第4部分两个视图的派生字段检查均为 PASS；
--   3. 两个视图字段顺序一致，便于后续复用同一套指标SQL；
--   4. 后续同周期比较只比较 2022-04-22 至 2022-05-08，
--      且只能解释为描述性差异，不能写成随机推荐导致了某种结果。
-- ============================================================
