/*
===============================================================================
ANALYSIS 03 - REPEAT PURCHASING (Q3)
===============================================================================
Business question:
    Do customers place a second order, how quickly, and does that differ by the
    year of their first order or by the kind of first order? Are the 2013
    "No bikes" orders first orders of customers, or later orders of customers
    who already bought a Bike? Section F describes the sequence of orders only;
    it says nothing about types of customers or about why customers bought, and
    it does not apportion the AOV decline described in Q2.

Data required:
    gold.fact_sales: order_number, customer_key, product_key, order_date,
                     sales_amount, quantity.
    gold.dim_customers: customer_id, used only in section G. Inside the script
                        customers are grouped by fact_sales.customer_key, which
                        is 1:1 with customer_id within a single query (checked
                        in G) and is never reported or hardcoded. Joining the
                        60,398 lines to the view on its ROW_NUMBER key made the
                        first version run for more than 18 minutes.
    gold.dim_products: product_key -> category (for the order class).

Grain:
    - Base grain: one row of gold.fact_sales (an order line), collapsed once to
      one row per order (customer_key, order date, class, lines, revenue, units).
    - Customer grain (CTE cu): first order, second order, their dates and
      classes, derived from the order rows with window functions.
    - Sections: A cohort group; B cohort x window (B2 cohort x calendar quarter;
      B3 cohort x window x end-of-data variant); C cohort x band;
      D class x window x variant (D2 adds the quarter of the first order);
      E first class x second class; F category of order (F2 customer groups);
      G check.

Definitions (shared by all analyses; decisions 7.1-7.9 in docs/decisions.md):
    - Order date = MIN(order_date) over the order (7.2). The 2 undated orders
      (3 lines, revenue 34) are outside the order sequence; customers with no
      dated order are reported apart (7.9).
    - Order sequence of a customer: dated orders by order date, then by
      order_number (the tie-break is arbitrary). First order = first of the
      sequence. Cohort = year of the first order (2011-2013). First orders in
      the 2010 tail (29-31 Dec) and in January 2014 are context, not cohorts.
    - End of data = latest dated order (computed). Eligible for N days = first
      order date <= end of data - N days (DATEDIFF(day), inclusive). Second
      order within N days = second order of the sequence dated at most N days
      after the first. A distinct order_number on the first order's date counts
      (0 days) and is reported (7.9).
    - January 2014 orders count as follow-up, never as cohort membership
      (exception to 7.1, see 7.9); B3 shows the effect.
    - Minimum group size: rates, medians and shares are shown only where the
      eligible count is at least 100 (NULL below that); counts are always shown.
    - Order class (7.8): Bikes only / Bikes + other / No bikes, from the
      categories of the order's lines.
    - Revenue = SUM(sales_amount); order = distinct order_number.

Method:
    Collapse the lines once to orders, derive the sequence with ROW_NUMBER, and
    aggregate to customers. Every CTE built on the Gold views is referenced once
    (CLAUDE.md, Known pitfalls). No temp tables or other objects.

Caveats:
    - Customers are observed from 2010-12-29: a first order in the data may not
      be the customer's first order ever. 2011 is the cohort most likely to be
      affected, in a direction that cannot be checked.
    - Cohort is confounded with calendar: Accessories and Clothing appear from
      December 2012 (Q2), so the 2012 cohort's follow-up falls largely in 2013
      with a different catalog, while 2011's falls mostly in the Bikes-only
      period. Cohort differences are not cohort effects (B2 shows the timing).
    - D and E use first orders from 2012-12-01 only, because all three classes
      exist for the whole follow-up window from then. Class is still confounded
      with calendar inside 2013.
    - Same-day second orders may be split baskets or real repeats; the data
      cannot tell. January 2014 has an unexplained AOV (Q1).
    - Orders per customer (A) depends on the length of follow-up and is not
      comparable across cohorts.
    - Section F counts orders, not customers; a customer with several orders
      weighs several times (F also shows distinct customers).

Control totals (section G): lines 60,398 / orders 27,659 /
    revenue 29,356,250 / units 60,423 / customers 18,484.

Read-only: SELECT statements only.
Run:
    scripts\run_analysis.ps1 -Script analysis\03_repeat_purchasing.sql -DatabaseName DataWarehouse_Test
    (or: sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\03_repeat_purchasing.sql)
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
A. CUSTOMERS AND ORDERS BY COHORT GROUP
===============================================================================
Partition of all customers by the date of their first dated order. orders_dated
are the dated orders of those customers; undated_orders are outside the
sequence. orders_per_customer depends on the follow-up length and is NOT
comparable across cohorts. customers_2plus_orders_all counts all orders (dated
and undated) and is the descriptive context of decision 7.6 (6,865 customers
with two or more orders); customers_2plus_dated_orders counts dated orders only.
first_date_ties = customers with more than one order on their first date.
*/

PRINT '--- A. CUSTOMERS AND ORDERS BY COHORT GROUP ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT cu.*,
           CASE WHEN first_dt IS NULL          THEN '6. No dated order'
                WHEN first_dt <  '2011-01-01'  THEN '1. First order in 2010 tail (context)'
                WHEN first_dt >= '2014-01-01'  THEN '5. First order in January 2014 (context)'
                ELSE '' + CAST(YEAR(first_dt) - 2009 AS VARCHAR(2)) + '. Cohort ' + CAST(YEAR(first_dt) AS VARCHAR(4)) END AS grp
    FROM cu
)
SELECT
    CASE WHEN GROUPING(grp) = 1 THEN 'TOTAL' ELSE grp END                         AS cohort_group,
    COUNT(*)                                                                      AS customers,
    SUM(n_dated)                                                                  AS orders_dated,
    SUM(n_undated)                                                                AS undated_orders,
    CAST(1.0 * SUM(n_dated) / COUNT(*) AS DECIMAL(6,2))                           AS orders_per_customer,
    SUM(CASE WHEN n_dated  >= 2 THEN 1 ELSE 0 END)                                AS customers_2plus_dated_orders,
    SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END)                                AS customers_2plus_orders_all,
    SUM(CASE WHEN n_on_first > 1 THEN 1 ELSE 0 END)                               AS first_date_ties
FROM x
GROUP BY ROLLUP (grp)
ORDER BY GROUPING(grp), grp;
GO


/*
===============================================================================
B. SECOND ORDER WITHIN 90 / 180 / 365 DAYS BY COHORT
===============================================================================
eligible = customers whose first order is at least N days before the end of
data. reordered = eligible customers with a second order within N days;
of_which_same_day = second order on the first order's date. rate_pct and
rate_excl_same_day_pct (reorders with a gap of at least one day) are shown only
where eligible >= 100. N = 365 covers the 2011 and 2012 cohorts and only the
first orders of 2013 up to 2013-01-28. Cohort differences are not cohort effects
(confounded with calendar and catalog): see header caveats and B2.
*/

PRINT '--- B1. SECOND ORDER WITHIN N DAYS BY COHORT ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        YEAR(cu.first_dt) AS cohort, v.n AS window_days,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) <= v.n THEN 1 ELSE 0 END AS re,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) = 0     THEN 1 ELSE 0 END AS sd
    FROM cu
    CROSS JOIN (VALUES (90), (180), (365)) v(n)
    WHERE cu.first_dt >= '2011-01-01' AND cu.first_dt < '2014-01-01'
      AND DATEDIFF(day, cu.first_dt, cu.end_dt) >= v.n
)
SELECT
    cohort, window_days,
    COUNT(*)                                                                           AS eligible,
    SUM(re)                                                                            AS reordered,
    SUM(CASE WHEN re = 1 THEN sd ELSE 0 END)                                           AS of_which_same_day,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(re) / COUNT(*) AS DECIMAL(5,1)) END AS rate_pct,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * (SUM(re) - SUM(CASE WHEN re = 1 THEN sd ELSE 0 END)) / COUNT(*) AS DECIMAL(5,1)) END AS rate_excl_same_day_pct
FROM x
GROUP BY cohort, window_days
ORDER BY window_days, cohort;
GO

/*
B2. Second orders by calendar quarter of the second order and by cohort (all
customers with a second order, regardless of eligibility): counts only. It
shows whether a cohort difference is a jump in calendar time.
*/

PRINT '--- B2. SECOND ORDERS BY CALENDAR QUARTER AND COHORT ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
)
SELECT
    YEAR(first_dt)                                                                         AS cohort,
    DATEFROMPARTS(YEAR(second_dt), (MONTH(second_dt) - 1) / 3 * 3 + 1, 1)                  AS quarter_of_second_order,
    COUNT(*)                                                                               AS second_orders
FROM cu
WHERE first_dt >= '2011-01-01' AND first_dt < '2014-01-01' AND second_dt IS NOT NULL
GROUP BY YEAR(first_dt), DATEFROMPARTS(YEAR(second_dt), (MONTH(second_dt) - 1) / 3 * 3 + 1, 1)
ORDER BY cohort, quarter_of_second_order;
GO

/*
B3. Sensitivity of N = 90 to January 2014: the same measure with end of data =
latest dated order (as in B1) and with end of data = 2013-12-31 (no January 2014
follow-up; later second orders are not counted and eligibility ends earlier).
*/

PRINT '--- B3. SENSITIVITY TO JANUARY 2014 FOLLOW-UP (N = 90) ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        v.variant, YEAR(cu.first_dt) AS cohort,
        CASE WHEN cu.second_dt IS NOT NULL
              AND DATEDIFF(day, cu.first_dt, cu.second_dt) <= 90
              AND cu.second_dt <= ISNULL(v.cap_dt, cu.end_dt) THEN 1 ELSE 0 END AS re
    FROM cu
    CROSS JOIN (VALUES ('end of data = latest dated order', CAST(NULL AS DATE)),
                       ('end of data = 2013-12-31',         CAST('2013-12-31' AS DATE))) v(variant, cap_dt)
    WHERE cu.first_dt >= '2011-01-01' AND cu.first_dt < '2014-01-01'
      AND DATEDIFF(day, cu.first_dt, ISNULL(v.cap_dt, cu.end_dt)) >= 90
)
SELECT
    variant, cohort,
    COUNT(*)                                                                           AS eligible,
    SUM(re)                                                                            AS reordered,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(re) / COUNT(*) AS DECIMAL(5,1)) END AS rate_pct
FROM x
GROUP BY variant, cohort
ORDER BY cohort, variant;
GO


/*
===============================================================================
C. DAYS TO SECOND ORDER (CUSTOMERS ELIGIBLE FOR 365 DAYS, REORDER WITHIN 365)
===============================================================================
Same follow-up window for every cohort: eligible customers are those whose
first order is at least 365 days before the end of data; only second orders
within 365 days are measured. The median and the band shares are of customers
who reordered within 365 days and are shown only where eligible >= 100.
Bands: 0 (same day), 1-30, 31-90, 91-180, 181-365 days.
C2 states the number of 2013-cohort customers eligible at N = 365.
*/

PRINT '--- C1. DAYS TO SECOND ORDER BY COHORT ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        YEAR(first_dt) AS cohort,
        CASE WHEN second_dt IS NOT NULL AND DATEDIFF(day, first_dt, second_dt) <= 365
             THEN DATEDIFF(day, first_dt, second_dt) END AS gap
    FROM cu
    WHERE first_dt >= '2011-01-01' AND first_dt < '2014-01-01'
      AND DATEDIFF(day, first_dt, end_dt) >= 365
),
m AS (
    SELECT cohort, gap,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap) OVER (PARTITION BY cohort) AS median_gap
    FROM x
)
SELECT
    cohort,
    COUNT(*)                                                                    AS eligible,
    COUNT(gap)                                                                  AS reordered_within_365,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(median_gap) AS DECIMAL(6,1)) END    AS median_days,
    SUM(CASE WHEN gap = 0              THEN 1 ELSE 0 END)                       AS n_0_days,
    SUM(CASE WHEN gap BETWEEN 1 AND 30   THEN 1 ELSE 0 END)                     AS n_1_30,
    SUM(CASE WHEN gap BETWEEN 31 AND 90  THEN 1 ELSE 0 END)                     AS n_31_90,
    SUM(CASE WHEN gap BETWEEN 91 AND 180 THEN 1 ELSE 0 END)                     AS n_91_180,
    SUM(CASE WHEN gap BETWEEN 181 AND 365 THEN 1 ELSE 0 END)                    AS n_181_365,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(CASE WHEN gap = 0 THEN 1 ELSE 0 END) / NULLIF(COUNT(gap), 0) AS DECIMAL(5,1)) END AS pct_0_days,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(CASE WHEN gap BETWEEN 1 AND 30 THEN 1 ELSE 0 END) / NULLIF(COUNT(gap), 0) AS DECIMAL(5,1)) END AS pct_1_30,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(CASE WHEN gap BETWEEN 31 AND 90 THEN 1 ELSE 0 END) / NULLIF(COUNT(gap), 0) AS DECIMAL(5,1)) END AS pct_31_90,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(CASE WHEN gap BETWEEN 91 AND 180 THEN 1 ELSE 0 END) / NULLIF(COUNT(gap), 0) AS DECIMAL(5,1)) END AS pct_91_180,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(CASE WHEN gap BETWEEN 181 AND 365 THEN 1 ELSE 0 END) / NULLIF(COUNT(gap), 0) AS DECIMAL(5,1)) END AS pct_181_365
FROM m
GROUP BY cohort
ORDER BY cohort;
GO

PRINT '--- C2. 2013-COHORT CUSTOMERS ELIGIBLE AT N = 365 ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
)
SELECT
    '2013 cohort, eligible at N = 365'                                       AS description,
    COUNT(*)                                                                 AS eligible_customers,
    MIN(first_dt)                                                            AS first_order_from,
    MAX(first_dt)                                                            AS first_order_to,
    MAX(end_dt)                                                              AS end_of_data
FROM cu
WHERE first_dt >= '2013-01-01' AND first_dt < '2014-01-01'
  AND DATEDIFF(day, first_dt, end_dt) >= 365;
GO


/*
===============================================================================
D. SECOND ORDER BY CLASS OF THE FIRST ORDER (FIRST ORDERS FROM 2012-12-01)
===============================================================================
Population: customers whose first order is on or after 2012-12-01, the period
in which all three classes exist for the whole follow-up window (a pooled
2011-2013 table would compare catalogs, not customers). Eligible for N = 90 /
180 days. Variant "excluding ties" drops customers with more than one order on
their first date, because the first order's class then depends on the arbitrary
tie-break. Rates only where eligible >= 100. D2 splits by quarter of the first
order (the mix still changes within 2013).
*/

PRINT '--- D1. SECOND ORDER WITHIN N DAYS BY FIRST-ORDER CLASS ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        va.variant, v.n AS window_days, cu.first_cls,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) <= v.n THEN 1 ELSE 0 END AS re,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) = 0     THEN 1 ELSE 0 END AS sd
    FROM cu
    CROSS JOIN (VALUES (90), (180)) v(n)
    CROSS JOIN (VALUES ('all customers'), ('excluding customers with >1 order on first date')) va(variant)
    WHERE cu.first_dt >= '2012-12-01'
      AND DATEDIFF(day, cu.first_dt, cu.end_dt) >= v.n
      AND (va.variant = 'all customers' OR cu.n_on_first = 1)
)
SELECT
    variant, window_days, first_cls AS first_order_class,
    COUNT(*)                                                                           AS eligible,
    SUM(re)                                                                            AS reordered,
    SUM(CASE WHEN re = 1 THEN sd ELSE 0 END)                                           AS of_which_same_day,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(re) / COUNT(*) AS DECIMAL(5,1)) END AS rate_pct,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * (SUM(re) - SUM(CASE WHEN re = 1 THEN sd ELSE 0 END)) / COUNT(*) AS DECIMAL(5,1)) END AS rate_excl_same_day_pct
FROM x
GROUP BY variant, window_days, first_cls
ORDER BY variant, window_days, first_cls;
GO

PRINT '--- D2. BY QUARTER OF THE FIRST ORDER ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        DATEFROMPARTS(YEAR(cu.first_dt), (MONTH(cu.first_dt) - 1) / 3 * 3 + 1, 1) AS first_order_quarter,
        v.n AS window_days, cu.first_cls,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) <= v.n THEN 1 ELSE 0 END AS re
    FROM cu
    CROSS JOIN (VALUES (90), (180)) v(n)
    WHERE cu.first_dt >= '2012-12-01'
      AND DATEDIFF(day, cu.first_dt, cu.end_dt) >= v.n
)
SELECT
    first_order_quarter, window_days, first_cls AS first_order_class,
    COUNT(*)                                                                           AS eligible,
    SUM(re)                                                                            AS reordered,
    CASE WHEN COUNT(*) >= 100 THEN CAST(100.0 * SUM(re) / COUNT(*) AS DECIMAL(5,1)) END AS rate_pct
FROM x
GROUP BY first_order_quarter, window_days, first_cls
ORDER BY window_days, first_order_quarter, first_cls;
GO


/*
===============================================================================
E. CLASS OF THE SECOND ORDER AGAINST CLASS OF THE FIRST ORDER
===============================================================================
Same population as D at N = 180: customers whose first order is on or after
2012-12-01 and who are eligible for 180 days. The second class is that of the
second order if it falls within 180 days; otherwise "(no second order within
180 days)". row_pct is the share of the first-order class's eligible customers
(row total) and is shown only where the row total is at least 100. Variant
"excluding ties" as in D.
*/

PRINT '--- E. CLASS OF SECOND ORDER AGAINST CLASS OF FIRST ORDER (N = 180) ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013
    FROM s
    GROUP BY customer_key
),
x AS (
    SELECT
        va.variant, cu.first_cls,
        CASE WHEN cu.second_dt IS NOT NULL AND DATEDIFF(day, cu.first_dt, cu.second_dt) <= 180
             THEN cu.second_cls ELSE '(no second order within 180 days)' END AS second_label
    FROM cu
    CROSS JOIN (VALUES ('all customers'), ('excluding customers with >1 order on first date')) va(variant)
    WHERE cu.first_dt >= '2012-12-01'
      AND DATEDIFF(day, cu.first_dt, cu.end_dt) >= 180
      AND (va.variant = 'all customers' OR cu.n_on_first = 1)
),
g AS (
    SELECT variant, first_cls, second_label, COUNT(*) AS customers,
           SUM(COUNT(*)) OVER (PARTITION BY variant, first_cls) AS row_total
    FROM x
    GROUP BY variant, first_cls, second_label
)
SELECT
    variant, first_cls AS first_order_class, second_label AS second_order_class, customers, row_total AS eligible_in_row,
    CASE WHEN row_total >= 100 THEN CAST(100.0 * customers / row_total AS DECIMAL(5,1)) END AS row_pct
FROM g
ORDER BY variant, first_cls, second_label;
GO


/*
===============================================================================
F. THE 2013 NO-BIKES ORDERS: FIRST ORDERS OR LATER ORDERS?
===============================================================================
Population: orders with class No bikes dated in 2013 (11,581 expected, 7.8).
Rules applied in this order (decision 7.9):
  a. first order of the customer;
  b. later order on the same date as the customer's first order;
  c. later date, the customer has a Bike in an order dated earlier;
  d. later date, no Bike in an earlier-dated order, but a Bike in another order
     on the same date;
  e. later date, no Bike in any earlier-dated or same-date order (a result, not
     a leftover: for example customers whose earlier orders were No bikes);
  unclassified: defensive catch-all, must be 0.
Shares are of ORDERS, not customers; distinct customers per category are shown
as well. This describes the sequence of orders only: it does not separate a new
kind of customer from an existing Bike customer, and says nothing about why
customers bought. A Bike bought before 2010-12-29 is not visible.
F2 gives the customer view and the reverse denominator.
*/

PRINT '--- F1. 2013 NO-BIKES ORDERS BY POSITION IN THE CUSTOMER SEQUENCE ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt,
        SUM(CASE WHEN bike_lines > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY customer_key, order_dt) AS bike_orders_same_date
    FROM o
),
t AS (
    SELECT
        customer_key,
        CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN
            CASE WHEN rn = 1                         THEN 'a. first order of the customer'
                 WHEN order_dt = first_dt            THEN 'b. later order, same date as the first order'
                 WHEN earliest_bike_dt < order_dt    THEN 'c. later date, Bike in an earlier-dated order'
                 WHEN bike_orders_same_date > 0      THEN 'd. later date, no earlier Bike, Bike on the same date'
                 WHEN order_dt > first_dt            THEN 'e. later date, no Bike earlier or on the same date'
                 ELSE 'unclassified' END
        END AS fcat
    FROM s
),
a AS (
    SELECT
        CASE WHEN GROUPING(fcat) = 1 THEN 'TOTAL' ELSE fcat END AS cat,
        COUNT(*)                     AS orders,
        COUNT(DISTINCT customer_key)  AS customers
    FROM t
    WHERE fcat IS NOT NULL
    GROUP BY ROLLUP (fcat)
)
SELECT
    k.cat                                                                             AS category,
    ISNULL(a.orders, 0)                                                               AS orders,
    CAST(100.0 * ISNULL(a.orders, 0) / SUM(CASE WHEN k.cat = 'TOTAL' THEN a.orders END) OVER () AS DECIMAL(5,1)) AS pct_of_orders,
    ISNULL(a.customers, 0)                                                            AS distinct_customers
FROM (VALUES ('a. first order of the customer'),
             ('b. later order, same date as the first order'),
             ('c. later date, Bike in an earlier-dated order'),
             ('d. later date, no earlier Bike, Bike on the same date'),
             ('e. later date, no Bike earlier or on the same date'),
             ('unclassified'),
             ('TOTAL')) k(cat)
LEFT JOIN a ON a.cat = k.cat
ORDER BY CASE WHEN k.cat = 'TOTAL' THEN 'z' WHEN k.cat = 'unclassified' THEN 'y' ELSE k.cat END;
GO

PRINT '--- F2. CUSTOMER VIEW AND REVERSE DENOMINATOR ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MAX(order_dt) OVER ()                                                 AS end_dt,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt
    FROM o
),
cu AS (
    SELECT
        customer_key,
        COUNT(*)                                                        AS n_orders,
        SUM(CASE WHEN order_dt IS NOT NULL THEN 1 ELSE 0 END)           AS n_dated,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)               AS n_undated,
        MAX(first_dt)                                                   AS first_dt,
        MAX(end_dt)                                                     AS end_dt,
        MAX(earliest_bike_dt)                                           AS earliest_bike_dt,
        MAX(CASE WHEN rn = 1 AND order_dt IS NOT NULL THEN cls END)     AS first_cls,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN order_dt END) AS second_dt,
        MAX(CASE WHEN rn = 2 AND order_dt IS NOT NULL THEN cls END)     AS second_cls,
        SUM(CASE WHEN order_dt = first_dt THEN 1 ELSE 0 END)            AS n_on_first,
        SUM(CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN 1 ELSE 0 END) AS nb_orders_2013,
        SUM(CASE WHEN cls = 'No bikes' THEN 1 ELSE 0 END)               AS nb_orders_all
    FROM s
    GROUP BY customer_key
)
SELECT
    d.description, d.customers, d.of_which, d.of_which_description,
    CAST(100.0 * d.of_which / NULLIF(d.customers, 0) AS DECIMAL(5,1)) AS pct
FROM (
    SELECT
        'customers with at least one No bikes order in 2013'                         AS description,
        SUM(CASE WHEN nb_orders_2013 > 0 THEN 1 ELSE 0 END)                          AS customers,
        SUM(CASE WHEN nb_orders_2013 > 0 AND earliest_bike_dt < '2013-01-01' THEN 1 ELSE 0 END) AS of_which,
        'of which had a Bike in an order dated before 2013'                          AS of_which_description
    FROM cu
    UNION ALL
    SELECT
        'customers with a Bike in an order dated before 2013',
        SUM(CASE WHEN earliest_bike_dt < '2013-01-01' THEN 1 ELSE 0 END),
        SUM(CASE WHEN earliest_bike_dt < '2013-01-01' AND nb_orders_2013 > 0 THEN 1 ELSE 0 END),
        'of which placed a No bikes order in 2013'
    FROM cu
    UNION ALL
    SELECT
        'customers with at least one Bike order (any date)',
        SUM(CASE WHEN earliest_bike_dt IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN earliest_bike_dt IS NOT NULL AND nb_orders_all > 0 THEN 1 ELSE 0 END),
        'of which also placed at least one No bikes order (any date)'
    FROM cu
    UNION ALL
    SELECT
        'customers with at least one No bikes order (any date)',
        SUM(CASE WHEN nb_orders_all > 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN nb_orders_all > 0 AND earliest_bike_dt IS NOT NULL THEN 1 ELSE 0 END),
        'of which also placed at least one Bike order (any date)'
    FROM cu
) d;
GO


/*
===============================================================================
G. CONTROL TOTALS
===============================================================================
Lines, orders, revenue, units and customers must match the fact table totals;
customers and orders are partitioned by cohort group; section F must add up to
11,581 with "unclassified" = 0 (the defensive catch-all).
*/

PRINT '--- G. CONTROL TOTALS ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.order_date)                                    AS order_dt,
        COUNT(*)                                             AS lines,
        SUM(CAST(f.sales_amount AS BIGINT))                  AS revenue,
        SUM(CAST(f.quantity AS BIGINT))                      AS units,
        SUM(CASE WHEN p.category = 'Bikes' THEN 1 ELSE 0 END) AS bike_lines
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
    GROUP BY f.order_number
),
s AS (
    SELECT
        customer_key, order_number, order_dt, lines, revenue, units, bike_lines,
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                         AS cls,
        ROW_NUMBER() OVER (PARTITION BY customer_key
                           ORDER BY CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END, order_dt, order_number) AS rn,
        MIN(order_dt) OVER (PARTITION BY customer_key)                         AS first_dt,
        MIN(CASE WHEN bike_lines > 0 THEN order_dt END) OVER (PARTITION BY customer_key) AS earliest_bike_dt,
        SUM(CASE WHEN bike_lines > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY customer_key, order_dt) AS bike_orders_same_date
    FROM o
),
t AS (
    SELECT
        customer_key, order_dt, lines, revenue, units, rn,
        CASE WHEN first_dt IS NULL          THEN 'no dated order'
             WHEN first_dt <  '2011-01-01'  THEN '2010 tail'
             WHEN first_dt <  '2014-01-01'  THEN 'cohort ' + CAST(YEAR(first_dt) AS VARCHAR(4))
             ELSE 'january 2014' END AS grp,
        CASE WHEN cls = 'No bikes' AND order_dt >= '2013-01-01' AND order_dt < '2014-01-01' THEN
            CASE WHEN rn = 1                         THEN 'a'
                 WHEN order_dt = first_dt            THEN 'b'
                 WHEN earliest_bike_dt < order_dt    THEN 'c'
                 WHEN bike_orders_same_date > 0      THEN 'd'
                 WHEN order_dt > first_dt            THEN 'e'
                 ELSE 'unclassified' END
        END AS fcat
    FROM s
),
r AS (
    SELECT
        SUM(CAST(lines AS BIGINT))                                                   AS tot_lines,
        COUNT(*)                                                                     AS tot_orders,
        SUM(revenue)                                                                 AS tot_revenue,
        SUM(units)                                                                   AS tot_units,
        COUNT(DISTINCT customer_key)                                                  AS tot_customers,
        SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END)                         AS orders_without_customer,
        SUM(CASE WHEN order_dt IS NULL THEN 1 ELSE 0 END)                            AS undated_orders,
        SUM(CASE WHEN rn = 1 AND grp IN ('2010 tail', 'cohort 2011', 'cohort 2012', 'cohort 2013', 'january 2014', 'no dated order') THEN 1 ELSE 0 END) AS customers_in_groups,
        SUM(CASE WHEN grp IN ('2010 tail', 'cohort 2011', 'cohort 2012', 'cohort 2013', 'january 2014', 'no dated order') THEN 1 ELSE 0 END)           AS orders_in_groups,
        SUM(CASE WHEN fcat IS NOT NULL THEN 1 ELSE 0 END)                            AS f_orders,
        SUM(CASE WHEN fcat = 'unclassified' THEN 1 ELSE 0 END)                       AS f_unclassified,
        (SELECT COUNT(DISTINCT customer_id) FROM gold.dim_customers)                 AS dim_customer_ids
    FROM t
)
SELECT
    c.check_name,
    c.actual_value,
    c.expected_value,
    CASE WHEN c.actual_value = c.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM r
CROSS APPLY (VALUES
    ('lines',                                                      CAST(tot_lines AS BIGINT),        CAST(60398 AS BIGINT)),
    ('orders',                                                     CAST(tot_orders AS BIGINT),       27659),
    ('revenue',                                                    CAST(tot_revenue AS BIGINT),      29356250),
    ('units',                                                      CAST(tot_units AS BIGINT),        60423),
    ('customers (distinct customer_key in the fact table)',        CAST(tot_customers AS BIGINT),    18484),
    ('customers (distinct customer_id in gold.dim_customers)',     CAST(dim_customer_ids AS BIGINT), 18484),
    ('orders without a customer',                                  CAST(orders_without_customer AS BIGINT), 0),
    ('undated orders',                                             CAST(undated_orders AS BIGINT),   2),
    ('customers in cohort groups (partition)',                     CAST(customers_in_groups AS BIGINT), 18484),
    ('orders of customers in cohort groups (partition)',           CAST(orders_in_groups AS BIGINT), 27659),
    ('section F: 2013 No bikes orders',                            CAST(f_orders AS BIGINT),         11581),
    ('section F: unclassified orders',                             CAST(f_unclassified AS BIGINT),   0)
) AS c(check_name, actual_value, expected_value);
GO
