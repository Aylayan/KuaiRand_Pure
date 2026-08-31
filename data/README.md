# 数据文件说明

本仓库收录本项目实际使用的 5 个 KuaiRand-Pure 原始 CSV，方便面试官直接查看并复现分析。原始数据来自 [KuaiRand 官方项目](https://github.com/chongminggao/KuaiRand) 和 [Zenodo 官方记录](https://zenodo.org/records/10439422)。

这里收录的是本项目实际使用的数据文件，并非官方 KuaiRand-Pure 完整文件包；官方包中的 `video_features_statistic_pure.csv` 未被本项目使用，因此不随仓库提供。如需完整数据，请从上述官方渠道下载。

```text
data/
├─ raw/
│  ├─ log_standard_4_08_to_4_21_pure.csv
│  ├─ log_standard_4_22_to_5_08_pure.csv
│  ├─ log_random_4_22_to_5_08_pure.csv
│  ├─ user_features_pure.csv
│  └─ video_features_basic_pure.csv
├─ processed/               # 本地运行 Python/01—03 后生成
│  ├─ log_standard_clean.parquet
│  ├─ log_random_clean.parquet
│  ├─ user_features_clean.parquet
│  └─ video_features_basic_clean.parquet
└─ mysql_import/            # 本地运行 Python/07 后生成
   ├─ fact_standard_behavior.csv
   ├─ fact_random_behavior.csv
   ├─ dim_user.csv
   └─ dim_video.csv
```

`data/raw` 中上述 5 个原始 CSV 纳入版本管理；`data/processed` 和 `data/mysql_import` 属于可由项目代码重新生成的中间或导入文件，继续通过 `.gitignore` 排除。字段定义和取值统计见 `docs/字段字典.md`。

## 数据许可与引用

KuaiRand 官方项目采用 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 许可。本仓库中的原始数据保持官方文件内容不变；公开使用、复制或再分发这些数据及其衍生成果时，请保留原作者署名、数据来源和许可说明，并遵守相同方式共享要求。

请引用 Gao et al., *KuaiRand: An Unbiased Sequential Recommendation Dataset with Randomly Exposed Videos*, CIKM 2022（[DOI](https://doi.org/10.1145/3511808.3557624)）。
