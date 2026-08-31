# SQL 执行说明

## 数据模型

| 表 | 角色 | 已验证规模 |
|---|---|---:|
| `fact_standard_behavior` | 标准推荐行为事实表 | 1,414,622 行 |
| `fact_random_behavior` | 随机推荐行为事实表 | 1,186,049 行 |
| `dim_user` | 用户维度表 | 27,285 行 |
| `dim_video` | 视频维度表 | 7,583 行 |

事实表使用 MySQL 生成的 `record_id` 作为代理主键；用户表和视频表分别以 `user_id`、`video_id` 为主键。当前不设置物理外键，关联完整性由导入后的质量检查验证。

## 执行顺序

1. `01_create_database.sql`：创建并选择数据库。
2. `02_create_tables.sql`：创建四张基础表和必要索引。
3. `03_load_data.sql`：全量刷新四张基础表。执行前，将脚本中的示例目录 `E:/path/to/KuaiRand_Pure` 替换为本机项目绝对路径。
4. `04_data_quality_checks.sql`：核验行数、主键、空值、范围和关联覆盖；所有检查应为 `PASS`。
5. `05_create_analysis_views.sql`：创建标准推荐和随机推荐分析明细视图。
6. `06_sql_core_metrics_reconciliation.sql`：复算核心指标并与 Python 基准核对。
7. `07_create_metric_views.sql`：创建 6 张 Power BI 稳定指标视图。

## 运行环境

- MySQL 8.0
- 数据库：`kuairand_analytics`
- `local_infile=ON`
- 客户端需允许 `LOAD DATA LOCAL INFILE`

`03_load_data.sql` 会先 `TRUNCATE` 再导入，属于覆盖式全量刷新。不要只运行其中单独的 `LOAD DATA` 区块；任一导入失败后应停止后续步骤并先检查行数。

## Power BI 数据源

仅导入以下聚合视图，不直接导入百万行事实表：

- `vw_metric_overall_standard`
- `vw_metric_daily_standard`
- `vw_metric_hourly_standard`
- `vw_metric_user_segments_standard`
- `vw_metric_content_segments_standard`
- `vw_metric_recommendation_comparison`

`*_rate_pct` 已是 0—100 的百分数值，Power BI 只添加 `%` 显示符号。
