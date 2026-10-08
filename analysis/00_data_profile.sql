/*
===============================================================================
ANALYSIS 00 - DATA PROFILE AND CONTROL TOTALS
===============================================================================
Purpose:
    Establish the control totals that every other analysis reconciles to, and
    document the data-quality facts that the analytical questions depend on.
    This script runs no business analysis.

Grain:
    - Section 1-3: one row per check or per period bucket.
    - Section 4-5: one row per profiled item.

Read-only:
    SELECT statements only. No objects are created or modified.

Run (SQLCMD variable DatabaseName is required; there is no default):
    sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\00_data_profile.sql

Expected values come from docs/rebuild_baseline.md (corrected rebuild).
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
1. CONTROL TOTALS
===============================================================================
Every analysis must tie back to these figures. Any MISMATCH means the data
changed and the analyses must not be trusted until it is understood.
*/

PRINT '--- 1. CONTROL TOTALS ---';

WITH actual AS (
    SELECT 'fact lines'                          AS check_name, COUNT_BIG(*)                              AS actual_value FROM gold.fact_sales
    UNION ALL SELECT 'distinct orders',                         COUNT(DISTINCT order_number)             FROM gold.fact_sales
    UNION ALL SELECT 'customers (dim_customers)',               COUNT(*)                                 FROM gold.dim_customers
    UNION ALL SELECT 'customers with at least one order',       COUNT(DISTINCT customer_key)             FROM gold.fact_sales
    UNION ALL SELECT 'products (dim_products)',                 COUNT(*)                                 FROM gold.dim_products
    UNION ALL SELECT 'revenue (SUM sales_amount)',              SUM(CAST(sales_amount AS BIGINT))        FROM gold.fact_sales
    UNION ALL SELECT 'units (SUM quantity)',                    SUM(CAST(quantity AS BIGINT))            FROM gold.fact_sales
),
expected AS (
    SELECT check_name, expected_value
    FROM (VALUES
        ('fact lines',                         60398),
        ('distinct orders',                    27659),
        ('customers (dim_customers)',          18484),
        ('customers with at least one order',  18484),
        ('products (dim_products)',              295),
        ('revenue (SUM sales_amount)',      29356250),
        ('units (SUM quantity)',               60423)
    ) AS v (check_name, expected_value)
)
SELECT
    a.check_name,
    a.actual_value,
    e.expected_value,
    CASE WHEN a.actual_value = e.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM actual AS a
JOIN expected AS e
    ON e.check_name = a.check_name;
GO


/*
===============================================================================
2. ORDER GRAIN
===============================================================================
Grain of gold.fact_sales: one row per order line (order_number + product).
An order is a distinct order_number. These checks confirm that an order has a
single customer and that no (order, product) pair is repeated. Note that
COUNT(DISTINCT order_date) ignores NULLs, so mixed NULL / dated orders are
counted separately.
*/

PRINT '--- 2. ORDER GRAIN ---';

WITH o AS (
    SELECT
        order_number,
        COUNT(*)                                                AS lines,
        COUNT(DISTINCT customer_key)                            AS customers,
        COUNT(DISTINCT order_date)                              AS distinct_dates,
        SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END)     AS null_date_lines
    FROM gold.fact_sales
    GROUP BY order_number
)
SELECT 'orders with more than one customer' AS item, COUNT(*) AS n FROM o WHERE customers > 1
UNION ALL SELECT 'orders with more than one distinct order_date', COUNT(*) FROM o WHERE distinct_dates > 1
UNION ALL SELECT 'orders where ALL lines have a NULL order_date', COUNT(*) FROM o WHERE null_date_lines = lines
UNION ALL SELECT 'orders MIXING NULL and dated lines', COUNT(*) FROM o WHERE null_date_lines > 0 AND null_date_lines < lines
UNION ALL SELECT 'lines with a NULL order_date', SUM(null_date_lines) FROM o
UNION ALL SELECT 'duplicated (order_number, product_key) pairs',
    COUNT(*) FROM (
        SELECT order_number, product_key
        FROM gold.fact_sales
        GROUP BY order_number, product_key
        HAVING COUNT(*) > 1
    ) AS d
UNION ALL SELECT 'maximum lines in one order', MAX(lines) FROM o;
GO


/*
===============================================================================
3. PERIOD COVERAGE
===============================================================================
Main comparison window: 2011-01-01 to 2013-12-31 (complete calendar years).
Context periods (2010 tail, January 2014) and undated orders are reported
separately and never mixed into annual comparisons.

ORDER DATE DEFINITION (used by every analysis):
    All dated lines of an order share one date (section 2), so the date of an
    order is taken from its dated lines: MIN(order_date) over the order. A
    line with a NULL order_date inherits the date of its order when a sibling
    line is dated (13 orders). Only orders with no dated line at all (2 orders)
    are "undated". This is an analytical definition; Silver and Gold are not
    changed.

The TOTAL row is computed directly from the table, so it also shows whether
the period buckets add up to it. With the order-level date, lines, orders,
units and revenue all reconcile.
*/

PRINT '--- 3. PERIOD COVERAGE ---';

WITH l AS (
    SELECT
        order_number,
        sales_amount,
        quantity,
        MIN(order_date) OVER (PARTITION BY order_number) AS order_dt
    FROM gold.fact_sales
),
f AS (
    SELECT
        CASE
            WHEN order_dt IS NULL           THEN '9. Undated orders (no dated line)'
            WHEN order_dt <  '2011-01-01'   THEN '1. Context: 2010 tail'
            WHEN order_dt >= '2014-01-01'   THEN '5. Context: January 2014'
            ELSE '2. Main: ' + CAST(YEAR(order_dt) AS VARCHAR(4))
        END                               AS period,
        order_number,
        order_dt,
        sales_amount,
        quantity
    FROM l
)
SELECT
    CASE WHEN GROUPING(period) = 1 THEN 'TOTAL' ELSE period END AS period,
    COUNT(*)                                                   AS lines,
    COUNT(DISTINCT order_number)                               AS orders,
    SUM(CAST(quantity AS BIGINT))                              AS units,
    SUM(CAST(sales_amount AS BIGINT))                          AS revenue,
    MIN(order_dt)                                              AS first_date,
    MAX(order_dt)                                              AS last_date
FROM f
GROUP BY ROLLUP (period)
ORDER BY GROUPING(period), period;
GO


/*
===============================================================================
4. UNKNOWN VALUES AND DIMENSION QUALITY
===============================================================================
*/

PRINT '--- 4a. CUSTOMER DIMENSION ---';

SELECT 'customers' AS item, COUNT(*) AS n FROM gold.dim_customers
UNION ALL SELECT 'country = N/A',             COUNT(*) FROM gold.dim_customers WHERE country = 'N/A'
UNION ALL SELECT 'country IS NULL',           COUNT(*) FROM gold.dim_customers WHERE country IS NULL
UNION ALL SELECT 'gender = N/A',              COUNT(*) FROM gold.dim_customers WHERE gender = 'N/A'
UNION ALL SELECT 'marital_status = N/A',      COUNT(*) FROM gold.dim_customers WHERE marital_status = 'N/A'
UNION ALL SELECT 'birthdate IS NULL',         COUNT(*) FROM gold.dim_customers WHERE birthdate IS NULL
UNION ALL SELECT 'birthdate before 1924-01-01 (data-quality flag)', COUNT(*) FROM gold.dim_customers WHERE birthdate < '1924-01-01';
GO

PRINT '--- 4b. PRODUCT DIMENSION AND REVENUE EXPOSURE ---';

SELECT 'products' AS item, COUNT(*) AS n FROM gold.dim_products
UNION ALL SELECT 'products with sales',              COUNT(DISTINCT product_key) FROM gold.fact_sales
UNION ALL SELECT 'products with cost = 0',           COUNT(*) FROM gold.dim_products WHERE cost = 0
UNION ALL SELECT 'products with category IS NULL',   COUNT(*) FROM gold.dim_products WHERE category IS NULL
UNION ALL SELECT 'products with product_line = N/A', COUNT(*) FROM gold.dim_products WHERE product_line = 'N/A'
UNION ALL SELECT 'revenue on products with cost = 0',
    ISNULL(SUM(CAST(f.sales_amount AS BIGINT)), 0)
    FROM gold.fact_sales AS f JOIN gold.dim_products AS p ON p.product_key = f.product_key WHERE p.cost = 0
UNION ALL SELECT 'revenue on products with category IS NULL',
    ISNULL(SUM(CAST(f.sales_amount AS BIGINT)), 0)
    FROM gold.fact_sales AS f JOIN gold.dim_products AS p ON p.product_key = f.product_key WHERE p.category IS NULL
UNION ALL SELECT 'revenue on products with product_line = N/A',
    ISNULL(SUM(CAST(f.sales_amount AS BIGINT)), 0)
    FROM gold.fact_sales AS f JOIN gold.dim_products AS p ON p.product_key = f.product_key WHERE p.product_line = 'N/A';
GO


/*
===============================================================================
5. COLUMN SEMANTICS
===============================================================================
create_date: expected to be a load date (years after the last order), not a
signup date. Shipping and due lags: expected to be constant (one combination).
*/

PRINT '--- 5. CREATE_DATE AND DATE LAGS ---';

SELECT
    MIN(create_date)                              AS min_create_date,
    MAX(create_date)                              AS max_create_date,
    (SELECT MAX(order_date) FROM gold.fact_sales) AS last_order_date
FROM gold.dim_customers;

SELECT
    COUNT(DISTINCT CONCAT(
        DATEDIFF(day, order_date, shipping_date), '/',
        DATEDIFF(day, order_date, due_date)))     AS distinct_lag_combinations
FROM gold.fact_sales
WHERE order_date IS NOT NULL;
GO
