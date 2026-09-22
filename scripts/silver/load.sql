/*
===============================================================================
CARGA DE LA CAPA SILVER
===============================================================================
Propósito:
    Transformar los datos almacenados en la capa Bronze y cargarlos en las
    tablas correspondientes de la capa Silver.

    La capa Silver es responsable de aplicar reglas de limpieza,
    estandarización, validación y transformación necesarias para obtener
    datos consistentes y preparados para su utilización en la capa Gold.

Patrón de carga:
    Se utiliza una estrategia de FULL REFRESH:

        1. TRUNCATE de la tabla Silver.
        2. Transformación de los datos provenientes de Bronze.
        3. INSERT de los datos transformados.

    Esto significa que cada ejecución reconstruye completamente la capa
    Silver a partir del contenido actual de Bronze.

Control de ejecución:
    - Se registra el tiempo de carga de cada tabla.
    - Se registra el tiempo total del proceso.
    - TRY/CATCH permite capturar errores durante la ejecución.

Nota:
    El procedimiento utiliza los datos de Bronze como fuente y no modifica
    directamente las tablas de esa capa.
===============================================================================
*/

USE DataWarehouse;
GO


/*
===============================================================================
CREACIÓN / ACTUALIZACIÓN DEL PROCEDIMIENTO
===============================================================================

CREATE OR ALTER permite ejecutar este script varias veces durante el
desarrollo sin necesidad de eliminar manualmente el procedimiento existente.

El procedimiento se ejecuta posteriormente mediante:

    EXEC silver.load_silver;

===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN

    /*
    ---------------------------------------------------------------------------
    VARIABLES DE CONTROL DE TIEMPO
    ---------------------------------------------------------------------------

    Como en la capa Bronze tenemos:

    @start_time y @end_time:
        Permiten medir la duración de la carga de cada tabla.

    @batch_start_time y @batch_end_time:
        Permiten medir la duración total de la carga de Silver.
    ---------------------------------------------------------------------------
    */

    DECLARE
        @start_time DATETIME,
        @end_time DATETIME,
        @batch_start_time DATETIME,
        @batch_end_time DATETIME;


    /*
    ---------------------------------------------------------------------------
    MANEJO DE ERRORES
    ---------------------------------------------------------------------------

    TRY/CATCH permite capturar errores producidos durante la carga y mostrar
    información básica sobre el problema sin detener el procedimiento de
    forma silenciosa.
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

        Las tablas provenientes del CRM contienen información de clientes,
        productos y ventas.

        Cada tabla se transforma antes de insertarse en Silver.
        =========================================================================
        */

        PRINT '--------------------';
        PRINT 'Loading CRM Tables';
        PRINT '--------------------';


        /*
        -------------------------------------------------------------------------
        CRM CUSTOMERS
        -------------------------------------------------------------------------

        Transformaciones principales:
            - Eliminación de espacios innecesarios en nombres y atributos.
            - Normalización de estado civil.
            - Normalización de género.
            - Eliminación de registros sin identificador de cliente.
            - Eliminación de duplicados lógicos conservando el registro
              más reciente para cada cliente.

        La tabla Bronze puede contener varias versiones de un mismo cliente.
        Se utiliza ROW_NUMBER() para identificar la versión más reciente
        mediante la fecha de creación.
        -------------------------------------------------------------------------
        */

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: silver.crm_cust_info';

        /*
        TRUNCATE elimina los registros existentes pero conserva la estructura
        de la tabla.

        Se utiliza porque Silver se reconstruye completamente en cada ejecución.
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
            TRIM elimina espacios al principio y al final de los nombres.
            */
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname) AS cst_lastname,

            /*
            Se normalizan los códigos de estado civil provenientes del CRM
            a valores descriptivos.

            Valores desconocidos se representan como 'N/A' para mantener
            una representación consistente en Silver.
            */
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'S'
                    THEN 'Single'
                WHEN UPPER(TRIM(cst_marital_status)) = 'M'
                    THEN 'Married'
                ELSE 'N/A'
            END AS cst_marital_status,

            /*
            Se normalizan los códigos de género a valores descriptivos.
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
            IDENTIFICACIÓN DE REGISTROS DUPLICADOS / VERSIONES
            ---------------------------------------------------------------------

            ROW_NUMBER() genera una numeración independiente para cada cliente.

            PARTITION BY cst_id:
                Agrupa las filas correspondientes al mismo cliente.

            ORDER BY cst_create_date DESC:
                Coloca primero el registro más reciente.

            Por lo tanto, flag_last = 1 representa la versión más reciente
            disponible para cada cliente.
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
            Los registros sin identificador no pueden asociarse de manera
            confiable a un cliente.
            */
            WHERE cst_id IS NOT NULL

        ) AS t

        /*
        Conservamos únicamente la versión más reciente de cada cliente.
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

        Transformaciones principales:
            - Extracción del identificador de categoría desde prd_key.
            - Limpieza de la clave del producto.
            - Reemplazo de costos NULL.
            - Normalización de la línea de producto.
            - Conversión de fechas.
            - Cálculo de la fecha de finalización de cada versión del producto.

        La fecha de finalización se obtiene a partir de la siguiente fecha
        de inicio del mismo producto.
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
            El identificador de categoría se encuentra dentro de prd_key.

            Ejemplo conceptual:
                CAT-001-XXX
                ↓
                CAT_001

            Se reemplaza '-' por '_' para obtener una clave compatible
            con la utilizada posteriormente para relacionar productos
            con la información de categorías del ERP.
            */
            REPLACE(
                SUBSTRING(prd_key, 1, 5),
                '-',
                '_'
            ) AS cat_id,

            /*
            Se extrae la parte correspondiente al identificador del producto
            a partir de prd_key.
            */
            SUBSTRING(
                prd_key,
                7,
                LEN(prd_key)
            ) AS prd_key,

            prd_nm,

            /*
            Los costos faltantes se reemplazan por 0 para evitar valores NULL
            en esta columna.
            */
            ISNULL(prd_cost, 0) AS prd_cost,

            /*
            Se convierten los códigos de línea de producto en valores
            descriptivos.
            */
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'N/A'
            END AS prd_line,

            /*
            Se convierte la fecha proveniente de Bronze al tipo DATE utilizado
            en Silver.
            */
            CAST(prd_start_dt AS DATE) AS prd_start_date,

            /*
            LEAD permite obtener la fecha de inicio de la siguiente versión
            del mismo producto.

            Se resta un día para obtener la fecha de finalización de la
            versión actual.

            Ejemplo:

                Inicio versión 1: 2020-01-01
                Inicio versión 2: 2021-01-01

                Fin versión 1:    2020-12-31
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

        Transformaciones principales:
            - Validación y conversión de fechas.
            - Corrección de valores de ventas inconsistentes.
            - Corrección / derivación de precios inválidos.

        Las fechas llegan desde Bronze como INT en formato YYYYMMDD.
        Antes de convertirlas a DATE se valida que tengan ocho dígitos y
        que no sean 0.
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
            Las fechas de Bronze se almacenan como enteros YYYYMMDD.

            Valores 0 o con una longitud diferente de 8 no representan
            una fecha válida y se convierten en NULL.
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
            Se valida el importe de venta.

            Si el valor original:
                - es NULL,
                - es menor o igual a 0, o
                - no coincide con quantity * price,

            se recalcula utilizando cantidad y precio.

            ABS(sls_price) evita que un precio negativo origine un importe
            de venta negativo.
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
            Si el precio original es NULL o no es positivo, se intenta
            derivarlo a partir del importe de venta y la cantidad.

            NULLIF evita una división por cero cuando sls_quantity = 0.
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

        Las tablas ERP aportan información complementaria que posteriormente
        será integrada con los datos del CRM en la capa Gold.
        =========================================================================
        */

        PRINT '--------------------';
        PRINT 'Loading ERP Tables';
        PRINT '--------------------';


        /*
        -------------------------------------------------------------------------
        ERP CUSTOMER
        -------------------------------------------------------------------------

        Transformaciones:
            - Eliminación del prefijo 'NAS' de los identificadores.
            - Validación de fechas de nacimiento.
            - Normalización del género.
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
            Algunos identificadores contienen el prefijo NAS.
            Se elimina para que el identificador pueda utilizarse
            posteriormente para relacionar esta fuente con CRM.
            */
            CASE
                WHEN cid LIKE 'NAS%'
                    THEN SUBSTRING(cid, 4, LEN(cid))
                ELSE cid
            END AS cid,

            /*
            Una fecha de nacimiento futura no es válida para este contexto,
            por lo que se transforma en NULL.
            */
            CASE
                WHEN bdate > GETDATE()
                    THEN NULL
                ELSE bdate
            END AS bdate,

            /*
            Se normalizan las diferentes representaciones de género
            encontradas en la fuente.
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

        Transformaciones:
            - Eliminación de '-' en los identificadores.
            - Normalización de países.
            - Tratamiento de valores NULL o vacíos.
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
            Se eliminan los guiones del identificador para homogeneizar
            su formato con las demás fuentes.
            */
            REPLACE(cid, '-', '') AS cid,

            /*
            Se convierten códigos de país a nombres descriptivos.

            Los valores vacíos o NULL se representan como 'N/A'.
            Los demás valores se conservan después de eliminar espacios.
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
        
        En esta tabla no se aplican transformaciones.

        Se mantiene la información tal como fue cargada en Bronze porque,
        en el contexto de este proyecto, no se identificaron transformaciones
        necesarias antes de utilizar estos datos en Gold.
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
        FINALIZACIÓN DE LA CARGA
        =========================================================================

        Se calcula el tiempo total empleado en la ejecución del procedimiento.
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
    MANEJO DE ERRORES
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
EJECUCIÓN
===============================================================================

Una vez creado o actualizado el procedimiento, se ejecuta la carga completa
de la capa Silver mediante:

    EXEC silver.load_silver;

===============================================================================
*/

EXEC silver.load_silver;
GO