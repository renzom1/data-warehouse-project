/*
===============================================================================
DDL Script: Gold layer view creation
===============================================================================
Purpose:
    This script creates the views that make up the Gold layer of the Data
    Warehouse.

    The Gold layer is the analytical consumption layer and organizes the data
    in a Star Schema dimensional model made up of:

        - gold.dim_customers
        - gold.dim_products
        - gold.fact_sales

    Unlike the Bronze and Silver layers, where data is physically stored in
    tables, the Gold layer is implemented as views that query and combine the
    transformed data of the Silver layer.

    The views:
        - integrate information coming from different sources;
        - generate surrogate keys for the dimensions;
        - select only the current product records;
        - link the sales facts to the dimensions through their corresponding
          keys;
        - expose a structure ready for analysis and reporting.

Usage:
    - Run this script after the Silver layer has been loaded and validated.
    - The views can be queried directly for SQL analysis and reporting.
    - The script can be run again during development, since it drops the
      existing views before creating them.
===============================================================================
*/


/*
===============================================================================
Dimension creation: gold.dim_customers
===============================================================================
Purpose:
    Build the customer dimension by integrating information from CRM and ERP.

    CRM is the primary source for customer information. ERP data is used as
    enrichment and as a fallback source when certain information is not
    available in CRM.

    A surrogate key (customer_key) is generated with ROW_NUMBER() to be used
    as the customer identifier within the dimensional model.
===============================================================================
*/

/*
SQLCMD script: run it with -v DatabaseName="<database>". The variable is
required and has no default.
*/

USE [$(DatabaseName)];
GO

IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key,

    ci.cst_id             AS customer_id,
    ci.cst_key            AS customer_number,
    ci.cst_firstname      AS first_name,
    ci.cst_lastname       AS last_name,
    la.cntry              AS country,
    ci.cst_marital_status AS marital_status,

    /*
        CRM is the primary source for gender.
        When CRM contains 'n/a', the value available in ERP is used.
        If ERP has no valid value either, 'n/a' is kept.
    */
    CASE
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END AS gender,

    ca.bdate             AS birthdate,
    ci.cst_create_date   AS create_date

FROM silver.crm_cust_info ci

/*
    ERP provides additional customer information, such as birthdate and
    gender, using the customer key as the integration criterion.
*/
LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid

/*
    ERP also provides the customer's geographic information.
*/
LEFT JOIN silver.erp_loc_a101 la
    ON ci.cst_key = la.cid;
GO


/*
===============================================================================
Dimension creation: gold.dim_products
===============================================================================
Purpose:
    Build the product dimension by integrating the product information from
    CRM with the category information from ERP.

    Only the records for the current version of each product are included.
    Historical versions are excluded through the filter on prd_end_dt.

    A surrogate key (product_key) is generated with ROW_NUMBER() to be used
    as the product identifier within the dimensional model.
===============================================================================
*/

IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY pn.prd_start_dt, pn.prd_key
    ) AS product_key,

    pn.prd_id       AS product_id,
    pn.prd_key      AS product_number,
    pn.prd_nm       AS product_name,
    pn.cat_id       AS category_id,
    pc.cat          AS category,
    pc.subcat       AS subcategory,
    pc.maintenance  AS maintenance,
    pn.prd_cost     AS cost,
    pn.prd_line     AS product_line,
    pn.prd_start_dt AS start_date

FROM silver.crm_prd_info pn

/*
    Category and subcategory information from the ERP system is added.
*/
LEFT JOIN silver.erp_px_cat_g1v2 pc
    ON pn.cat_id = pc.id

/*
    Only the currently active product versions are kept. Historical records
    have an end date.
*/
WHERE pn.prd_end_dt IS NULL;
GO


/*
===============================================================================
Fact table creation: gold.fact_sales
===============================================================================
Purpose:
    Build the sales fact view from the transformed Silver data.

    The view links each sales transaction to the product and customer
    dimensions through their surrogate keys.

    In this way, fact_sales is the logical fact table of the star schema and
    holds the metrics and dates needed for sales analysis.
===============================================================================
*/

IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num  AS order_number,
    pr.product_key  AS product_key,
    cu.customer_key AS customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt  AS shipping_date,
    sd.sls_due_dt   AS due_date,
    sd.sls_sales    AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price    AS price

FROM silver.crm_sales_details sd

/*
    The product surrogate key is obtained from the natural key stored in the
    sales data.
*/
LEFT JOIN gold.dim_products pr
    ON sd.sls_prd_key = pr.product_number

/*
    The customer surrogate key is obtained from the customer identifier
    present in the sales data.
*/
LEFT JOIN gold.dim_customers cu
    ON sd.sls_cust_id = cu.customer_id;
GO