/*
===============================================================================
QUALITY CHECKS - SILVER LAYER
===============================================================================
Purpose:
    This script runs quality checks on the data loaded into the Silver layer.

    The checks look for problems related to:

        - Null or duplicate keys.
        - Unnecessary spaces.
        - Lack of standardization.
        - Null, negative or invalid values.
        - Out-of-range dates.
        - Incorrect chronological order between dates.
        - Inconsistencies between related fields.

Usage:
    Run this script after loading the Silver layer.

    The queries do not modify the data. Their goal is to identify potential
    problems that must be investigated before using Silver as the source for
    the Gold layer.

General expectation:
    The queries marked "Expectation: No rows." should return no records when
    the data meets the defined quality rules.

Note:
    Some queries use SELECT DISTINCT to inspect the existing values and
    visually verify that standardization produced a consistent set of values.
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
CRM - CUSTOMERS
===============================================================================
*/

-- Check for null or duplicate keys
-- Expectation: No rows.
--
-- cst_id works as the customer identifier within this table.
-- There should be no more than one record for the same customer after the
-- deduplication performed during the Silver load.

SELECT
    cst_id,
    COUNT(*)
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1
    OR cst_id IS NULL;


-- Check for unnecessary spaces
-- Expectation: No rows.
--
-- Verifies that cst_key has no leading or trailing spaces.
-- This matters because cst_key is later used to link information coming from
-- different sources.

SELECT
    cst_key
FROM silver.crm_cust_info
WHERE cst_key != TRIM(cst_key);


-- Check marital status standardization
--
-- This query lets you inspect the existing values after the transformation
-- done during the Silver load.
--
-- The expected values correspond to the categories defined during the
-- transformation, for example: Single, Married and N/A.

SELECT DISTINCT
    cst_marital_status
FROM silver.crm_cust_info;


/*
===============================================================================
CRM - PRODUCTS
===============================================================================
*/

-- Check for null or duplicate keys
-- Expectation: No rows.
--
-- prd_id identifies each product record and is expected to be unique and
-- non-null within Silver.

SELECT
    prd_id,
    COUNT(*)
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1
    OR prd_id IS NULL;


-- Check for unnecessary spaces in the product name
-- Expectation: No rows.

SELECT
    prd_nm
FROM silver.crm_prd_info
WHERE prd_nm != TRIM(prd_nm);


-- Check for null or negative costs
-- Expectation: No rows.
--
-- A product cost should be neither negative nor NULL after applying the
-- corresponding transformation rule.

SELECT
    prd_cost
FROM silver.crm_prd_info
WHERE prd_cost < 0
    OR prd_cost IS NULL;


-- Check product line standardization
--
-- Lets you inspect the resulting values after converting the original codes
-- to descriptive values.

SELECT DISTINCT
    prd_line
FROM silver.crm_prd_info;


-- Check the chronological consistency of product versions
-- Expectation: No rows.
--
-- The end date of a version should not be earlier than its start date.
--
-- This check is related to the calculation of prd_end_dt using LEAD during
-- the Bronze to Silver transformation.

SELECT
    *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;


/*
===============================================================================
CRM - SALES
===============================================================================
*/


/*
Check for invalid dates in the Bronze source
-----------------------------------------------

This query runs against Bronze because it looks for problematic values in the
original data before their conversion to DATE during the Silver load.

Bronze dates are stored as integers in YYYYMMDD format.

The following are considered invalid, among other cases:
    - Values lower than 19000101.
    - Values greater than 20500101.
    - Values with a length other than 8 digits.
    - Values equal to or lower than 0.

The query lets you verify the quality of the original source and check which
values were handled during the transformation.
*/

SELECT
    NULLIF(sls_due_dt, 0) AS sls_due_dt
FROM bronze.crm_sales_details
WHERE sls_due_dt <= 0
    OR LEN(sls_due_dt) != 8
    OR sls_due_dt > 20500101
    OR sls_due_dt < 19000101;


/*
Check the chronological order of the dates
------------------------------------------

Expectation: No rows.

The order date should not be later than the shipping date or the due date.

This detects temporal inconsistencies in the sales data already transformed in
Silver.
*/

SELECT
    *
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;


/*
Check consistency between sales, quantity and price
-------------------------------------------------------

Expectation: No rows.

The expected relationship is:

    sales = quantity × price

Besides checking this relationship, the query also checks:
    - NULL values.
    - Values lower than or equal to zero.

DISTINCT shows only the different combinations of problematic values, avoiding
repeating exactly the same combination several times.
*/

SELECT DISTINCT
    sls_sales,
    sls_quantity,
    sls_price
FROM silver.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
   OR sls_sales IS NULL
   OR sls_quantity IS NULL
   OR sls_price IS NULL
   OR sls_sales <= 0
   OR sls_quantity <= 0
   OR sls_price <= 0
ORDER BY
    sls_sales,
    sls_quantity,
    sls_price;


/*
===============================================================================
ERP - CUSTOMERS
===============================================================================
*/


/*
Check for out-of-range birthdates
----------------------------------------------

Expectation:
    Dates should fall between 1924-01-01 (assumed to be possible)
    and the current date.

This check looks for birthdates that are not reasonable for the dataset used
in the project.

The lower bound of 1924 is the range defined for this quality check.
*/

SELECT DISTINCT
    bdate
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01'
   OR bdate > GETDATE();


/*
Check gender standardization
-------------------------------------

Lets you inspect the existing values after the normalization done during the
Silver load.

The values should correspond to the categories defined in the transformation,
such as Female, Male and N/A.
*/

SELECT DISTINCT
    gen
FROM silver.erp_cust_az12;


/*
===============================================================================
ERP - LOCATIONS
===============================================================================
*/


/*
Check country standardization
------------------------------------

Lets you inspect the existing values after normalizing the country codes and
handling NULL or empty values.

The query is ordered to make the results easier to inspect.
*/

SELECT DISTINCT
    cntry
FROM silver.erp_loc_a101
ORDER BY cntry;


/*
===============================================================================
ERP - PRODUCT CATEGORIES
===============================================================================
*/


-- Check for unnecessary spaces
-- Expectation: No rows.
--
-- Although this table receives no transformations during the Silver load,
-- its text fields are checked for unnecessary spaces.

SELECT
    *
FROM silver.erp_px_cat_g1v2
WHERE cat != TRIM(cat)
   OR subcat != TRIM(subcat)
   OR maintenance != TRIM(maintenance);


-- Check standardization of the maintenance field
--
-- Lets you inspect the existing values in the source and detect possible
-- inconsistencies or unexpected categories.

SELECT DISTINCT
    maintenance
FROM silver.erp_px_cat_g1v2;