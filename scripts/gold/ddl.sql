/*
===============================================================================
DDL Script: Creación de views de la capa Gold
===============================================================================
Propósito:
    Este script crea las vistas que conforman la capa Gold del Data Warehouse.

    La capa Gold representa la capa de consumo analítico y organiza los datos
    mediante un modelo dimensional de tipo Star Schema, compuesto por:

        - gold.dim_customers
        - gold.dim_products
        - gold.fact_sales

    A diferencia de las capas Bronze y Silver, donde los datos se almacenan
    físicamente en tablas, la capa Gold se implementa mediante vistas que
    consultan y combinan los datos transformados de la capa Silver.

    Las vistas:
        - integran información proveniente de diferentes fuentes;
        - generan claves sustitutas para las dimensiones;
        - seleccionan únicamente los registros de producto vigentes;
        - relacionan los hechos de ventas con las dimensiones mediante sus
          claves correspondientes;
        - exponen una estructura preparada para análisis y reporting.

Uso:
    - Ejecutar este script después de haber cargado y validado la capa Silver.
    - Las vistas pueden consultarse directamente para realizar análisis SQL
      y construir reportes (algo que voy a hacer más adelante).
    - El script puede ejecutarse nuevamente durante el desarrollo, ya que
      elimina las vistas existentes antes de crearlas.
===============================================================================
*/


/*
===============================================================================
Creación de dimensión: gold.dim_customers
===============================================================================
Propósito:
    Construir la dimensión de clientes integrando información proveniente de
    CRM y ERP.

    CRM constituye la fuente principal para la información del cliente.
    Los datos provenientes de ERP se utilizan como enriquecimiento y como
    fuente alternativa cuando determinada información no está disponible
    en CRM.

    Se genera una clave sustituta (customer_key) mediante ROW_NUMBER() para
    utilizarla como identificador del cliente dentro del modelo dimensional.
===============================================================================
*/

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
        CRM es la fuente principal para el género.
        Cuando CRM contiene 'n/a', se utiliza el valor disponible en ERP.
        Si tampoco existe un valor válido en ERP, se conserva 'n/a'.
    */
    CASE
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END AS gender,

    ca.bdate             AS birthdate,
    ci.cst_create_date   AS create_date

FROM silver.crm_cust_info ci

/*
    ERP aporta información adicional del cliente, como fecha de nacimiento
    y género, utilizando la clave del cliente como criterio de integración.
*/
LEFT JOIN silver.erp_cust_az12 ca
    ON ci.cst_key = ca.cid

/*
    ERP aporta además información geográfica del cliente.
*/
LEFT JOIN silver.erp_loc_a101 la
    ON ci.cst_key = la.cid;
GO


/*
===============================================================================
Creación de dimensión: gold.dim_products
===============================================================================
Propósito:
    Construir la dimensión de productos integrando la información de productos
    proveniente de CRM con la información de categorías proveniente de ERP.

    Solo se incluyen los registros correspondientes a la versión vigente de
    cada producto. Las versiones históricas se excluyen mediante el filtro
    sobre prd_end_dt.

    Se genera una clave sustituta (product_key) mediante ROW_NUMBER() para
    utilizarla como identificador del producto dentro del modelo dimensional.
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
    Se incorpora información de categorías y subcategorías proveniente
    del sistema ERP.
*/
LEFT JOIN silver.erp_px_cat_g1v2 pc
    ON pn.cat_id = pc.id

/*
    Se conservan únicamente las versiones actualmente vigentes de los
    productos. Los registros históricos poseen una fecha de finalización.
*/
WHERE pn.prd_end_dt IS NULL;
GO


/*
===============================================================================
Creación de tabla de hechos: gold.fact_sales
===============================================================================
Propósito:
    Construir la vista de hechos de ventas a partir de los datos transformados
    de Silver.

    La vista relaciona cada operación de venta con las dimensiones de productos
    y clientes mediante sus claves sustitutas.

    De esta manera, fact_sales constituye la tabla de hechos lógica del modelo
    estrella y contiene las métricas y fechas necesarias para el análisis de
    las ventas.
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
    Se obtiene la clave sustituta del producto a partir de la clave natural
    almacenada en los datos de ventas.
*/
LEFT JOIN gold.dim_products pr
    ON sd.sls_prd_key = pr.product_number

/*
    Se obtiene la clave sustituta del cliente a partir del identificador
    del cliente presente en los datos de ventas.
*/
LEFT JOIN gold.dim_customers cu
    ON sd.sls_cust_id = cu.customer_id;
GO