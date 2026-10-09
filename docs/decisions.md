# Decisiones técnicas

Este documento registra las principales decisiones tomadas durante el desarrollo del Data Warehouse, junto con su justificación y las limitaciones de cada enfoque.

El objetivo es dejar constancia de las decisiones que afectan la arquitectura, así como mostrar el razonamiento detrás del modelado y procesamiento de los datos.

---

## 1. Implementación de la capa Gold mediante views

### Decisión

La capa Gold se implementó mediante views de SQL Server construidas a partir de las tablas de la capa Silver.

Las principales entidades de Gold son:

* `gold.dim_customers`
* `gold.dim_products`
* `gold.fact_sales`

Estas views integran y reorganizan los datos previamente transformados en Silver para exponer un modelo dimensional orientado al análisis.

### Justificación

Silver contiene los datos ya limpiados y transformados, pero mantiene una organización principalmente relacionada con las distintas fuentes de origen.

Gold tiene un objetivo diferente, el cual es presentar los datos mediante un modelo dimensional compuesto por dimensiones y una tabla lógica de hechos.

Para este proyecto se optó por construir este modelo directamente mediante consultas sobre Silver, sin materializar una segunda copia física de los datos.

Esto permite mantener una separación clara entre:

* **Silver:** datos transformados y preparados.
* **Gold:** modelo orientado al consumo analítico.

Además, al utilizar views, los resultados de Gold se obtienen a partir del estado actual de las tablas Silver, sin requerir un proceso adicional de carga física de Gold.

### Consideración

Esta implementación es adecuada para el alcance y objetivo de aprendizaje del proyecto, pero no debe interpretarse como una estrategia universal para Data Warehouses productivos.

En un entorno de mayor escala, podrían existir razones para materializar las dimensiones y la tabla de hechos, como necesidades de rendimiento, persistencia de claves, control explícito de las cargas o manejo de históricos.

### Limitación

Las surrogate keys utilizadas en las dimensiones de este proyecto se generan dinámicamente mediante funciones como `ROW_NUMBER()`. Al formar parte de una view, estas claves no se almacenan como identificadores persistentes.

Por lo tanto, la implementación representa el modelo dimensional conceptualmente, pero no reproduce todas las características que tendría un modelo dimensional físico en un entorno productivo.

---

## 2. Uso de surrogate keys en las dimensiones

### Decisión

Se utilizaron surrogate keys para identificar los registros de las dimensiones dentro del Data Warehouse:

* `customer_key` en `gold.dim_customers`
* `product_key` en `gold.dim_products`

Estas claves son independientes de los identificadores provenientes de los sistemas fuente, como `cst_id` y `prd_key`.

### Justificación

Los identificadores de los sistemas fuente pertenecen a los sistemas operacionales que originan los datos. El Data Warehouse, en cambio, necesita contar con identificadores propios para sus entidades.

Esto nos permite desacoplar el modelo dimensional de los identificadores específicos de CRM y ERP, y facilita la integración de información proveniente de diferentes fuentes.

Además, las surrogate keys permiten establecer las relaciones entre las dimensiones y la tabla de hechos mediante claves propias del Data Warehouse.

### Implementación

Las claves son generadas dinámicamente mediante `ROW_NUMBER()`.

Para clientes:

```sql
ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key
```

Para productos:

```sql
ROW_NUMBER() OVER (
    ORDER BY prd_start_dt, prd_key
) AS product_key
```

### Limitación

Las claves generadas mediante `ROW_NUMBER()` no son persistentes. Si cambia el conjunto de registros o el criterio utilizado para ordenarlos, un mismo registro podría recibir una clave diferente.

Esto es especialmente relevante porque las dimensiones y la tabla de hechos de Gold están implementadas como views.

Por este motivo, esta estrategia es suficiente para representar el modelo dimensional en el contexto de este proyecto, pero una implementación productiva requeriría un mecanismo de generación y persistencia de surrogate keys que mantuviera estable la identidad de cada entidad a lo largo del tiempo.


---

## 3. CRM como fuente principal para la información de clientes

### Decisión

Para la construcción de `gold.dim_customers`, se estableció al CRM como la fuente principal (*master*) de información de clientes, mientras que el ERP se utiliza como fuente complementaria.

La información proveniente de ambas fuentes se integra mediante los identificadores disponibles y se incorporan al modelo dimensional los atributos necesarios de cada sistema.

En caso de existir información equivalente en ambas fuentes, se prioriza la proveniente del CRM para los atributos definidos como propios de esta fuente. Por ejemplo, el género del cliente utiliza el CRM como fuente principal.

### Justificación

Esta decisión permite establecer una regla explícita de precedencia entre las distintas fuentes de información.

El CRM contiene una mayor cantidad de información directamente relacionada con la entidad cliente, mientras que el ERP aporta atributos adicionales que complementan dicha información.

Definir una fuente principal evita que los valores provenientes de diferentes sistemas sean tratados como igualmente confiables sin establecer previamente cuál debe prevalecer ante posibles discrepancias.

### Consideración

La elección del CRM como fuente principal responde al contexto y a la estructura de datos de este proyecto. En un entorno real, la definición de un sistema como fuente maestra debería basarse en criterios propios del negocio, como la responsabilidad sobre el dato, los procesos que lo generan y las reglas de gobierno de datos establecidas por la organización.

### Limitación

La integración realizada depende de los identificadores y atributos disponibles en las fuentes proporcionadas para este proyecto. No se implementó un proceso completo de *Master Data Management* ni reglas avanzadas para resolver conflictos entre múltiples fuentes.

Por lo tanto, la regla de precedencia aplicada representa una estrategia de integración adecuada para este modelo, pero no constituye por sí misma un sistema general de gestión de datos maestros.


---

## 4. Diseño y responsabilidades de las capas Bronze, Silver y Gold

### Decisión

El Data Warehouse se organizó en tres capas con responsabilidades diferenciadas:

* **Bronze:** incorporación de los datos provenientes de las fuentes, manteniendo su estructura y contenido lo más cerca posible del origen.
* **Silver:** limpieza, validación y transformación de los datos para obtener información consistente y preparada para su integración.
* **Gold:** organización de los datos transformados mediante un modelo dimensional (de tipo star schema) orientado al consumo analítico.

### Bronze

La capa Bronze recibe los datos de los archivos fuente mediante un *full load*.

No se aplican transformaciones, reglas de negocio ni procesos de limpieza durante esta etapa. De esta forma, se conserva una representación de los datos de origen antes de aplicar modificaciones sobre ellos.

Esta separación permite utilizar Bronze como punto de partida para las transformaciones posteriores. Si una transformación en Silver necesitara ser modificada o corregida, los datos originales seguirían disponibles en Bronze para volver a procesarlos.

### Silver

La capa Silver concentra las transformaciones necesarias para mejorar la calidad y consistencia de los datos.

Entre otras operaciones, se realizan procesos de limpieza, estandarización, validación, eliminación de duplicados y tratamiento de valores inválidos.

Estas operaciones se mantienen separadas de Bronze para conservar los datos de origen y evitar que las transformaciones realizadas durante el procesamiento alteren la representación original de los datos.

Además, concentrar las transformaciones en Silver permite separar la incorporación de los datos de su procesamiento y facilita la trazabilidad del flujo desde los datos originales hasta los datos preparados para análisis.

### Gold

La capa Gold presenta los datos mediante un modelo dimensional orientado al consumo analítico.

Gold no introduce una nueva etapa de limpieza o transformación de los datos. Las operaciones realizadas principalmente consisten en relacionar la información previamente preparada en Silver y exponerla mediante las dimensiones y la tabla lógica de hechos del modelo.

Las entidades de Gold se implementaron como views de SQL Server. Esto permite obtener la información necesaria para el análisis a partir de las relaciones entre las tablas de Silver, sin necesidad de almacenar una nueva copia física de esos datos.

Esta decisión mantiene una separación clara entre los datos transformados de Silver y su representación orientada al consumo en Gold, evitando duplicar físicamente información que ya se encuentra disponible en las capas anteriores.

### Consideración

La separación de responsabilidades entre las capas permite mantener un flujo de procesamiento claro:

**Origen → Bronze → Silver → Gold → Consumo analítico**

Cada etapa tiene un propósito específico y las transformaciones se aplican progresivamente, manteniendo disponible el resultado de las etapas anteriores.

---

## 5. Transformaciones y quality checks en Silver y Gold

### Decisión

Las transformaciones y controles de calidad se concentraron principalmente en las capas Silver y Gold, pero con objetivos diferentes.

En **Silver**, los controles se orientan a la calidad y consistencia de los datos antes de utilizarlos en el modelo analítico.

En **Gold**, los controles se orientan a verificar la integridad y coherencia del modelo dimensional construido a partir de los datos de Silver.

### Transformaciones y controles en Silver

Las transformaciones realizadas en Silver responden a problemas identificados en los datos de origen y a los requisitos necesarios para integrarlos posteriormente.

Entre las operaciones realizadas se encuentran:

* limpieza y normalización de valores;
* tratamiento de espacios y valores inconsistentes;
* conversión y validación de fechas;
* eliminación de registros duplicados según criterios definidos;
* tratamiento de valores nulos o inválidos;
* aplicación de reglas de negocio específicas de cada entidad;
* validación de relaciones y rangos esperados para determinados atributos.

Los controles de calidad se utilizan para verificar que estas transformaciones produzcan datos consistentes. Por ejemplo, se comprueban duplicados, valores nulos, rangos de fechas, valores inválidos y otras condiciones específicas de cada conjunto de datos.

De esta forma, Silver funciona como la etapa en la que los datos provenientes de las fuentes se convierten en información preparada para ser integrada y utilizada por las capas posteriores.

### Controles en Gold

Los controles realizados sobre Gold tienen un objetivo diferente. En lugar de centrarse principalmente en la limpieza de los datos, buscan comprobar que el modelo dimensional construido sea coherente.

Entre las validaciones realizadas se encuentran:

* existencia de las relaciones esperadas entre `fact_sales` y las dimensiones;
* ausencia de registros de hechos sin una dimensión de cliente correspondiente;
* ausencia de registros de hechos sin una dimensión de producto correspondiente;
* unicidad de las surrogate keys de las dimensiones.

Estos controles permiten verificar que la construcción de `gold.fact_sales` y su relación con `gold.dim_customers` y `gold.dim_products` produzcan un modelo consistente para el análisis.

### Consideración

La separación entre los controles de Silver y Gold permite detectar problemas en diferentes etapas del flujo.

Un problema relacionado con la calidad o consistencia de un dato de origen debería detectarse en Silver, mientras que un problema relacionado con la integración o las relaciones del modelo dimensional debería detectarse en Gold.

---

## 6. Source CSV line terminators and completeness of Bronze ingestion

### Decision

The missing trailing line terminator (CRLF, matching the files' existing line endings) was added to two source files:

* `datasets/source_crm/cust_info.csv`
* `datasets/source_erp/cust_az12.csv`

The `BULK INSERT` strategy was not changed.

This is a reproducibility and ingestion decision. Bronze is meant to preserve the source rows, and the clean rebuild showed that it did not preserve all of them.

### Justification

During the reproducibility rebuild into a dedicated test database (`DataWarehouse_Test`), Bronze held one row fewer than the CSV files contain in two tables. In both cases the missing row was the last line of the file:

| File | CSV data rows | Bronze rows | Missing final row |
|---|---|---|---|
| `cust_info.csv` | 18,494 | 18,493 | `cst_key = A01Ass` (no customer ID, like three other rows already in Bronze) |
| `cust_az12.csv` | 18,484 | 18,483 | `AW00029483` (a customer with birthdate 1965-06-06 and an empty gender) |

In both files the final line has no line terminator and ends with an empty field. With the existing `BULK INSERT` configuration, such a final row is not loaded, and no error is raised. The other four files load completely. That includes `px_cat_g1v2.csv`, which also ends without a line terminator, but whose last field is not empty. This cause was inferred from the pattern across the six source files; the parser's behavior was not tested in isolation.

The counts in the existing `DataWarehouse` and in a from-scratch rebuild in `DataWarehouse_Test` were identical, so this is deterministic pipeline behavior, not random data loss.

### Result

After appending the line terminator to the two files and reloading `DataWarehouse_Test`:

| Object | Before | After |
|---|---|---|
| `bronze.crm_cust_info` | 18,493 | 18,494 |
| `bronze.erp_cust_az12` | 18,483 | 18,484 |
| `silver.erp_cust_az12` | 18,483 | 18,484 |
| `gold.dim_customers`, customer `29483`, `birthdate` | `NULL` | `1965-06-06` |

The recovered `A01Ass` row stays in Bronze, because Bronze preserves the source data, and is filtered out in Silver because its customer ID is `NULL`. As a result `silver.crm_cust_info` and `gold.dim_customers` keep their previous counts. All other relevant counts and the `fact_sales` totals are unchanged. The full comparison is in [`rebuild_baseline.md`](rebuild_baseline.md).

Each of the two files differs from its original only by the added final line terminator.

### Consideration

`px_cat_g1v2.csv` also ends without a line terminator. It was intentionally left unchanged because its final row loads correctly and no data loss was observed there.

The 15 birthdates before 1924 reported by the Silver quality check were not modified. They are a separate data-quality question.

### Limitation

The correction is in the source files, not in the loader. A source file that is replaced by one ending the same way (no final line terminator and an empty last field) would behave the same way.

The original `DataWarehouse` database was not modified as part of this work, so it still reflects the load that preceded the correction until it is rebuilt.

---

## 7. Analytical conventions established by the data profiling

These decisions come from profiling `gold` before the analysis phase (`analysis/00_data_profile.sql`). They define how the data is interpreted in the analyses. None of them changes Silver or Gold.

### 7.1 Main analytical period

**Observed.** Orders run from 2010-12-29 to 2014-01-28. Only 2011, 2012 and 2013 cover all twelve months. The 2010 tail has 14 lines (29–31 December). January 2014 covers only 1–28 January and has 1,970 lines but revenue of 45,642, about 3% of an average 2013 month.

**Decision.** The main comparison window is 2011–2013. The 2010 tail and January 2014 are reported separately as context and never enter annual comparisons or trends.

**Justification** Mixing partial periods into year-over-year comparisons would create artificial changes, and January 2014 is not a representative month.

### 7.2 Order-level date for temporal analysis

**Observed.** 19 fact lines have a `NULL` `order_date`. 13 orders contain both dated and `NULL`-dated lines, and 2 orders have no dated line at all. No order has more than one distinct non-`NULL` `order_date`.

**Decision.** For temporal analysis, an order's date is the date shared by its dated lines (`MIN(order_date)` over the order). A `NULL`-dated line inherits that date. Only the 2 orders with no dated line (3 lines, revenue of 34) are treated as undated and reported separately.

**Justification** Counting lines by their own date would count 13 orders in two periods, so orders by period would not add up to the total (27,672 instead of 27,659), and revenue of 4,958 on orders with a known date would be lost from every time series. With the order-level date, lines, orders, units and revenue all reconcile.

### 7.3 Suspicious historical birthdates

**Observed.** 15 customers have birthdates between 1916-02-10 and 1923-11-16, which makes them 90–97 years old at their first order. Together they account for revenue of 973. A further 16 customers have no birthdate.

**Decision.** The 15 birthdates are left unchanged. The customers are not excluded from any general analysis. For the age analysis, age is measured at the customer's first order, so each customer falls in exactly one band, and the oldest band is labeled `90+ (data-quality flag)`, with a note that it consists entirely of these 15 customers. Customers with no birthdate form an "Unknown" age band.

**Justification** Excluding or correcting the dates would silently change the customer base. Showing the band with an explicit flag keeps the data intact while stopping a reader from treating that band as a real age segment.

### 7.4 Meaning of `create_date`

**Observed.** `dim_customers.create_date` ranges from 2025-10-06 to 2026-01-27 (114 distinct dates), more than eleven years after the last order (2014-01-28).

**Decision.** `create_date` is not used as a customer acquisition or signup date. It reflects when the records were created or loaded, not when customers began buying. Customer cohorts and first-purchase analysis use the date of the customer's first order.

**Justification** Using `create_date` for tenure or acquisition cohorts would place every customer after their own purchases and produce meaningless results.

### 7.5 Shipping and due dates

**Observed.** Every dated line has the same pattern: shipping 7 days after the order date and due date 12 days after.

**Decision.** No shipping-lag or on-time analysis is carried out.

**Justification** With no variation there is nothing to analyze, and any figure derived from it would describe how the dates were generated, not fulfilment performance.

### 7.6 Repeat-purchase cohorts

**Observed.** 6,865 of 18,484 customers (37.1%) placed two or more orders and 11,619 placed one. The data ends on 2014-01-28, so customers whose first order is recent have had far less time to buy again than earlier ones.

**Decision.** Customers are grouped into cohorts by the year of their first order. Repeat rates are not compared across cohorts using the raw share of repeat buyers. Instead, "second order within N days" (N = 90, 180, 365) counts only customers whose first order is at least N days before the end of the data, and the number of eligible customers is always reported. The overall 37.1% is kept as descriptive context only and is not a conclusion.

**Justification** A raw repeat rate would make recent cohorts look worse simply because they were observed for less time. Eligibility-based measures compare customers over the same follow-up period.

### 7.7 Analytical database

**Observed.** `DataWarehouse_Test` was rebuilt from the corrected source files (decision 6). The original `DataWarehouse` still reflects the earlier load and differs from it only in the two affected rows and their downstream effect on customer 29483's birthdate.

**Decision.** The analysis runs on `DataWarehouse_Test`. The original `DataWarehouse` is not reloaded or modified for now.

**Justification** Analysis results must come from the validated, corrected build. Running them on the original database would mix in a known ingestion difference.

---


