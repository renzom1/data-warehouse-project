/*
===============================================================================
ANALYSIS 01 - REVENUE TRENDS (Q1)
===============================================================================
Business question:
    How have revenue, units and orders changed over time, and is there
    seasonality? Is revenue growth driven by more orders or by higher order
    value?

Data required:
    gold.fact_sales: order_number, order_date, sales_amount, quantity.

Grain:
    - Sections A and B: one row per period / per calendar year.
    - Sections C and D: one row per calendar month / per month of the year.
    The base grain is one row of gold.fact_sales (an order line).

Definitions (shared by all analyses; see 00_data_profile.sql and decision 7 in
docs/decisions.md):
    - Revenue = SUM(sales_amount). Units = SUM(quantity).
    - Order = distinct order_number. AOV = revenue / orders.
    - Order date = MIN(order_date) over the order (all dated lines of an order
      share one date). A line with a NULL order_date inherits its order's date;
      only orders with no dated line are "undated" (2 orders).
    - Main window: 2011-01-01 to 2013-12-31 (complete calendar years).
      Context periods (2010 tail, January 2014) and undated orders are shown
      separately and are never part of year-over-year comparisons.

Method:
    Aggregate by period, compare consecutive main-window years, and split the
    revenue change into an "orders" effect and an "AOV" effect:
        change in revenue = (orders_t - orders_t-1) * AOV_t-1
                          + orders_t * (AOV_t - AOV_t-1)
    The two effects add up exactly to the change.

Caveats:
    - Orders and revenue per order can move in different directions between
      years (see section B). A growth story based on order counts alone would
      be misleading; the product mix behind it is analysed in 02_product_mix.sql.
    - Seasonality rests on three years only, and the years differ structurally.
    - January 2014 is not a normal month (see section C) and is context only.

Control totals (section E): lines 60,398 / orders 27,659 / revenue 29,356,250.

Read-only: SELECT statements only.
Run:
    sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\01_revenue_trends.sql
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
A. ANNUAL SUMMARY BY PERIOD
===============================================================================
*/

PRINT '--- A. ANNUAL SUMMARY BY PERIOD ---';

WITH l AS (
    SELECT
        order_number, sales_amount, quantity,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
f AS (
    SELECT
        CASE
            WHEN order_dt IS NULL           THEN '9. Undated orders (no dated line)'
            WHEN order_dt <  '2011-01-01'   THEN '1. Context: 2010 tail (29-31 Dec)'
            WHEN order_dt >= '2014-01-01'   THEN '5. Context: January 2014 (1-28 Jan)'
            ELSE '2. Main: ' + CAST(YEAR(order_dt) AS VARCHAR(4))
        END AS period,
        order_number, sales_amount, quantity
    FROM l
)
SELECT
    CASE WHEN GROUPING(period) = 1 THEN 'TOTAL' ELSE period END                                   AS period,
    COUNT(*)                                                                                      AS lines,
    COUNT(DISTINCT order_number)                                                                  AS orders,
    SUM(CAST(quantity AS BIGINT))                                                                 AS units,
    SUM(CAST(sales_amount AS BIGINT))                                                             AS revenue,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(DISTINCT order_number) AS DECIMAL(12,2)) AS aov,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(*)                     AS DECIMAL(12,2)) AS revenue_per_line,
    CAST(1.0 * SUM(CAST(quantity AS BIGINT))     / COUNT(DISTINCT order_number) AS DECIMAL(8,2))  AS units_per_order
FROM f
GROUP BY ROLLUP (period)
ORDER BY GROUPING(period), period;
GO


/*
===============================================================================
B. YEAR-OVER-YEAR CHANGE AND DECOMPOSITION (MAIN WINDOW ONLY)
===============================================================================
effect_more_orders + effect_higher_aov = revenue_change (decomposition_check
should be 0, apart from rounding).
*/

PRINT '--- B. YEAR-OVER-YEAR CHANGE (2011-2013) ---';

WITH l AS (
    SELECT
        order_number, sales_amount, quantity,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
y AS (
    SELECT
        YEAR(order_dt)                               AS yr,
        COUNT(*)                                     AS lines,
        COUNT(DISTINCT order_number)                 AS orders,
        SUM(CAST(quantity AS BIGINT))                AS units,
        SUM(CAST(sales_amount AS BIGINT))            AS revenue,
        CAST(SUM(CAST(sales_amount AS BIGINT)) AS DECIMAL(18,6)) / COUNT(DISTINCT order_number) AS aov
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY YEAR(order_dt)
),
c AS (
    SELECT
        yr, lines, orders, units, revenue, aov,
        LAG(lines)   OVER (ORDER BY yr) AS p_lines,
        LAG(orders)  OVER (ORDER BY yr) AS p_orders,
        LAG(units)   OVER (ORDER BY yr) AS p_units,
        LAG(revenue) OVER (ORDER BY yr) AS p_revenue,
        LAG(aov)     OVER (ORDER BY yr) AS p_aov
    FROM y
)
SELECT
    yr                                                                         AS year,
    orders,
    CAST(100.0 * (orders - p_orders)   / p_orders   AS DECIMAL(8,1))           AS orders_chg_pct,
    lines,
    CAST(100.0 * (lines - p_lines)     / p_lines    AS DECIMAL(8,1))           AS lines_chg_pct,
    units,
    CAST(100.0 * (units - p_units)     / p_units    AS DECIMAL(8,1))           AS units_chg_pct,
    CAST(aov AS DECIMAL(12,2))                                                 AS aov,
    CAST(100.0 * (aov - p_aov)         / p_aov      AS DECIMAL(8,1))           AS aov_chg_pct,
    revenue,
    CAST(100.0 * (revenue - p_revenue) / p_revenue  AS DECIMAL(8,1))           AS revenue_chg_pct,
    revenue - p_revenue                                                        AS revenue_change,
    CAST((orders - p_orders) * p_aov AS DECIMAL(18,0))                         AS effect_more_orders,
    CAST(orders * (aov - p_aov)      AS DECIMAL(18,0))                         AS effect_higher_aov,
    CAST((orders - p_orders) * p_aov + orders * (aov - p_aov) - (revenue - p_revenue) AS DECIMAL(18,2)) AS decomposition_check
FROM c
ORDER BY yr;
GO


/*
===============================================================================
C. MONTHLY TABLE
===============================================================================
share_of_year_pct is the month's share of its calendar year's revenue and is
shown for main-window years only (context months would trivially be 100%).
*/

PRINT '--- C. MONTHLY TABLE ---';

WITH l AS (
    SELECT
        order_number, sales_amount, quantity,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
m AS (
    SELECT
        DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1) AS month_start,
        COUNT(*)                                          AS lines,
        COUNT(DISTINCT order_number)                      AS orders,
        SUM(CAST(quantity AS BIGINT))                     AS units,
        SUM(CAST(sales_amount AS BIGINT))                 AS revenue
    FROM l
    WHERE order_dt IS NOT NULL
    GROUP BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)
)
SELECT
    month_start,
    CASE WHEN month_start >= '2011-01-01' AND month_start < '2014-01-01' THEN 'main' ELSE 'context' END AS window_flag,
    lines,
    orders,
    units,
    revenue,
    CAST(1.0 * revenue / orders AS DECIMAL(12,2)) AS aov,
    CASE WHEN month_start >= '2011-01-01' AND month_start < '2014-01-01'
         THEN CAST(100.0 * revenue / SUM(revenue) OVER (PARTITION BY YEAR(month_start)) AS DECIMAL(5,1))
    END                                           AS share_of_year_pct
FROM m
ORDER BY month_start;
GO


/*
===============================================================================
D. SEASONALITY PROFILE (MAIN WINDOW): SHARE OF EACH YEAR'S REVENUE BY MONTH
===============================================================================
Each year column sums to 100. Compare the shapes across years; with only three
years, and years that differ structurally, this is suggestive, not established.
*/

PRINT '--- D. SEASONALITY PROFILE ---';

WITH l AS (
    SELECT
        order_number, sales_amount,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
m AS (
    SELECT
        YEAR(order_dt)  AS yr,
        MONTH(order_dt) AS mth,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue,
        COUNT(DISTINCT order_number)      AS orders
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY YEAR(order_dt), MONTH(order_dt)
),
s AS (
    SELECT
        yr, mth, revenue, orders,
        100.0 * revenue / SUM(revenue) OVER (PARTITION BY yr) AS rev_share,
        100.0 * orders  / SUM(orders)  OVER (PARTITION BY yr) AS ord_share
    FROM m
)
SELECT
    mth AS month_of_year,
    CAST(MAX(CASE WHEN yr = 2011 THEN rev_share END) AS DECIMAL(5,1)) AS revenue_share_2011,
    CAST(MAX(CASE WHEN yr = 2012 THEN rev_share END) AS DECIMAL(5,1)) AS revenue_share_2012,
    CAST(MAX(CASE WHEN yr = 2013 THEN rev_share END) AS DECIMAL(5,1)) AS revenue_share_2013,
    CAST(MAX(CASE WHEN yr = 2011 THEN ord_share END) AS DECIMAL(5,1)) AS orders_share_2011,
    CAST(MAX(CASE WHEN yr = 2012 THEN ord_share END) AS DECIMAL(5,1)) AS orders_share_2012,
    CAST(MAX(CASE WHEN yr = 2013 THEN ord_share END) AS DECIMAL(5,1)) AS orders_share_2013
FROM s
GROUP BY mth
ORDER BY mth;
GO


/*
===============================================================================
E. CONTROL TOTALS
===============================================================================
Monthly figures plus undated orders must add up to the fact table totals.
*/

PRINT '--- E. CONTROL TOTALS ---';

WITH l AS (
    SELECT
        order_number, sales_amount,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
mm AS (
    SELECT
        COUNT(*)                          AS n,
        COUNT(DISTINCT order_number)      AS o,
        SUM(CAST(sales_amount AS BIGINT)) AS r
    FROM l
    WHERE order_dt IS NOT NULL
    GROUP BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)
),
und AS (
    SELECT
        COUNT(*)                                     AS n,
        COUNT(DISTINCT order_number)                 AS o,
        ISNULL(SUM(CAST(sales_amount AS BIGINT)), 0) AS r
    FROM l
    WHERE order_dt IS NULL
)
SELECT
    c.check_name,
    c.actual_value,
    c.expected_value,
    CASE WHEN c.actual_value = c.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'lines: all months + undated'  AS check_name,
           (SELECT SUM(CAST(n AS BIGINT)) FROM mm) + (SELECT n FROM und) AS actual_value,
           60398 AS expected_value
    UNION ALL
    SELECT 'orders: all months + undated',
           (SELECT SUM(CAST(o AS BIGINT)) FROM mm) + (SELECT o FROM und),
           27659
    UNION ALL
    SELECT 'revenue: all months + undated',
           (SELECT SUM(r) FROM mm) + (SELECT r FROM und),
           29356250
) AS c;
GO
