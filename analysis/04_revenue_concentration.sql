/*
===============================================================================
ANALYSIS 04 - REVENUE CONCENTRATION (Q4)
===============================================================================
Business question:
    How concentrated is revenue: what share of revenue is accounted for by the
    highest-revenue customers and products? The analysis is descriptive: it
    shows how much revenue the largest entities account for. It makes no claim
    of dependence and no causal claim.

Data required:
    gold.fact_sales: order_number, customer_key, product_key, order_date,
                     sales_amount, quantity.
    gold.dim_products: product_key -> product_number, category (295 current
                       versions; small, so the join is cheap).
    gold.dim_customers: customer_id, used only in section G as a scalar count.
                        Inside the script customers are grouped by
                        fact_sales.customer_key, which is never reported or
                        hardcoded (Known pitfalls; decision 7.9 rule 1).

Grain:
    - Base grain: one row of gold.fact_sales (an order line).
    - Customers: lines are collapsed once to one row per order (CTE o), then to
      one row per customer and year (CTE cy), then the customer group is added
      (CTE cg). Ranks and shares are derived with window functions.
    - Products: lines get the order-level date by window, are grouped by
      product_key and year, and only then joined to the 295-row dimension.
    - Sections: A customers by year; B customer concentration, all customers
      (2011 and 2012 are context only); C customer groups (the customer result
      of Q4 is 2013 within each group; C1 group summary, C2 top shares inside
      each group); D sensitivity to the group rule; E products (E1
      distribution, E2 rank-based cuts, E3 the 10 largest per year);
      F category shares; G control totals.

Definitions (decisions 7.1, 7.2, 7.8 and 7.10 in docs/decisions.md):
    - Year = year of the order-level date, MIN(order_date) over the order
      (7.2). Years 2011-2013 are compared (7.1). The 2010 tail, January 2014
      and the 2 undated orders appear only as context rows (A, G).
    - Entity-year: one row per customer (or product) per year with revenue =
      SUM(sales_amount). An entity is active in a year if it has such a row;
      N = active entities in that year.
    - Customer top group: the k highest-revenue active customers for
      p = 1, 5, 10, 20 percent; k = CEILING(p x N) in integer arithmetic,
      (p x N + 99) / 100. Share = revenue of the top group / revenue of all
      active customers in the year (or of the group in C). Every share is
      printed with k and N.
    - Product cuts: top 1, 5, 10 and 20 products by revenue (rank-based, no
      percentages), with N; E3 lists the 10 largest per year. Rank ties are
      broken by product_number.
    - Ties: tied entities have equal revenue, so the SHARE of the top k does
      not depend on which tied entities are picked (it does not hold for the
      identity of the entities). Section D varies the group rule instead:
      CEILING, FLOOR, and tie-inclusive (every entity tied with the k-th is in
      the group), with the number of entities tied at the boundary.
    - Minimum sizes (Q4-specific, declared before the run, not part of
      decision 7): a customer statistic is interpreted only if the base is at
      least 100 active customers and the top group has at least 30; otherwise
      it is printed and flagged 'not interpreted'. Reason: a percentage means
      little on a small base; the shares cover the whole population, so this
      is about meaning, not sampling noise. Distribution statistics are shown
      only where N is at least 100.
    - Customer group (decision 7.10): Bike customer = at least one order with an
      order-level date that contains a Bike line; No bikes customer = every
      other customer (as in Q3 section F2). The 2 customers with no dated
      order are No bikes customers and have no revenue in any year.
    - Revenue = SUM(sales_amount) (currency unknown); order = distinct
      order_number.

Method:
    Collapse the lines once to orders, then to customer-year; derive the rest
    from that small result with window functions (ROW_NUMBER, RANK, COUNT OVER,
    SUM OVER, PERCENTILE_CONT OVER) and conditional aggregation. Every CTE built
    on the Gold views is referenced once (CLAUDE.md, Known pitfalls). Each
    section repeats the chain. No temp tables or other objects.

Caveats:
    - In 2011 every customer has one order of one line, so revenue per customer
      is the price of one bike; 2012 is nearly the same. Customer concentration
      for 2011 and 2012 is context only and is not compared across years as a
      trend. In 2013 the year mixes Bike orders and No bikes orders (Q2
      section H). The customer result of Q4 is section C for 2013.
    - A customer's yearly revenue depends on the months active; in 2013 there
      are 12,521 first-time customers, and there is no No bikes order in 2011
      or 2012 (Q2 section H).
    - Customers are not followed across years.
    - A revenue share reflects price, not popularity.
    - Product = distinct product_number, current version only (Q2): a
      relaunch under a new number counts as two products.

Control totals (section G): lines 60,398 / orders 27,659 /
    revenue 29,356,250 / units 60,423 / customers 18,484; revenue by year
    against Q1 section A; groups, products and categories add up to the year;
    customer groups 9,132 + 9,352 = 18,484 with no overlap.

Read-only: SELECT statements only.
Run:
    scripts\run_analysis.ps1 -Script analysis\04_revenue_concentration.sql -DatabaseName DataWarehouse_Test
    (or: sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\04_revenue_concentration.sql)
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
A. ACTIVE CUSTOMERS AND REVENUE BY YEAR
===============================================================================
One row per period: active customers, revenue, distribution of revenue per
customer (shown only where N >= 100) and the split of customers by number of
orders in the year (1 / 2 / 3 or more) with their revenue. The context rows
(2010 tail, January 2014, undated orders) are there so that revenue ties to
control totals; they are not compared.
*/

PRINT '--- A. ACTIVE CUSTOMERS AND REVENUE PER CUSTOMER BY YEAR ---';

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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
pa AS (
    SELECT
        yr, orders, revenue,
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p10,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p75,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p90,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p99
    FROM cy
)
SELECT
    CASE WHEN yr IS NULL  THEN '9. Undated orders (no dated order)'
         WHEN yr = 2010   THEN '1. Context: 2010 tail (29-31 Dec)'
         WHEN yr = 2014   THEN '5. Context: January 2014 (1-28 Jan)'
         ELSE '2. Main: ' + CAST(yr AS VARCHAR(4)) END                    AS period,
    COUNT(*)                                                              AS active_customers,
    SUM(revenue)                                                          AS revenue,
    CASE WHEN COUNT(*) >= 100 THEN CAST(1.0 * SUM(revenue) / COUNT(*) AS DECIMAL(12,2)) END AS mean_revenue,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p10) AS DECIMAL(12,2)) END    AS p10,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p25) AS DECIMAL(12,2)) END    AS p25,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p50) AS DECIMAL(12,2)) END    AS median,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p75) AS DECIMAL(12,2)) END    AS p75,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p90) AS DECIMAL(12,2)) END    AS p90,
    CASE WHEN COUNT(*) >= 100 THEN CAST(MAX(p99) AS DECIMAL(12,2)) END    AS p99,
    CASE WHEN COUNT(*) >= 100 THEN MAX(revenue) END                       AS max_revenue,
    CASE WHEN COUNT(*) >= 100 THEN CAST(1.0 * SUM(revenue) / COUNT(*) / NULLIF(MAX(p50), 0) AS DECIMAL(8,2)) END AS mean_over_median,
    SUM(CASE WHEN orders = 1 THEN 1 ELSE 0 END)                           AS customers_1_order,
    SUM(CASE WHEN orders = 1 THEN revenue ELSE 0 END)                     AS revenue_1_order,
    SUM(CASE WHEN orders = 2 THEN 1 ELSE 0 END)                           AS customers_2_orders,
    SUM(CASE WHEN orders = 2 THEN revenue ELSE 0 END)                     AS revenue_2_orders,
    SUM(CASE WHEN orders >= 3 THEN 1 ELSE 0 END)                          AS customers_3plus_orders,
    SUM(CASE WHEN orders >= 3 THEN revenue ELSE 0 END)                    AS revenue_3plus_orders
FROM pa
GROUP BY yr
ORDER BY CASE WHEN yr IS NULL THEN 1 ELSE 0 END, yr;
GO


/*
===============================================================================
B. CUSTOMER CONCENTRATION, ALL CUSTOMERS
===============================================================================
Top 1 / 5 / 10 / 20 percent of the active customers of each year. 2011 and 2012
are CONTEXT ONLY (one order per customer, so revenue per customer is the price
of one bike) and are not compared across years as a trend; 2013 as a whole
mixes two customer groups (see C for the customer result). interpretable =
'yes' only if N >= 100 and the top group has at least 30 customers.
*/

PRINT '--- B. CUSTOMER CONCENTRATION, ALL CUSTOMERS (CONTEXT; SEE C) ---';

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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        MAX(bike_dated) OVER (PARTITION BY customer_key)                  AS bike_any_c,
        MAX(nb_any)     OVER (PARTITION BY customer_key)                  AS nb_any_c
    FROM cy
),
cs AS (
    SELECT cg.yr, v.scope, cg.revenue
    FROM cg
    CROSS APPLY (VALUES ('All customers'), (cg.grp)) v(scope)
    WHERE cg.yr BETWEEN 2011 AND 2013
      AND v.scope = 'All customers'
),
rk AS (
    SELECT
        yr, scope, revenue,
        ROW_NUMBER() OVER (PARTITION BY yr, scope ORDER BY revenue DESC) AS rn,
        COUNT(*)     OVER (PARTITION BY yr, scope)                       AS n,
        SUM(revenue) OVER (PARTITION BY yr, scope)                       AS tot
    FROM cs
),
b AS (
    SELECT
        r.yr, r.scope, pv.p                                              AS top_pct,
        MAX(r.n)                                                         AS n,
        (pv.p * MAX(r.n) + 99) / 100                                     AS k,
        SUM(CASE WHEN r.rn <= (pv.p * r.n + 99) / 100 THEN r.revenue ELSE 0 END) AS top_rev,
        MAX(r.tot)                                                       AS tot
    FROM rk r
    CROSS JOIN (VALUES (1), (5), (10), (20)) pv(p)
    GROUP BY r.yr, r.scope, pv.p
)
SELECT
    yr                                                                   AS [year],
    top_pct,
    n                                                                    AS active_customers,
    k                                                                    AS top_group_customers,
    top_rev                                                              AS top_group_revenue,
    tot                                                                  AS total_revenue,
    CAST(100.0 * top_rev / NULLIF(tot, 0) AS DECIMAL(5,1))               AS share_pct,
    CASE WHEN n >= 100 AND k >= 30 THEN 'yes' ELSE 'not interpreted' END AS interpretable
FROM b
ORDER BY yr, top_pct;
GO


/*
===============================================================================
C1. CUSTOMER GROUPS (DECISION 7.10): SUMMARY BY YEAR
===============================================================================
THE CUSTOMER RESULT OF Q4 is 2013 within each group. Per year and group: active
customers, revenue, share of the year's revenue, and the distribution of
revenue per customer (shown only where N >= 100). In 2011 and 2012 the No bikes
group has no active customers (Q2 section H: no No bikes orders before 2013), so
its rows show 0.
*/

PRINT '--- C1. CUSTOMER GROUPS: SUMMARY BY YEAR ---';

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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        MAX(bike_dated) OVER (PARTITION BY customer_key)                  AS bike_any_c,
        MAX(nb_any)     OVER (PARTITION BY customer_key)                  AS nb_any_c
    FROM cy
),
cs AS (
    SELECT cg.yr, cg.grp AS scope, cg.revenue
    FROM cg
    WHERE cg.yr BETWEEN 2011 AND 2013
),
rk AS (
    SELECT
        yr, scope, revenue,
        COUNT(*)     OVER (PARTITION BY yr, scope)                       AS n,
        SUM(revenue) OVER (PARTITION BY yr, scope)                       AS tot,
        SUM(revenue) OVER (PARTITION BY yr)                              AS year_rev,
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p10,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p75,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p90,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr, scope) AS p99
    FROM cs
),
a AS (
    SELECT
        yr, scope,
        MAX(n)                                                           AS n,
        MAX(tot)                                                         AS revenue,
        MAX(year_rev)                                                    AS year_rev,
        MAX(p10) AS p10, MAX(p25) AS p25, MAX(p50) AS p50, MAX(p75) AS p75,
        MAX(p90) AS p90, MAX(p99) AS p99,
        MAX(revenue)                                                     AS max_revenue
    FROM rk
    GROUP BY yr, scope
)
SELECT
    v.yr                                                                 AS [year],
    v.scope                                                              AS customer_group,
    ISNULL(a.n, 0)                                                       AS active_customers,
    ISNULL(a.revenue, 0)                                                 AS revenue,
    CAST(100.0 * ISNULL(a.revenue, 0) / NULLIF(a.year_rev, 0) AS DECIMAL(5,1)) AS pct_of_year_revenue,
    CASE WHEN a.n >= 100 THEN CAST(1.0 * a.revenue / a.n AS DECIMAL(12,2)) END AS mean_revenue,
    CASE WHEN a.n >= 100 THEN CAST(a.p10 AS DECIMAL(12,2)) END           AS p10,
    CASE WHEN a.n >= 100 THEN CAST(a.p25 AS DECIMAL(12,2)) END           AS p25,
    CASE WHEN a.n >= 100 THEN CAST(a.p50 AS DECIMAL(12,2)) END           AS median,
    CASE WHEN a.n >= 100 THEN CAST(a.p75 AS DECIMAL(12,2)) END           AS p75,
    CASE WHEN a.n >= 100 THEN CAST(a.p90 AS DECIMAL(12,2)) END           AS p90,
    CASE WHEN a.n >= 100 THEN CAST(a.p99 AS DECIMAL(12,2)) END           AS p99,
    CASE WHEN a.n >= 100 THEN a.max_revenue END                          AS max_revenue,
    CASE WHEN a.n >= 100 THEN CAST(1.0 * a.revenue / a.n / NULLIF(a.p50, 0) AS DECIMAL(8,2)) END AS mean_over_median
FROM (VALUES
    (2011, 'Bike customer'), (2011, 'No bikes customer'),
    (2012, 'Bike customer'), (2012, 'No bikes customer'),
    (2013, 'Bike customer'), (2013, 'No bikes customer')
) v(yr, scope)
LEFT JOIN a ON a.yr = v.yr AND a.scope = v.scope
ORDER BY v.yr, v.scope;
GO


/*
===============================================================================
C2. CUSTOMER GROUPS: TOP SHARES INSIDE EACH GROUP
===============================================================================
Top 1 / 5 / 10 / 20 percent of the active customers of each group and year,
with the group's own revenue as denominator. interpretable = 'yes' only if the
group has at least 100 active customers and the top group has at least 30.
*/

PRINT '--- C2. CUSTOMER GROUPS: TOP SHARES INSIDE EACH GROUP ---';

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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        MAX(bike_dated) OVER (PARTITION BY customer_key)                  AS bike_any_c,
        MAX(nb_any)     OVER (PARTITION BY customer_key)                  AS nb_any_c
    FROM cy
),
cs AS (
    SELECT cg.yr, cg.grp AS scope, cg.revenue
    FROM cg
    WHERE cg.yr BETWEEN 2011 AND 2013
),
rk AS (
    SELECT
        yr, scope, revenue,
        ROW_NUMBER() OVER (PARTITION BY yr, scope ORDER BY revenue DESC) AS rn,
        COUNT(*)     OVER (PARTITION BY yr, scope)                       AS n,
        SUM(revenue) OVER (PARTITION BY yr, scope)                       AS tot
    FROM cs
),
b AS (
    SELECT
        r.yr, r.scope, pv.p                                              AS top_pct,
        MAX(r.n)                                                         AS n,
        (pv.p * MAX(r.n) + 99) / 100                                     AS k,
        SUM(CASE WHEN r.rn <= (pv.p * r.n + 99) / 100 THEN r.revenue ELSE 0 END) AS top_rev,
        MAX(r.tot)                                                       AS tot
    FROM rk r
    CROSS JOIN (VALUES (1), (5), (10), (20)) pv(p)
    GROUP BY r.yr, r.scope, pv.p
)
SELECT
    v0.yr                                                                AS [year],
    v0.scope                                                             AS customer_group,
    pp.p                                                                 AS top_pct,
    ISNULL(b.n, 0)                                                       AS active_customers,
    ISNULL(b.k, 0)                                                       AS top_group_customers,
    ISNULL(b.top_rev, 0)                                                 AS top_group_revenue,
    ISNULL(b.tot, 0)                                                     AS group_revenue,
    CAST(100.0 * b.top_rev / NULLIF(b.tot, 0) AS DECIMAL(5,1))           AS share_pct,
    CASE WHEN b.n >= 100 AND b.k >= 30 THEN 'yes' ELSE 'not interpreted' END AS interpretable
FROM (VALUES
    (2011, 'Bike customer'), (2011, 'No bikes customer'),
    (2012, 'Bike customer'), (2012, 'No bikes customer'),
    (2013, 'Bike customer'), (2013, 'No bikes customer')
) v0(yr, scope)
CROSS JOIN (VALUES (1), (5), (10), (20)) pp(p)
LEFT JOIN b ON b.yr = v0.yr AND b.scope = v0.scope AND b.top_pct = pp.p
ORDER BY v0.yr, v0.scope, pp.p;
GO


/*
===============================================================================
D. SENSITIVITY TO THE GROUP RULE
===============================================================================
Share of revenue of the top p percent under three rules for the size of the
group: CEILING (the rule used in B and C), FLOOR, and tie-inclusive (every
customer tied in revenue with the k-th is in the group). tied_at_boundary is
the number of customers whose revenue equals that of the k-th (1 = no tie).
For a fixed k the share does not depend on which tied customers are picked; the
rule changes the size of the group. FLOOR with k = 0 prints no share. Scopes:
all customers (B) and the two customer groups (C).
*/

PRINT '--- D. SENSITIVITY OF THE TOP SHARES TO THE GROUP RULE ---';

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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        MAX(bike_dated) OVER (PARTITION BY customer_key)                  AS bike_any_c,
        MAX(nb_any)     OVER (PARTITION BY customer_key)                  AS nb_any_c
    FROM cy
),
cs AS (
    SELECT cg.yr, v.scope, cg.revenue
    FROM cg
    CROSS APPLY (VALUES ('All customers'), (cg.grp)) v(scope)
    WHERE cg.yr BETWEEN 2011 AND 2013
),
rk AS (
    SELECT
        yr, scope, revenue,
        ROW_NUMBER() OVER (PARTITION BY yr, scope ORDER BY revenue DESC) AS rn,
        RANK()       OVER (PARTITION BY yr, scope ORDER BY revenue DESC) AS rnk,
        COUNT(*)     OVER (PARTITION BY yr, scope)                       AS n,
        SUM(revenue) OVER (PARTITION BY yr, scope)                       AS tot
    FROM cs
),
x AS (
    SELECT
        r.yr, r.scope, pv.p, r.revenue, r.rn, r.rnk, r.n, r.tot,
        (pv.p * r.n + 99) / 100                                          AS k_ceil,
        (pv.p * r.n) / 100                                               AS k_floor
    FROM rk r
    CROSS JOIN (VALUES (1), (5), (10), (20)) pv(p)
),
y AS (
    SELECT
        x.yr, x.scope, x.p, x.revenue, x.rn, x.rnk, x.n, x.tot, x.k_ceil, x.k_floor,
        MAX(CASE WHEN x.rn = x.k_ceil THEN x.revenue END)
            OVER (PARTITION BY x.yr, x.scope, x.p)                       AS kth_rev
    FROM x
),
d AS (
    SELECT
        yr, scope, p,
        MAX(n) AS n, MAX(k_ceil) AS k_ceil, MAX(k_floor) AS k_floor, MAX(tot) AS tot,
        SUM(CASE WHEN rn  <= k_ceil  THEN revenue ELSE 0 END)            AS rev_ceil,
        SUM(CASE WHEN rn  <= k_floor THEN revenue ELSE 0 END)            AS rev_floor,
        SUM(CASE WHEN rnk <= k_ceil  THEN 1 ELSE 0 END)                  AS k_tie,
        SUM(CASE WHEN rnk <= k_ceil  THEN revenue ELSE 0 END)            AS rev_tie,
        SUM(CASE WHEN revenue = kth_rev THEN 1 ELSE 0 END)               AS tied_at_boundary
    FROM y
    GROUP BY yr, scope, p
)
SELECT
    yr                                                                   AS [year],
    scope,
    p                                                                    AS top_pct,
    n                                                                    AS active_customers,
    k_ceil                                                               AS k_ceiling,
    CAST(100.0 * rev_ceil  / NULLIF(tot, 0) AS DECIMAL(6,2))             AS share_ceiling_pct,
    k_floor                                                              AS k_floor,
    CASE WHEN k_floor > 0 THEN CAST(100.0 * rev_floor / NULLIF(tot, 0) AS DECIMAL(6,2)) END AS share_floor_pct,
    k_tie                                                                AS k_tie_inclusive,
    CAST(100.0 * rev_tie   / NULLIF(tot, 0) AS DECIMAL(6,2))             AS share_tie_inclusive_pct,
    tied_at_boundary
FROM d
ORDER BY yr, scope, p;
GO


/*
===============================================================================
E. PRODUCTS (GRAIN: product_number, CURRENT VERSION)
===============================================================================
Product = distinct product_number of gold.dim_products (current versions; Q2
product-identity caveat). Cuts are rank-based (no percentages). Rank ties are
broken by product_number: the SHARE of a cut does not depend on the tie-break,
but the list can; ties are flagged.
E1 distribution of revenue per product by year; E2 top 1 / 5 / 10 / 20 products;
E3 the 10 largest products per year.
*/

PRINT '--- E1. PRODUCTS: ACTIVE PRODUCTS AND DISTRIBUTION OF REVENUE PER PRODUCT ---';

WITH l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date) OVER (PARTITION BY f.order_number)) AS yr,
        CAST(f.sales_amount AS BIGINT)                             AS revenue,
        CAST(f.quantity AS BIGINT)                                 AS units
    FROM gold.fact_sales f
),
py AS (
    SELECT product_key, yr, COUNT(*) AS lines, SUM(revenue) AS revenue, SUM(units) AS units
    FROM l
    GROUP BY product_key, yr
),
pd AS (
    SELECT py.yr, py.lines, py.revenue, py.units, p.product_number,
           ISNULL(p.category, 'Unclassified') AS category
    FROM py
    LEFT JOIN gold.dim_products p ON p.product_key = py.product_key
),
rkp AS (
    SELECT
        yr, product_number, category, revenue,
        COUNT(*)     OVER (PARTITION BY yr)                              AS n,
        SUM(revenue) OVER (PARTITION BY yr)                              AS tot,
        PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p10,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p75,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p90,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY revenue) OVER (PARTITION BY yr) AS p99
    FROM pd
    WHERE yr BETWEEN 2011 AND 2013
)
SELECT
    yr                                                                   AS [year],
    MAX(n)                                                               AS active_products,
    MAX(tot)                                                             AS revenue,
    CAST(1.0 * MAX(tot) / MAX(n) AS DECIMAL(12,2))                       AS mean_revenue,
    CAST(MAX(p10) AS DECIMAL(12,2))                                      AS p10,
    CAST(MAX(p25) AS DECIMAL(12,2))                                      AS p25,
    CAST(MAX(p50) AS DECIMAL(12,2))                                      AS median,
    CAST(MAX(p75) AS DECIMAL(12,2))                                      AS p75,
    CAST(MAX(p90) AS DECIMAL(12,2))                                      AS p90,
    CAST(MAX(p99) AS DECIMAL(12,2))                                      AS p99,
    MAX(revenue)                                                         AS max_revenue,
    CAST(1.0 * MAX(tot) / MAX(n) / NULLIF(MAX(p50), 0) AS DECIMAL(8,2))  AS mean_over_median
FROM rkp
GROUP BY yr
ORDER BY yr;
GO

PRINT '--- E2. PRODUCTS: TOP 1 / 5 / 10 / 20 PRODUCTS BY REVENUE ---';

WITH l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date) OVER (PARTITION BY f.order_number)) AS yr,
        CAST(f.sales_amount AS BIGINT)                             AS revenue,
        CAST(f.quantity AS BIGINT)                                 AS units
    FROM gold.fact_sales f
),
py AS (
    SELECT product_key, yr, COUNT(*) AS lines, SUM(revenue) AS revenue, SUM(units) AS units
    FROM l
    GROUP BY product_key, yr
),
pd AS (
    SELECT py.yr, py.lines, py.revenue, py.units, p.product_number,
           ISNULL(p.category, 'Unclassified') AS category
    FROM py
    LEFT JOIN gold.dim_products p ON p.product_key = py.product_key
),
rkp AS (
    SELECT
        yr, product_number, category, revenue,
        ROW_NUMBER() OVER (PARTITION BY yr ORDER BY revenue DESC, product_number) AS rn,
        COUNT(*)     OVER (PARTITION BY yr)                              AS n,
        SUM(revenue) OVER (PARTITION BY yr)                              AS tot,
        COUNT(*)     OVER (PARTITION BY yr, revenue)                     AS same_rev
    FROM pd
    WHERE yr BETWEEN 2011 AND 2013
)
SELECT
    r.yr                                                                 AS [year],
    pv.n_top                                                             AS top_products,
    MAX(r.n)                                                             AS active_products,
    SUM(CASE WHEN r.rn <= pv.n_top THEN r.revenue ELSE 0 END)            AS top_revenue,
    MAX(r.tot)                                                           AS total_revenue,
    CAST(100.0 * SUM(CASE WHEN r.rn <= pv.n_top THEN r.revenue ELSE 0 END) / NULLIF(MAX(r.tot), 0) AS DECIMAL(5,1)) AS share_pct,
    MAX(CASE WHEN r.rn = pv.n_top THEN r.same_rev END)                   AS products_tied_at_cut_boundary
FROM rkp r
CROSS JOIN (VALUES (1), (5), (10), (20)) pv(n_top)
GROUP BY r.yr, pv.n_top
ORDER BY r.yr, pv.n_top;
GO

PRINT '--- E3. PRODUCTS: THE 10 LARGEST PER YEAR ---';

WITH l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date) OVER (PARTITION BY f.order_number)) AS yr,
        CAST(f.sales_amount AS BIGINT)                             AS revenue,
        CAST(f.quantity AS BIGINT)                                 AS units
    FROM gold.fact_sales f
),
py AS (
    SELECT product_key, yr, COUNT(*) AS lines, SUM(revenue) AS revenue, SUM(units) AS units
    FROM l
    GROUP BY product_key, yr
),
pd AS (
    SELECT py.yr, py.lines, py.revenue, py.units, p.product_number,
           ISNULL(p.category, 'Unclassified') AS category
    FROM py
    LEFT JOIN gold.dim_products p ON p.product_key = py.product_key
),
rkp AS (
    SELECT
        yr, product_number, category, revenue, units,
        ROW_NUMBER() OVER (PARTITION BY yr ORDER BY revenue DESC, product_number) AS rn,
        SUM(revenue) OVER (PARTITION BY yr)                              AS tot,
        COUNT(*)     OVER (PARTITION BY yr, revenue)                     AS same_rev
    FROM pd
    WHERE yr BETWEEN 2011 AND 2013
)
SELECT
    yr                                                                   AS [year],
    rn                                                                   AS rank_in_year,
    product_number,
    category,
    revenue,
    units,
    CAST(100.0 * revenue / NULLIF(tot, 0) AS DECIMAL(5,1))               AS pct_of_year_revenue,
    CASE WHEN same_rev > 1 THEN 'tied in revenue' ELSE '' END            AS tie_flag
FROM rkp
WHERE rn <= 10
ORDER BY yr, rn;
GO


/*
===============================================================================
F. CATEGORY SHARES OF REVENUE BY YEAR
===============================================================================
Revenue share of each category by year; it ties to Q2 section C (the category
is the current product version, decision 7.8). A revenue share reflects price
as well as volume.
*/

PRINT '--- F. REVENUE SHARE OF EACH CATEGORY BY YEAR ---';

WITH l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date) OVER (PARTITION BY f.order_number)) AS yr,
        CAST(f.sales_amount AS BIGINT)                             AS revenue,
        CAST(f.quantity AS BIGINT)                                 AS units
    FROM gold.fact_sales f
),
py AS (
    SELECT product_key, yr, COUNT(*) AS lines, SUM(revenue) AS revenue, SUM(units) AS units
    FROM l
    GROUP BY product_key, yr
),
pd AS (
    SELECT py.yr, py.lines, py.revenue, py.units, p.product_number,
           ISNULL(p.category, 'Unclassified') AS category
    FROM py
    LEFT JOIN gold.dim_products p ON p.product_key = py.product_key
)
SELECT
    yr                                                                   AS [year],
    category,
    COUNT(*)                                                             AS products_sold,
    SUM(lines)                                                           AS lines,
    SUM(revenue)                                                         AS revenue,
    CAST(100.0 * SUM(revenue) / NULLIF(SUM(SUM(revenue)) OVER (PARTITION BY yr), 0) AS DECIMAL(5,1)) AS pct_of_year_revenue
FROM pd
WHERE yr BETWEEN 2011 AND 2013
GROUP BY yr, category
ORDER BY yr, category;
GO


/*
===============================================================================
G. CONTROL TOTALS
===============================================================================
Lines, orders, revenue, units and customers must match the fact table totals;
revenue by period must match Q1 section A; the customer groups, the products and
the categories must each add up to the year's revenue; the customer groups are
a partition (9,132 Bike customers + 9,352 No bikes customers = 18,484) with no
customer in both (decision 7.10, Q3 section F2).
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
    LEFT JOIN gold.dim_products p ON p.product_key = f.product_key
    GROUP BY f.order_number
),
cy AS (
    SELECT
        customer_key,
        YEAR(order_dt)                                                   AS yr,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        MAX(bike_dated) OVER (PARTITION BY customer_key)                  AS bike_any_c,
        MAX(nb_any)     OVER (PARTITION BY customer_key)                  AS nb_any_c
    FROM cy
),
rc AS (
    SELECT
        SUM(lines)                                                                AS tot_lines,
        SUM(orders)                                                               AS tot_orders,
        SUM(revenue)                                                              AS tot_revenue,
        SUM(units)                                                                AS tot_units,
        COUNT(DISTINCT customer_key)                                              AS tot_customers,
        SUM(CASE WHEN customer_key IS NULL THEN orders ELSE 0 END)                AS orders_without_customer,
        SUM(CASE WHEN yr = 2010 THEN revenue ELSE 0 END)                          AS rev_2010,
        SUM(CASE WHEN yr = 2011 THEN revenue ELSE 0 END)                          AS rev_2011,
        SUM(CASE WHEN yr = 2012 THEN revenue ELSE 0 END)                          AS rev_2012,
        SUM(CASE WHEN yr = 2013 THEN revenue ELSE 0 END)                          AS rev_2013,
        SUM(CASE WHEN yr = 2014 THEN revenue ELSE 0 END)                          AS rev_2014,
        SUM(CASE WHEN yr IS NULL THEN revenue ELSE 0 END)                         AS rev_undated,
        SUM(CASE WHEN yr IS NULL THEN orders ELSE 0 END)                          AS undated_orders,
        SUM(CASE WHEN yr = 2011 AND grp = 'Bike customer'     THEN revenue ELSE 0 END)
          + SUM(CASE WHEN yr = 2011 AND grp = 'No bikes customer' THEN revenue ELSE 0 END) AS grp_rev_2011,
        SUM(CASE WHEN yr = 2012 AND grp = 'Bike customer'     THEN revenue ELSE 0 END)
          + SUM(CASE WHEN yr = 2012 AND grp = 'No bikes customer' THEN revenue ELSE 0 END) AS grp_rev_2012,
        SUM(CASE WHEN yr = 2013 AND grp = 'Bike customer'     THEN revenue ELSE 0 END)
          + SUM(CASE WHEN yr = 2013 AND grp = 'No bikes customer' THEN revenue ELSE 0 END) AS grp_rev_2013,
        COUNT(DISTINCT CASE WHEN grp = 'Bike customer'     THEN customer_key END)  AS bike_customers,
        COUNT(DISTINCT CASE WHEN grp = 'No bikes customer' THEN customer_key END)  AS nobikes_customers,
        COUNT(DISTINCT CASE WHEN bike_any_c = 1 AND nb_any_c = 1 THEN customer_key END) AS customers_in_both,
        COUNT(DISTINCT CASE WHEN bike_any_c = 0 AND nb_any_c = 0 THEN customer_key END) AS customers_in_neither,
        (SELECT COUNT(DISTINCT customer_id) FROM gold.dim_customers)              AS dim_customer_ids
    FROM cg
),
l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date) OVER (PARTITION BY f.order_number)) AS yr,
        CAST(f.sales_amount AS BIGINT)                             AS revenue,
        CAST(f.quantity AS BIGINT)                                 AS units
    FROM gold.fact_sales f
),
py AS (
    SELECT product_key, yr, COUNT(*) AS lines, SUM(revenue) AS revenue, SUM(units) AS units
    FROM l
    GROUP BY product_key, yr
),
pd AS (
    SELECT py.yr, py.lines, py.revenue, py.units, p.product_number,
           ISNULL(p.category, 'Unclassified') AS category
    FROM py
    LEFT JOIN gold.dim_products p ON p.product_key = py.product_key
),
rp AS (
    SELECT
        SUM(CASE WHEN yr = 2011 THEN revenue ELSE 0 END)                          AS prod_rev_2011,
        SUM(CASE WHEN yr = 2012 THEN revenue ELSE 0 END)                          AS prod_rev_2012,
        SUM(CASE WHEN yr = 2013 THEN revenue ELSE 0 END)                          AS prod_rev_2013,
        SUM(CASE WHEN yr = 2011 AND category IN ('Bikes', 'Accessories', 'Clothing', 'Components', 'Unclassified') THEN revenue ELSE 0 END) AS cat_rev_2011,
        SUM(CASE WHEN yr = 2012 AND category IN ('Bikes', 'Accessories', 'Clothing', 'Components', 'Unclassified') THEN revenue ELSE 0 END) AS cat_rev_2012,
        SUM(CASE WHEN yr = 2013 AND category IN ('Bikes', 'Accessories', 'Clothing', 'Components', 'Unclassified') THEN revenue ELSE 0 END) AS cat_rev_2013,
        SUM(CASE WHEN product_number IS NULL THEN lines ELSE 0 END)               AS lines_without_product
    FROM pd
)
SELECT
    c.check_name,
    c.actual_value,
    c.expected_value,
    CASE WHEN c.actual_value = c.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM rc
CROSS JOIN rp
CROSS APPLY (VALUES
    ('lines',                                                          CAST(tot_lines AS BIGINT),        CAST(60398 AS BIGINT)),
    ('orders',                                                         CAST(tot_orders AS BIGINT),       27659),
    ('revenue',                                                        CAST(tot_revenue AS BIGINT),      29356250),
    ('units',                                                          CAST(tot_units AS BIGINT),        60423),
    ('customers (distinct customer_key in the fact table)',            CAST(tot_customers AS BIGINT),    18484),
    ('customers (distinct customer_id in gold.dim_customers)',         CAST(dim_customer_ids AS BIGINT), 18484),
    ('orders without a customer',                                      CAST(orders_without_customer AS BIGINT), 0),
    ('undated orders',                                                 CAST(undated_orders AS BIGINT),   2),
    ('revenue 2010 tail (Q1 section A)',                               CAST(rev_2010 AS BIGINT),         43419),
    ('revenue 2011 (Q1 section A)',                                    CAST(rev_2011 AS BIGINT),         7075088),
    ('revenue 2012 (Q1 section A)',                                    CAST(rev_2012 AS BIGINT),         5842231),
    ('revenue 2013 (Q1 section A)',                                    CAST(rev_2013 AS BIGINT),         16349836),
    ('revenue January 2014 (Q1 section A)',                            CAST(rev_2014 AS BIGINT),         45642),
    ('revenue undated orders (Q1 section A)',                          CAST(rev_undated AS BIGINT),      34),
    ('customer groups revenue 2011 (Bike + No bikes)',                 CAST(grp_rev_2011 AS BIGINT),     7075088),
    ('customer groups revenue 2012 (Bike + No bikes)',                 CAST(grp_rev_2012 AS BIGINT),     5842231),
    ('customer groups revenue 2013 (Bike + No bikes)',                 CAST(grp_rev_2013 AS BIGINT),     16349836),
    ('products revenue 2011',                                          CAST(prod_rev_2011 AS BIGINT),    7075088),
    ('products revenue 2012',                                          CAST(prod_rev_2012 AS BIGINT),    5842231),
    ('products revenue 2013',                                          CAST(prod_rev_2013 AS BIGINT),    16349836),
    ('categories revenue 2011 (all categories)',                       CAST(cat_rev_2011 AS BIGINT),     7075088),
    ('categories revenue 2012 (all categories)',                       CAST(cat_rev_2012 AS BIGINT),     5842231),
    ('categories revenue 2013 (all categories)',                       CAST(cat_rev_2013 AS BIGINT),     16349836),
    ('lines without a product in gold.dim_products',                   CAST(lines_without_product AS BIGINT), 0),
    ('Bike customers (Q3 section F2)',                                 CAST(bike_customers AS BIGINT),   9132),
    ('No bikes customers (Q3 section F2)',                             CAST(nobikes_customers AS BIGINT), 9352),
    ('customers in both groups',                                       CAST(customers_in_both AS BIGINT), 0),
    ('customers with neither a dated Bike order nor a No bikes order', CAST(customers_in_neither AS BIGINT), 0),
    ('customer groups partition (Bike + No bikes)',                    CAST(bike_customers + nobikes_customers AS BIGINT), 18484)
) AS c(check_name, actual_value, expected_value);
GO
