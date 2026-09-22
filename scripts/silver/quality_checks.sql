/*
===============================================================================
QUALITY CHECKS - CAPA SILVER
===============================================================================
Propósito:
    Este script realiza controles de calidad sobre los datos cargados en la
    capa Silver.

    Las validaciones buscan detectar problemas relacionados con:

        - Claves nulas o duplicadas.
        - Espacios innecesarios.
        - Falta de estandarización.
        - Valores nulos, negativos o inválidos.
        - Fechas fuera de rango.
        - Orden temporal incorrecto entre fechas.
        - Inconsistencias entre campos relacionados.

Uso:
    Ejecutar este script después de realizar la carga de la capa Silver.

    Las consultas no modifican los datos. Su objetivo es identificar posibles
    problemas que deben investigarse antes de utilizar Silver como fuente
    para la capa Gold.

Expectativa general:
    Las consultas que indican "Sin resultados" deberían no devolver registros
    cuando los datos cumplen con las reglas de calidad definidas.

Nota:
    Algunas consultas utilizan SELECT DISTINCT para inspeccionar los valores
    existentes y verificar visualmente que la estandarización haya producido
    un conjunto consistente de valores.
===============================================================================
*/


/*
===============================================================================
CRM - CLIENTES
===============================================================================
*/

-- Verificar claves nulas o duplicadas
-- Expectativa: Sin resultados.
--
-- cst_id funciona como identificador del cliente dentro de esta tabla.
-- No debería existir más de un registro para el mismo cliente después de
-- aplicar la deduplicación realizada durante la carga de Silver.

SELECT
    cst_id,
    COUNT(*)
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1
    OR cst_id IS NULL;


-- Verificar espacios innecesarios
-- Expectativa: Sin resultados.
--
-- Se comprueba que cst_key no contenga espacios al principio o al final.
-- Esto es importante porque cst_key se utiliza posteriormente para relacionar
-- información proveniente de diferentes fuentes.

SELECT
    cst_key
FROM silver.crm_cust_info
WHERE cst_key != TRIM(cst_key);


-- Verificar estandarización del estado civil
--
-- Esta consulta permite inspeccionar los valores existentes después de la
-- transformación realizada durante la carga de Silver.
--
-- Los valores esperados corresponden a las categorías definidas durante
-- la transformación, por ejemplo: Single, Married y N/A.

SELECT DISTINCT
    cst_marital_status
FROM silver.crm_cust_info;


/*
===============================================================================
CRM - PRODUCTOS
===============================================================================
*/

-- Verificar claves nulas o duplicadas
-- Expectativa: Sin resultados.
--
-- prd_id identifica cada registro de producto y se espera que sea único
-- y no nulo dentro de Silver.

SELECT
    prd_id,
    COUNT(*)
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1
    OR prd_id IS NULL;


-- Verificar espacios innecesarios en el nombre del producto
-- Expectativa: Sin resultados.

SELECT
    prd_nm
FROM silver.crm_prd_info
WHERE prd_nm != TRIM(prd_nm);


-- Verificar costos nulos o negativos
-- Expectativa: Sin resultados.
--
-- El costo de un producto no debería ser negativo ni quedar NULL después
-- de aplicar la regla de transformación correspondiente.

SELECT
    prd_cost
FROM silver.crm_prd_info
WHERE prd_cost < 0
    OR prd_cost IS NULL;


-- Verificar estandarización de la línea de producto
--
-- Permite inspeccionar los valores resultantes después de convertir los
-- códigos originales a valores descriptivos.

SELECT DISTINCT
    prd_line
FROM silver.crm_prd_info;


-- Verificar consistencia temporal de las versiones de producto
-- Expectativa: Sin resultados.
--
-- La fecha de finalización de una versión no debería ser anterior a su
-- fecha de inicio.
--
-- Esta validación está relacionada con el cálculo de prd_end_dt realizado
-- mediante LEAD durante la transformación de Bronze a Silver.

SELECT
    *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;


/*
===============================================================================
CRM - VENTAS
===============================================================================
*/


/*
Verificar fechas inválidas en la fuente Bronze
-----------------------------------------------

Esta consulta se ejecuta sobre Bronze porque busca identificar valores
problemáticos en los datos originales antes de su conversión a DATE durante
la carga de Silver.

Las fechas de Bronze se almacenan como enteros en formato YYYYMMDD.

Se consideran inválidos, entre otros casos:
    - Valores menores que 19000101.
    - Valores mayores que 20500101.
    - Valores con una longitud distinta de 8 dígitos.
    - Valores iguales o menores que 0.

La consulta permite verificar la calidad de la fuente original y comprobar
qué valores fueron tratados durante la transformación.
*/

SELECT
    NULLIF(sls_due_dt, 0) AS sls_due_dt
FROM bronze.crm_sales_details
WHERE sls_due_dt <= 0
    OR LEN(sls_due_dt) != 8
    OR sls_due_dt > 20500101
    OR sls_due_dt < 19000101;


/*
Verificar orden cronológico de las fechas
------------------------------------------

Expectativa: Sin resultados.

La fecha de orden no debería ser posterior a la fecha de envío ni a la
fecha de vencimiento.

Esto permite detectar inconsistencias temporales en los datos de ventas
ya transformados en Silver.
*/

SELECT
    *
FROM silver.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;


/*
Verificar consistencia entre ventas, cantidad y precio
-------------------------------------------------------

Expectativa: Sin resultados.

La relación esperada es:

    ventas = cantidad × precio

Además de comprobar esta relación, se verifican:
    - Valores NULL.
    - Valores menores o iguales a cero.

DISTINCT permite mostrar únicamente combinaciones diferentes de valores
problemáticos, evitando repetir exactamente la misma combinación varias veces.
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
ERP - CLIENTES
===============================================================================
*/


/*
Verificar fechas de nacimiento fuera de rango
----------------------------------------------

Expectativa:
    Las fechas deberían encontrarse entre 1924-01-01 (lo asumimos posible) 
    y la fecha actual.

Esta validación busca identificar fechas de nacimiento que no resulten
razonables para el conjunto de datos utilizado en el proyecto.

El límite inferior de 1924 corresponde al rango definido para este control
de calidad.
*/

SELECT DISTINCT
    bdate
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01'
   OR bdate > GETDATE();


/*
Verificar estandarización del género
-------------------------------------

Permite inspeccionar los valores existentes después de la normalización
realizada durante la carga de Silver.

Los valores deberían corresponder a las categorías definidas en la
transformación, como Female, Male y N/A.
*/

SELECT DISTINCT
    gen
FROM silver.erp_cust_az12;


/*
===============================================================================
ERP - UBICACIONES
===============================================================================
*/


/*
Verificar estandarización de países
------------------------------------

Permite inspeccionar los valores existentes después de normalizar los
códigos de país y tratar los valores NULL o vacíos.

La consulta se ordena para facilitar la inspección de los resultados.
*/

SELECT DISTINCT
    cntry
FROM silver.erp_loc_a101
ORDER BY cntry;


/*
===============================================================================
ERP - CATEGORÍAS DE PRODUCTOS
===============================================================================
*/


-- Verificar espacios innecesarios
-- Expectativa: Sin resultados.
--
-- Aunque esta tabla no recibe transformaciones durante la carga a Silver,
-- se verifica que sus campos de texto no contengan espacios innecesarios.

SELECT
    *
FROM silver.erp_px_cat_g1v2
WHERE cat != TRIM(cat)
   OR subcat != TRIM(subcat)
   OR maintenance != TRIM(maintenance);


-- Verificar estandarización del campo de mantenimiento
--
-- Permite inspeccionar los valores existentes en la fuente y detectar
-- posibles inconsistencias o categorías inesperadas.

SELECT DISTINCT
    maintenance
FROM silver.erp_px_cat_g1v2;