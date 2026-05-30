-- results.sql
-- Run after `dbt build` to see the migration results.
--
-- Usage:
--   cz-cli sql "$(cat results.sql)" --write
--   Or paste into Lakehouse Studio SQL editor
--
-- Schema prefix: dbt_migration_test (matches profiles.yml)

-- ═══════════════════════════════════════════════════════════
-- 1. 分层概览 — 各层表数量
-- ═══════════════════════════════════════════════════════════
SELECT 'Bronze' AS layer, count(*) AS tables FROM (SHOW TABLES IN dbt_migration_test_bronze)
UNION ALL
SELECT 'Silver', count(*) FROM (SHOW TABLES IN dbt_migration_test_silver)
UNION ALL
SELECT 'Gold', count(*) FROM (SHOW TABLES IN dbt_migration_test_gold);

-- ═══════════════════════════════════════════════════════════
-- 2. 客户分群分布 — 5 个分群各有多少客户
-- ═══════════════════════════════════════════════════════════
SELECT
    customer_segment,
    count(*) AS customer_count,
    round(count(*) * 100.0 / sum(count(*)) over (), 1) AS pct
FROM dbt_migration_test_silver.customer_segments
GROUP BY 1
ORDER BY 2 DESC;

-- ═══════════════════════════════════════════════════════════
-- 3. 客户洞察 Top 10 — 按账户余额排序
-- ═══════════════════════════════════════════════════════════
SELECT
    customer_name,
    customer_tier,
    risk_category,
    country,
    account_balance
FROM dbt_migration_test_gold.customer_insights
ORDER BY account_balance DESC
LIMIT 10;

-- ═══════════════════════════════════════════════════════════
-- 4. 订单事实 Dynamic Table — 刷新状态
-- ═══════════════════════════════════════════════════════════
SHOW DYNAMIC TABLE REFRESH HISTORY WHERE name = 'order_facts_dynamic' LIMIT 3;

-- ═══════════════════════════════════════════════════════════
-- 5. 日历维度 — 日期范围
-- ═══════════════════════════════════════════════════════════
SELECT
    min(day_dt) AS start_date,
    max(day_dt) AS end_date,
    count(*) AS total_days
FROM dbt_migration_test_gold.dim_calendar_day;

-- ═══════════════════════════════════════════════════════════
-- 6. CDC Stream — 变更类型分布
-- ═══════════════════════════════════════════════════════════
SELECT
    cdc_change_type,
    count(*) AS change_count
FROM dbt_migration_test_bronze.customer_cdc_stream
GROUP BY 1
ORDER BY 2 DESC;
