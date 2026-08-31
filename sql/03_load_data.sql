-- ============================================================
-- KuaiRand-Pure：全量刷新四张 MySQL 基础表
-- 前置条件：
--   1. 已执行 01_create_database.sql 和 02_create_tables.sql；
--   2. 已生成 data/mysql_import 下的四张 CSV；
--   3. MySQL 服务端 local_infile 已开启；
--   4. DBeaver 驱动属性 allowLoadLocalInfile 已设为 true，并已重新连接。
--
-- 重要说明：
--   1. 本脚本采用“先清空目标表，再完整导入 CSV”的全量刷新方式；
--   2. 重复执行整份脚本，最终数据不会重复追加；
--   3. 每张表的 TRUNCATE 与紧随其后的 LOAD DATA 必须作为一个完整区块执行；
--   4. 不要只选中 LOAD DATA 单独执行，否则仍可能重复追加数据；
--   5. 任一导入失败后，应停止后续分析，并根据末尾行数核验结果排查。
--   6. 下方 E:/path/to/KuaiRand_Pure 为公开仓库示例路径，执行前请替换为本机项目绝对路径。
-- ============================================================

USE `kuairand_analytics`;



-- ------------------------------------------------------------
-- 0. 导入前检查
-- local_infile_enabled 应为 ON 或 1。
-- rows_before 仅用于记录刷新前状态；随后各表会在自己的导入区块内被清空。
-- ------------------------------------------------------------
SHOW VARIABLES LIKE 'local_infile';

SELECT 'fact_standard_behavior' AS `table_name`, COUNT(*) AS `rows_before` FROM `fact_standard_behavior`
UNION ALL
SELECT 'fact_random_behavior', COUNT(*) FROM `fact_random_behavior`
UNION ALL
SELECT 'dim_user', COUNT(*) FROM `dim_user`
UNION ALL
SELECT 'dim_video', COUNT(*) FROM `dim_video`;

-- ------------------------------------------------------------
-- 1. 导入标准推荐行为事实表
-- CSV 不包含 record_id；该字段由 MySQL AUTO_INCREMENT 自动生成。
-- TRUNCATE 会删除该表旧数据并重置 AUTO_INCREMENT，随后立即重新完整导入。
-- ------------------------------------------------------------
TRUNCATE TABLE `fact_standard_behavior`;

LOAD DATA LOCAL INFILE
    'E:/path/to/KuaiRand_Pure/data/mysql_import/fact_standard_behavior.csv'
INTO TABLE `fact_standard_behavior`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    `user_id`,
    `video_id`,
    `date`,
    `hourmin`,
    `time_ms`,
    `is_click`,
    `is_like`,
    `is_follow`,
    `is_comment`,
    `is_forward`,
    `is_hate`,
    `long_view`,
    `play_time_ms`,
    `duration_ms`,
    `profile_stay_time`,
    `comment_stay_time`,
    `is_profile_enter`,
    `is_rand`,
    `tab`,
    `is_duration_missing`,
    `duration_ms_clean`,
    `play_ratio_raw`,
    `is_complete_play`,
    `date_clean`,
    `log_source`
);

-- ------------------------------------------------------------
-- 2. 导入随机推荐行为事实表
-- CSV 不包含 record_id；该字段由 MySQL AUTO_INCREMENT 自动生成。
-- TRUNCATE 与 LOAD DATA 必须一起执行。
-- ------------------------------------------------------------
TRUNCATE TABLE `fact_random_behavior`;

LOAD DATA LOCAL INFILE
    'E:/path/to/KuaiRand_Pure/data/mysql_import/fact_random_behavior.csv'
INTO TABLE `fact_random_behavior`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    `user_id`,
    `video_id`,
    `date`,
    `hourmin`,
    `time_ms`,
    `is_click`,
    `is_like`,
    `is_follow`,
    `is_comment`,
    `is_forward`,
    `is_hate`,
    `long_view`,
    `play_time_ms`,
    `duration_ms`,
    `profile_stay_time`,
    `comment_stay_time`,
    `is_profile_enter`,
    `is_rand`,
    `tab`,
    `is_duration_missing`,
    `duration_ms_clean`,
    `play_ratio_raw`,
    `is_complete_play`,
    `date_clean`,
    `log_source`
);

-- ------------------------------------------------------------
-- 3. 导入用户维度表
-- user_id 是 CSV 与数据库表共同使用的主键。
-- TRUNCATE 与 LOAD DATA 必须一起执行。
-- ------------------------------------------------------------
TRUNCATE TABLE `dim_user`;

LOAD DATA LOCAL INFILE
    'E:/path/to/KuaiRand_Pure/data/mysql_import/dim_user.csv'
INTO TABLE `dim_user`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    `user_id`,
    `user_active_degree`,
    `is_lowactive_period`,
    `is_live_streamer`,
    `is_video_author`,
    `follow_user_num`,
    `follow_user_num_range`,
    `fans_user_num`,
    `fans_user_num_range`,
    `friend_user_num`,
    `friend_user_num_range`,
    `register_days`,
    `register_days_range`,
    `onehot_feat0`,
    `onehot_feat1`,
    `onehot_feat2`,
    `onehot_feat3`,
    `onehot_feat4`,
    `onehot_feat5`,
    `onehot_feat6`,
    `onehot_feat7`,
    `onehot_feat8`,
    `onehot_feat9`,
    `onehot_feat10`,
    `onehot_feat11`,
    `onehot_feat12`,
    `onehot_feat13`,
    `onehot_feat14`,
    `onehot_feat15`,
    `onehot_feat16`,
    `onehot_feat17`,
    `is_live_streamer_clean`
);

-- ------------------------------------------------------------
-- 4. 导入视频维度表
-- tag 中可能包含逗号，因此使用 OPTIONALLY ENCLOSED BY '"' 解析引号。
-- TRUNCATE 与 LOAD DATA 必须一起执行。
-- ------------------------------------------------------------
TRUNCATE TABLE `dim_video`;

LOAD DATA LOCAL INFILE
    'E:/path/to/KuaiRand_Pure/data/mysql_import/dim_video.csv'
INTO TABLE `dim_video`
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '\\'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    `video_id`,
    `author_id`,
    `video_type`,
    `upload_dt`,
    `upload_type`,
    `visible_status`,
    `video_duration`,
    `server_width`,
    `server_height`,
    `music_id`,
    `music_type`,
    `tag`,
    `upload_date_clean`,
    `is_duration_missing`,
    `video_duration_seconds`,
    `music_type_clean`,
    `tag_clean`
);


-- ------------------------------------------------------------
-- 5. 导入后行数核验
-- 预期：
--   fact_standard_behavior = 1,414,622
--   fact_random_behavior   = 1,186,049
--   dim_user               =    27,285
--   dim_video              =     7,583
-- check_result 四行均为 PASS，才表示本次全量刷新行数核验通过。
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
    SELECT
        'fact_standard_behavior' AS `table_name`,
        COUNT(*) AS `actual_rows`,
        1414622 AS `expected_rows`
    FROM `fact_standard_behavior`

    UNION ALL

    SELECT
        'fact_random_behavior',
        COUNT(*),
        1186049
    FROM `fact_random_behavior`

    UNION ALL

    SELECT
        'dim_user',
        COUNT(*),
        27285
    FROM `dim_user`

    UNION ALL

    SELECT
        'dim_video',
        COUNT(*),
        7583
    FROM `dim_video`
) AS `row_count_check`;
