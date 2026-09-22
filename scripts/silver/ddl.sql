/*
===============================================================================
DDL: Creación de tablas de la capa Silver
===============================================================================
Propósito:
    Crear la estructura de las tablas de la capa Silver a partir de los datos
    recibidos en Bronze.

    A diferencia de Bronze, Silver contiene datos que posteriormente serán
    limpiados, estandarizados y transformados para facilitar su integración
    y consumo en la capa Gold.

    Las tablas se eliminan y recrean si ya existen para permitir ejecutar
    nuevamente el script durante el desarrollo y redefinir su estructura.

    Además, cada tabla incorpora dwh_create_date para registrar cuándo se
    realizó la inserción del registro en el Data Warehouse.
===============================================================================
*/

USE DataWarehouse;
GO


/*
-------------------------------------------------------------------------------
CRM: Información de clientes
-------------------------------------------------------------------------------

La estructura mantiene las columnas principales provenientes de Bronze.

La columna dwh_create_date no proviene de la fuente original. Es un atributo
de auditoría generado por el Data Warehouse mediante DEFAULT GETDATE().
Permite registrar cuándo fue creado el registro dentro de Silver.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_cust_info;
GO

CREATE TABLE silver.crm_cust_info (
    cst_id              INT,
    cst_key             NVARCHAR(50),
    cst_firstname       NVARCHAR(50),
    cst_lastname        NVARCHAR(50),
    cst_marital_status  NVARCHAR(50),
    cst_gndr            NVARCHAR(50),
    cst_create_date     DATE,
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);


/*
-------------------------------------------------------------------------------
CRM: Información de productos
-------------------------------------------------------------------------------

En Silver se incorpora cat_id, que posteriormente permite relacionar los
productos con la información de categorías proveniente del ERP.

Las fechas se almacenan como DATE porque durante la transformación desde
Bronze se validan y convierten los valores originales.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE silver.crm_prd_info;
GO

CREATE TABLE silver.crm_prd_info (
    prd_id              INT,
    cat_id              NVARCHAR(50),
    prd_key             NVARCHAR(50),
    prd_nm              NVARCHAR(50),
    prd_cost            INT,
    prd_line            NVARCHAR(50),
    prd_start_dt        DATE,
    prd_end_dt          DATE,
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);


/*
-------------------------------------------------------------------------------
CRM: Detalle de ventas
-------------------------------------------------------------------------------

A diferencia de Bronze, las fechas de pedido, envío y vencimiento se
almacenan como DATE.

Esto refleja una transformación realizada durante la carga de Silver,
donde los valores originales provenientes de Bronze son validados y
convertidos a un tipo de fecha adecuado.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE silver.crm_sales_details;
GO

CREATE TABLE silver.crm_sales_details (
    sls_ord_num         NVARCHAR(50),
    sls_prd_key         NVARCHAR(50),
    sls_cust_id         INT,
    sls_order_dt        DATE,
    sls_ship_dt         DATE,
    sls_due_dt          DATE,
    sls_sales           INT,
    sls_quantity        INT,
    sls_price           INT,
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);


/*
-------------------------------------------------------------------------------
ERP: Información adicional de clientes
-------------------------------------------------------------------------------

Esta tabla conserva la información de fecha de nacimiento y género
proveniente del sistema ERP.

La información será posteriormente integrada con los datos de clientes
provenientes del CRM en la capa Gold.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.erp_cust_az12', 'U') IS NOT NULL
    DROP TABLE silver.erp_cust_az12;
GO

CREATE TABLE silver.erp_cust_az12 (
    cid                 NVARCHAR(50),
    bdate               DATE,
    gen                 NVARCHAR(50),
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);


/*
-------------------------------------------------------------------------------
ERP: Ubicación de clientes
-------------------------------------------------------------------------------

Contiene la información geográfica proveniente del ERP.

La tabla será posteriormente utilizada para complementar la dimensión
de clientes en la capa Gold.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.erp_loc_a101', 'U') IS NOT NULL
    DROP TABLE silver.erp_loc_a101;
GO

CREATE TABLE silver.erp_loc_a101 (
    cid                 NVARCHAR(50),
    cntry               NVARCHAR(50),
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);


/*
-------------------------------------------------------------------------------
ERP: Categorías y subcategorías de productos
-------------------------------------------------------------------------------

Contiene la información de categorización de productos proveniente
del ERP.

Esta información será posteriormente integrada con los productos
provenientes del CRM para construir la dimensión de productos en Gold.
-------------------------------------------------------------------------------
*/

IF OBJECT_ID('silver.erp_px_cat_g1v2', 'U') IS NOT NULL
    DROP TABLE silver.erp_px_cat_g1v2;
GO

CREATE TABLE silver.erp_px_cat_g1v2 (
    id                  NVARCHAR(50),
    cat                 NVARCHAR(50),
    subcat              NVARCHAR(50),
    maintenance         NVARCHAR(50),
    dwh_create_date     DATETIME2 DEFAULT GETDATE()
);