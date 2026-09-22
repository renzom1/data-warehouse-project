/*
============================================================
CARGA DE LA CAPA BRONZE
============================================================

Este procedimiento almacenado realiza la carga de las tablas
de la capa Bronze a partir de los archivos CSV provenientes
de las fuentes CRM y ERP.

El proceso utiliza un enfoque de carga completa (full load):
las tablas se vacían mediante TRUNCATE TABLE y luego se
recargan con los datos disponibles en los archivos fuente.

Además, se registra el tiempo de ejecución de cada carga y
del proceso completo, y se incorpora manejo básico de errores
mediante TRY/CATCH.

CONFIGURACIÓN:
    Antes de ejecutar este script, reemplazar <PROJECT_ROOT>
    por la ruta local donde se encuentra el repositorio.

    Ejemplo:
    C:\Users\<usuario>\Desktop\data-warehouse-project
*/


/*
------------------------------------------------------------
Selecciona la base de datos donde se encuentra el Data
Warehouse.
------------------------------------------------------------
*/

USE DataWarehouse;
GO


/*
------------------------------------------------------------
CREACIÓN / ACTUALIZACIÓN DEL PROCEDIMIENTO
------------------------------------------------------------

CREATE OR ALTER permite crear el procedimiento si no existe
o modificarlo si ya existe.
Esto facilita el desarrollo y permite ejecutar nuevamente
el script después de realizar cambios sin tener que eliminar
manualmente el procedimiento.
*/

CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN


    /*
    --------------------------------------------------------
    Variables para medir los tiempos de ejecución.

    @start_time y @end_time se utilizan para medir la
    duración de cada carga individual.

    @batch_start_time y @batch_end_time permiten medir la
    duración total del proceso de carga de Bronze.
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

    TRY contiene el proceso normal de carga.

    Si ocurre un error durante alguna de las operaciones,
    la ejecución pasa al bloque CATCH, donde se muestran
    datos básicos sobre el error.
    --------------------------------------------------------
    */

    BEGIN TRY

        SET @batch_start_time = GETDATE();


        /*
        ----------------------------------------------------
        Inicio del proceso de carga.
        ----------------------------------------------------
        */

        PRINT '====================';
        PRINT 'Loading Bronze Layer';
        PRINT '====================';


        /*
        ====================================================
        CARGA DE TABLAS CRM
        ====================================================
        */

        PRINT '--------------------';
        PRINT 'Loading CRM Tables';
        PRINT '--------------------';


        /*
        ----------------------------------------------------
        CRM - Clientes

        TRUNCATE TABLE elimina todos los registros existentes
        pero conserva la estructura de la tabla.

        Se utiliza un full load: antes de incorporar los datos
        del archivo fuente se elimina la carga anterior, para
        así evitar acumular registros entre ejecuciones.
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_cust_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_cust_info;

        BULK INSERT bronze.crm_cust_info
        FROM '<PROJECT_ROOT>\datasets\source_crm\cust_info.csv'
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
        CRM - Productos
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_prd_info';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_prd_info;

        BULK INSERT bronze.crm_prd_info
        FROM '<PROJECT_ROOT>\datasets\source_crm\prd_info.csv'
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
        CRM - Detalle de ventas
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.crm_sales_details';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.crm_sales_details;

        BULK INSERT bronze.crm_sales_details
        FROM '<PROJECT_ROOT>\datasets\source_crm\sales_details.csv'
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
        CARGA DE TABLAS ERP
        ====================================================
        */

        PRINT '--------------------';
        PRINT 'Loading ERP Tables';
        PRINT '--------------------';


        /*
        ----------------------------------------------------
        ERP - Información adicional de clientes
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_cust_az12';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_cust_az12;

        BULK INSERT bronze.erp_cust_az12
        FROM '<PROJECT_ROOT>\datasets\source_erp\cust_az12.csv'
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
        ERP - Ubicación de clientes
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_loc_a101';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_loc_a101;

        BULK INSERT bronze.erp_loc_a101
        FROM '<PROJECT_ROOT>\datasets\source_erp\loc_a101.csv'
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
        ERP - Categorías y subcategorías de productos
        ----------------------------------------------------
        */

        PRINT '>> Truncating Table: bronze.erp_px_cat_g1v2';

        SET @start_time = GETDATE();

        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        BULK INSERT bronze.erp_px_cat_g1v2
        FROM '<PROJECT_ROOT>\datasets\source_erp\px_cat_g1v2.csv'
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
        FINALIZACIÓN DEL PROCESO
        ====================================================

        Se registra el tiempo total transcurrido desde el
        comienzo hasta la finalización de la carga de Bronze.
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
    MANEJO DE ERRORES
    ========================================================

    Si alguna operación dentro del TRY produce un error,
    SQL Server pasa a este bloque.

    Se muestran el mensaje, número y estado del error para
    facilitar la identificación del problema durante el
    desarrollo y ejecución del proceso.
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
EJECUCIÓN DEL PROCEDIMIENTO
------------------------------------------------------------

Una vez creado o actualizado el procedimiento, se ejecuta
para realizar la carga completa de la capa Bronze.
------------------------------------------------------------
*/

EXEC bronze.load_bronze;
GO