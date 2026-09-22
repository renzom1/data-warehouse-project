/*
============================================================
DDL: Creación de tablas de la capa Bronze
============================================================

Propósito:
La capa Bronze recibe los datos provenientes de las fuentes
CRM y ERP manteniendo, en la medida de lo posible, su
estructura y formato originales.

En esta etapa no se aplican transformaciones ni reglas de
negocio. La limpieza, estandarización y validación de los
datos se realizan posteriormente en la capa Silver.
============================================================

------------------------------------------------------------
CRM: Información de clientes
------------------------------------------------------------

Se elimina la tabla si ya existe antes de recrearla.

Esto permite hacer re-ejecutable el DDL durante el
desarrollo sin tener que eliminar manualmente las tablas
existentes.
*/

USE DataWarehouse;
GO

IF OBJECT_ID('bronze.crm_cust_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_cust_info;
GO

CREATE TABLE bronze.crm_cust_info (
    cst_id              INT,
    cst_key             NVARCHAR(50),
    cst_firstname       NVARCHAR(50),
    cst_lastname        NVARCHAR(50),
    cst_marital_status  NVARCHAR(50),
    cst_gndr            NVARCHAR(50),
    cst_create_date     DATE
);
GO


/*
------------------------------------------------------------
CRM: Información de productos
------------------------------------------------------------
*/

IF OBJECT_ID('bronze.crm_prd_info', 'U') IS NOT NULL
    DROP TABLE bronze.crm_prd_info;
GO

CREATE TABLE bronze.crm_prd_info (
    prd_id       INT,
    prd_key      NVARCHAR(50),
    prd_nm       NVARCHAR(50),
    prd_cost     INT,
    prd_line     NVARCHAR(50),
    prd_start_dt DATETIME,
    prd_end_dt   DATETIME
);
GO


/*
------------------------------------------------------------
CRM: Detalle de ventas
------------------------------------------------------------

Las fechas de las ventas se mantienen como INT porque en la
fuente original están representadas como valores numéricos.

No se transforman en esta etapa para conservar los datos lo
más cerca posible de su formato de origen. La validación y
conversión de estos valores se realiza posteriormente en
Silver.
*/

IF OBJECT_ID('bronze.crm_sales_details', 'U') IS NOT NULL
    DROP TABLE bronze.crm_sales_details;
GO

CREATE TABLE bronze.crm_sales_details (
    sls_ord_num  NVARCHAR(50),
    sls_prd_key  NVARCHAR(50),
    sls_cust_id  INT,
    sls_order_dt INT,
    sls_ship_dt  INT,
    sls_due_dt   INT,
    sls_sales    INT,
    sls_quantity INT,
    sls_price    INT
);
GO


/*
------------------------------------------------------------
ERP: Información de ubicación de clientes
------------------------------------------------------------
*/

IF OBJECT_ID('bronze.erp_loc_a101', 'U') IS NOT NULL
    DROP TABLE bronze.erp_loc_a101;
GO

CREATE TABLE bronze.erp_loc_a101 (
    cid    NVARCHAR(50),
    cntry  NVARCHAR(50)
);
GO


/*
------------------------------------------------------------
ERP: Información adicional de clientes
------------------------------------------------------------
*/

IF OBJECT_ID('bronze.erp_cust_az12', 'U') IS NOT NULL
    DROP TABLE bronze.erp_cust_az12;
GO

CREATE TABLE bronze.erp_cust_az12 (
    cid    NVARCHAR(50),
    bdate  DATE,
    gen    NVARCHAR(50)
);
GO


/*
------------------------------------------------------------
ERP: Categorías y subcategorías de productos
------------------------------------------------------------
*/

IF OBJECT_ID('bronze.erp_px_cat_g1v2', 'U') IS NOT NULL
    DROP TABLE bronze.erp_px_cat_g1v2;
GO

CREATE TABLE bronze.erp_px_cat_g1v2 (
    id           NVARCHAR(50),
    cat          NVARCHAR(50),
    subcat       NVARCHAR(50),
    maintenance  NVARCHAR(50)
);
GO