/*
===============================================================================
Quality Checks: Capa Gold
===============================================================================
Propósito:
    Este script realiza controles de calidad sobre la capa Gold para validar
    la integridad y consistencia del modelo dimensional.

    Los controles principales verifican:

        - Unicidad de las surrogate keys en las dimensiones.
        - Integridad referencial entre la tabla de hechos y las dimensiones.
        - Existencia de relaciones válidas entre los elementos del modelo
          estrella.

Uso:
    - Ejecutar estos controles después de crear las vistas de la capa Gold.
    - Las consultas que verifican unicidad no deberían devolver resultados.
    - Cualquier registro devuelto por el control de integridad referencial
      debe ser investigado para determinar el origen de la discrepancia.
===============================================================================
*/


/*
===============================================================================
Verificación de gold.dim_customers
===============================================================================
Objetivo:
    Verificar que customer_key sea único dentro de la dimensión de clientes.

    La clave sustituta identifica cada registro de la dimensión y, por lo tanto,
    no debería existir más de un registro con el mismo valor.

Resultado esperado:
    La consulta no debería devolver resultados.
===============================================================================
*/

SELECT
    customer_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;


/*
===============================================================================
Verificación de gold.dim_products
===============================================================================
Objetivo:
    Verificar que product_key sea único dentro de la dimensión de productos.

Resultado esperado:
    La consulta no debería devolver resultados.
===============================================================================
*/

SELECT
    product_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1;


/*
===============================================================================
Verificación de gold.fact_sales
===============================================================================
Objetivo:
    Verificar la integridad de las relaciones entre la tabla de hechos y las
    dimensiones de clientes y productos.

    Cada registro de ventas debería poder asociarse con un cliente y un
    producto existentes en las dimensiones correspondientes.

    Se utiliza LEFT JOIN para conservar todos los registros de fact_sales y
    detectar aquellos que no encuentran una correspondencia en alguna de las
    dimensiones.

Resultado esperado:
    La consulta no debería devolver resultados.

    Cualquier registro devuelto indica que una venta no pudo asociarse
    correctamente con la dimensión de clientes, la dimensión de productos,
    o ambas.
===============================================================================
*/

SELECT
    *
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
    ON c.customer_key = f.customer_key
LEFT JOIN gold.dim_products p
    ON p.product_key = f.product_key
WHERE p.product_key IS NULL
   OR c.customer_key IS NULL;