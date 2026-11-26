/*
===============================================================================
ANALYSIS 05 - GEOGRAPHY (Q5)
===============================================================================
Business question:
    How are customers, orders and revenue distributed across countries, and do
    the direction of the AOV changes 2011->2012 and 2012->2013 and the 2013
    share of No bikes orders hold in each country? The analysis is descriptive.
    It makes no claim about markets or demand and gives no reason why a country
    differs.

Data required:
    gold.fact_sales: order_number, customer_key, product_key, order_date,
                     sales_amount, quantity.
    gold.dim_customers: customer_key -> country (ERP location, normalised in
                        Silver). Joined ONCE per section, on an aggregate of
                        about 30 thousand rows, never on the 60 thousand lines
                        (Known pitfalls). customer_key is never reported or
                        hardcoded.
    gold.dim_products: product_key -> category (295 current versions; small).

Grain:
    - Base grain: one row of gold.fact_sales (an order line).
    - Lines are collapsed once to one row per order (CTE o), then to one row
      per customer, year and order class (CTE cy); only then is
      gold.dim_customers joined (CTE cc). Country-level figures are derived
      from cc with GROUPING SETS and window functions.
    - Sections: A countries by year (A1 customers in the dimension, A2 active
      customers, orders and revenue by country and year); B order share and AOV
      by country and year with the total next to it and the AOV changes;
      C 2013 (C1 order classes by country, C2 customer groups by country on two
      bases); D price-list consistency (not a currency test); E control totals.

Definitions (decisions 7.1, 7.2, 7.8, 7.10 and 7.11 in docs/decisions.md):
    - Year = year of the order-level date, MIN(order_date) over the order
      (7.2). Years 2011-2013 are compared (7.1). The 2010 tail, January 2014
      and the 2 undated orders appear only as context rows (A2, E).
    - Country = the country recorded for the customer in gold.dim_customers
      (7.11): the customer's location in the source, not where the order
      shipped; the data has no history, so whether a customer moved cannot be
      checked. 'N/A' is its own category, never imputed, it is not a country
      and is not read as a place; it stays in every total.
    - Active customers = distinct customer_key with at least one order in the
      period. Order = distinct order_number. Revenue = SUM(sales_amount)
      (currency unknown). AOV = revenue / orders.
    - Order class (7.8): 'Bikes only', 'Bikes + other', 'No bikes'. 'Bike
      orders' = 'Bikes only' + 'Bikes + other' (every order with a Bike line).
    - Customer group (7.10): Bike customer = at least one dated order with a
      Bike line; No bikes customer = every other customer.
    - READING RULE (declared before the run; decision 7.11). The currency is
      unknown. Across countries only CUSTOMER SHARES and ORDER SHARES are read.
      Revenue shares and AOV levels across countries are printed but flagged
      "comparable only if amounts are in one currency, which the data cannot
      show"; they are not interpreted. Within-country AOV changes are read,
      assuming each country's amounts are in one unit over time (this cannot be
      checked). The total AOV is printed next to the countries so that a change
      in the country mix is not read as a change inside countries. No
      counterfactual or decomposition is computed.
    - 'Same pattern' criterion (fixed before the run). For each step
      (2011->2012 and 2012->2013) the pattern holds in a country if its AOV
      change has the same sign as the total AOV change, reported for every
      interpretable country. For the 2013 No bikes share the range across the
      interpretable countries is reported next to the total, with no threshold
      for 'same'.
    - Minimum sizes (Q5-specific, declared before the run, not part of decision
      7; the cell sizes were not seen). Reason: sensitivity, not sampling (the
      data are the population): a ratio built on few orders moves a lot with
      one order, and in 2011 an order has one line, so a country's AOV is an
      average of bike prices.
        * AOV of a country-year: at least 100 orders.
        * A within-country AOV change: both years must have at least 100 orders.
        * 2013 class figures: the No bikes share and the No bikes AOV need at
          least 30 No bikes orders; the Bike-order AOV needs at least 30 Bike
          orders; both also need the country to have 100 orders in 2013.
        * Cells below the minimum are printed with 'not interpreted', never
          dropped.
        * 'Most' rule: if in some year 4 or more of the six named countries
          fail a minimum, the table is not interpreted, and work stops for the
          author before findings are written. B and C1 print the number of
          failing countries on every row.
    - Section D, 'price-list consistency (not a currency test)': realized unit
      price per line = 1.0 * sales_amount / quantity, in decimal so the
      division does not truncate (the Q2 section I definition of realized price,
      revenue / units; the fact table's price column is not used). It is
      computed per line by product and month (order-level date) and reports the
      product-months with more than one price. No country is joined. Under any
      result the currency stays unknown.

Method:
    One chain per section: lines -> order (o) -> customer, year, class (cy) ->
    join to gold.dim_customers once (cc; OPTION (HASH JOIN) on the statements
    where the optimizer accepts it, not on C2, whose several COUNT(DISTINCT)
    make the hint impossible) -> GROUPING SETS / window functions. Every CTE built on the Gold
    views is referenced once (CLAUDE.md, Known pitfalls). No temp tables or
    other objects. Section D reads the fact table and nothing else.

Caveats:
    - Country is the customer's location at an unknown date, not a ship-to
      country, and the data has no history.
    - Country differences in 2013 (AOV, No bikes share) may reflect when in the
      year each country's customers started buying: 2013 has 12,521 first-time
      customers (Q3 section A) and there is no No bikes order in 2011 or 2012
      (Q2 section H).
    - The currency is unknown; section D does not test it.
    - A within-country AOV change 2011->2012 contains the model mix and the
      price changes within Bikes (Q2 section I). A 2013 change contains the
      Bike / No bikes class mix inside the country (section C shows it; B does
      not separate it).
    - Country is one attribute; nothing here tests it against product or class.
      No causal claim.

Control totals (section E): lines 60,398 / orders 27,659 /
    revenue 29,356,250 / units 60,423 / customers 18,484; revenue by period
    against Q1 section A after the join to the dimension (no fan-out); active
    customers by year against Q4 section A; countries add up to the totals;
    no NULL country; no order with two customers; customer groups on both
    bases (9,132 / 9,352 / 18,484 and 8,583 / 8,844 active in 2013) with no
    overlap.

Read-only: SELECT statements only.
Run:
    scripts\run_analysis.ps1 -Script analysis\05_geography.sql -DatabaseName DataWarehouse_Test
    (or: sqlcmd -S <server> -E -C -b -W -s "|" -v DatabaseName="DataWarehouse_Test" -i analysis\05_geography.sql)
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;
GO


/*
===============================================================================
A. COUNTRIES BY YEAR
===============================================================================
A1: customers in the dimension per country (the whole base, 18,484).
A2: per period and country: active customers, orders, lines, units, revenue and
their shares of the period's totals. Customer and order shares are read;
revenue shares are printed and flagged (reading rule). The N/A rows show the
N/A share of customers, orders and revenue by year. The context rows (2010
tail, January 2014, undated orders) are there so that the totals tie to the
control totals; they are not compared.
*/

PRINT '--- A1. CUSTOMERS IN THE DIMENSION BY COUNTRY ---';

WITH d AS (
    SELECT COALESCE(country, '(NULL country)') AS country, customer_id
    FROM gold.dim_customers
)
SELECT
    CASE WHEN GROUPING(country) = 1 THEN 'TOTAL' ELSE country END           AS country,
    CASE WHEN country = 'N/A' THEN 'not a country' ELSE '' END              AS country_note,
    COUNT(*)                                                                AS customers,
    COUNT(DISTINCT customer_id)                                             AS distinct_customer_ids,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY GROUPING(country)) AS DECIMAL(5,1)) AS customer_share_pct
FROM d
GROUP BY GROUPING SETS ((country), ())
ORDER BY GROUPING(country), CASE WHEN country = 'N/A' THEN 1 ELSE 0 END, COUNT(*) DESC;
GO

PRINT '--- A2. ACTIVE CUSTOMERS, ORDERS AND REVENUE BY COUNTRY AND PERIOD ---';
PRINT 'revenue_share_pct_flagged: comparable only if amounts are in one currency, which the data cannot show (not interpreted).';

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
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                    AS cls,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue
    FROM o
    GROUP BY customer_key, YEAR(order_dt),
             CASE WHEN bike_lines = 0 THEN 'No bikes'
                  WHEN bike_lines = lines THEN 'Bikes only'
                  ELSE 'Bikes + other' END
),
cc AS (
    SELECT
        cy.customer_key, cy.yr, cy.cls, cy.orders, cy.lines, cy.units, cy.revenue,
        CASE WHEN c.customer_key IS NULL THEN '(no dimension row)'
             ELSE ISNULL(c.country, '(NULL country)') END                AS country
    FROM cy
    LEFT JOIN gold.dim_customers c ON c.customer_key = cy.customer_key
),
a AS (
    SELECT
        yr,
        CASE WHEN GROUPING(country) = 1 THEN 'TOTAL' ELSE country END    AS country,
        COUNT(DISTINCT customer_key)                                     AS customers,
        SUM(orders)                                                      AS orders,
        SUM(lines)                                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue
    FROM cc
    GROUP BY GROUPING SETS ((yr, country), (yr))
)
SELECT
    CASE WHEN yr = 2010 THEN '2010 tail (context)'
         WHEN yr = 2014 THEN 'Jan 2014 (context)'
         WHEN yr IS NULL THEN 'undated (context)'
         ELSE CAST(yr AS CHAR(4)) END                                    AS period,
    country,
    CASE WHEN country = 'N/A' THEN 'not a country' ELSE '' END           AS country_note,
    customers,
    CAST(100.0 * customers / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN customers END) OVER (PARTITION BY yr), 0) AS DECIMAL(5,1)) AS customer_share_pct,
    orders,
    CAST(100.0 * orders    / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN orders    END) OVER (PARTITION BY yr), 0) AS DECIMAL(5,1)) AS order_share_pct,
    lines,
    units,
    revenue,
    CAST(100.0 * revenue   / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN revenue   END) OVER (PARTITION BY yr), 0) AS DECIMAL(5,1)) AS revenue_share_pct_flagged
FROM a
ORDER BY ISNULL(yr, 9999),
         CASE WHEN country = 'TOTAL' THEN 0 WHEN country = 'N/A' THEN 2 ELSE 1 END,
         orders DESC
OPTION (HASH JOIN);
GO


/*
===============================================================================
B. ORDER SHARE AND AOV BY COUNTRY AND YEAR, WITH THE TOTAL
===============================================================================
Years 2011-2013. Per country and year: orders, order share, AOV, the AOV change
from the previous year (absolute and %), and next to it the total AOV change of
the same year. 'sign_vs_total' applies the 'same pattern' criterion to the
interpretable countries (both years with at least 100 orders; N/A excluded).
AOV levels across countries are flagged (reading rule); only the changes within
a country are read. The last column counts the named countries (of 6) that do
not reach 100 orders in the year; 4 or more means the 'most' rule applies.
*/

PRINT '--- B. ORDER SHARE AND AOV BY COUNTRY AND YEAR (TOTAL NEXT TO THE COUNTRIES) ---';
PRINT 'aov_level_flagged: comparable across countries only if amounts are in one currency, which the data cannot show (not interpreted); the changes within a country are read.';

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
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                    AS cls,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue
    FROM o
    GROUP BY customer_key, YEAR(order_dt),
             CASE WHEN bike_lines = 0 THEN 'No bikes'
                  WHEN bike_lines = lines THEN 'Bikes only'
                  ELSE 'Bikes + other' END
),
cc AS (
    SELECT
        cy.customer_key, cy.yr, cy.cls, cy.orders, cy.lines, cy.units, cy.revenue,
        CASE WHEN c.customer_key IS NULL THEN '(no dimension row)'
             ELSE ISNULL(c.country, '(NULL country)') END                AS country
    FROM cy
    LEFT JOIN gold.dim_customers c ON c.customer_key = cy.customer_key
),
a AS (
    SELECT
        yr,
        CASE WHEN GROUPING(country) = 1 THEN 'TOTAL' ELSE country END    AS country,
        SUM(orders)                                                      AS orders,
        SUM(revenue)                                                     AS revenue
    FROM cc
    WHERE yr BETWEEN 2011 AND 2013
    GROUP BY GROUPING SETS ((yr, country), (yr))
),
b AS (
    SELECT
        yr, country, orders, revenue,
        100.0 * orders / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN orders END) OVER (PARTITION BY yr), 0) AS order_share_pct,
        1.0 * revenue / NULLIF(orders, 0)                                                                   AS aov,
        LAG(orders)                          OVER (PARTITION BY country ORDER BY yr)                        AS prev_orders,
        LAG(1.0 * revenue / NULLIF(orders, 0)) OVER (PARTITION BY country ORDER BY yr)                      AS prev_aov
    FROM a
),
c AS (
    SELECT
        yr, country, orders, order_share_pct, aov, prev_orders, prev_aov,
        aov - prev_aov                                                   AS aov_chg,
        100.0 * (aov / NULLIF(prev_aov, 0) - 1)                          AS aov_chg_pct,
        MAX(CASE WHEN country = 'TOTAL' THEN aov - prev_aov END) OVER (PARTITION BY yr) AS total_chg,
        6 - SUM(CASE WHEN country NOT IN ('TOTAL', 'N/A') AND orders >= 100 THEN 1 ELSE 0 END) OVER (PARTITION BY yr) AS countries_below_minimum
    FROM b
)
SELECT
    country,
    CASE WHEN country = 'N/A' THEN 'not a country' ELSE '' END           AS country_note,
    yr,
    orders,
    CAST(order_share_pct AS DECIMAL(5,1))                                AS order_share_pct,
    CAST(aov AS DECIMAL(12,2))                                           AS aov_level_flagged,
    CASE WHEN orders >= 100 THEN 'interpreted' ELSE 'not interpreted' END AS aov_minimum_100_orders,
    CAST(aov_chg AS DECIMAL(12,2))                                       AS aov_change,
    CAST(aov_chg_pct AS DECIMAL(8,1))                                    AS aov_change_pct,
    CASE WHEN prev_orders IS NULL THEN 'n/a (first year)'
         WHEN country = 'TOTAL' THEN 'total'
         WHEN country = 'N/A' THEN 'not a country'
         WHEN orders >= 100 AND prev_orders >= 100 THEN 'interpreted'
         ELSE 'not interpreted' END                                      AS change_rule_both_years,
    CAST(total_chg AS DECIMAL(12,2))                                     AS total_aov_change,
    CASE WHEN prev_orders IS NOT NULL AND country NOT IN ('TOTAL', 'N/A')
              AND orders >= 100 AND prev_orders >= 100
         THEN CASE WHEN SIGN(aov_chg) = SIGN(total_chg) THEN 'same sign' ELSE 'different sign' END
         ELSE '' END                                                     AS sign_vs_total,
    countries_below_minimum                                              AS named_countries_below_100_orders
FROM c
ORDER BY CASE WHEN country = 'TOTAL' THEN 0 WHEN country = 'N/A' THEN 2 ELSE 1 END,
         country, yr
OPTION (HASH JOIN);
GO


/*
===============================================================================
C. 2013: ORDER CLASSES AND CUSTOMER GROUPS BY COUNTRY
===============================================================================
C1: orders of 2013 by class (7.8) and country, with the No bikes share of orders
(read) and of revenue (flagged), the AOV of Bike orders and of No bikes orders
(flagged across countries), the minimum-size rules and the range of the No bikes
share of orders across the interpretable named countries next to the total.
The two last columns count the named countries (of 6) failing each minimum; 4
or more means the 'most' rule applies. 2011 and 2012 have no No bikes order (Q2
section H) and are not tabulated.
C2: customers by group (7.10) and country on two bases: the whole-data partition
(every customer, 18,484) and the customers active in 2013 (the group rule is
the whole-data one, as in Q4 section C1).
*/

PRINT '--- C1. 2013 ORDER CLASSES BY COUNTRY ---';
PRINT 'no_bikes_share_revenue_pct_flagged, bike_aov_flagged and no_bikes_aov_flagged: comparable across countries only if amounts are in one currency, which the data cannot show (not interpreted).';

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
        CASE WHEN bike_lines = 0 THEN 'No bikes'
             WHEN bike_lines = lines THEN 'Bikes only'
             ELSE 'Bikes + other' END                                    AS cls,
        COUNT(*)                                                         AS orders,
        SUM(CAST(lines AS BIGINT))                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue
    FROM o
    GROUP BY customer_key, YEAR(order_dt),
             CASE WHEN bike_lines = 0 THEN 'No bikes'
                  WHEN bike_lines = lines THEN 'Bikes only'
                  ELSE 'Bikes + other' END
),
cc AS (
    SELECT
        cy.customer_key, cy.yr, cy.cls, cy.orders, cy.lines, cy.units, cy.revenue,
        CASE WHEN c.customer_key IS NULL THEN '(no dimension row)'
             ELSE ISNULL(c.country, '(NULL country)') END                AS country
    FROM cy
    LEFT JOIN gold.dim_customers c ON c.customer_key = cy.customer_key
),
a AS (
    SELECT
        CASE WHEN GROUPING(country) = 1 THEN 'TOTAL' ELSE country END    AS country,
        SUM(orders)                                                      AS orders,
        SUM(CASE WHEN cls = 'Bikes only'    THEN orders ELSE 0 END)      AS bikes_only_orders,
        SUM(CASE WHEN cls = 'Bikes + other' THEN orders ELSE 0 END)      AS bikes_other_orders,
        SUM(CASE WHEN cls = 'No bikes'      THEN orders ELSE 0 END)      AS no_bikes_orders,
        SUM(revenue)                                                     AS revenue,
        SUM(CASE WHEN cls <> 'No bikes' THEN revenue ELSE 0 END)         AS bike_revenue,
        SUM(CASE WHEN cls =  'No bikes' THEN revenue ELSE 0 END)         AS no_bikes_revenue
    FROM cc
    WHERE yr = 2013
    GROUP BY GROUPING SETS ((country), ())
),
b AS (
    SELECT
        country, orders, bikes_only_orders, bikes_other_orders, no_bikes_orders,
        bikes_only_orders + bikes_other_orders                           AS bike_orders,
        revenue, bike_revenue, no_bikes_revenue,
        CASE WHEN orders >= 100 AND no_bikes_orders >= 30 THEN 1 ELSE 0 END                              AS nb_ok,
        CASE WHEN orders >= 100 AND bikes_only_orders + bikes_other_orders >= 30 THEN 1 ELSE 0 END       AS bike_ok
    FROM a
)
SELECT
    country,
    CASE WHEN country = 'N/A' THEN 'not a country' ELSE '' END           AS country_note,
    orders                                                               AS orders_2013,
    bikes_only_orders,
    bikes_other_orders,
    bike_orders,
    no_bikes_orders,
    CAST(100.0 * no_bikes_orders / NULLIF(orders, 0) AS DECIMAL(5,1))    AS no_bikes_share_orders_pct,
    CAST(100.0 * no_bikes_revenue / NULLIF(revenue, 0) AS DECIMAL(5,1))  AS no_bikes_share_revenue_pct_flagged,
    CAST(1.0 * bike_revenue / NULLIF(bike_orders, 0) AS DECIMAL(12,2))   AS bike_aov_flagged,
    CAST(1.0 * no_bikes_revenue / NULLIF(no_bikes_orders, 0) AS DECIMAL(12,2)) AS no_bikes_aov_flagged,
    CASE WHEN nb_ok = 1 THEN 'interpreted' ELSE 'not interpreted' END    AS no_bikes_rule_30_orders,
    CASE WHEN bike_ok = 1 THEN 'interpreted' ELSE 'not interpreted' END  AS bike_aov_rule_30_orders,
    CAST(MIN(CASE WHEN country NOT IN ('TOTAL', 'N/A') AND nb_ok = 1 THEN 100.0 * no_bikes_orders / NULLIF(orders, 0) END) OVER () AS DECIMAL(5,1)) AS range_min_no_bikes_share_pct,
    CAST(MAX(CASE WHEN country NOT IN ('TOTAL', 'N/A') AND nb_ok = 1 THEN 100.0 * no_bikes_orders / NULLIF(orders, 0) END) OVER () AS DECIMAL(5,1)) AS range_max_no_bikes_share_pct,
    6 - SUM(CASE WHEN country NOT IN ('TOTAL', 'N/A') AND nb_ok = 1   THEN 1 ELSE 0 END) OVER ()  AS named_countries_failing_no_bikes_rule,
    6 - SUM(CASE WHEN country NOT IN ('TOTAL', 'N/A') AND bike_ok = 1 THEN 1 ELSE 0 END) OVER ()  AS named_countries_failing_bike_rule
FROM b
ORDER BY CASE WHEN country = 'TOTAL' THEN 0 WHEN country = 'N/A' THEN 2 ELSE 1 END, orders DESC
OPTION (HASH JOIN);
GO

PRINT '--- C2. CUSTOMER GROUPS BY COUNTRY (WHOLE-DATA PARTITION AND ACTIVE IN 2013) ---';

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
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
              AND MAX(nb_any)     OVER (PARTITION BY customer_key) = 1
             THEN 1 ELSE 0 END                                            AS both_flag
    FROM cy
),
cc AS (
    SELECT
        cg.customer_key, cg.yr, cg.grp, cg.both_flag,
        CASE WHEN c.customer_key IS NULL THEN '(no dimension row)'
             ELSE ISNULL(c.country, '(NULL country)') END                AS country
    FROM cg
    LEFT JOIN gold.dim_customers c ON c.customer_key = cg.customer_key
),
a AS (
    SELECT
        CASE WHEN GROUPING(country) = 1 THEN 'TOTAL' ELSE country END    AS country,
        COUNT(DISTINCT customer_key)                                     AS customers,
        COUNT(DISTINCT CASE WHEN grp = 'Bike customer'     THEN customer_key END) AS bike_customers,
        COUNT(DISTINCT CASE WHEN grp = 'No bikes customer' THEN customer_key END) AS no_bikes_customers,
        COUNT(DISTINCT CASE WHEN both_flag = 1 THEN customer_key END)    AS customers_in_both,
        COUNT(DISTINCT CASE WHEN yr = 2013 THEN customer_key END)        AS active_2013,
        COUNT(DISTINCT CASE WHEN yr = 2013 AND grp = 'Bike customer'     THEN customer_key END) AS active_2013_bike,
        COUNT(DISTINCT CASE WHEN yr = 2013 AND grp = 'No bikes customer' THEN customer_key END) AS active_2013_no_bikes
    FROM cc
    GROUP BY GROUPING SETS ((country), ())
)
SELECT
    country,
    CASE WHEN country = 'N/A' THEN 'not a country' ELSE '' END           AS country_note,
    customers                                                            AS customers_whole_data,
    CAST(100.0 * customers / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN customers END) OVER (), 0) AS DECIMAL(5,1)) AS customer_share_pct,
    bike_customers,
    no_bikes_customers,
    CAST(100.0 * bike_customers / NULLIF(customers, 0) AS DECIMAL(5,1))  AS bike_customers_pct,
    customers_in_both,
    active_2013,
    CAST(100.0 * active_2013 / NULLIF(MAX(CASE WHEN country = 'TOTAL' THEN active_2013 END) OVER (), 0) AS DECIMAL(5,1)) AS active_2013_share_pct,
    active_2013_bike,
    active_2013_no_bikes,
    CAST(100.0 * active_2013_bike / NULLIF(active_2013, 0) AS DECIMAL(5,1)) AS active_2013_bike_pct
FROM a
ORDER BY CASE WHEN country = 'TOTAL' THEN 0 WHEN country = 'N/A' THEN 2 ELSE 1 END, customers DESC;
GO


/*
===============================================================================
D. PRICE-LIST CONSISTENCY (NOT A CURRENCY TEST)
===============================================================================
For each product and month (order-level date), the realized unit price per line,
1.0 * sales_amount / quantity (Q2 section I definition: revenue / units). The
table counts the product-months in which the lowest and the highest line price
differ. No country is joined: if no product has more than one price within a
month, no country can differ within that month; if some do, the variation is
reported here and Q5 stops there. Under any result the currency stays unknown.
Lines with quantity 0 have no price and are counted apart.
*/

PRINT '--- D. PRICE-LIST CONSISTENCY BY PRODUCT AND MONTH (NO COUNTRY; NOT A CURRENCY TEST) ---';

WITH l AS (
    SELECT
        f.product_key,
        YEAR(MIN(f.order_date)  OVER (PARTITION BY f.order_number))      AS yr,
        MONTH(MIN(f.order_date) OVER (PARTITION BY f.order_number))      AS mo,
        CAST(1.0 * f.sales_amount / NULLIF(f.quantity, 0) AS DECIMAL(18,6)) AS price
    FROM gold.fact_sales f
),
pm AS (
    SELECT
        product_key, yr, mo,
        COUNT(*)                                                         AS lines,
        SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END)                   AS lines_without_price,
        MIN(price)                                                       AS min_price,
        MAX(price)                                                       AS max_price
    FROM l
    GROUP BY product_key, yr, mo
)
SELECT
    CASE WHEN GROUPING(yr) = 1 THEN 'ALL' ELSE ISNULL(CAST(yr AS VARCHAR(8)), 'undated') END AS period,
    COUNT(*)                                                             AS product_months,
    SUM(lines)                                                           AS lines,
    SUM(lines_without_price)                                             AS lines_without_price,
    SUM(CASE WHEN max_price > min_price THEN 1 ELSE 0 END)               AS product_months_with_more_than_one_price,
    SUM(CASE WHEN max_price > min_price THEN lines ELSE 0 END)           AS lines_in_those_product_months,
    CAST(100.0 * MAX(max_price / NULLIF(min_price, 0) - 1) AS DECIMAL(12,2)) AS largest_relative_gap_pct
FROM pm
GROUP BY GROUPING SETS ((yr), ())
ORDER BY GROUPING(yr), ISNULL(yr, 9999);
GO


/*
===============================================================================
E. CONTROL TOTALS
===============================================================================
Lines, orders, revenue, units and customers must match the fact table totals
after the join to gold.dim_customers (a different count would mean fan-out or
lost lines); revenue by period must match Q1 section A and active customers by
year Q4 section A; the countries (with N/A) must add up to the totals; no NULL
country, no line without a dimension row, no order with more than one
customer; the customer groups are a partition on both bases (9,132 + 9,352 =
18,484 over the whole data; 8,583 + 8,844 active in 2013, Q4 section C1) with no
customer in both.
*/

PRINT '--- E. CONTROL TOTALS ---';

WITH o AS (
    SELECT
        f.order_number,
        MAX(f.customer_key)                                  AS customer_key,
        MIN(f.customer_key)                                  AS customer_key_min,
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
        SUM(CASE WHEN customer_key_min <> customer_key THEN 1 ELSE 0 END) AS multi_customer_orders,
        MAX(CASE WHEN order_dt IS NOT NULL AND bike_lines > 0 THEN 1 ELSE 0 END) AS bike_dated,
        MAX(CASE WHEN bike_lines = 0 THEN 1 ELSE 0 END)                  AS nb_any
    FROM o
    GROUP BY customer_key, YEAR(order_dt)
),
cg AS (
    SELECT
        customer_key, yr, orders, lines, units, revenue, multi_customer_orders,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
             THEN 'Bike customer' ELSE 'No bikes customer' END           AS grp,
        CASE WHEN MAX(bike_dated) OVER (PARTITION BY customer_key) = 1
              AND MAX(nb_any)     OVER (PARTITION BY customer_key) = 1
             THEN 1 ELSE 0 END                                            AS both_flag
    FROM cy
),
cc AS (
    SELECT
        cg.customer_key, cg.yr, cg.orders, cg.lines, cg.units, cg.revenue,
        cg.multi_customer_orders, cg.grp, cg.both_flag,
        CASE WHEN c.customer_key IS NULL THEN '(no dimension row)'
             ELSE ISNULL(c.country, '(NULL country)') END                AS country
    FROM cg
    LEFT JOIN gold.dim_customers c ON c.customer_key = cg.customer_key
),
ca AS (
    SELECT
        country, yr, grp, both_flag,
        GROUPING(yr)                                                     AS g_yr,
        COUNT(DISTINCT customer_key)                                     AS customers,
        SUM(orders)                                                      AS orders,
        SUM(lines)                                                       AS lines,
        SUM(units)                                                       AS units,
        SUM(revenue)                                                     AS revenue,
        SUM(multi_customer_orders)                                       AS multi_customer_orders
    FROM cc
    GROUP BY GROUPING SETS ((country, yr, grp, both_flag), (country, grp, both_flag))
),
rc AS (
    SELECT
        ISNULL(SUM(CASE WHEN g_yr = 0 THEN lines   END), 0)                              AS tot_lines,
        ISNULL(SUM(CASE WHEN g_yr = 0 THEN orders  END), 0)                              AS tot_orders,
        ISNULL(SUM(CASE WHEN g_yr = 0 THEN revenue END), 0)                              AS tot_revenue,
        ISNULL(SUM(CASE WHEN g_yr = 0 THEN units   END), 0)                              AS tot_units,
        ISNULL(SUM(CASE WHEN g_yr = 1 THEN customers END), 0)                            AS tot_customers,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2010   THEN revenue END), 0)              AS rev_2010,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2011   THEN revenue END), 0)              AS rev_2011,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2012   THEN revenue END), 0)              AS rev_2012,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2013   THEN revenue END), 0)              AS rev_2013,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2014   THEN revenue END), 0)              AS rev_2014,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr IS NULL  THEN revenue END), 0)              AS rev_undated,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr IS NULL  THEN orders  END), 0)              AS undated_orders,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2011   THEN customers END), 0)            AS active_2011,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2012   THEN customers END), 0)            AS active_2012,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2013   THEN customers END), 0)            AS active_2013,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND country IN ('United States', 'Australia', 'United Kingdom', 'France', 'Germany', 'Canada', 'N/A') THEN orders END), 0) AS orders_in_listed_countries,
        ISNULL(SUM(CASE WHEN g_yr = 1 AND country IN ('United States', 'Australia', 'United Kingdom', 'France', 'Germany', 'Canada', 'N/A') THEN customers END), 0) AS customers_in_listed_countries,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND country = '(no dimension row)' THEN lines END), 0) AS lines_without_dimension_row,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND country = '(NULL country)'     THEN lines END), 0) AS lines_with_null_country,
        ISNULL(SUM(CASE WHEN g_yr = 0 THEN multi_customer_orders END), 0)                AS orders_with_two_customers,
        ISNULL(SUM(CASE WHEN g_yr = 1 AND grp = 'Bike customer'     THEN customers END), 0) AS bike_customers,
        ISNULL(SUM(CASE WHEN g_yr = 1 AND grp = 'No bikes customer' THEN customers END), 0) AS nobikes_customers,
        ISNULL(SUM(CASE WHEN g_yr = 1 AND both_flag = 1 THEN customers END), 0)          AS customers_in_both,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2013 AND grp = 'Bike customer'     THEN customers END), 0) AS active_2013_bike,
        ISNULL(SUM(CASE WHEN g_yr = 0 AND yr = 2013 AND grp = 'No bikes customer' THEN customers END), 0) AS active_2013_nobikes,
        (SELECT COUNT(*)                    FROM gold.dim_customers)                     AS dim_rows,
        (SELECT COUNT(DISTINCT customer_id) FROM gold.dim_customers)                     AS dim_customer_ids,
        (SELECT COUNT(*) FROM gold.dim_customers WHERE country IS NULL)                  AS dim_null_country,
        (SELECT COUNT(*) FROM gold.dim_customers WHERE country = 'N/A')                  AS dim_na_country,
        (SELECT COUNT(*) FROM gold.dim_customers WHERE country IN ('United States', 'Australia', 'United Kingdom', 'France', 'Germany', 'Canada', 'N/A')) AS dim_listed_countries
    FROM ca
)
SELECT
    c.check_name,
    c.actual_value,
    c.expected_value,
    CASE WHEN c.actual_value = c.expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM rc
CROSS APPLY (VALUES
    ('lines (after the join to gold.dim_customers)',                    CAST(tot_lines AS BIGINT),        CAST(60398 AS BIGINT)),
    ('orders (after the join)',                                         CAST(tot_orders AS BIGINT),       27659),
    ('revenue (after the join)',                                        CAST(tot_revenue AS BIGINT),      29356250),
    ('units (after the join)',                                          CAST(tot_units AS BIGINT),        60423),
    ('customers (distinct customer_key in the fact table)',             CAST(tot_customers AS BIGINT),    18484),
    ('customers (rows in gold.dim_customers)',                          CAST(dim_rows AS BIGINT),         18484),
    ('customers (distinct customer_id in gold.dim_customers)',          CAST(dim_customer_ids AS BIGINT), 18484),
    ('undated orders',                                                  CAST(undated_orders AS BIGINT),   2),
    ('revenue 2010 tail, all countries (Q1 section A)',                 CAST(rev_2010 AS BIGINT),         43419),
    ('revenue 2011, all countries (Q1 section A)',                      CAST(rev_2011 AS BIGINT),         7075088),
    ('revenue 2012, all countries (Q1 section A)',                      CAST(rev_2012 AS BIGINT),         5842231),
    ('revenue 2013, all countries (Q1 section A)',                      CAST(rev_2013 AS BIGINT),         16349836),
    ('revenue January 2014, all countries (Q1 section A)',              CAST(rev_2014 AS BIGINT),         45642),
    ('revenue undated orders, all countries (Q1 section A)',            CAST(rev_undated AS BIGINT),      34),
    ('active customers 2011, all countries (Q4 section A)',             CAST(active_2011 AS BIGINT),      2216),
    ('active customers 2012, all countries (Q4 section A)',             CAST(active_2012 AS BIGINT),      3255),
    ('active customers 2013, all countries (Q4 section A)',             CAST(active_2013 AS BIGINT),      17427),
    ('orders in the six countries + N/A',                               CAST(orders_in_listed_countries AS BIGINT), 27659),
    ('customers in the six countries + N/A (whole data)',               CAST(customers_in_listed_countries AS BIGINT), 18484),
    ('customers in gold.dim_customers in the six countries + N/A',      CAST(dim_listed_countries AS BIGINT), 18484),
    ('customers with country N/A (Q0 profile)',                         CAST(dim_na_country AS BIGINT),   337),
    ('customers with NULL country in gold.dim_customers',               CAST(dim_null_country AS BIGINT), 0),
    ('lines with NULL country after the join',                          CAST(lines_with_null_country AS BIGINT), 0),
    ('lines without a row in gold.dim_customers',                       CAST(lines_without_dimension_row AS BIGINT), 0),
    ('orders with more than one customer_key',                          CAST(orders_with_two_customers AS BIGINT), 0),
    ('Bike customers, whole data, all countries (Q3 section F2)',       CAST(bike_customers AS BIGINT),   9132),
    ('No bikes customers, whole data, all countries (Q3 section F2)',   CAST(nobikes_customers AS BIGINT), 9352),
    ('customers in both groups',                                        CAST(customers_in_both AS BIGINT), 0),
    ('customer groups partition (Bike + No bikes)',                     CAST(bike_customers + nobikes_customers AS BIGINT), 18484),
    ('Bike customers active in 2013, all countries (Q4 section C1)',    CAST(active_2013_bike AS BIGINT),    8583),
    ('No bikes customers active in 2013, all countries (Q4 section C1)', CAST(active_2013_nobikes AS BIGINT), 8844)
) AS c(check_name, actual_value, expected_value);
GO
