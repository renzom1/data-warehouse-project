# Data Warehouse

## Descripción

Construcción de un Data Warehouse en SQL Server para aplicar conceptos fundamentales de Data Engineering y modelado dimensional.

El proyecto implementa una arquitectura Medallion compuesta por las capas Bronze, Silver y Gold. Los datos provenientes de fuentes CRM y ERP son incorporados, transformados, integrados y finalmente organizados en un modelo dimensional orientado al análisis.

El foco del proyecto estuvo en comprender y aplicar conceptos de integración de datos, transformación y validación, modelado dimensional, surrogate keys y controles de calidad a lo largo del flujo de datos.

## Arquitectura

El flujo de datos se organiza de la siguiente manera:

```text
Fuentes CRM / ERP
       │
       ▼
    Bronze
       │
       ▼
    Silver
       │
       ▼
     Gold
       │
       ▼
Consumo analítico
```

Cada capa tiene una responsabilidad específica:

* **Bronze:** incorpora los datos de las fuentes manteniendo su estructura y contenido lo más cerca posible del origen.
* **Silver:** realiza la limpieza, validación, estandarización y transformación de los datos.
* **Gold:** integra los datos transformados y los presenta mediante un modelo dimensional orientado al análisis.

### Flujo de datos

El siguiente diagrama muestra el recorrido de los datos desde las fuentes hasta la capa Gold:

![Flujo de datos](docs/data_flow.png)

[Ver diagrama editable](docs/data_flow.drawio)

### Integración de fuentes

La integración entre las diferentes fuentes CRM y ERP se encuentra representada en el siguiente modelo:

![Integración de fuentes](docs/integration_model.png)

[Ver diagrama editable](docs/integration_model.drawio)

## Modelo dimensional

La capa Gold representa un modelo dimensional compuesto por:

* `gold.dim_customers`
* `gold.dim_products`
* `gold.fact_sales`

Las dimensiones utilizan surrogate keys propias del Data Warehouse para establecer las relaciones con la tabla de hechos.

En este proyecto, las entidades de Gold se implementaron como **views de SQL Server**, por lo que el modelo dimensional se construye lógicamente a partir de los datos disponibles en Silver sin almacenar una nueva copia física de la información.

### Modelo de datos

El modelo dimensional se encuentra representado en el siguiente diagrama:

![Modelo dimensional](docs/data_mart.png)

[Ver diagrama editable](docs/data_mart.drawio)

## Controles de calidad

Se implementaron controles de calidad en las capas Silver y Gold con objetivos diferentes.

En **Silver**, los controles verifican la calidad y consistencia de los datos luego de aplicar las transformaciones, incluyendo duplicados, valores nulos, fechas inválidas y otras condiciones específicas de cada entidad.

En **Gold**, los controles verifican la integridad del modelo dimensional, incluyendo la correspondencia entre los registros de la tabla de hechos y sus dimensiones y la unicidad de las surrogate keys.

Los scripts de validación se encuentran en:

* [`scripts/silver/quality_checks.sql`](scripts/silver/quality_checks.sql)
* [`scripts/gold/quality_checks.sql`](scripts/gold/quality_checks.sql)

## Reproducible rebuild

The warehouse can be rebuilt from this repository. The scripts are SQLCMD scripts and take two variables, both required and without a default:

* `DatabaseName`: the target database.
* `ProjectRoot`: absolute path of the repository root, without a trailing backslash (only used by `scripts/bronze/load.sql`).

The scripts never drop a database: `init_database.sql` only creates the database and the three schemas if they do not exist. Run the rebuild against a dedicated test database first (for example `DataWarehouse_Test`) so that an existing database is never overwritten.

### Prerequisites

* SQL Server (developed and tested on SQL Server Express) and the `sqlcmd` utility.
* A login that can create databases and run `BULK INSERT`.
* The SQL Server service account must be able to read the `datasets` folder, because `BULK INSERT` reads the CSV files as that account.
* The repository's source CSVs should be kept in the state documented by decision 6 in [`docs/decisions.md`](docs/decisions.md), including the corrected trailing line terminators for the two affected files.

### Execution order

| # | Script | Variables |
|---|---|---|
| 1 | `scripts/init_database.sql` | `DatabaseName` |
| 2 | `scripts/bronze/ddl.sql` | `DatabaseName` |
| 3 | `scripts/bronze/load.sql` | `DatabaseName`, `ProjectRoot` |
| 4 | `scripts/silver/ddl.sql` | `DatabaseName` |
| 5 | `scripts/silver/load.sql` | `DatabaseName` |
| 6 | `scripts/silver/quality_checks.sql` | `DatabaseName` |
| 7 | `scripts/gold/ddl.sql` | `DatabaseName` |
| 8 | `scripts/gold/quality_checks.sql` | `DatabaseName` |

### Usage

`cmd.exe` (run from the repository root; shown for steps 1 and 3, the others only need `DatabaseName`):

```text
sqlcmd -S .\SQLEXPRESS -E -C -b -v DatabaseName="DataWarehouse_Test" -i scripts\init_database.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -v DatabaseName="DataWarehouse_Test" ProjectRoot="C:\path\to\data-warehouse-project" -i scripts\bronze\load.sql
```

Windows PowerShell 5.1 removes double quotes from arguments, which makes `sqlcmd` fail with `Invalid argument` when a value contains a drive letter. Wrap each assignment in single quotes so the double quotes reach `sqlcmd`:

```powershell
sqlcmd -S .\SQLEXPRESS -E -C -b -v 'DatabaseName="DataWarehouse_Test"' -i scripts\init_database.sql
sqlcmd -S .\SQLEXPRESS -E -C -b -v 'DatabaseName="DataWarehouse_Test"' 'ProjectRoot="C:\path\to\data-warehouse-project"' -i scripts\bronze\load.sql
```

`-S` selects the server and `-C` trusts its certificate (local development). In SSMS, enable SQLCMD Mode and define the variables with `:setvar` instead of `-v`.

### Verifying a rebuild

The load procedures catch errors and print them instead of failing, so `sqlcmd` can return exit code 0 after a failed load. Check the printed output and the row counts. The expected counts and totals are in [`docs/rebuild_baseline.md`](docs/rebuild_baseline.md). The Silver birthdate check currently returns 15 birthdates before 1924; this is known and is documented there.

## Tecnologías

* SQL Server
* Medallion Architecture
* Dimensional Modeling
* Git / GitHub

## Estructura del repositorio

```text
data-warehouse-project/
│
├── datasets/
│   ├── source_crm/
│   └── source_erp/
│
├── docs/
│   ├── data_flow.drawio
│   ├── data_flow.png
│   ├── data_mart.drawio
│   ├── data_mart.png
│   ├── integration_model.drawio
│   ├── integration_model.png
│   ├── decisions.md
│   └── rebuild_baseline.md
│
├── scripts/
│   ├── init_database.sql
│   │
│   ├── bronze/
│   │   ├── ddl.sql
│   │   └── load.sql
│   │
│   ├── silver/
│   │   ├── ddl.sql
│   │   ├── load.sql
│   │   └── quality_checks.sql
│   │
│   └── gold/
│       ├── ddl.sql
│       └── quality_checks.sql
│
└── .gitignore
```

## Decisiones técnicas

Las principales decisiones tomadas durante el desarrollo y sus justificaciones se encuentran documentadas en [`docs/decisions.md`](docs/decisions.md).

El documento aborda, entre otros aspectos:

* implementación de Gold mediante views
* uso de surrogate keys
* integración de información CRM y ERP
* responsabilidades de las capas Bronze, Silver y Gold
* transformaciones y controles de calidad

## Referencias

Los datos utilizados en este proyecto y la estructura conceptual de referencia fueron obtenidos de **Data With Baraa** como parte de su proyecto educativo de Data Warehouse.
