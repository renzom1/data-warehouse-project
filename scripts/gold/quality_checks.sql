/*
===============================================================================
Quality Checks: Gold layer
===============================================================================
Purpose:
    This script runs quality checks on the Gold layer to validate the
    integrity and consistency of the dimensional model.

    The main checks verify:

        - Uniqueness of the surrogate keys in the dimensions.
        - Referential integrity between the fact table and the dimensions.
        - Existence of valid relationships between the elements of the
          star schema.

Usage:
    - Run these checks after creating the Gold layer views.
    - The uniqueness queries should return no rows.
    - Any row returned by the referential integrity check must be
      investigated to determine the source of the discrepancy.
===============================================================================
*/


/*
SQLCMD script: run it with -v DatabaseName="<database>". The variable is
required and has no default.
*/

USE [$(DatabaseName)];
GO


/*
===============================================================================
Check: gold.dim_customers
===============================================================================
Objective:
    Verify that customer_key is unique within the customer dimension.

    The surrogate key identifies each dimension record, so no more than one
    record should have the same value.

Expected result:
    The query should return no rows.
===============================================================================
*/

SELECT
    customer_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;


/*
===============================================================================
Check: gold.dim_products
===============================================================================
Objective:
    Verify that product_key is unique within the product dimension.

Expected result:
    The query should return no rows.
===============================================================================
*/

SELECT
    product_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1;


/*
===============================================================================
Check: gold.fact_sales
===============================================================================
Objective:
    Verify the integrity of the relationships between the fact table and the
    customer and product dimensions.

    Every sales record should be linkable to an existing customer and an
    existing product in the corresponding dimensions.

    A LEFT JOIN is used to keep all fact_sales records and detect those with
    no match in one of the dimensions.

Expected result:
    The query should return no rows.

    Any row returned means that a sale could not be linked correctly to the
    customer dimension, the product dimension, or both.
===============================================================================
*/

SELECT
    *
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
    ON c.customer_key = f.customer_key
LEFT JOIN gold.dim_products p
    ON p.product_key = f.product_key
WHERE p.product_key IS NULL
   OR c.customer_key IS NULL;