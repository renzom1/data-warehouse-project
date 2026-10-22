/*
===============================================================================
Validation: warehouse state against the corrected rebuild baseline
===============================================================================
Purpose:
    Check, in one run, that a database holds the warehouse documented in
    docs/rebuild_baseline.md (corrected rebuild) and that the Gold model is
    consistent. Unlike the quality-check scripts, which return rows to be read,
    this script fails: if any check does not match, it raises an error, so
    sqlcmd -b exits with a non-zero code.

    The checks cover:
        - row counts of every Bronze and Silver table and every Gold view;
        - fact table control totals (orders, revenue, units, date range);
        - uniqueness of the dimension surrogate keys;
        - fact lines with no matching customer or product;
        - known facts that tell the corrected build apart from the original
          load (customer 29483 birthdate, decision 6) and the known
          data-quality flag (15 birthdates before 1924, decision 7.3).

Usage:
    scripts\validate.ps1 -DatabaseName DataWarehouse_Test
    or directly:
    sqlcmd -S .\SQLEXPRESS -E -C -b -W -v DatabaseName=DataWarehouse_Test -i scripts\validate.sql

Read-only: SELECT statements only. No objects are created or modified.

If an expected value changes on purpose (for example after a documented
change to Silver), update it here and in docs/rebuild_baseline.md together.
===============================================================================
*/

USE [$(DatabaseName)];
GO

SET NOCOUNT ON;

DECLARE @checks TABLE (
    check_name     VARCHAR(100) NOT NULL,
    actual_value   BIGINT       NULL,
    expected_value BIGINT       NOT NULL
);

/*
Row counts by layer (corrected rebuild).
*/
INSERT INTO @checks VALUES
    ('bronze.crm_cust_info rows',      (SELECT COUNT_BIG(*) FROM bronze.crm_cust_info),      18494),
    ('bronze.crm_prd_info rows',       (SELECT COUNT_BIG(*) FROM bronze.crm_prd_info),         397),
    ('bronze.crm_sales_details rows',  (SELECT COUNT_BIG(*) FROM bronze.crm_sales_details),  60398),
    ('bronze.erp_cust_az12 rows',      (SELECT COUNT_BIG(*) FROM bronze.erp_cust_az12),      18484),
    ('bronze.erp_loc_a101 rows',       (SELECT COUNT_BIG(*) FROM bronze.erp_loc_a101),       18484),
    ('bronze.erp_px_cat_g1v2 rows',    (SELECT COUNT_BIG(*) FROM bronze.erp_px_cat_g1v2),       37),
    ('silver.crm_cust_info rows',      (SELECT COUNT_BIG(*) FROM silver.crm_cust_info),      18484),
    ('silver.crm_prd_info rows',       (SELECT COUNT_BIG(*) FROM silver.crm_prd_info),         397),
    ('silver.crm_sales_details rows',  (SELECT COUNT_BIG(*) FROM silver.crm_sales_details),  60398),
    ('silver.erp_cust_az12 rows',      (SELECT COUNT_BIG(*) FROM silver.erp_cust_az12),      18484),
    ('silver.erp_loc_a101 rows',       (SELECT COUNT_BIG(*) FROM silver.erp_loc_a101),       18484),
    ('silver.erp_px_cat_g1v2 rows',    (SELECT COUNT_BIG(*) FROM silver.erp_px_cat_g1v2),       37),
    ('gold.dim_customers rows',        (SELECT COUNT_BIG(*) FROM gold.dim_customers),        18484),
    ('gold.dim_products rows',         (SELECT COUNT_BIG(*) FROM gold.dim_products),           295),
    ('gold.fact_sales rows',           (SELECT COUNT_BIG(*) FROM gold.fact_sales),           60398);

/*
Fact table control totals. Dates are compared as yyyymmdd integers.
*/
INSERT INTO @checks VALUES
    ('fact distinct orders',  (SELECT COUNT(DISTINCT order_number)           FROM gold.fact_sales),    27659),
    ('fact revenue',          (SELECT SUM(CAST(sales_amount AS BIGINT))      FROM gold.fact_sales), 29356250),
    ('fact units',            (SELECT SUM(CAST(quantity AS BIGINT))          FROM gold.fact_sales),    60423),
    ('fact first order_date', (SELECT CONVERT(INT, CONVERT(CHAR(8), MIN(order_date), 112)) FROM gold.fact_sales), 20101229),
    ('fact last order_date',  (SELECT CONVERT(INT, CONVERT(CHAR(8), MAX(order_date), 112)) FROM gold.fact_sales), 20140128);

/*
Gold model integrity. Each count must be 0.
*/
INSERT INTO @checks VALUES
    ('duplicate customer_key values',
        (SELECT COUNT_BIG(*) FROM (SELECT customer_key FROM gold.dim_customers GROUP BY customer_key HAVING COUNT(*) > 1) AS d), 0),
    ('duplicate product_key values',
        (SELECT COUNT_BIG(*) FROM (SELECT product_key FROM gold.dim_products GROUP BY product_key HAVING COUNT(*) > 1) AS d), 0),
    ('fact lines without customer',
        (SELECT COUNT_BIG(*) FROM gold.fact_sales f LEFT JOIN gold.dim_customers c ON c.customer_key = f.customer_key WHERE c.customer_key IS NULL), 0),
    ('fact lines without product',
        (SELECT COUNT_BIG(*) FROM gold.fact_sales f LEFT JOIN gold.dim_products p ON p.product_key = f.product_key WHERE p.product_key IS NULL), 0);

/*
Known facts.
    - Customer 29483 has birthdate 1965-06-06 only in the corrected build
      (decision 6). In the original DataWarehouse it is NULL, so this check
      also stops an analysis from running on the pre-fix load (decision 7.7).
    - 15 birthdates before 1924 are a known, unmodified flag (decision 7.3).
      A different count means Silver or the source changed.
*/
INSERT INTO @checks VALUES
    ('customer 29483 birthdate (yyyymmdd)',
        (SELECT CONVERT(INT, CONVERT(CHAR(8), birthdate, 112)) FROM gold.dim_customers WHERE customer_id = 29483), 19650606),
    ('customers with birthdate before 1924',
        (SELECT COUNT_BIG(*) FROM gold.dim_customers WHERE birthdate < '1924-01-01'), 15);

SELECT
    check_name,
    actual_value,
    expected_value,
    CASE WHEN actual_value = expected_value THEN 'OK' ELSE 'MISMATCH' END AS status
FROM @checks;

DECLARE @failed INT = (
    SELECT COUNT(*) FROM @checks
    WHERE actual_value IS NULL OR actual_value <> expected_value
);

IF @failed > 0
BEGIN
    DECLARE @msg NVARCHAR(200) = CONCAT('VALIDATION FAILED: ', @failed, ' check(s) do not match the baseline. See the MISMATCH rows above.');
    THROW 50001, @msg, 1;
END

PRINT 'VALIDATION PASSED: all checks match the baseline.';
GO
