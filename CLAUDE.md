# CLAUDE.md

## Project Overview

This repository is a portfolio project focused on building a practical SQL Server data warehouse and using that warehouse for analytical work.

The project is intended to demonstrate more than the ability to build ETL pipelines. The broader goal is to show the complete path from raw data to reliable, modeled data and, ultimately, meaningful analytical insights.

The current architecture is:

```text
Source CSV files
      ↓
   Bronze
      ↓
   Silver
      ↓
    Gold
      ↓
Analytical layer
      ↓
Insights / Python / Visualization
```

The Bronze, Silver, and Gold layers already exist.

The current work has two related goals:

1. Validate and improve the reproducibility of the existing Data Warehouse.
2. Build an analytical layer on top of the validated Gold layer.

---

## Current Phase: Reproducibility

An important current objective is to verify that a clean environment can recreate the Data Warehouse using the artifacts contained in this repository.

The intended workflow is:

```text
Repository
    ↓
Source CSV files
    ↓
Database initialization
    ↓
Bronze
    ↓
Silver
    ↓
Gold
```

A person who clones this repository should not need access to the author's existing SQL Server database or local machine-specific configuration in order to understand and reproduce the pipeline, apart from clearly documented external prerequisites.

This means Claude should actively test whether the existing scripts are sufficient to recreate the warehouse from scratch.

### Reproducibility principles

When validating reproducibility:

* Prefer creating a clean test database/environment.
* Use the existing repository scripts as the starting point.
* Identify hardcoded local assumptions.
* Identify missing setup steps or dependencies.
* Verify that scripts execute in the correct order.
* Verify that scripts target the intended database and schemas.
* Verify that source files can be located through documented configuration.
* Preserve the intended behavior of the existing pipeline.

Changes to existing scripts are allowed and encouraged when they are necessary to make the repository reproducible.

Do not rewrite working components simply because they could be implemented differently.

The goal is to make the existing project reproducible, not to replace the author's implementation with an unrelated architecture.

---

## Database Safety

The existing working database and its data are valuable.

Do not destroy or overwrite the author's existing working database unless explicitly authorized.

When testing reproducibility, prefer a clean test database or environment.

Dropping and recreating a dedicated test database is acceptable when necessary to verify that the repository can truly build the warehouse from scratch.

Database initialization scripts should be idempotent and non-destructive whenever practical.

---

## Current Architecture

### Bronze

Raw ingestion of the source CSV files into SQL Server.

The Bronze layer should preserve the source data as faithfully as practical while providing a reliable ingestion mechanism.

### Silver

Cleans, standardizes, deduplicates, and prepares data for analytical use.

### Gold

Business-oriented dimensional model using a star-schema approach.

Current Gold objects include:

* `gold.dim_customers`
* `gold.dim_products`
* `gold.fact_sales`

The Gold layer is the primary source for analytical queries.

Do not bypass the Gold layer for business analysis unless there is a specific, documented reason to do so.

---

## Current Objective After Reproducibility

Once the warehouse is reproducible and its data quality assumptions are validated, the main objective is to answer meaningful business questions using the data available in Gold.

The preferred progression is:

```text
Gold
  ↓
SQL analysis
  ↓
Findings and interpretation
  ↓
Evaluate whether further analysis adds value
  ↓
Python / visualization / Power BI when justified
```

SQL analysis comes first.

Potential analytical areas include:

* sales trends
* product mix
* customer behavior
* repeat purchasing
* geographic distribution
* revenue concentration
* customer segmentation
* RFM analysis
* cohort analysis

These are examples, not mandatory deliverables.

The actual analytical scope must be determined from the data and from the questions the data can answer reliably.

Do not implement every possible analysis simply because it was mentioned.

---

## Analytical Principles

Every analysis should start with a question.

Prefer this structure:

```text
Business question
        ↓
Data required
        ↓
Method
        ↓
SQL analysis
        ↓
Result
        ↓
Interpretation
        ↓
Potential implication
```

A technically correct query is not automatically a useful analysis.

When presenting an analytical result, distinguish clearly between:

* what the data directly shows;
* what can reasonably be inferred;
* what remains uncertain;
* what would require additional data to establish.

Avoid unsupported business claims.

---

## Technology Choices

Use the simplest appropriate technology.

### SQL

SQL Server is the primary analytical environment.

Use SQL when the task naturally involves:

* joins
* aggregations
* filtering
* grouping
* CTEs
* window functions
* dimensional analysis
* business metrics

Do not move an analysis to Python merely because Python is available.

### Python

Python may be introduced when it provides a meaningful advantage over SQL, such as:

* statistical analysis;
* more flexible exploration;
* transformations that are awkward in SQL;
* visualizations that provide additional insight;
* analyses requiring Python-specific libraries.

Python is optional. Its inclusion must have a reason.

### Power BI / dashboards

Visualization should communicate or explore findings rather than replace analytical reasoning.

Do not create dashboards simply to add Power BI to the technology stack.

---

## Data Quality

Data quality is part of both the reproducibility and analytical processes.

Before relying on a dataset for an important analysis, verify relevant assumptions such as:

* null values;
* duplicate records;
* referential integrity;
* unexpected categories;
* date ranges;
* impossible or suspicious values;
* metric definitions;
* grain of each table.

The project has already used validation checks for issues such as:

* null order dates;
* unmatched countries;
* order-number uniqueness;
* `create_date` ranges;
* zero costs;
* missing foreign-key matches.

Do not assume a metric is valid merely because the SQL query executes successfully.

When a data-quality issue is discovered, determine whether it is:

1. a source-data characteristic;
2. an ingestion problem;
3. a transformation problem;
4. a modeling problem;
5. a validation/documentation problem.

Fix the problem at the appropriate layer rather than masking it downstream.

---

## Development Workflow

When working on a task:

1. Understand the existing repository and relevant documentation.
2. Identify the smallest appropriate change.
3. Check whether the requested change affects existing behavior.
4. Implement the change.
5. Review the resulting diff.
6. Run relevant validation or tests.
7. Report what changed and what was verified.

Claude may implement changes autonomously when the scope is clear and the changes are reasonably contained and reversible.

Ask for confirmation before making decisions that materially affect:

* project architecture;
* analytical scope;
* data semantics;
* existing pipeline behavior;
* technology choices;
* destructive operations;
* large-scale refactoring.

Do not stop for confirmation for every small implementation detail.

---

## Protecting Existing Work

The existing implementation represents previous engineering decisions and should be understood before being changed.

Do not:

* rewrite major parts of the pipeline without a concrete reason;
* replace working implementations merely because another approach is possible;
* delete existing documentation without understanding its purpose;
* introduce destructive setup scripts;
* change data semantics without documenting the reason.

However, preserving existing code is not an absolute requirement.

If an existing implementation prevents reproducibility, causes incorrect results, or creates an unnecessary dependency on the author's local environment, modify it when appropriate.

The priority is a correct, reproducible, understandable project — not preservation of every historical implementation detail.

---

## SQL Conventions

Use clear and readable SQL.

Prefer block comments:

```sql
/*
Purpose:
Explain why this script or section exists.
*/
```

Keep SQL scripts focused on one logical responsibility.

Avoid unnecessary abstraction or excessive procedural complexity.

When creating analytical SQL, make the analytical question and metric definitions easy to identify.

---

## Repository Organization

Prefer separating implementation from analytical output.

A possible structure is:

```text
scripts/
    init_database.sql
    bronze/
    silver/
    gold/
    analytics/

analysis/
    ...

docs/
    architecture.md
    decisions.md
    ...

README.md
CLAUDE.md
```

Do not create directories or files solely because they are conventional. Add structure when it improves maintainability or communicates a meaningful separation of responsibilities.

---

## Documentation

Documentation should describe the actual state of the project.

Important decisions should be documented when they affect:

* architecture;
* data modeling;
* analytical methodology;
* technology choices;
* assumptions;
* trade-offs;
* reproducibility.

Do not document every trivial implementation detail.

Use English filenames for project documentation and code artifacts.

---

## Git

Do not create commits unless explicitly requested.

Before significant changes, inspect the repository status and avoid overwriting unrelated uncommitted work.

Keep changes focused and easy to review.

Commit messages, when requested, should describe the actual change rather than the intended future state.

---

## Important Debugging History

The project exposed a useful ingestion edge case involving `BULK INSERT`. It has been understood and resolved.

During the reproducibility rebuild, the final row of two source files was missing from Bronze: `AW00029483` in `cust_az12.csv` and the row with `cst_key = A01Ass` in `cust_info.csv`. In both files the final line had no line terminator and ended with an empty field, and the existing `BULK INSERT` configuration did not load such a row. The behavior was reproduced consistently in the baseline rebuild.

The minimal fix was to append the missing trailing line terminator (CRLF) to those two CSV files. The `BULK INSERT` strategy was not changed, and `px_cat_g1v2.csv` was left as is because it loads completely. The corrected rebuild was validated in `DataWarehouse_Test`. The original `DataWarehouse` database was not modified and still reflects the pre-fix load.

The full account is in decision 6 of `docs/decisions.md`, and the before/after numbers are in `docs/rebuild_baseline.md`.

This is an example of the type of practical data-engineering issue worth preserving and documenting when relevant. Bronze should preserve the source rows; a missing final row is an ingestion problem, not a data-quality rule.

Do not "fix" such historical behavior without first understanding why it occurred and what the intended ingestion semantics are.

---

## Decision-Making Philosophy

Optimize for:

1. correctness;
2. reproducibility;
3. clarity;
4. maintainability;
5. analytical usefulness;
6. simplicity;
7. portfolio value.

Portfolio value does not mean maximum technical complexity.

A smaller analysis with a clear business question, defensible methodology, and thoughtful interpretation is preferable to a larger collection of superficial techniques.

When multiple approaches are reasonable, explain the important trade-offs and choose the simplest approach that satisfies the objective.

---

## Working Style

Act as an engineering and analytical collaborator.

Do not merely execute instructions mechanically. When a request reveals a potential issue, inconsistency, unnecessary complexity, or better alternative, point it out.

At the same time, do not expand the scope without justification.

The goal is to build a project that is:

* technically sound;
* reproducible;
* analytically meaningful;
* maintainable;
* understandable;
* credible as a Data Engineering / Data Analytics portfolio project.
