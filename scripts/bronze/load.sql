/*
============================================================
BRONZE LAYER LOAD
============================================================

This stored procedure loads the Bronze layer tables from the
CSV files coming from the CRM and ERP sources.

The process uses a full load approach: the tables are emptied
with TRUNCATE TABLE and then reloaded with the data available
in the source files.

It also records the execution time of each load and of the
whole process, and includes basic error handling through
TRY/CATCH.

CONFIGURATION (SQLCMD):
    This is a sqlcmd script. Two scripting variables are required and have
    no default:

        DatabaseName   target database (for example DataWarehouse_Test)
        ProjectRoot    absolute path of the repository root, with no
                       trailing backslash

    Example:

        sqlcmd -S <server> -E -b ^
               -v DatabaseName="DataWarehouse_Test" ProjectRoot="C:\path\to\data-warehouse-project" ^
               -i scripts\bronze\load.sql

    Notes:
    - In SSMS, enable Query > SQLCMD Mode and define both variables with
      :setvar above the script instead of using -v.
    - BULK INSERT reads the files as the SQL Server service account, so that
      account needs read access to the datasets folder.
    - The resolved path is stored inside the procedure definition.
*/


/*
------------------------------------------------------------
Selects the target database, supplied through the sqlcmd
variable DatabaseName.
------------------------------------------------------------
*/

USE [$(DatabaseName)];
GO


/*
------------------------------------------------------------
PROCEDURE CREATION / UPDATE
------------------------------------------------------------

CREATE OR ALTER creates the procedure if it does not exist
or modifies it if it already does.
This makes development easier and allows the script to be
run again after making changes without having to drop the
procedure manually.
*/

CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN


    /*
    --------------------------------------------------------
    Variables used to measure execution times.

    @start_time and @end_time are used to measure the
    duration of each individual load.

    @batch_start_time and @batch_end_time measure the total
    duration of the Bronze load process.
    --------------------------------------------------------
    */

    DECLARE
        @start_time DATETIME,
        @end_time DATETIME,
        @batch_start_time DATETIME,
        @batch_end_time DATETIME;


    /*
    --------------------------------------------------------
    TRY/CATCH

    TRY contains the normal load process.

    If an error occurs during any of the operations,
    execution moves to the CATCH block, where basic
    information about the error is displayed.
    --------------------------------------------------------
    */

    BEGIN TRY

        SET @batch_start_time = GETDATE();


        /*
        ----------------------------------------------------
        Start of the load process.
        ----------------------------------------------------
        */

        PRINT '====================';
        PRINT 'Loading Bronze Layer';
        PRINT '====================';


        /*
        ====================================================
        CRM TABLE LOAD
        ====================================================
        */

        PRINT '--------------------';
        PRINT 'Loading CRM Tables';
        PRINT '--------------------';


        /*
        ----------------------------------------------------
        CRM - Customers

        TRUNCATE TABLE removes all existing records but keeps
        the table structure.

        A full load is used: before bringing in the data from
        the source file, the previous load is removed, so that
        records do not accumulate between runs.
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_cust_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_cust_info;

        BULK INSERT bronze.crm_cust_info
        FROM '$(ProjectRoot)\datasets\source_crm\cust_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        ----------------------------------------------------
        CRM - Products
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_prd_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_prd_info;

        BULK INSERT bronze.crm_prd_info
        FROM '$(ProjectRoot)\datasets\source_crm\prd_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> --------------';


        /*
        ----------------------------------------------------
        CRM - Sales details
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_sales_details';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_sales_details;

        BULK INSERT bronze.crm_sales_details
        FROM '$(ProjectRoot)\datasets\source_crm\sales_details.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';


        /*
        ====================================================
        ERP TABLE LOAD
        ====================================================
        */

        PRINT '--------------------';
        PRINT 'Loading ERP Tables';
        PRINT '--------------------';


        /*
        ----------------------------------------------------
        ERP - Additional customer information
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_cust_az12';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_cust_az12;

        BULK INSERT bronze.erp_cust_az12
        FROM '$(ProjectRoot)\datasets\source_erp\cust_az12.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '--------------------';


        /*
        ----------------------------------------------------
        ERP - Customer location
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_loc_a101';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_loc_a101;

        BULK INSERT bronze.erp_loc_a101
        FROM '$(ProjectRoot)\datasets\source_erp\loc_a101.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '--------------------';


        /*
        ----------------------------------------------------
        ERP - Product categories and subcategories
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_px_cat_g1v2';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        BULK INSERT bronze.erp_px_cat_g1v2
        FROM '$(ProjectRoot)\datasets\source_erp\px_cat_g1v2.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '--------------------';


        /*
        ====================================================
        END OF THE PROCESS
        ====================================================

        The total time elapsed from the start to the end of
        the Bronze load is recorded.
        ====================================================
        */

        SET @batch_end_time = GETDATE();

        PRINT '====================';
        PRINT 'Loading Bronze Layer is Completed';

        PRINT ' - Total Load Duration: '
            + CAST(DATEDIFF(second, @batch_start_time, @batch_end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '====================';


    END TRY


    /*
    ========================================================
    ERROR HANDLING
    ========================================================

    If any operation inside the TRY produces an error,
    SQL Server moves to this block.

    The error message, number and state are displayed to
    make it easier to identify the problem during
    development and execution of the process.
    ========================================================
    */

    BEGIN CATCH

        PRINT '====================';
        PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER';

        PRINT 'Error Message: ' + ERROR_MESSAGE();

        PRINT 'Error Number: '
            + CAST(ERROR_NUMBER() AS NVARCHAR);

        PRINT 'Error State: '
            + CAST(ERROR_STATE() AS NVARCHAR);

        PRINT '====================';

    END CATCH

END;
GO


/*
------------------------------------------------------------
PROCEDURE EXECUTION
------------------------------------------------------------

Once the procedure has been created or updated, it is
executed to perform the full load of the Bronze layer.
------------------------------------------------------------
*/

EXEC bronze.load_bronze;
GO