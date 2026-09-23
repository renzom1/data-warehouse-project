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


