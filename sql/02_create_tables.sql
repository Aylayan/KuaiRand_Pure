-- ============================================================
-- KuaiRand-Pure：创建四张清洗后基础表
-- 前置条件：已经执行 01_create_database.sql
-- 数据层次：清洗明细层，不在这里创建临时分析分组字段。
-- 本脚本不会删除已有表。
-- 反引号 常用于在MySQL中定义字段名、表名等等
-- ============================================================

USE `kuairand_analytics`;

-- ------------------------------------------------------------
-- 1. 标准推荐行为事实表
-- 一行代表一条用户—视频推荐行为记录。
-- record_id 是数据库生成的代理主键，不来自 Parquet 文件。
-- 字段定义的通用格式如下： `字段名` 数据类型 是否允许为空 其他约束 COMMENT '字段说明'
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `fact_standard_behavior` (
    `record_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '数据库代理主键',   #定义全部字段（为了让数据库中的每一行都有唯一标识而额外增加的代理主键 + 数据表中的原始字段）
    `user_id` INT UNSIGNED NOT NULL COMMENT '脱敏用户ID',
    `video_id` INT UNSIGNED NOT NULL COMMENT '脱敏视频ID',
    `date` INT UNSIGNED NOT NULL COMMENT '原始事件日期YYYYMMDD',
    `hourmin` SMALLINT UNSIGNED NOT NULL COMMENT '小时档位HH00',
    `time_ms` BIGINT UNSIGNED NOT NULL COMMENT '毫秒级事件时间戳',
    `is_click` TINYINT UNSIGNED NOT NULL COMMENT '点击或有效播放标记0/1',
    `is_like` TINYINT UNSIGNED NOT NULL COMMENT '点赞标记0/1',
    `is_follow` TINYINT UNSIGNED NOT NULL COMMENT '关注标记0/1',
    `is_comment` TINYINT UNSIGNED NOT NULL COMMENT '评论标记0/1',
    `is_forward` TINYINT UNSIGNED NOT NULL COMMENT '转发标记0/1',
    `is_hate` TINYINT UNSIGNED NOT NULL COMMENT '负反馈标记0/1',
    `long_view` TINYINT UNSIGNED NOT NULL COMMENT '长播标记0/1',
    `play_time_ms` INT UNSIGNED NOT NULL COMMENT '本次播放时长毫秒',
    `duration_ms` INT UNSIGNED NOT NULL COMMENT '原始视频时长毫秒，0表示无效',
    `profile_stay_time` INT UNSIGNED NOT NULL COMMENT '作者主页停留时长原始字段',
    `comment_stay_time` INT UNSIGNED NOT NULL COMMENT '评论区停留时长原始字段',
    `is_profile_enter` TINYINT UNSIGNED NOT NULL COMMENT '进入作者主页标记0/1',
    `is_rand` TINYINT UNSIGNED NOT NULL COMMENT '随机推荐标记；标准表固定为0',
    `tab` TINYINT UNSIGNED NOT NULL COMMENT '推荐场景脱敏编码',
    `is_duration_missing` TINYINT UNSIGNED NOT NULL COMMENT '视频时长缺失标记0/1',
    `duration_ms_clean` INT UNSIGNED NULL COMMENT '清洗后有效视频时长毫秒',
    `play_ratio_raw` DOUBLE NULL COMMENT '原始播放进度，允许大于1',
    `is_complete_play` TINYINT UNSIGNED NULL COMMENT '完整播放标记；时长无效时为空',
    `date_clean` DATE NOT NULL COMMENT '清洗后事件日期',
    `log_source` VARCHAR(32) NOT NULL COMMENT '日志来源标签',
    PRIMARY KEY (`record_id`),               #定义主键
    KEY `idx_std_user_id` (`user_id`),        #定义了三个索引，两个是单列索引，一个是联合索引。
    KEY `idx_std_video_id` (`video_id`),
    KEY `idx_std_date_hour` (`date_clean`, `hourmin`)  
) ENGINE=InnoDB             #指定使用 InnoDB 存储引擎。InnoDB支持事务、行级锁和崩溃恢复，是MySQL中最常用的默认存储引擎。
  DEFAULT CHARSET=utf8mb4    #设置默认字符集为 utf8mb4。可以安全保存中文、英文、符号和emoji。
  COLLATE=utf8mb4_unicode_ci  #指定文本的排序和比较规则。unicode 表示按照Unicode规则比较字符。ci 是 case-insensitive，表示英文字母比较时通常不区分大小写。
  COMMENT='标准推荐行为事实表';  #给整张表添加中文说明。以后在DBeaver或MySQL中查看表结构时，可以知道这张表的业务用途。

-- ------------------------------------------------------------
-- 2. 随机推荐行为事实表
-- 与标准推荐表保持同构，但继续分表存储，避免混淆抽样机制。
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `fact_random_behavior` (
    `record_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '数据库代理主键',
    `user_id` INT UNSIGNED NOT NULL COMMENT '脱敏用户ID',
    `video_id` INT UNSIGNED NOT NULL COMMENT '脱敏视频ID',
    `date` INT UNSIGNED NOT NULL COMMENT '原始事件日期YYYYMMDD',
    `hourmin` SMALLINT UNSIGNED NOT NULL COMMENT '小时档位HH00',
    `time_ms` BIGINT UNSIGNED NOT NULL COMMENT '毫秒级事件时间戳',
    `is_click` TINYINT UNSIGNED NOT NULL COMMENT '点击或有效播放标记0/1',
    `is_like` TINYINT UNSIGNED NOT NULL COMMENT '点赞标记0/1',
    `is_follow` TINYINT UNSIGNED NOT NULL COMMENT '关注标记0/1',
    `is_comment` TINYINT UNSIGNED NOT NULL COMMENT '评论标记0/1',
    `is_forward` TINYINT UNSIGNED NOT NULL COMMENT '转发标记0/1',
    `is_hate` TINYINT UNSIGNED NOT NULL COMMENT '负反馈标记0/1',
    `long_view` TINYINT UNSIGNED NOT NULL COMMENT '长播标记0/1',
    `play_time_ms` INT UNSIGNED NOT NULL COMMENT '本次播放时长毫秒',
    `duration_ms` INT UNSIGNED NOT NULL COMMENT '原始视频时长毫秒，0表示无效',
    `profile_stay_time` INT UNSIGNED NOT NULL COMMENT '作者主页停留时长原始字段',
    `comment_stay_time` INT UNSIGNED NOT NULL COMMENT '评论区停留时长原始字段',
    `is_profile_enter` TINYINT UNSIGNED NOT NULL COMMENT '进入作者主页标记0/1',
    `is_rand` TINYINT UNSIGNED NOT NULL COMMENT '随机推荐标记；随机表固定为1',
    `tab` TINYINT UNSIGNED NOT NULL COMMENT '推荐场景脱敏编码',
    `is_duration_missing` TINYINT UNSIGNED NOT NULL COMMENT '视频时长缺失标记0/1',
    `duration_ms_clean` INT UNSIGNED NULL COMMENT '清洗后有效视频时长毫秒',
    `play_ratio_raw` DOUBLE NULL COMMENT '原始播放进度，允许大于1',
    `is_complete_play` TINYINT UNSIGNED NULL COMMENT '完整播放标记；时长无效时为空',
    `date_clean` DATE NOT NULL COMMENT '清洗后事件日期',
    `log_source` VARCHAR(32) NOT NULL COMMENT '日志来源标签',
    PRIMARY KEY (`record_id`),
    KEY `idx_rand_user_id` (`user_id`),
    KEY `idx_rand_video_id` (`video_id`),
    KEY `idx_rand_date_hour` (`date_clean`, `hourmin`)
) ENGINE=InnoDB                 #设置存储引擎
  DEFAULT CHARSET=utf8mb4       #设置默认字符集
  COLLATE=utf8mb4_unicode_ci    #设置排序及比较规则
  COMMENT='随机推荐行为事实表';       #补充字段说明

-- ------------------------------------------------------------
-- 3. 用户维度表
-- user_id 在清洗数据中唯一，因此直接作为主键。
-- onehot_feat0 至 onehot_feat17 是脱敏类别编码，不解释真实属性。
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dim_user` (
    `user_id` INT UNSIGNED NOT NULL COMMENT '脱敏用户ID',
    `user_active_degree` VARCHAR(32) NOT NULL COMMENT '用户活跃度等级',
    `is_lowactive_period` TINYINT UNSIGNED NOT NULL COMMENT '低活跃时期标记',
    `is_live_streamer` SMALLINT NOT NULL COMMENT '直播作者原字段；-124表示未知哨兵值',
    `is_video_author` TINYINT UNSIGNED NOT NULL COMMENT '视频作者标记0/1',
    `follow_user_num` INT UNSIGNED NOT NULL COMMENT '关注人数',
    `follow_user_num_range` VARCHAR(32) NOT NULL COMMENT '关注人数分箱',
    `fans_user_num` INT UNSIGNED NOT NULL COMMENT '粉丝人数',
    `fans_user_num_range` VARCHAR(32) NOT NULL COMMENT '粉丝人数分箱',
    `friend_user_num` INT UNSIGNED NOT NULL COMMENT '互关或好友人数',
    `friend_user_num_range` VARCHAR(32) NOT NULL COMMENT '互关或好友人数分箱',
    `register_days` SMALLINT UNSIGNED NOT NULL COMMENT '注册天数',
    `register_days_range` VARCHAR(16) NOT NULL COMMENT '注册天数原始分箱',
    `onehot_feat0` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段0',
    `onehot_feat1` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段1',
    `onehot_feat2` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段2',
    `onehot_feat3` SMALLINT UNSIGNED NOT NULL COMMENT '脱敏类别字段3',
    `onehot_feat4` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段4',
    `onehot_feat5` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段5',
    `onehot_feat6` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段6',
    `onehot_feat7` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段7',
    `onehot_feat8` SMALLINT UNSIGNED NOT NULL COMMENT '脱敏类别字段8',
    `onehot_feat9` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段9',
    `onehot_feat10` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段10',
    `onehot_feat11` TINYINT UNSIGNED NOT NULL COMMENT '脱敏类别字段11',
    `onehot_feat12` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段12',
    `onehot_feat13` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段13',
    `onehot_feat14` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段14',
    `onehot_feat15` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段15',
    `onehot_feat16` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段16',
    `onehot_feat17` TINYINT UNSIGNED NULL COMMENT '脱敏类别字段17',
    `is_live_streamer_clean` TINYINT UNSIGNED NULL COMMENT '清洗后直播作者字段；空值表示未知',
    PRIMARY KEY (`user_id`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='用户特征维度表';

-- ------------------------------------------------------------
-- 4. 视频维度表
-- video_id 在清洗数据中唯一，因此直接作为主键。
-- upload_dt、tag 保留原始形式，clean字段用于正式分析。
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `dim_video` (
    `video_id` INT UNSIGNED NOT NULL COMMENT '脱敏视频ID',
    `author_id` INT UNSIGNED NOT NULL COMMENT '脱敏作者ID',
    `video_type` VARCHAR(16) NOT NULL COMMENT '视频类型',
    `upload_dt` CHAR(10) NOT NULL COMMENT '原始上传日期字符串',
    `upload_type` VARCHAR(32) NOT NULL COMMENT '上传方式类别',
    `visible_status` TINYINT UNSIGNED NOT NULL COMMENT '视频可见状态编码',
    `video_duration` INT UNSIGNED NULL COMMENT '原始视频时长毫秒',
    `server_width` SMALLINT UNSIGNED NOT NULL COMMENT '服务端视频宽度像素',
    `server_height` SMALLINT UNSIGNED NOT NULL COMMENT '服务端视频高度像素',
    `music_id` BIGINT UNSIGNED NOT NULL COMMENT '脱敏音乐ID',
    `music_type` TINYINT UNSIGNED NULL COMMENT '背景音乐类型原始编码',
    `tag` VARCHAR(32) NULL COMMENT '视频标签脱敏编号组合',
    `upload_date_clean` DATE NOT NULL COMMENT '清洗后上传日期',
    `is_duration_missing` TINYINT UNSIGNED NOT NULL COMMENT '视频时长缺失标记0/1',
    `video_duration_seconds` DECIMAL(10,3) NULL COMMENT '清洗后视频时长秒',
    `music_type_clean` VARCHAR(16) NOT NULL COMMENT '清洗后背景音乐类型编码或UNKNOWN',
    `tag_clean` VARCHAR(32) NOT NULL COMMENT '清洗后标签组合或UNKNOWN',
    PRIMARY KEY (`video_id`),
    KEY `idx_video_author_id` (`author_id`)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='视频基础特征维度表';

-- 查看当前数据库中四张表是否均已建立。
SHOW TABLES;
