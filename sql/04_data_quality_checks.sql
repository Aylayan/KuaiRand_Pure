-- ============================================================
-- KuaiRand-Pure：MySQL 导入后数据质量核验
--
-- 使用方法：
--   1. 先完整执行 03_load_data.sql；
--   2. 再在 DBeaver 中整份执行本脚本（Alt + X）；
--   3. 依次查看各结果页签。check_result 应全部为 PASS；
--   4. 本脚本只读取数据，不会执行 TRUNCATE、DELETE、UPDATE 或 INSERT。
--
-- 注意：
--   两张事实表合计约 260 万行，部分检查需要全表扫描。
--   DBeaver 执行期间可能暂时显示 0%，请等待脚本完成，不要重复启动。
-- ============================================================

USE `kuairand_analytics`;


-- ------------------------------------------------------------
-- 1. 表规模核验
-- 目的：确认导入后的行数与四张清洗后 Parquet 完全一致。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `actual_rows`,
    `expected_rows`,
    CASE
        WHEN `actual_rows` = `expected_rows` THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT 'fact_standard_behavior' AS `table_name`, COUNT(*) AS `actual_rows`, 1414622 AS `expected_rows`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT 'fact_random_behavior', COUNT(*), 1186049
    FROM `fact_random_behavior`

    UNION ALL

    SELECT 'dim_user', COUNT(*), 27285
    FROM `dim_user`

    UNION ALL

    SELECT 'dim_video', COUNT(*), 7583
    FROM `dim_video`
) AS `row_count_check`;


-- ------------------------------------------------------------
-- 2. 主键完整性核验
-- 目的：确认主键不存在空值或重复值。
-- 说明：MySQL 主键本身会强制唯一且非空，本段再次以结果形式留存证据。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `total_rows`,
    `distinct_keys`,
    `null_keys`,
    CASE
        WHEN `total_rows` = `distinct_keys` AND `null_keys` = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior.record_id' AS `table_name`,
        COUNT(*) AS `total_rows`,
        COUNT(DISTINCT `record_id`) AS `distinct_keys`,
        SUM(`record_id` IS NULL) AS `null_keys`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior.record_id',
        COUNT(*),
        COUNT(DISTINCT `record_id`),
        SUM(`record_id` IS NULL)
    FROM `fact_random_behavior`

    UNION ALL

    SELECT
        'dim_user.user_id',
        COUNT(*),
        COUNT(DISTINCT `user_id`),
        SUM(`user_id` IS NULL)
    FROM `dim_user`

    UNION ALL

    SELECT
        'dim_video.video_id',
        COUNT(*),
        COUNT(DISTINCT `video_id`),
        SUM(`video_id` IS NULL)
    FROM `dim_video`
) AS `primary_key_check`;


-- ------------------------------------------------------------
-- 3. 缺失值数量核验
-- 目的：确认 CSV 中的 \N 被正确导入为 MySQL NULL，而不是数字 0 或空字符串。
--
-- 3.1 两张事实表
-- 三个派生字段的缺失数量应完全一致，并等于视频时长缺失记录数。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `duration_clean_nulls`,
    `ratio_nulls`,
    `complete_play_nulls`,
    `expected_nulls`,
    CASE
        WHEN `duration_clean_nulls` = `expected_nulls`
         AND `ratio_nulls` = `expected_nulls`
         AND `complete_play_nulls` = `expected_nulls`
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        SUM(`duration_ms_clean` IS NULL) AS `duration_clean_nulls`,
        SUM(`play_ratio_raw` IS NULL) AS `ratio_nulls`,
        SUM(`is_complete_play` IS NULL) AS `complete_play_nulls`,
        28860 AS `expected_nulls`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        SUM(`duration_ms_clean` IS NULL),
        SUM(`play_ratio_raw` IS NULL),
        SUM(`is_complete_play` IS NULL),
        36920
    FROM `fact_random_behavior`
) AS `fact_null_check`;


-- 3.2 用户维度表
SELECT
    `onehot_feat4_nulls`,
    `onehot_feat12_nulls`,
    `onehot_feat13_nulls`,
    `onehot_feat14_nulls`,
    `onehot_feat15_nulls`,
    `onehot_feat16_nulls`,
    `onehot_feat17_nulls`,
    `live_streamer_clean_nulls`,
    CASE
        WHEN `onehot_feat4_nulls` = 874
         AND `onehot_feat12_nulls` = 714
         AND `onehot_feat13_nulls` = 714
         AND `onehot_feat14_nulls` = 714
         AND `onehot_feat15_nulls` = 714
         AND `onehot_feat16_nulls` = 714
         AND `onehot_feat17_nulls` = 714
         AND `live_streamer_clean_nulls` = 21127
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        SUM(`onehot_feat4` IS NULL) AS `onehot_feat4_nulls`,
        SUM(`onehot_feat12` IS NULL) AS `onehot_feat12_nulls`,
        SUM(`onehot_feat13` IS NULL) AS `onehot_feat13_nulls`,
        SUM(`onehot_feat14` IS NULL) AS `onehot_feat14_nulls`,
        SUM(`onehot_feat15` IS NULL) AS `onehot_feat15_nulls`,
        SUM(`onehot_feat16` IS NULL) AS `onehot_feat16_nulls`,
        SUM(`onehot_feat17` IS NULL) AS `onehot_feat17_nulls`,
        SUM(`is_live_streamer_clean` IS NULL) AS `live_streamer_clean_nulls`
    FROM `dim_user`
) AS `user_null_check`;


-- 3.3 视频维度表
SELECT
    `video_duration_nulls`,
    `music_type_nulls`,
    `tag_nulls`,
    `duration_seconds_nulls`,
    `music_type_clean_nulls`,
    `music_type_unknowns`,
    CASE
        WHEN `video_duration_nulls` = 239
         AND `music_type_nulls` = 203
         AND `tag_nulls` = 96
         AND `duration_seconds_nulls` = 239
         AND `music_type_clean_nulls` = 0
         AND `music_type_unknowns` = 203
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        SUM(`video_duration` IS NULL) AS `video_duration_nulls`,
        SUM(`music_type` IS NULL) AS `music_type_nulls`,
        SUM(`tag` IS NULL) AS `tag_nulls`,
        SUM(`video_duration_seconds` IS NULL) AS `duration_seconds_nulls`,
        SUM(`music_type_clean` IS NULL) AS `music_type_clean_nulls`,
        SUM(`music_type_clean` = 'UNKNOWN') AS `music_type_unknowns`
    FROM `dim_video`
) AS `video_null_check`;


-- ------------------------------------------------------------
-- 4. 0/1 标记字段取值域核验
-- 目的：确认布尔标记没有出现 0、1、NULL 之外的异常数字。
-- is_complete_play 允许为 NULL，因此只检查它的非空记录。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `invalid_values`,
    CASE WHEN `invalid_values` = 0 THEN 'PASS' ELSE 'FAIL' END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        SUM(`is_click` NOT IN (0, 1))
      + SUM(`is_like` NOT IN (0, 1))
      + SUM(`is_follow` NOT IN (0, 1))
      + SUM(`is_comment` NOT IN (0, 1))
      + SUM(`is_forward` NOT IN (0, 1))
      + SUM(`is_hate` NOT IN (0, 1))
      + SUM(`long_view` NOT IN (0, 1))
      + SUM(`is_profile_enter` NOT IN (0, 1))
      + SUM(`is_rand` NOT IN (0, 1))
      + SUM(`is_duration_missing` NOT IN (0, 1))
      + SUM(`is_complete_play` IS NOT NULL AND `is_complete_play` NOT IN (0, 1)) AS `invalid_values`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        SUM(`is_click` NOT IN (0, 1))
      + SUM(`is_like` NOT IN (0, 1))
      + SUM(`is_follow` NOT IN (0, 1))
      + SUM(`is_comment` NOT IN (0, 1))
      + SUM(`is_forward` NOT IN (0, 1))
      + SUM(`is_hate` NOT IN (0, 1))
      + SUM(`long_view` NOT IN (0, 1))
      + SUM(`is_profile_enter` NOT IN (0, 1))
      + SUM(`is_rand` NOT IN (0, 1))
      + SUM(`is_duration_missing` NOT IN (0, 1))
      + SUM(`is_complete_play` IS NOT NULL AND `is_complete_play` NOT IN (0, 1))
    FROM `fact_random_behavior`

    UNION ALL

    SELECT
        'dim_user',
        SUM(`is_lowactive_period` NOT IN (0, 1))
      + SUM(`is_video_author` NOT IN (0, 1))
      + SUM(`is_live_streamer_clean` IS NOT NULL AND `is_live_streamer_clean` NOT IN (0, 1))
    FROM `dim_user`

    UNION ALL

    SELECT
        'dim_video',
        SUM(`is_duration_missing` NOT IN (0, 1))
    FROM `dim_video`
) AS `binary_domain_check`;


-- ------------------------------------------------------------
-- 5. 推荐方式与日志来源核验
-- 目的：标准表只能保存标准推荐记录，随机表只能保存随机推荐记录。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `wrong_is_rand_rows`,
    `wrong_source_rows`,
    CASE
        WHEN `wrong_is_rand_rows` = 0 AND `wrong_source_rows` = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        SUM(`is_rand` <> 0) AS `wrong_is_rand_rows`,
        SUM(`log_source` NOT IN ('standard_0408_0421', 'standard_0422_0508')) AS `wrong_source_rows`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        SUM(`is_rand` <> 1),
        SUM(`log_source` <> 'random_0422_0508')
    FROM `fact_random_behavior`
) AS `recommendation_type_check`;


-- 5.1 日志来源的精确行数
SELECT
    `log_source`,
    `actual_rows`,
    `expected_rows`,
    CASE WHEN `actual_rows` = `expected_rows` THEN 'PASS' ELSE 'FAIL' END AS `check_result`
FROM
(
    SELECT
        'standard_0408_0421' AS `log_source`,
        SUM(`log_source` = 'standard_0408_0421') AS `actual_rows`,
        1125503 AS `expected_rows`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'standard_0422_0508',
        SUM(`log_source` = 'standard_0422_0508'),
        289119
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'random_0422_0508',
        SUM(`log_source` = 'random_0422_0508'),
        1186049
    FROM `fact_random_behavior`
) AS `source_count_check`;


-- ------------------------------------------------------------
-- 6. 日期与小时档位核验
-- 目的：检查日期范围、原始日期和清洗日期的一致性，以及小时档位是否合法。
-- hourmin 合法范围为 0、100、200……2300。
-- 本项目不再使用 time_ms 反推日期，因为数据说明未承诺其时区口径一致。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `actual_min_date`,
    `actual_max_date`,
    `date_mismatch_rows`,
    `invalid_hour_rows`,
    CASE
        WHEN `actual_min_date` = `expected_min_date`
         AND `actual_max_date` = `expected_max_date`
         AND `date_mismatch_rows` = 0
         AND `invalid_hour_rows` = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        MIN(`date_clean`) AS `actual_min_date`,
        MAX(`date_clean`) AS `actual_max_date`,
        DATE('2022-04-09') AS `expected_min_date`,
        DATE('2022-05-08') AS `expected_max_date`,
        SUM(`date` <> CAST(DATE_FORMAT(`date_clean`, '%Y%m%d') AS UNSIGNED)) AS `date_mismatch_rows`,
        SUM(`hourmin` < 0 OR `hourmin` > 2300 OR MOD(`hourmin`, 100) <> 0) AS `invalid_hour_rows`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        MIN(`date_clean`),
        MAX(`date_clean`),
        DATE('2022-04-22'),
        DATE('2022-05-08'),
        SUM(`date` <> CAST(DATE_FORMAT(`date_clean`, '%Y%m%d') AS UNSIGNED)), #先把2022-04-22转换成”20220422“，再用CAST(... AS UNSIGNED)把字符串转换为非负整数。
        SUM(`hourmin` < 0 OR `hourmin` > 2300 OR MOD(`hourmin`, 100) <> 0)
    FROM `fact_random_behavior`
) AS `fact_time_check`;


-- 6.1 视频上传日期范围
SELECT
    MIN(`upload_date_clean`) AS `actual_min_date`,
    MAX(`upload_date_clean`) AS `actual_max_date`,
    DATE('2022-04-09') AS `expected_min_date`,
    DATE('2022-04-11') AS `expected_max_date`,
    CASE
        WHEN MIN(`upload_date_clean`) = DATE('2022-04-09')
         AND MAX(`upload_date_clean`) = DATE('2022-04-11')
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM `dim_video`;


-- ------------------------------------------------------------
-- 7. 两张事实表的清洗字段逻辑核验
-- 目的：确认 MySQL 中的派生字段仍符合 Python 清洗口径。
-- 所有 mismatch 字段都应为 0。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `duration_flag_mismatch`,
    `duration_clean_null_mismatch`,
    `ratio_null_mismatch`,
    `complete_null_mismatch`,
    `ratio_value_mismatch`,
    `complete_value_mismatch`,
    CASE
        WHEN `duration_flag_mismatch` = 0
         AND `duration_clean_null_mismatch` = 0
         AND `ratio_null_mismatch` = 0
         AND `complete_null_mismatch` = 0
         AND `ratio_value_mismatch` = 0
         AND `complete_value_mismatch` = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        SUM((`duration_ms` <= 0) <> (`is_duration_missing` = 1)) AS `duration_flag_mismatch`,
        SUM((`duration_ms_clean` IS NULL) <> (`is_duration_missing` = 1)) AS `duration_clean_null_mismatch`,
        SUM((`play_ratio_raw` IS NULL) <> (`is_duration_missing` = 1)) AS `ratio_null_mismatch`,
        SUM((`is_complete_play` IS NULL) <> (`is_duration_missing` = 1)) AS `complete_null_mismatch`,
        SUM(
            `duration_ms_clean` IS NOT NULL
            AND ABS(
                `play_ratio_raw`
                - (`play_time_ms` * 1e0 / NULLIF(`duration_ms_clean`, 0))
            ) > GREATEST(
                1e-12,
                ABS(`play_ratio_raw`) * 1e-12
            )
        ) AS `ratio_value_mismatch`,
        SUM(
            `duration_ms_clean` IS NOT NULL
            AND `is_complete_play` <> (`play_time_ms` >= `duration_ms_clean`)
        ) AS `complete_value_mismatch`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        SUM((`duration_ms` <= 0) <> (`is_duration_missing` = 1)),
        SUM((`duration_ms_clean` IS NULL) <> (`is_duration_missing` = 1)),
        SUM((`play_ratio_raw` IS NULL) <> (`is_duration_missing` = 1)),
        SUM((`is_complete_play` IS NULL) <> (`is_duration_missing` = 1)),
        SUM(
            `duration_ms_clean` IS NOT NULL
            AND ABS(
                `play_ratio_raw`
                - (`play_time_ms` * 1e0 / NULLIF(`duration_ms_clean`, 0))
            ) > GREATEST(
                1e-12,
                ABS(`play_ratio_raw`) * 1e-12
            )
        ),
        SUM(
            `duration_ms_clean` IS NOT NULL
            AND `is_complete_play` <> (`play_time_ms` >= `duration_ms_clean`)
        )
    FROM `fact_random_behavior`
) AS `fact_cleaning_logic_check`;


-- ------------------------------------------------------------
-- 8. 用户维度表的清洗逻辑核验
-- -124 是 is_live_streamer 原字段中的未知哨兵值；清洗后应变成 NULL。
-- ------------------------------------------------------------
SELECT
    `sentinel_minus124_rows`,
    `clean_null_rows`,
    `clean_value_mismatch`,
    CASE
        WHEN `sentinel_minus124_rows` = 21127
         AND `clean_null_rows` = 21127
         AND `clean_value_mismatch` = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        SUM(`is_live_streamer` = -124) AS `sentinel_minus124_rows`,
        SUM(`is_live_streamer_clean` IS NULL) AS `clean_null_rows`,
        SUM(
            NOT (
                `is_live_streamer_clean`
                <=> IF(`is_live_streamer` = -124, NULL, `is_live_streamer`)
            )
        ) AS `clean_value_mismatch`
    FROM `dim_user`
) AS `user_cleaning_logic_check`;


-- ------------------------------------------------------------
-- 9. 视频维度表的清洗逻辑核验
-- 目的：验证时长、音乐类型和标签的清洗结果。
-- ------------------------------------------------------------
SELECT
    `duration_flag_mismatch`,
    `duration_seconds_null_mismatch`,
    `duration_seconds_value_mismatch`,
    `music_type_clean_mismatch`,
    `tag_clean_mismatch`,
    CASE
        WHEN `duration_flag_mismatch` = 0
         AND `duration_seconds_null_mismatch` = 0
         AND `duration_seconds_value_mismatch` = 0
         AND `music_type_clean_mismatch` = 0
         AND `tag_clean_mismatch` = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        SUM((`video_duration` IS NULL) <> (`is_duration_missing` = 1)) AS `duration_flag_mismatch`,
        SUM((`video_duration_seconds` IS NULL) <> (`is_duration_missing` = 1)) AS `duration_seconds_null_mismatch`,
        SUM(
            `video_duration` IS NOT NULL
            AND ABS(`video_duration_seconds` - `video_duration` / 1000) > 0.0005
        ) AS `duration_seconds_value_mismatch`,
        SUM(
            NOT (
                `music_type_clean` <=> COALESCE(CAST(`music_type` AS CHAR), 'UNKNOWN')
            )
        ) AS `music_type_clean_mismatch`,
        SUM(NOT (`tag_clean` <=> COALESCE(`tag`, 'UNKNOWN'))) AS `tag_clean_mismatch`
    FROM `dim_video`
) AS `video_cleaning_logic_check`;


-- ------------------------------------------------------------
-- 10. 事实表与维度表关联完整性核验
-- 目的：确认每条行为记录都能找到对应用户和视频。
-- 四个 orphan 字段都应为 0。
-- ------------------------------------------------------------
SELECT
    `table_name`,
    `user_orphan_rows`,
    `video_orphan_rows`,
    CASE
        WHEN `user_orphan_rows` = 0 AND `video_orphan_rows` = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS `check_result`
FROM
(
    SELECT
        'fact_standard_behavior' AS `table_name`,
        SUM(`u`.`user_id` IS NULL) AS `user_orphan_rows`,
        SUM(`v`.`video_id` IS NULL) AS `video_orphan_rows`
    FROM `fact_standard_behavior` AS `f`
    LEFT JOIN `dim_user` AS `u`
        ON `f`.`user_id` = `u`.`user_id`
    LEFT JOIN `dim_video` AS `v`
        ON `f`.`video_id` = `v`.`video_id`

    UNION ALL

    SELECT
        'fact_random_behavior',
        SUM(`u`.`user_id` IS NULL),
        SUM(`v`.`video_id` IS NULL)
    FROM `fact_random_behavior` AS `f`
    LEFT JOIN `dim_user` AS `u`
        ON `f`.`user_id` = `u`.`user_id`
    LEFT JOIN `dim_video` AS `v`
        ON `f`.`video_id` = `v`.`video_id`
) AS `relationship_check`;


-- ------------------------------------------------------------
-- 11. 索引完整性检查
--
-- 检查目的：
-- 确认四张业务表中应有的主键和普通索引是否都已成功创建，
-- 避免后续筛选、关联和日期查询因缺少索引而降低效率。
--
-- 检查逻辑：
-- 1. 子查询 e 使用 UNION ALL 手动构造“预期索引清单”；
-- 2. 子查询 s 从 information_schema.statistics 中读取
--    kuairand_analytics 数据库实际存在的索引；
-- 3. DISTINCT 用于消除联合索引在系统表中的多行记录；
-- 4. 使用表名和索引名作为连接条件进行 LEFT JOIN，
--    保留全部预期索引，即使某个索引实际不存在也不会丢行；
-- 5. 若 s.index_name 不为 NULL，说明索引存在，返回 PASS；
--    若为 NULL，说明预期索引未找到，返回 FAIL；
-- 6. 最后按照表名和索引名排序，方便逐项查看结果。
--
-- 别名说明：
-- e = expected indexes，表示预期索引清单；
-- s = statistics，表示MySQL系统目录中的实际索引清单。
--
-- 预期结果：
-- 所有 check_result 均应为 PASS。
-- 本检查只验证“表名和索引名是否存在”，不验证联合索引内部
-- 包含的字段、字段顺序以及索引是否真正被查询执行计划使用。
-- ------------------------------------------------------------
-- ------------------------------------------------------------
SELECT
    `e`.`table_name`,
    `e`.`index_name`,
    CASE WHEN `s`.`index_name` IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS `check_result`
FROM
(
    SELECT 'fact_standard_behavior' AS `table_name`, 'PRIMARY' AS `index_name`
    UNION ALL SELECT 'fact_standard_behavior', 'idx_std_user_id'
    UNION ALL SELECT 'fact_standard_behavior', 'idx_std_video_id'
    UNION ALL SELECT 'fact_standard_behavior', 'idx_std_date_hour'
    UNION ALL SELECT 'fact_random_behavior', 'PRIMARY'
    UNION ALL SELECT 'fact_random_behavior', 'idx_rand_user_id'
    UNION ALL SELECT 'fact_random_behavior', 'idx_rand_video_id'
    UNION ALL SELECT 'fact_random_behavior', 'idx_rand_date_hour'
    UNION ALL SELECT 'dim_user', 'PRIMARY'
    UNION ALL SELECT 'dim_video', 'PRIMARY'
    UNION ALL SELECT 'dim_video', 'idx_video_author_id'
) AS `e`
LEFT JOIN
(
    SELECT DISTINCT `table_name`, `index_name`
    FROM `information_schema`.`statistics`
    WHERE `table_schema` = 'kuairand_analytics'
) AS `s`
    ON `e`.`table_name` = `s`.`table_name`
   AND `e`.`index_name` = `s`.`index_name`
ORDER BY `e`.`table_name`, `e`.`index_name`;


-- ============================================================
-- 判定标准
-- 上述各结果页签的 check_result 全部为 PASS，表示：
--   1. 四张表完整导入且主键正常；
--   2. CSV 缺失值被正确保留为 MySQL NULL；
--   3. 0/1字段、日期、日志来源和清洗字段逻辑正确；
--   4. 两张事实表与用户、视频维度表能够完整关联；
--   5. 后续 SQL 分析所需关键索引存在。
-- ============================================================
