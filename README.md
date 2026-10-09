# Data Warehouse

## Overview

A SQL Server Data Warehouse built to apply core Data Engineering concepts and dimensional modeling, followed by an analytical layer on top of it.

The project implements a Medallion architecture made up of Bronze, Silver and Gold layers. Data coming from CRM and ERP sources is ingested, transformed, integrated and finally organized in a dimensional model oriented to analysis.

The project focuses on data integration, transformation and validation, dimensional modeling, surrogate keys, quality checks throughout the data flow, and a repeatable rebuild from the repository alone. Its current phase uses the validated Gold layer to answer business questions with SQL.

## Architecture

The data flows as follows:

```text
CRM / ERP sources
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
Analytical layer (SQL)
```

Each layer has a specific responsibility:

* **Bronze:** ingests the source data, keeping its structure and content as close to the origin as practical.
* **Silver:** cleans, validates, standardizes and transforms the data.
* **Gold:** integrates the transformed data and presents it through a dimensional model oriented to analysis.
* **Analytical layer:** SQL scripts that answer business questions using the Gold layer.

### Data flow

The following diagram shows the path of the data from the sources to the Gold layer:

![Data flow](docs/data_flow.png)


### Source integration

The integration between the CRM and ERP sources is represented in the following model:

![Source integration](docs/integration_model.png)


## Dimensional model

The Gold layer is a dimensional model made up of:

* `gold.dim_customers`
* `gold.dim_products`
* `gold.fact_sales`

The dimensions use surrogate keys owned by the Data Warehouse to relate to the fact table.

In this project, the Gold entities are implemented as **SQL Server views**, so the dimensional model is built logically from the data available in Silver, without storing a new physical copy of the information. The trade-offs of this choice, including the non-persistent surrogate keys, are discussed in [`docs/decisions.md`](docs/decisions.md).

### Data model

The dimensional model is represented in the following diagram:

![Dimensional model](docs/data_mart.png)


## Quality checks

Quality checks were implemented in the Silver and Gold layers with different goals.

In **Silver**, the checks verify the quality and consistency of the data after the transformations, including duplicates, null values, invalid dates and other conditions specific to each entity.

In **Gold**, the checks verify the integrity of the dimensional model, including the match between fact table records and their dimensions and the uniqueness of the surrogate keys.

The validation scripts are located in:

* [`scripts/silver/quality_checks.sql`](scripts/silver/quality_checks.sql)
* [`scripts/gold/quality_checks.sql`](scripts/gold/quality_checks.sql)

## Analytical layer

The analysis runs on top of the Gold layer and is organized as numbered, read-only SQL scripts in [`analysis/`](analysis/). Each script states its business question, the data it needs, the grain, the metric definitions, the method and its caveats.

| Script | Purpose |
|---|---|
| [`00_data_profile.sql`](analysis/00_data_profile.sql) | Control totals and the data-quality facts that every other analysis depends on. It runs no business analysis. |
| [`01_revenue_trends.sql`](analysis/01_revenue_trends.sql) | Revenue, units and orders over time, seasonality, and whether growth comes from more orders or a higher order value. |

Planned lines of analysis: product mix, revenue concentration, geographic distribution, customer demographics, and repeat purchasing with RFM segmentation.

The analytical conventions that come out of the data profiling (analysis window, order dating, the meaning of `create_date`, repeat-purchase cohorts) are recorded in decision 7 of [`docs/decisions.md`](docs/decisions.md). None of them changes Silver or Gold.

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

## Technologies

* SQL Server
* T-SQL
* Medallion Architecture
* Dimensional Modeling
* Git / GitHub

## Repository structure

```text
data-warehouse-project/
│
├── datasets/
│   ├── source_crm/
│   └── source_erp/
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
├── analysis/
│   ├── 00_data_profile.sql
│   └── 01_revenue_trends.sql
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
├── CLAUDE.md
├── README.md
└── .gitignore
```

## Technical decisions

The main decisions made during development and their justifications are documented in [`docs/decisions.md`](docs/decisions.md):

1. Implementing the Gold layer with views
2. Surrogate keys in the dimensions
3. CRM as the primary source for customer information
4. Design and responsibilities of the Bronze, Silver and Gold layers
5. Transformations and quality checks in Silver and Gold
6. Source CSV line terminators and completeness of Bronze ingestion
7. Analytical conventions established by the data profiling

## References

The data used in this project and the reference conceptual structure come from **Data With Baraa**, as part of his educational Data Warehouse project.

The additions in this repository are the reproducible rebuild, the ingestion fix documented in decision 6, the documented design decisions and the analytical layer.
