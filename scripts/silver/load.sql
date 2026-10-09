/*
===============================================================================
SILVER LAYER LOAD
===============================================================================
Purpose:
    Transform the data stored in the Bronze layer and load it into the
    corresponding Silver layer tables.

    The Silver layer is responsible for applying the cleaning,
    standardization, validation and transformation rules needed to obtain
    consistent data ready to be used in the Gold layer.

Load pattern:
    A FULL REFRESH strategy is used:

        1. TRUNCATE the Silver table.
        2. Transform the data coming from Bronze.
        3. INSERT the transformed data.

    This means each run completely rebuilds the Silver layer from the current
    contents of Bronze.

Execution control:
    - The load time of each table is recorded.
    - The total time of the process is recorded.
    - TRY/CATCH captures errors during execution.

Note:
    The procedure uses the Bronze data as its source and does not modify the
    tables of that layer directly.
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
PROCEDURE CREATION / UPDATE
===============================================================================

CREATE OR ALTER allows this script to be run several times during development
without having to drop the existing procedure manually.

The procedure is then executed with:

    EXEC silver.load_silver;

===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN

    /*
    ---------------------------------------------------------------------------
    TIME CONTROL VARIABLES
    ---------------------------------------------------------------------------

    As in the Bronze layer we have:

    @start_time and @end_time:
        Measure the load duration of each table.

    @batch_start_time and @batch_end_time:
        Measure the total duration of the Silver load.
    ---------------------------------------------------------------------------
    */

    DECLARE
        @start_time DATETIME,
        @end_time DATETIME,
        @batch_start_time DATETIME,
        @batch_end_time DATETIME;


    /*
    ---------------------------------------------------------------------------
    ERROR HANDLING
    ---------------------------------------------------------------------------

    TRY/CATCH captures errors produced during the load and shows basic
    information about the problem, instead of stopping the procedure silently.
    ---------------------------------------------------------------------------
    */

    BEGIN TRY

        SET @batch_start_time = GETDATE();

        PRINT '====================';
        PRINT 'Loading Silver Layer';
        PRINT '====================';


        /*
        =========================================================================
        CRM
        =========================================================================

        The tables coming from the CRM hold customer, product and sales
        information.

        Each table is transformed before being inserted into Silver.
        =========================================================================
        */

        PRINT '--------------------';
        PRINT 'Loading CRM Tables';
        PRINT '--------------------';


        /*
        -------------------------------------------------------------------------
        CRM CUSTOMERS
        -------------------------------------------------------------------------

        Main transformations:
            - Removal of unnecessary spaces in names and attributes.
            - Marital status normalization.
            - Gender normalization.
            - Removal of records with no customer identifier.
            - Removal of logical duplicates, keeping the most recent record
              for each customer.

        The Bronze table can contain several versions of the same customer.
        ROW_NUMBER() is used to identify the most recent version through the
        creation date.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.crm_cust_info';

        /*
        TRUNCATE removes the existing records but keeps the table structure.

        It is used because Silver is completely rebuilt on every run.
        */
        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '>> Inserting Data Into: silver.crm_cust_info';


        INSERT INTO silver.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )

        SELECT
            cst_id,
            cst_key,

            /*
            TRIM removes leading and trailing spaces from the names.
            */
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,

            /*
            The marital status codes coming from the CRM are normalized to
            descriptive values.

            Unknown values are represented as 'N/A' to keep a consistent
            representation in Silver.
            */
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'S'
                    THEN 'Single'
                WHEN UPPER(TRIM(cst_marital_status)) = 'M'
                    THEN 'Married'
                ELSE 'N/A'
            END AS cst_marital_status,

            /*
            The gender codes are normalized to descriptive values.
            */
            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'F'
                    THEN 'Female'
                WHEN UPPER(TRIM(cst_gndr)) = 'M'
                    THEN 'Male'
                ELSE 'N/A'
            END AS cst_gndr,

            cst_create_date

        FROM (
            /*
            ---------------------------------------------------------------------
            IDENTIFYING DUPLICATE RECORDS / VERSIONS
            ---------------------------------------------------------------------

            ROW_NUMBER() generates an independent numbering for each customer.

            PARTITION BY cst_id:
                Groups the rows belonging to the same customer.

            ORDER BY cst_create_date DESC:
                Puts the most recent record first.

            Therefore, flag_last = 1 represents the most recent version
            available for each customer.
            ---------------------------------------------------------------------
            */

            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY cst_id
                    ORDER BY cst_create_date DESC
                ) AS flag_last

            FROM bronze.crm_cust_info

            /*
            Records with no identifier cannot be reliably associated with a
            customer.
            */
            WHERE cst_id IS NOT NULL

        ) AS t

        /*
        Only the most recent version of each customer is kept.
        */
        WHERE flag_last = 1;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        -------------------------------------------------------------------------
        CRM PRODUCTS
        -------------------------------------------------------------------------

        Main transformations:
            - Extraction of the category identifier from prd_key.
            - Cleaning of the product key.
            - Replacement of NULL costs.
            - Product line normalization.
            - Date conversion.
            - Calculation of the end date of each product version.

        The end date is derived from the next start date of the same product.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.crm_prd_info';

        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '>> Inserting Data Into: silver.crm_prd_info';


        INSERT INTO silver.crm_prd_info (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )

        SELECT
            prd_id,

            /*
            The category identifier is found inside prd_key.

            Conceptual example:
                CAT-001-XXX
                ↓
                CAT_001

            '-' is replaced by '_' to obtain a key compatible with the one
            later used to link products with the ERP category information.
            */
            REPLACE(
                SUBSTRING(prd_key, 1, 5),
                '-',
                '_'
            ) AS cat_id,

            /*
            The part corresponding to the product identifier is extracted
            from prd_key.
            */
            SUBSTRING(
                prd_key,
                7,
                LEN(prd_key)
            ) AS prd_key,

            prd_nm,

            /*
            Missing costs are replaced by 0 to avoid NULL values in this
            column.
            */
            ISNULL(prd_cost, 0) AS prd_cost,

            /*
            The product line codes are converted to descriptive values.
            */
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'N/A'
            END AS prd_line,

            /*
            The date coming from Bronze is converted to the DATE type used in
            Silver.
            */
            CAST(prd_start_dt AS DATE) AS prd_start_date,

            /*
            LEAD returns the start date of the next version of the same
            product.

            One day is subtracted to obtain the end date of the current
            version.

            Example:

                Version 1 start: 2020-01-01
                Version 2 start: 2021-01-01

                Version 1 end:   2020-12-31
            */
            CAST(
                LEAD(prd_start_dt) OVER (
                    PARTITION BY prd_key
                    ORDER BY prd_start_dt
                ) - 1 AS DATE
            ) AS prd_end_dt

        FROM bronze.crm_prd_info;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        -------------------------------------------------------------------------
        CRM SALES
        -------------------------------------------------------------------------

        Main transformations:
            - Date validation and conversion.
            - Correction of inconsistent sales values.
            - Correction / derivation of invalid prices.

        Dates arrive from Bronze as INT in YYYYMMDD format.
        Before converting them to DATE, they are validated to have eight digits
        and to not be 0.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.crm_sales_details';

        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '>> Inserting Data Into: silver.crm_sales_details';


        INSERT INTO silver.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )

        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,

            /*
            Bronze dates are stored as YYYYMMDD integers.

            Values of 0 or with a length other than 8 do not represent a valid
            date and are converted to NULL.
            */
            CASE
                WHEN sls_order_dt = 0
                     OR LEN(sls_order_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_order_dt AS NVARCHAR) AS DATE)
            END AS sls_order_dt,

            CASE
                WHEN sls_ship_dt = 0
                     OR LEN(sls_ship_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS NVARCHAR) AS DATE)
            END AS sls_ship_dt,

            CASE
                WHEN sls_due_dt = 0
                     OR LEN(sls_due_dt) != 8
                    THEN NULL
                ELSE CAST(CAST(sls_due_dt AS NVARCHAR) AS DATE)
            END AS sls_due_dt,

            /*
            The sales amount is validated.

            If the original value:
                - is NULL,
                - is less than or equal to 0, or
                - does not match quantity * price,

            it is recalculated using quantity and price.

            ABS(sls_price) prevents a negative price from producing a
            negative sales amount.
            */
            CASE
                WHEN sls_sales IS NULL
                     OR sls_sales <= 0
                     OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,

            sls_quantity,

            /*
            If the original price is NULL or not positive, an attempt is made
            to derive it from the sales amount and the quantity.

            NULLIF avoids a division by zero when sls_quantity = 0.
            */
            CASE
                WHEN sls_price IS NULL
                     OR sls_price <= 0
                    THEN ABS(sls_sales) / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS sls_price

        FROM bronze.crm_sales_details;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        =========================================================================
        ERP
        =========================================================================

        The ERP tables provide complementary information that is later
        integrated with the CRM data in the Gold layer.
        =========================================================================
        */

        PRINT '--------------------';
        PRINT 'Loading ERP Tables';
        PRINT '--------------------';


        /*
        -------------------------------------------------------------------------
        ERP CUSTOMER
        -------------------------------------------------------------------------

        Transformations:
            - Removal of the 'NAS' prefix from the identifiers.
            - Birthdate validation.
            - Gender normalization.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.erp_cust_az12';

        TRUNCATE TABLE silver.erp_cust_az12;

        PRINT '>> Inserting Data Into: silver.erp_cust_az12';


        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )

        SELECT

            /*
            Some identifiers contain the NAS prefix.
            It is removed so that the identifier can later be used to link
            this source with the CRM.
            */
            CASE
                WHEN cid LIKE 'NAS%'
                    THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE cid
            END AS cid,

            /*
            A future birthdate is not valid in this context, so it is
            converted to NULL.
            */
            CASE
                WHEN bdate > GETDATE()
                    THEN NULL
                ELSE bdate
            END AS bdate,

            /*
            The different gender representations found in the source are
            normalized.
            */
            CASE
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE')
                    THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')
                    THEN 'Male'
                ELSE 'N/A'
            END AS gen

        FROM bronze.erp_cust_az12;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        -------------------------------------------------------------------------
        ERP LOCATION
        -------------------------------------------------------------------------

        Transformations:
            - Removal of '-' from the identifiers.
            - Country normalization.
            - Handling of NULL or empty values.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.erp_loc_a101';

        TRUNCATE TABLE silver.erp_loc_a101;

        PRINT '>> Inserting Data Into: silver.erp_loc_a101';


        INSERT INTO silver.erp_loc_a101 (
            cid,
            cntry
        )

        SELECT

            /*
            Hyphens are removed from the identifier to make its format
            consistent with the other sources.
            */
            REPLACE(cid, '-', '') AS cid,

            /*
            Country codes are converted to descriptive names.

            Empty or NULL values are represented as 'N/A'.
            Other values are kept after removing spaces.
            */
            CASE
                WHEN TRIM(cntry) = 'DE'
                    THEN 'Germany'
                WHEN TRIM(cntry) IN ('US', 'USA')
                    THEN 'United States'
                WHEN TRIM(cntry) = ''
                     OR cntry IS NULL
                    THEN 'N/A'
                ELSE TRIM(cntry)
            END AS cntry

        FROM bronze.erp_loc_a101;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        -------------------------------------------------------------------------
        ERP PRODUCT CATEGORY
        -------------------------------------------------------------------------

        No transformations are applied to this table.

        The information is kept as it was loaded in Bronze because, in the
        context of this project, no transformations were identified as
        necessary before using this data in Gold.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';

        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';


        INSERT INTO silver.erp_px_cat_g1v2 (
            id,
            cat,
            subcat,
            maintenance
        )

        SELECT
            id,
            cat,
            subcat,
            maintenance

        FROM bronze.erp_px_cat_g1v2;


        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        =========================================================================
        END OF THE LOAD
        =========================================================================

        The total time spent running the procedure is calculated.
        =========================================================================
        */

        SET @batch_end_time = GETDATE();

        PRINT '====================';
        PRINT 'Loading Silver Layer is Completed';

        PRINT ' - Total Load Duration: '
            + CAST(
                DATEDIFF(
                    second,
                    @batch_start_time,
                    @batch_end_time
                ) AS NVARCHAR
            )
            + ' seconds';

        PRINT '====================';


    END TRY


    /*
    =========================================================================
    ERROR HANDLING
    =========================================================================
    */

    BEGIN CATCH

        PRINT '====================';
        PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER';

        PRINT 'Error Message: '
            + ERROR_MESSAGE();

        PRINT 'Error Number: '
            + CAST(ERROR_NUMBER() AS NVARCHAR);

        PRINT 'Error State: '
            + CAST(ERROR_STATE() AS NVARCHAR);

        PRINT '====================';

    END CATCH

END;
GO


/*
===============================================================================
EXECUTION
===============================================================================

Once the procedure has been created or updated, the full load of the Silver
layer is run with:

    EXEC silver.load_silver;

===============================================================================
*/

EXEC silver.load_silver;
GO