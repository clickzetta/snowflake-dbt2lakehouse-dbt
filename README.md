# snowflake-dbt2lakehouse-dbt

Migrating a real-world Snowflake dbt project to ClickZetta Lakehouse.

**Source project**: [sfc-gh-dflippo/snowflake-dbt-demo](https://github.com/sfc-gh-dflippo/snowflake-dbt-demo)  
**Dataset**: TPC-H (built-in sample data on both platforms) + mock FX rates seed

## Repository Structure

```
01_snowflake/   Original Snowflake dbt project (unchanged)
02_migration/   Migration notes — what changed and why
03_lakehouse/   ClickZetta version (runnable with dbt-clickzetta)
```

## Key Migration Points

| Feature | Snowflake | ClickZetta |
|---|---|---|
| Dynamic Table config | `snowflake_warehouse` + `target_lag` | `refresh_vc` + `refresh_interval` |
| CDC stream columns | `METADATA$ACTION` | `__change_type` |
| Row generation | `table(generator(...))` | Recursive CTE |
| Surrogate key | `SEQUENCE .nextval` | `row_number() over (...)` |
| Python models | Snowpark (`sproc.register`) | Not yet supported — use SQL alternative |
| Marketplace data | Cybersyn FX rates | Mock seed CSV |

See [02_migration/MIGRATION_NOTES.md](02_migration/MIGRATION_NOTES.md) for the full diff.

## Quick Start (ClickZetta)

默认使用 1 万行样本数据，约 **1 分钟** 跑完：

```bash
cd 03_lakehouse
cp profiles.yml.example ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml with your connection details

pip install dbt-clickzetta
dbt deps
dbt seed          # Load mock FX rates
dbt build         # ~1 min (sample mode)
```

Or use the one-click script:

```bash
bash run.sh
```

## Expected Runtime

| 模式 | 数据量 | 运行时间 | 命令 |
|------|--------|----------|------|
| **Sample（默认）** | 1 万行 | ~1 分钟 | `dbt build` |
| **Full** | 1.5 亿行 | ~10 分钟 | `bash run.sh --full` |

> ⚠️ **Dynamic Table 首次创建必须全量刷新**，不是增量计算。Full 模式下 `order_facts_dynamic` 首次刷新约 4 分钟，这是正常行为，不是卡住。后续增量刷新通常只需几秒。

## Data Sources

- **TPC-H**: Available as `clickzetta_sample_data.tpch_100g` on ClickZetta (no import needed)
- **FX rates**: `data/fx_rates_timeseries.csv` — mock USD-based daily rates for EUR/CNY/JPY/GBP/CAD (2020–2024)

## After Build — See Your Results

跑完后执行 `results.sql` 查看各层数据样例：

```bash
# 用 cz-cli
cz-cli sql "$(cat results.sql)" --write

# 或在 Lakehouse Studio SQL 编辑器中粘贴 results.sql 内容
```

你会看到：
- 分层概览（Bronze/Silver/Gold 各多少表）
- 客户分群分布（5 个分群的客户数量和占比）
- 客户洞察 Top 10（按账户余额排序）
- Dynamic Table 刷新状态
- CDC Stream 变更类型分布

## Cleanup

测试完成后清理所有创建的对象：

```bash
cz-cli sql "$(cat cleanup.sql)" --write
```
