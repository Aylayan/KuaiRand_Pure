-- ============================================================
-- KuaiRand-Pure：Python 业务深化分析结果入库与 Power BI 视图
--
-- 目标：
--   1. 保存共同用户 Bootstrap 配对验证的 5 行结果；
--   2. 保存用户/内容构成校正的 20 行结果；
--   3. 为 Power BI 提供两个稳定的聚合结果视图。
--
-- 数据来源：
--   outputs/business_analysis/paired_user_validation.csv
--   outputs/business_analysis/composition_adjustment.csv
--
-- 边界：
--   - 本脚本只改写下方两张业务结果表；
--   - 不修改四张基础表和 08 脚本创建的视图；
--   - 视图展示的是 Python 已计算完成的固定结果，不在 MySQL 中
--     重新执行 Bootstrap 或构成校正。
-- ============================================================

USE kuairand_analytics;


-- ------------------------------------------------------------
-- 1. Python Bootstrap 配对验证结果表（预期 5 行）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS result_business_paired_validation
(
    metric                    VARCHAR(50)    NOT NULL COMMENT '业务指标',
    paired_users              INT UNSIGNED   NOT NULL COMMENT '有效配对用户数',
    mean_gap_pp               DECIMAL(24,15) NOT NULL COMMENT '标准推荐减随机推荐的用户等权平均差值，百分点',
    median_gap_pp             DECIMAL(24,15) NOT NULL COMMENT '用户差值中位数，百分点',
    ci95_low_pp               DECIMAL(24,15) NOT NULL COMMENT 'Bootstrap 95% 置信区间下限，百分点',
    ci95_high_pp              DECIMAL(24,15) NOT NULL COMMENT 'Bootstrap 95% 置信区间上限，百分点',
    positive_user_share_pct   DECIMAL(24,15) NOT NULL COMMENT '差值大于 0 的用户占比，百分比',
    negative_user_share_pct   DECIMAL(24,15) NOT NULL COMMENT '差值小于 0 的用户占比，百分比',
    zero_user_share_pct       DECIMAL(24,15) NOT NULL COMMENT '差值等于 0 的用户占比，百分比',
    PRIMARY KEY (metric)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COMMENT = 'Python 生成的共同用户 Bootstrap 配对验证结果';


-- ------------------------------------------------------------
-- 2. Python 构成校正结果表（预期 20 行）
-- 每行代表一个分层维度 × 一个业务指标。
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS result_business_composition_adjustment
(
    segment_dimension           VARCHAR(50)    NOT NULL COMMENT '中文分层维度',
    segment_column              VARCHAR(64)    NOT NULL COMMENT '对应的原始字段名',
    metric                      VARCHAR(50)    NOT NULL COMMENT '业务指标',
    raw_standard_rate_pct       DECIMAL(24,15) NOT NULL COMMENT '标准推荐原始指标率，百分比',
    raw_random_rate_pct         DECIMAL(24,15) NOT NULL COMMENT '随机推荐原始指标率，百分比',
    raw_gap_pp                  DECIMAL(24,15) NOT NULL COMMENT '校正前标准减随机差值，百分点',
    adjusted_standard_rate_pct  DECIMAL(24,15) NOT NULL COMMENT '标准推荐构成校正后指标率，百分比',
    adjusted_random_rate_pct    DECIMAL(24,15) NOT NULL COMMENT '随机推荐构成校正后指标率，百分比',
    adjusted_gap_pp             DECIMAL(24,15) NOT NULL COMMENT '校正后标准减随机差值，百分点',
    adjustment_effect_pp        DECIMAL(24,15) NOT NULL COMMENT '校正后差值减校正前差值，百分点',
    PRIMARY KEY (segment_dimension, metric)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COMMENT = 'Python 生成的单一分层变量构成校正结果';


-- ------------------------------------------------------------
-- 3. 使用 Python 本次输出替换结果表中的旧快照
-- 若任一 INSERT 失败，可在 COMMIT 前回滚本次数据改写。
-- ------------------------------------------------------------
START TRANSACTION;

DELETE FROM result_business_paired_validation;

INSERT INTO result_business_paired_validation
(
    metric,
    paired_users,
    mean_gap_pp,
    median_gap_pp,
    ci95_low_pp,
    ci95_high_pp,
    positive_user_share_pct,
    negative_user_share_pct,
    zero_user_share_pct
)
VALUES
    ('点击/有效播放率', 25877, 30.829394958578412, 30.194805194805200, 30.502073744778300, 31.138648118000060, 86.582679599644480,  9.877497391505970,  3.539823008849558),
    ('长播率',         25877, 26.630806639426343, 24.025974025974023, 26.307502310776890, 26.932357050859174, 81.160876453993900, 10.263940951424043,  8.575182594582060),
    ('完整播放率',     25846, 13.356883371791664,  8.333333333333332, 13.099621818545273, 13.601931386634714, 61.943821094173180, 14.667646831231137, 23.388532074595684),
    ('正向互动率',     25877,  1.634046876046689,  0.000000000000000,  1.542104394371171,  1.730582426046254, 12.590331182130852,  7.110561502492561, 80.299107315376590),
    ('负反馈率',       25877, -0.056014632874826,  0.000000000000000, -0.078431682511615, -0.033949484513882,  0.440545658306604,  1.657842872048537, 97.901611469644860);

DELETE FROM result_business_composition_adjustment;

INSERT INTO result_business_composition_adjustment
(
    segment_dimension,
    segment_column,
    metric,
    raw_standard_rate_pct,
    raw_random_rate_pct,
    raw_gap_pp,
    adjusted_standard_rate_pct,
    adjusted_random_rate_pct,
    adjusted_gap_pp,
    adjustment_effect_pp
)
VALUES
    ('用户活跃度', 'user_active_degree',   '点击/有效播放率', 45.117062524427660, 17.615966962579120, 27.501095561848540, 44.791574044548035, 17.638819684964872, 27.152754359583163, -0.348341202265377),
    ('用户活跃度', 'user_active_degree',   '长播率',         31.832913091149320,  8.496191978577613, 23.336721112571706, 31.578582628900914,  8.506652701705288, 23.071929927195626, -0.264791185376080),
    ('用户活跃度', 'user_active_degree',   '完整播放率',     14.324654176089702,  3.318687458066066, 11.005966718023636, 14.210928029751074,  3.321739402516865, 10.889188627234208, -0.116778090789428),
    ('用户活跃度', 'user_active_degree',   '正向互动率',      2.143062199302017,  0.557396869775195,  1.585665329526822,  2.093793157173101,  0.559032479572587,  1.534760677600514, -0.050904651926308),

    ('注册时长',   'register_days_group',  '点击/有效播放率', 45.117062524427660, 17.615966962579120, 27.501095561848540, 45.055690714396250, 17.622434603637675, 27.433256110758574, -0.067839451089966),
    ('注册时长',   'register_days_group',  '长播率',         31.832913091149320,  8.496191978577613, 23.336721112571706, 31.781896013480814,  8.499469131758977, 23.282426881721840, -0.054294230849866),
    ('注册时长',   'register_days_group',  '完整播放率',     14.324654176089702,  3.318687458066066, 11.005966718023636, 14.299843558474710,  3.319849663853413, 10.979993894621296, -0.025972823402340),
    ('注册时长',   'register_days_group',  '正向互动率',      2.143062199302017,  0.557396869775195,  1.585665329526822,  2.131471566196174,  0.558211656429024,  1.573259909767150, -0.012405419759672),

    ('视频时长',   'duration_group',       '点击/有效播放率', 45.117062524427660, 17.615966962579120, 27.501095561848540, 45.061910765149490, 17.634668520136234, 27.427242245013257, -0.073853316835283),
    ('视频时长',   'duration_group',       '长播率',         31.832913091149320,  8.496191978577613, 23.336721112571706, 31.714431461496567,  8.521547307976885, 23.192884153519680, -0.143836959052024),
    ('视频时长',   'duration_group',       '完整播放率',     14.324654176089702,  3.318687458066066, 11.005966718023636, 13.791523266185028,  3.374213003695805, 10.417310262489222, -0.588656455534414),
    ('视频时长',   'duration_group',       '正向互动率',      2.143062199302017,  0.557396869775195,  1.585665329526822,  2.132702173021681,  0.558417966976007,  1.574284206045674, -0.011381123481148),

    ('视频类型',   'video_type',           '点击/有效播放率', 45.117062524427660, 17.615966962579120, 27.501095561848540, 45.114637251009995, 17.615709463602652, 27.498927787407343, -0.002167774441197),
    ('视频类型',   'video_type',           '长播率',         31.832913091149320,  8.496191978577613, 23.336721112571706, 31.831057655176420,  8.496047760570750, 23.335009894605670, -0.001711217966037),
    ('视频类型',   'video_type',           '完整播放率',     14.324654176089702,  3.318687458066066, 11.005966718023636, 14.327665917708252,  3.319196659043215, 11.008469258665038,  0.002502540641402),
    ('视频类型',   'video_type',           '正向互动率',      2.143062199302017,  0.557396869775195,  1.585665329526822,  2.143062263201403,  0.557396683223769,  1.585665579977634,  0.000000250450811),

    ('画面方向',   'screen_orientation',   '点击/有效播放率', 45.117062524427660, 17.615966962579120, 27.501095561848540, 45.200099427997560, 17.616199091497380, 27.583900336500180,  0.082804774651638),
    ('画面方向',   'screen_orientation',   '长播率',         31.832913091149320,  8.496191978577613, 23.336721112571706, 31.900032528341924,  8.496602259752846, 23.403430268589076,  0.066709156017371),
    ('画面方向',   'screen_orientation',   '完整播放率',     14.324654176089702,  3.318687458066066, 11.005966718023636, 14.270879830780400,  3.337216314198496, 10.933663516581904, -0.072303201441732),
    ('画面方向',   'screen_orientation',   '正向互动率',      2.143062199302017,  0.557396869775195,  1.585665329526822,  2.140192708112373,  0.557507337679397,  1.582685370432976, -0.002979959093847);

COMMIT;


-- ------------------------------------------------------------
-- 4. Power BI 使用的两个聚合结果视图
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_metric_business_paired_validation AS
SELECT
    metric,
    paired_users,
    mean_gap_pp,
    median_gap_pp,
    ci95_low_pp,
    ci95_high_pp,
    positive_user_share_pct,
    negative_user_share_pct,
    zero_user_share_pct
FROM result_business_paired_validation;


CREATE OR REPLACE VIEW vw_metric_business_composition_adjustment AS
SELECT
    segment_dimension,
    segment_column,
    metric,
    raw_standard_rate_pct,
    raw_random_rate_pct,
    raw_gap_pp,
    adjusted_standard_rate_pct,
    adjusted_random_rate_pct,
    adjusted_gap_pp,
    adjustment_effect_pp
FROM result_business_composition_adjustment;


-- ------------------------------------------------------------
-- 5. 创建后核验
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS paired_validation_rows,
    CASE
        WHEN COUNT(*) = 5 THEN 'PASS'
        ELSE 'CHECK'
    END AS row_count_check
FROM vw_metric_business_paired_validation;

SELECT
    COUNT(*) AS composition_adjustment_rows,
    CASE
        WHEN COUNT(*) = 20 THEN 'PASS'
        ELSE 'CHECK'
    END AS row_count_check
FROM vw_metric_business_composition_adjustment;

SELECT
    COUNT(*) AS invalid_bootstrap_rows,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'CHECK'
    END AS bootstrap_logic_check
FROM vw_metric_business_paired_validation
WHERE ci95_low_pp > mean_gap_pp
   OR mean_gap_pp > ci95_high_pp
   OR ABS(
        positive_user_share_pct
        + negative_user_share_pct
        + zero_user_share_pct
        - 100.0
      ) > 0.000001;

SELECT
    COUNT(*) AS invalid_adjustment_rows,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'CHECK'
    END AS adjustment_logic_check
FROM vw_metric_business_composition_adjustment
WHERE ABS(
        adjusted_standard_rate_pct
        - adjusted_random_rate_pct
        - adjusted_gap_pp
      ) > 0.000001
   OR ABS(
        adjusted_gap_pp
        - raw_gap_pp
        - adjustment_effect_pp
      ) > 0.000001;

SELECT
    table_name AS power_bi_view_name
FROM information_schema.views
WHERE table_schema = DATABASE()
  AND table_name IN
  (
      'vw_metric_business_paired_validation',
      'vw_metric_business_composition_adjustment'
  )
ORDER BY table_name;
