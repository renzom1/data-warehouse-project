/*
===============================================================================
ANALYSIS 02 - PRODUCT MIX AND THE DECLINE IN AOV (Q2)
===============================================================================
Business question:
    Could changes in the product mix help explain the decline in average order
    value (AOV) seen in Q1, and does the mix change at the same time as the AOV
    steps? A mix effect is an association, not a cause, and may explain only
    part of the decline.

Data required:
    gold.fact_sales: order_number, product_key, order_date, sales_amount,
                     quantity.
    gold.dim_products: product_key, category, subcategory, product_line
                       (current product version only).

Grain:
    - Base grain: one row of gold.fact_sales (an order line).
    - Section A: year / month. B: category. C: category x year. D: category x
      year transition. E1: subcategory. E2: subcategory x year. F: product line
      x year. G1-G4: year x category / category / month / first-sale month.
      H: order class x year. I: category x year transition. J: check.

Definitions (shared by all analyses; see 00_data_profile.sql and decision 7 in
docs/decisions.md):
    - Revenue = SUM(sales_amount). Units = SUM(quantity).
    - Order = distinct order_number. AOV = revenue / orders.
      AOV = lines per order x revenue per line (identity, not an explanation).
    - Order date = MIN(order_date) over the order (7.2). Orders with no dated
      line are "undated" (2 orders) and appear only in the control totals.
    - Main window: 2011-01-01 to 2013-12-31 (7.1). Sections B, E1, G2, G4 and J
      use every line (context periods included) so that totals tie to the fact
      table; all other sections use the main window only.
    - Average unit price = revenue / units (realized price; list price and
      discounts are not available). Units are the base for prices, lines for
      the AOV factorization.
    - Share = value / total of the same year (or of the whole dataset in B and
      E1). Share changes are in percentage points against the true previous
      year; categories, subcategories and product lines without sales in a year
      are shown with zero rows, and those with no sale in the whole main window
      (e.g. the Components category) are omitted from C-F.
    - Orders containing a category are not additive across categories.
    - Contribution to change (D) = a category's change between consecutive
      years / total change. It can exceed 100% or be negative.
    - Order class (decision 7.8): Bikes only / Bikes + other / No bikes.
    - Product attributes are the current version of each product. Products are
      counted, never reported by surrogate key.

Method:
    Descriptive composition tables. No price-mix decomposition (out of scope).
    Section I is a simple like-for-like comparison: for products sold in two
    consecutive main-window years, the realized unit price in each year, the
    median product price change, and a price index with current-year units as
    weights (current revenue / current units valued at previous-year prices).

Caveats:
    - Volumes are very uneven (2011 and 2012 are small): every share is shown
      next to its counts.
    - Realized price is not list price; a price cut cannot be told apart from
      discounting. Amounts are whole numbers.
    - Section I compares only products sold in both years; it does not cover
      new or discontinued products and is not a decomposition.
    - Customer or country mix and changes in how the dataset was produced are
      not addressed here.
    - Section G3 and the pivot columns in G3/G4 assume the three categories
      Bikes, Accessories and Clothing; section J checks that nothing else exists.

Control totals (section J): lines 60,398 / orders 27,659 /
    revenue 29,356,250 / units 60,423.

Read-only: SELECT statements only.
Run:
    scripts\run_analysis.ps1 -Script analysis\02_product_mix.sql -DatabaseName DataWarehouse_Test
    (or: sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\02_product_mix.sql)
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
A. AOV FACTORIZATION: LINES PER ORDER x REVENUE PER LINE (MAIN WINDOW)
===============================================================================
By year and by month. bikes_pct_of_lines shows when the share of Bike lines
moves. In every row lines_per_order * revenue_per_line = aov.
*/

PRINT '--- A1. AOV FACTORIZATION BY YEAR ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
)
SELECT
    YEAR(order_dt)                                                                    AS year,
    COUNT(*)                                                                          AS lines,
    COUNT(DISTINCT order_number)                                                      AS orders,
    CAST(1.0 * COUNT(*) / COUNT(DISTINCT order_number) AS DECIMAL(8,2))               AS lines_per_order,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(*) AS DECIMAL(12,2))         AS revenue_per_line,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(DISTINCT order_number) AS DECIMAL(12,2)) AS aov,
    CAST(100.0 * SUM(CASE WHEN category = 'Bikes' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS bikes_pct_of_lines
FROM l
WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
GROUP BY YEAR(order_dt)
ORDER BY YEAR(order_dt);
GO

PRINT '--- A2. AOV FACTORIZATION BY MONTH ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
)
SELECT
    DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)                                 AS month_start,
    COUNT(*)                                                                          AS lines,
    COUNT(DISTINCT order_number)                                                      AS orders,
    CAST(1.0 * COUNT(*) / COUNT(DISTINCT order_number) AS DECIMAL(8,2))               AS lines_per_order,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(*) AS DECIMAL(12,2))         AS revenue_per_line,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(DISTINCT order_number) AS DECIMAL(12,2)) AS aov,
    CAST(100.0 * SUM(CASE WHEN category = 'Bikes' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS bikes_pct_of_lines
FROM l
WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
GROUP BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)
ORDER BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1);
GO


/*
===============================================================================
B. CATEGORY SUMMARY (WHOLE DATASET, ALL LINES)
===============================================================================
All lines, so the TOTAL row ties to the fact table. orders_containing is not
additive across categories (the TOTAL row counts each order once).
products_sold counts distinct products with at least one sale;
products_in_dim counts the current products of the category in the dimension.
Categories of the dimension without any sale are listed with zeros;
'(unclassified)' groups dimension products with no category.
*/

PRINT '--- B. CATEGORY SUMMARY ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
ag AS (
    /* One pass over l: the category rows plus the grand total (GROUPING SETS). */
    SELECT
        GROUPING(category)                 AS is_total,
        category,
        COUNT(*)                           AS lines,
        COUNT(DISTINCT order_number)       AS orders_containing,
        SUM(CAST(quantity AS BIGINT))      AS units,
        SUM(CAST(sales_amount AS BIGINT))  AS revenue,
        COUNT(DISTINCT product_key)        AS products_sold
    FROM l
    GROUP BY GROUPING SETS ((category), ())
),
pd AS (
    SELECT ISNULL(category, '(unclassified)') AS category, COUNT(*) AS products_in_dim
    FROM gold.dim_products
    GROUP BY ISNULL(category, '(unclassified)')
),
j AS (
    SELECT
        CASE WHEN ag.is_total = 1 THEN 'TOTAL' ELSE COALESCE(ag.category, pd.category) END AS category,
        ISNULL(ag.is_total, 0)                AS is_total,
        ISNULL(ag.lines, 0)                   AS lines,
        ISNULL(ag.orders_containing, 0)       AS orders_containing,
        ISNULL(ag.units, 0)                   AS units,
        ISNULL(ag.revenue, 0)                 AS revenue,
        ISNULL(ag.products_sold, 0)           AS products_sold,
        CASE WHEN ag.is_total = 1 THEN SUM(pd.products_in_dim) OVER ()
             ELSE ISNULL(pd.products_in_dim, 0) END AS products_in_dim,
        SUM(CASE WHEN ag.is_total = 1 THEN ag.lines   END) OVER () AS t_lines,
        SUM(CASE WHEN ag.is_total = 1 THEN ag.revenue END) OVER () AS t_revenue
    FROM ag
    FULL OUTER JOIN pd ON pd.category = ag.category
)
SELECT
    category, lines, orders_containing, units, revenue,
    CAST(100.0 * lines   / t_lines   AS DECIMAL(5,1))         AS pct_of_lines,
    CAST(100.0 * revenue / t_revenue AS DECIMAL(5,1))         AS pct_of_revenue,
    CAST(1.0 * revenue / NULLIF(lines, 0) AS DECIMAL(12,2))   AS revenue_per_line,
    CAST(1.0 * revenue / NULLIF(units, 0) AS DECIMAL(12,2))   AS avg_unit_price,
    products_sold, products_in_dim
FROM j
ORDER BY is_total, revenue DESC, products_in_dim DESC;
GO


/*
===============================================================================
C. CATEGORY MIX BY YEAR (MAIN WINDOW)
===============================================================================
Shares are of the year's total. share_*_chg_pp is the change in percentage
points against the previous year (NULL for 2011). Rows with zero lines are
categories without sales in that year.
*/

PRINT '--- C. CATEGORY MIX BY YEAR ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
g AS (
    SELECT c.category, y.yr
    FROM (SELECT DISTINCT ISNULL(category, '(unclassified)') AS category FROM gold.dim_products) c
    CROSS JOIN (VALUES (2011), (2012), (2013)) y(yr)
),
a AS (
    SELECT
        category, YEAR(order_dt) AS yr,
        COUNT(*)                          AS lines,
        SUM(CAST(quantity AS BIGINT))     AS units,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY category, YEAR(order_dt)
),
m AS (
    SELECT g.category, g.yr,
           ISNULL(a.lines, 0) AS lines, ISNULL(a.units, 0) AS units, ISNULL(a.revenue, 0) AS revenue
    FROM g LEFT JOIN a ON a.category = g.category AND a.yr = g.yr
),
s AS (
    SELECT m.*,
           SUM(lines)   OVER (PARTITION BY yr) AS t_lines,
           SUM(units)   OVER (PARTITION BY yr) AS t_units,
           SUM(revenue) OVER (PARTITION BY yr) AS t_revenue,
           SUM(lines)   OVER (PARTITION BY category) AS any_lines
    FROM m
)
SELECT
    category, yr AS year, lines, units, revenue,
    CAST(100.0 * lines   / t_lines   AS DECIMAL(5,1)) AS share_lines_pct,
    CAST(100.0 * units   / t_units   AS DECIMAL(5,1)) AS share_units_pct,
    CAST(100.0 * revenue / t_revenue AS DECIMAL(5,1)) AS share_revenue_pct,
    CAST(100.0 * lines / t_lines - LAG(100.0 * lines / t_lines) OVER (PARTITION BY category ORDER BY yr) AS DECIMAL(6,1))       AS share_lines_chg_pp,
    CAST(100.0 * revenue / t_revenue - LAG(100.0 * revenue / t_revenue) OVER (PARTITION BY category ORDER BY yr) AS DECIMAL(6,1)) AS share_revenue_chg_pp,
    CAST(1.0 * revenue / NULLIF(lines, 0) AS DECIMAL(12,2)) AS revenue_per_line,
    CAST(1.0 * revenue / NULLIF(units, 0) AS DECIMAL(12,2)) AS avg_unit_price
FROM s
WHERE any_lines > 0
ORDER BY category, yr;
GO


/*
===============================================================================
D. CONTRIBUTION OF EACH CATEGORY TO THE CHANGE BETWEEN CONSECUTIVE YEARS
===============================================================================
contrib_*_pct = category change / total change x 100. Descriptive: when
categories move in opposite directions a contribution can exceed 100% or be
negative. The TOTAL rows give the total change.
*/

PRINT '--- D. CONTRIBUTION TO CHANGE ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
g AS (
    SELECT c.category, y.yr
    FROM (SELECT DISTINCT ISNULL(category, '(unclassified)') AS category FROM gold.dim_products) c
    CROSS JOIN (VALUES (2011), (2012), (2013)) y(yr)
),
a AS (
    SELECT
        category, YEAR(order_dt) AS yr,
        COUNT(*)                          AS lines,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY category, YEAR(order_dt)
),
m AS (
    SELECT g.category, g.yr, ISNULL(a.lines, 0) AS lines, ISNULL(a.revenue, 0) AS revenue,
           COUNT(a.category) OVER (PARTITION BY g.category) AS years_with_sales
    FROM g LEFT JOIN a ON a.category = g.category AND a.yr = g.yr
),
d AS (
    SELECT
        category, yr, years_with_sales,
        lines   - LAG(lines)   OVER (PARTITION BY category ORDER BY yr) AS d_lines,
        revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY yr) AS d_revenue
    FROM m
),
e AS (
    SELECT category, yr, d_lines, d_revenue,
           SUM(d_lines)   OVER (PARTITION BY yr) AS t_lines,
           SUM(d_revenue) OVER (PARTITION BY yr) AS t_revenue
    FROM d
    WHERE d_lines IS NOT NULL AND years_with_sales > 0
)
SELECT *
FROM (
    SELECT
        CAST(yr - 1 AS VARCHAR(4)) + ' to ' + CAST(yr AS VARCHAR(4)) AS transition,
        category,
        d_lines   AS change_lines,
        CAST(100.0 * d_lines   / t_lines   AS DECIMAL(8,1)) AS contrib_lines_pct,
        d_revenue AS change_revenue,
        CAST(100.0 * d_revenue / t_revenue AS DECIMAL(8,1)) AS contrib_revenue_pct
    FROM e
    UNION ALL
    SELECT
        CAST(yr - 1 AS VARCHAR(4)) + ' to ' + CAST(yr AS VARCHAR(4)),
        'TOTAL', MAX(t_lines), CAST(100.0 AS DECIMAL(8,1)), MAX(t_revenue), CAST(100.0 AS DECIMAL(8,1))
    FROM e
    GROUP BY yr
) x
ORDER BY transition, CASE WHEN category = 'TOTAL' THEN 1 ELSE 0 END, category;
GO


/*
===============================================================================
E. SUBCATEGORY MIX
===============================================================================
E1 ranks subcategories over the whole dataset (all lines). E2 shows the main
window by year, with shares of the year's total and the change in share in
percentage points (zero rows for years without sales; subcategories with no
sales in the main window are omitted).
*/

PRINT '--- E1. SUBCATEGORY RANKING (WHOLE DATASET) ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
a AS (
    SELECT
        category, subcategory,
        COUNT(*)                          AS lines,
        SUM(CAST(quantity AS BIGINT))     AS units,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue,
        COUNT(DISTINCT product_key)       AS products_sold
    FROM l
    GROUP BY category, subcategory
)
SELECT
    RANK() OVER (ORDER BY revenue DESC)                                          AS revenue_rank,
    category, subcategory, lines, units, revenue,
    CAST(100.0 * revenue / SUM(revenue) OVER () AS DECIMAL(5,1))                 AS pct_of_revenue,
    CAST(100.0 * lines   / SUM(lines)   OVER () AS DECIMAL(5,1))                 AS pct_of_lines,
    CAST(1.0 * revenue / lines AS DECIMAL(12,2))                                 AS revenue_per_line,
    CAST(1.0 * revenue / units AS DECIMAL(12,2))                                 AS avg_unit_price,
    products_sold
FROM a
ORDER BY revenue DESC, category, subcategory;
GO

PRINT '--- E2. SUBCATEGORY MIX BY YEAR (MAIN WINDOW) ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
g AS (
    SELECT sc.category, sc.subcategory, y.yr
    FROM (SELECT DISTINCT ISNULL(category, '(no product)') AS category, ISNULL(subcategory, '(none)') AS subcategory
          FROM gold.dim_products) sc
    CROSS JOIN (VALUES (2011), (2012), (2013)) y(yr)
),
a AS (
    SELECT
        category, subcategory, YEAR(order_dt) AS yr,
        COUNT(*)                          AS lines,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY category, subcategory, YEAR(order_dt)
),
m AS (
    SELECT g.category, g.subcategory, g.yr,
           ISNULL(a.lines, 0) AS lines, ISNULL(a.revenue, 0) AS revenue
    FROM g LEFT JOIN a ON a.category = g.category AND a.subcategory = g.subcategory AND a.yr = g.yr
),
s AS (
    SELECT m.*,
           SUM(lines)   OVER (PARTITION BY yr)                      AS t_lines,
           SUM(revenue) OVER (PARTITION BY yr)                      AS t_revenue,
           SUM(lines)   OVER (PARTITION BY category, subcategory)   AS any_lines
    FROM m
)
SELECT
    category, subcategory, yr AS year, lines, revenue,
    CAST(100.0 * lines   / t_lines   AS DECIMAL(5,1)) AS share_lines_pct,
    CAST(100.0 * revenue / t_revenue AS DECIMAL(5,1)) AS share_revenue_pct,
    CAST(100.0 * lines / t_lines - LAG(100.0 * lines / t_lines) OVER (PARTITION BY category, subcategory ORDER BY yr) AS DECIMAL(6,1)) AS share_lines_chg_pp,
    CAST(1.0 * revenue / NULLIF(lines, 0) AS DECIMAL(12,2)) AS revenue_per_line
FROM s
WHERE any_lines > 0
ORDER BY category, subcategory, yr;
GO


/*
===============================================================================
F. PRODUCT-LINE MIX BY YEAR (MAIN WINDOW)
===============================================================================
Same layout as section C. product_line 'n/a' means the source has no product
line for the product.
*/

PRINT '--- F. PRODUCT-LINE MIX BY YEAR ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
g AS (
    SELECT c.product_line, y.yr
    FROM (SELECT DISTINCT ISNULL(product_line, 'n/a') AS product_line FROM gold.dim_products) c
    CROSS JOIN (VALUES (2011), (2012), (2013)) y(yr)
),
a AS (
    SELECT
        product_line, YEAR(order_dt) AS yr,
        COUNT(*)                          AS lines,
        SUM(CAST(quantity AS BIGINT))     AS units,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY product_line, YEAR(order_dt)
),
m AS (
    SELECT g.product_line, g.yr,
           ISNULL(a.lines, 0) AS lines, ISNULL(a.units, 0) AS units, ISNULL(a.revenue, 0) AS revenue
    FROM g LEFT JOIN a ON a.product_line = g.product_line AND a.yr = g.yr
),
s AS (
    SELECT m.*,
           SUM(lines)   OVER (PARTITION BY yr) AS t_lines,
           SUM(revenue) OVER (PARTITION BY yr) AS t_revenue,
           SUM(lines)   OVER (PARTITION BY product_line) AS any_lines
    FROM m
)
SELECT
    product_line, yr AS year, lines, units, revenue,
    CAST(100.0 * lines   / t_lines   AS DECIMAL(5,1)) AS share_lines_pct,
    CAST(100.0 * revenue / t_revenue AS DECIMAL(5,1)) AS share_revenue_pct,
    CAST(100.0 * lines / t_lines - LAG(100.0 * lines / t_lines) OVER (PARTITION BY product_line ORDER BY yr) AS DECIMAL(6,1))       AS share_lines_chg_pp,
    CAST(100.0 * revenue / t_revenue - LAG(100.0 * revenue / t_revenue) OVER (PARTITION BY product_line ORDER BY yr) AS DECIMAL(6,1)) AS share_revenue_chg_pp,
    CAST(1.0 * revenue / NULLIF(lines, 0) AS DECIMAL(12,2)) AS revenue_per_line,
    CAST(1.0 * revenue / NULLIF(units, 0) AS DECIMAL(12,2)) AS avg_unit_price
FROM s
WHERE any_lines > 0
ORDER BY product_line, yr;
GO


/*
===============================================================================
G. ASSORTMENT AND TIMING
===============================================================================
G1: distinct products sold per year and category; "new" = first sale falls in
    that year (first sale = earliest order-level date over all dated lines;
    for 2011 this includes products already sold in the 2010 tail as not new).
    pct_revenue_from_new_products is the share of that group's revenue.
G2: first month with sales per category (all dated lines).
G3: monthly category mix around the AOV breaks (Oct 2011 - Mar 2012 and
    Oct 2012 - Apr 2013): lines per category, share of non-Bike lines, AOV,
    and the average unit price of Bikes.
G4: number of products first sold in each month, by category.
*/

PRINT '--- G1. DISTINCT PRODUCTS SOLD BY YEAR AND CATEGORY ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
f1 AS (
    /* first sale of the product over all dated lines, as a window so that l is read once */
    SELECT
        category, product_key, sales_amount, order_dt,
        MIN(order_dt) OVER (PARTITION BY product_key) AS first_dt
    FROM l
    WHERE order_dt IS NOT NULL
),
x AS (
    SELECT
        category, YEAR(order_dt) AS yr, product_key, sales_amount,
        CASE WHEN YEAR(first_dt) = YEAR(order_dt) THEN 1 ELSE 0 END AS is_new
    FROM f1
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
)
SELECT
    yr AS year,
    CASE WHEN GROUPING(category) = 1 THEN 'ALL' ELSE category END                     AS category,
    COUNT(DISTINCT product_key)                                                       AS products_sold,
    COUNT(DISTINCT CASE WHEN is_new = 1 THEN product_key END)                         AS new_products,
    COUNT(*)                                                                          AS lines,
    CAST(100.0 * SUM(CASE WHEN is_new = 1 THEN CAST(sales_amount AS BIGINT) ELSE 0 END)
         / SUM(CAST(sales_amount AS BIGINT)) AS DECIMAL(5,1))                         AS pct_revenue_from_new_products
FROM x
GROUP BY GROUPING SETS ((yr, category), (yr))
ORDER BY yr, GROUPING(category), category;
GO

PRINT '--- G2. FIRST MONTH WITH SALES, BY CATEGORY ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
cm AS (
    SELECT
        category,
        DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1) AS month_start,
        COUNT(*)                                          AS lines,
        COUNT(DISTINCT product_key)                       AS products
    FROM l
    WHERE order_dt IS NOT NULL
    GROUP BY category, DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)
),
r AS (
    SELECT cm.*, ROW_NUMBER() OVER (PARTITION BY category ORDER BY month_start) AS rn
    FROM cm
)
SELECT category, month_start AS first_month, lines AS lines_in_first_month, products AS products_in_first_month
FROM r
WHERE rn = 1
ORDER BY month_start, category;
GO

PRINT '--- G3. MONTHLY CATEGORY MIX AROUND THE AOV BREAKS ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
)
SELECT
    DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)                                 AS month_start,
    COUNT(*)                                                                          AS lines,
    COUNT(DISTINCT order_number)                                                      AS orders,
    SUM(CASE WHEN category = 'Bikes'       THEN 1 ELSE 0 END)                         AS lines_bikes,
    SUM(CASE WHEN category = 'Accessories' THEN 1 ELSE 0 END)                         AS lines_accessories,
    SUM(CASE WHEN category = 'Clothing'    THEN 1 ELSE 0 END)                         AS lines_clothing,
    CAST(100.0 * SUM(CASE WHEN category <> 'Bikes' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS non_bike_pct_of_lines,
    CAST(1.0 * SUM(CAST(sales_amount AS BIGINT)) / COUNT(DISTINCT order_number) AS DECIMAL(12,2)) AS aov,
    CAST(1.0 * SUM(CASE WHEN category = 'Bikes' THEN CAST(sales_amount AS BIGINT) ELSE 0 END)
         / NULLIF(SUM(CASE WHEN category = 'Bikes' THEN CAST(quantity AS BIGINT) ELSE 0 END), 0) AS DECIMAL(12,2)) AS bikes_avg_unit_price
FROM l
WHERE (order_dt >= '2011-10-01' AND order_dt < '2012-04-01')
   OR (order_dt >= '2012-10-01' AND order_dt < '2013-05-01')
GROUP BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1)
ORDER BY DATEFROMPARTS(YEAR(order_dt), MONTH(order_dt), 1);
GO

PRINT '--- G4. PRODUCTS FIRST SOLD, BY MONTH ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
pf AS (
    SELECT product_key, MAX(category) AS category, MIN(order_dt) AS first_dt
    FROM l
    WHERE order_dt IS NOT NULL
    GROUP BY product_key
)
SELECT
    DATEFROMPARTS(YEAR(first_dt), MONTH(first_dt), 1)             AS first_sale_month,
    COUNT(*)                                                      AS products_first_sold,
    SUM(CASE WHEN category = 'Bikes'       THEN 1 ELSE 0 END)     AS bikes,
    SUM(CASE WHEN category = 'Accessories' THEN 1 ELSE 0 END)     AS accessories,
    SUM(CASE WHEN category = 'Clothing'    THEN 1 ELSE 0 END)     AS clothing
FROM pf
GROUP BY DATEFROMPARTS(YEAR(first_dt), MONTH(first_dt), 1)
ORDER BY DATEFROMPARTS(YEAR(first_dt), MONTH(first_dt), 1);
GO


/*
===============================================================================
H. ORDER COMPOSITION BY CLASS (MAIN WINDOW)
===============================================================================
Each order has one class (decision 7.8): Bikes only / Bikes + other / No bikes.
Shares are of the year's orders and revenue. Classes without orders in a year
are shown with zeros.
*/

PRINT '--- H. ORDER COMPOSITION BY CLASS ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
o AS (
    SELECT
        order_number,
        MAX(order_dt)                                  AS order_dt,
        COUNT(*)                                       AS lines,
        SUM(CAST(sales_amount AS BIGINT))              AS revenue,
        SUM(CASE WHEN category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM l
    GROUP BY order_number
),
oc AS (
    SELECT *,
           CASE WHEN bike_lines = 0 THEN 'No bikes'
                WHEN bike_lines = lines THEN 'Bikes only'
                ELSE 'Bikes + other' END AS cls
    FROM o
),
g AS (
    SELECT c.cls, y.yr
    FROM (VALUES ('Bikes only'), ('Bikes + other'), ('No bikes')) c(cls)
    CROSS JOIN (VALUES (2011), (2012), (2013)) y(yr)
),
a AS (
    SELECT
        cls, YEAR(order_dt) AS yr,
        COUNT(*) AS orders, SUM(lines) AS lines, SUM(revenue) AS revenue
    FROM oc
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY cls, YEAR(order_dt)
),
m AS (
    SELECT g.cls, g.yr,
           ISNULL(a.orders, 0) AS orders, ISNULL(a.lines, 0) AS lines, ISNULL(a.revenue, 0) AS revenue
    FROM g LEFT JOIN a ON a.cls = g.cls AND a.yr = g.yr
),
s AS (
    SELECT m.*,
           SUM(orders)  OVER (PARTITION BY yr) AS t_orders,
           SUM(revenue) OVER (PARTITION BY yr) AS t_revenue
    FROM m
)
SELECT
    yr AS year, cls AS order_class, orders,
    CAST(100.0 * orders  / t_orders  AS DECIMAL(5,1)) AS pct_of_orders,
    lines, revenue,
    CAST(100.0 * revenue / t_revenue AS DECIMAL(5,1)) AS pct_of_revenue,
    CAST(1.0 * revenue / NULLIF(orders, 0) AS DECIMAL(12,2)) AS aov,
    CAST(1.0 * lines   / NULLIF(orders, 0) AS DECIMAL(8,2))  AS lines_per_order,
    CAST(1.0 * revenue / NULLIF(lines, 0)  AS DECIMAL(12,2)) AS revenue_per_line
FROM s
ORDER BY yr, cls;
GO


/*
===============================================================================
I. LIKE-FOR-LIKE REALIZED UNIT PRICE (MAIN WINDOW, CONSECUTIVE YEARS)
===============================================================================
Products sold in both years of a transition, by category. For each product the
realized unit price (revenue / units) is compared between the two years.
  products_in_both      products sold in both years.
  products_sold_cur     products of the category sold in the later year.
  pct_cat_revenue_cur   revenue of those products in the later year, as a share
                        of the category's revenue in that year.
  lower / same / higher number of products whose later-year price is below /
                        equal to / above the earlier-year price.
  median_price_chg_pct  median of the products' price changes (unweighted).
  price_index_chg_pct   later-year revenue / later-year units valued at the
                        earlier-year prices, minus 1 (current-year units as
                        weights; mix changes between the products are held
                        fixed by the weights).
Realized prices only: a price cut cannot be told apart from discounting.
*/

PRINT '--- I. LIKE-FOR-LIKE UNIT PRICE BY CATEGORY ---';

WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
py AS (
    SELECT
        product_key, MAX(category) AS category, YEAR(order_dt) AS yr,
        SUM(CAST(quantity AS BIGINT))     AS units,
        SUM(CAST(sales_amount AS BIGINT)) AS revenue
    FROM l
    WHERE order_dt >= '2011-01-01' AND order_dt < '2014-01-01'
    GROUP BY product_key, YEAR(order_dt)
),
x AS (
    /* Everything is derived from the small product x year result py, read once:
       the previous year of the same product (LAG) and the category-year totals
       (windows). Rows keep all products until the filter in pp. */
    SELECT
        category, yr, product_key, units, revenue,
        LAG(yr)      OVER (PARTITION BY product_key ORDER BY yr) AS prev_yr,
        LAG(units)   OVER (PARTITION BY product_key ORDER BY yr) AS prev_units,
        LAG(revenue) OVER (PARTITION BY product_key ORDER BY yr) AS prev_revenue,
        COUNT(*)     OVER (PARTITION BY category, yr)            AS products_sold,
        SUM(revenue) OVER (PARTITION BY category, yr)            AS cat_revenue
    FROM py
),
pp AS (
    SELECT
        category, yr, product_key, products_sold, cat_revenue,
        units AS cur_units, revenue AS cur_revenue,
        1.0 * revenue      / NULLIF(units, 0)      AS cur_price,
        1.0 * prev_revenue / NULLIF(prev_units, 0) AS prev_price
    FROM x
    WHERE prev_yr = yr - 1
),
pm AS (
    SELECT *,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY 100.0 * (cur_price / NULLIF(prev_price, 0) - 1))
               OVER (PARTITION BY category, yr) AS median_chg
    FROM pp
)
SELECT
    CAST(pm.yr - 1 AS VARCHAR(4)) + ' to ' + CAST(pm.yr AS VARCHAR(4))              AS transition,
    pm.category,
    COUNT(*)                                                                         AS products_in_both,
    MAX(pm.products_sold)                                                            AS products_sold_cur,
    CAST(100.0 * SUM(pm.cur_revenue) / MAX(pm.cat_revenue) AS DECIMAL(5,1))          AS pct_cat_revenue_cur,
    SUM(CASE WHEN pm.cur_price <  pm.prev_price THEN 1 ELSE 0 END)                   AS lower,
    SUM(CASE WHEN pm.cur_price =  pm.prev_price THEN 1 ELSE 0 END)                   AS same,
    SUM(CASE WHEN pm.cur_price >  pm.prev_price THEN 1 ELSE 0 END)                   AS higher,
    CAST(MAX(pm.median_chg) AS DECIMAL(8,1))                                         AS median_price_chg_pct,
    CAST(100.0 * (SUM(pm.cur_revenue) / SUM(pm.cur_units * pm.prev_price) - 1) AS DECIMAL(8,1)) AS price_index_chg_pct
FROM pm
GROUP BY pm.yr, pm.category
ORDER BY pm.yr, pm.category;
GO


/*
===============================================================================
J. CONTROL TOTALS
===============================================================================
The join to gold.dim_products must not change the number of lines. Totals by
period, category, subcategory, order class, and the main-window sections must
add up to the fact table totals.
*/

PRINT '--- J. CONTROL TOTALS ---';

/*
Single pass: l is read once (every CTE below is referenced once). The groupings
are produced together with GROUPING SETS and the checks are read from them.
*/
WITH l AS (
    SELECT
        f.order_number, f.product_key, f.sales_amount, f.quantity,
        MIN(f.order_date) OVER (PARTITION BY f.order_number) AS order_dt,
        ISNULL(p.category, '(no product)')    AS category,
        ISNULL(p.subcategory, '(none)')       AS subcategory,
        ISNULL(p.product_line, 'n/a')         AS product_line
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
),
l2 AS (
    SELECT
        order_number, sales_amount, quantity, category, subcategory, order_dt,
        SUM(CASE WHEN category = 'Bikes' THEN 1 ELSE 0 END) OVER (PARTITION BY order_number) AS bike_lines,
        COUNT(*) OVER (PARTITION BY order_number)                                              AS order_lines
    FROM l
),
l3 AS (
    SELECT
        order_number, sales_amount, quantity, category, subcategory,
        CASE WHEN order_dt IS NULL          THEN 'undated'
             WHEN order_dt <  '2011-01-01'  THEN 'pre'
             WHEN order_dt >= '2014-01-01'  THEN 'post'
             ELSE 'main' END AS period,
        CASE WHEN order_dt >= '2011-01-01' AND order_dt < '2014-01-01' THEN YEAR(order_dt) END AS yr,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = order_lines THEN 'Bikes only'
             ELSE 'Bikes + other' END AS cls
    FROM l2
),
gs AS (
    SELECT
        CASE WHEN GROUPING(period) = 0 AND GROUPING(cls) = 1 THEN 'period'
             WHEN GROUPING(period) = 0 AND GROUPING(cls) = 0 THEN 'cls_period'
             WHEN GROUPING(cls) = 0                          THEN 'cls'
             WHEN GROUPING(subcategory) = 0                  THEN 'subcategory'
             WHEN GROUPING(yr) = 0                           THEN 'category_year'
             WHEN GROUPING(category) = 0                     THEN 'category'
             ELSE 'total' END AS kind,
        period, category, yr,
        COUNT(*)                                     AS n,
        COUNT(DISTINCT order_number)                 AS o,
        SUM(CAST(sales_amount AS BIGINT))            AS r,
        SUM(CAST(quantity AS BIGINT))                AS u
    FROM l3
    GROUP BY GROUPING SETS ((period), (cls, period), (cls), (category, subcategory), (category, yr), (category), ())
),
s AS (
    SELECT
        SUM(CASE WHEN kind = 'total' THEN CAST(n AS BIGINT) END)       AS tot_n,
        SUM(CASE WHEN kind = 'total' THEN CAST(o AS BIGINT) END)       AS tot_o,
        SUM(CASE WHEN kind = 'total' THEN r END)                       AS tot_r,
        SUM(CASE WHEN kind = 'total' THEN u END)                       AS tot_u,
        SUM(CASE WHEN kind = 'period' THEN CAST(n AS BIGINT) END)      AS per_n,
        SUM(CASE WHEN kind = 'period' THEN CAST(o AS BIGINT) END)      AS per_o,
        SUM(CASE WHEN kind = 'period' THEN r END)                      AS per_r,
        SUM(CASE WHEN kind = 'period' THEN u END)                      AS per_u,
        SUM(CASE WHEN kind = 'period' AND period = 'main' THEN CAST(n AS BIGINT) END) AS main_n,
        SUM(CASE WHEN kind = 'period' AND period = 'main' THEN CAST(o AS BIGINT) END) AS main_o,
        SUM(CASE WHEN kind = 'category' THEN CAST(n AS BIGINT) END)    AS cat_n,
        SUM(CASE WHEN kind = 'category' THEN r END)                    AS cat_r,
        SUM(CASE WHEN kind = 'category' THEN u END)                    AS cat_u,
        ISNULL(SUM(CASE WHEN kind = 'category' AND category NOT IN ('Bikes', 'Accessories', 'Clothing') THEN CAST(n AS BIGINT) END), 0) AS cat_other_n,
        SUM(CASE WHEN kind = 'subcategory' THEN CAST(n AS BIGINT) END) AS sub_n,
        SUM(CASE WHEN kind = 'subcategory' THEN r END)                 AS sub_r,
        SUM(CASE WHEN kind = 'category_year' AND yr IS NOT NULL THEN CAST(n AS BIGINT) END) AS catyr_n,
        SUM(CASE WHEN kind = 'cls' THEN CAST(o AS BIGINT) END)         AS cls_o,
        SUM(CASE WHEN kind = 'cls' THEN CAST(n AS BIGINT) END)         AS cls_n,
        SUM(CASE WHEN kind = 'cls' THEN r END)                         AS cls_r,
        SUM(CASE WHEN kind = 'cls_period' AND period = 'main' THEN CAST(o AS BIGINT) END) AS clsmain_o
    FROM gs
)
SELECT
    c.check_name,
    c.actual_value,
    c.expected_value,
    CASE WHEN c.actual_value = c.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM s
CROSS APPLY (VALUES
    ('lines: fact joined to dimension',                              tot_n, CAST(60398 AS BIGINT)),
    ('orders',                                                       tot_o, 27659),
    ('revenue',                                                      tot_r, 29356250),
    ('units',                                                        tot_u, 60423),
    ('lines: periods (main, context, undated)',                      per_n, 60398),
    ('orders: periods (main, context, undated)',                     per_o, 27659),
    ('revenue: periods (main, context, undated)',                    per_r, 29356250),
    ('units: periods (main, context, undated)',                      per_u, 60423),
    ('lines: categories',                                            cat_n, 60398),
    ('revenue: categories',                                          cat_r, 29356250),
    ('units: categories',                                            cat_u, 60423),
    ('categories outside Bikes / Accessories / Clothing (lines)',    cat_other_n, 0),
    ('lines: subcategories',                                         sub_n, 60398),
    ('revenue: subcategories',                                       sub_r, 29356250),
    ('lines: category x year (main) = main window',                  catyr_n, main_n),
    ('orders: order classes (all orders)',                           cls_o, 27659),
    ('lines: order classes',                                         cls_n, 60398),
    ('revenue: order classes',                                       cls_r, 29356250),
    ('orders: order classes (main) = main window',                   clsmain_o, main_o)
) AS c(check_name, actual_value, expected_value);
GO