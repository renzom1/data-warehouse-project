# CLAUDE.md

## Project

Portfolio project: a SQL Server data warehouse (Bronze → Silver → Gold, star schema in Gold) and an analytical layer that answers business questions with SQL on top of Gold.

Goal: show the full path from raw CSV data to reliable modeled data to defensible insights. A smaller analysis with a clear question and sound method beats many superficial ones.

## Current status

Update this section at the end of every task, so the next session starts from here.

- **Pipeline and reproducibility: done.** The warehouse rebuilds from the repository ([README, "Reproducible rebuild"](README.md#reproducible-rebuild)). The CSV line-terminator fix is [decision 6](docs/decisions.md#6-source-csv-line-terminators-and-completeness-of-bronze-ingestion). Do not re-validate the rebuild unless a pipeline script or source file changes.
- **Analysis:**
  - Q0 data profile: done ([`analysis/00_data_profile.sql`](analysis/00_data_profile.sql), conventions in [decision 7](docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling)).
  - Q1 revenue trends: done ([`analysis/01_revenue_trends.sql`](analysis/01_revenue_trends.sql), [`analysis/findings.md`](analysis/findings.md#q1-how-have-revenue-units-and-orders-changed-over-time)).
  - **Next: Q2 product mix.** It tests the Q1 hypothesis that product-mix changes explain part of the AOV decline (see ["Hypothesis" under Q1 in `findings.md`](analysis/findings.md#hypothesis-not-established)).
- **Planned after Q2** (candidates, not commitments; confirm scope with the author): revenue concentration, geography, customer demographics, repeat purchasing / RFM.

## Commands

Run from the repository root. Instance: `.\SQLEXPRESS`. All SQLCMD scripts require `DatabaseName` (no default).

```powershell
# Validate the database against the baseline (exit code 0 = OK)
scripts\validate.ps1 -DatabaseName DataWarehouse_Test

# Run an analysis: validates first, saves output to analysis/output/<name>.txt, fails on MISMATCH
scripts\run_analysis.ps1 -Script analysis\01_revenue_trends.sql -DatabaseName DataWarehouse_Test
```

Scripts: [`scripts/validate.ps1`](scripts/validate.ps1) (runs [`scripts/validate.sql`](scripts/validate.sql)) and [`scripts/run_analysis.ps1`](scripts/run_analysis.ps1).

If PowerShell blocks the scripts, run them through `powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...`.

The full rebuild (8 scripts in order) is in the [README](README.md#execution-order). Values with a drive letter (`ProjectRoot`) must be quoted as `'ProjectRoot="C:\..."'` in Windows PowerShell 5.1.

## Databases

- **`DataWarehouse_Test`**: the validated, corrected build. **All analysis runs here** ([decision 7.7](docs/decisions.md#77-analytical-database)). Dropping and rebuilding it is allowed when testing the pipeline.
- **`DataWarehouse`**: the author's original database (pre-fix load). **Never write to it, reload it or drop it** without explicit authorization. [`validate.ps1`](scripts/validate.ps1) fails on it by design (4 known mismatches from [decision 6](docs/decisions.md#6-source-csv-line-terminators-and-completeness-of-bronze-ingestion)).
- Analysis scripts are read-only: `SELECT` only, no objects created or modified.

## Analytical conventions (mandatory)

Defined in [decision 7 of `docs/decisions.md`](docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling). Apply them in every analysis without re-deriving them:

- **Window:** compare 2011–2013 only. The 2010 tail (29–31 Dec) and January 2014 (1–28 Jan) are context, never part of trends or year-over-year comparisons ([7.1](docs/decisions.md#71-main-analytical-period)).
- **Order date:** `MIN(order_date) OVER (PARTITION BY order_number)`. Lines with a NULL date inherit it. Only 2 orders (3 lines, revenue 34) are undated and are reported separately ([7.2](docs/decisions.md#72-order-level-date-for-temporal-analysis)).
- **Birthdates before 1924** (15 customers): keep them, and label the oldest age band `90+ (data-quality flag)`. Age is measured at the first order. Missing birthdate means "Unknown" ([7.3](docs/decisions.md#73-suspicious-historical-birthdates)).
- **`create_date`** is a load date (2025–2026), not an acquisition date. Use the first order date for cohorts and tenure ([7.4](docs/decisions.md#74-meaning-of-create_date)).
- **Shipping/due dates** are constant offsets (+7 / +12 days). No fulfilment analysis ([7.5](docs/decisions.md#75-shipping-and-due-dates)).
- **Repeat purchase:** use cohorts by first-order year and "second order within N days" restricted to eligible customers, always reporting the eligible count. Never compare raw repeat rates across cohorts ([7.6](docs/decisions.md#76-repeat-purchase-cohorts)).
- **Metrics:** Revenue = `SUM(sales_amount)` (currency unknown). Order = distinct `order_number`. AOV = revenue / orders. The grain of `gold.fact_sales` is one order line.
- **Control totals:** 60,398 lines / 27,659 orders / revenue 29,356,250 / units 60,423 ([`docs/rebuild_baseline.md`](docs/rebuild_baseline.md)).

A new convention that affects how data is interpreted goes into [decision 7](docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling) before it is used.

## Definition of done

### An analysis (Qn) is done when

1. `analysis/0N_<topic>.sql` has the standard header: business question, data required, grain, definitions, method, caveats, control totals, run command (copy the structure of [`01_revenue_trends.sql`](analysis/01_revenue_trends.sql)).
2. It ends with a control-totals section that prints `OK` / `MISMATCH` against the control totals, and every section's figures tie back to them.
3. It was run with [`scripts\run_analysis.ps1`](scripts/run_analysis.ps1) and passed, and `analysis/output/0N_<topic>.txt` is saved in [`analysis/output/`](analysis/output/).
4. [`analysis/findings.md`](analysis/findings.md) has a QN section with Observations / Inferences / Hypotheses / Uncertainty / Needs additional data. **Every number in it appears in the saved output** (or is derived from it with the arithmetic shown).
5. The [README analysis table](README.md#analytical-layer) and [Current status](#current-status) are updated, as is [decision 7](docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling) if a new convention was introduced.

Before writing a new analysis script, present a short plan (question, metrics, method, expected sections) and wait for the author's OK. That plan is the main point of review. After it is approved, implement without stopping for small details.

### A pipeline change (Bronze / Silver / Gold / sources) is done when

1. It was rebuilt in `DataWarehouse_Test` ([README order](README.md#execution-order)).
2. `scripts\validate.ps1 -DatabaseName DataWarehouse_Test` passes. If an expected value changes on purpose, update [`scripts/validate.sql`](scripts/validate.sql) and [`docs/rebuild_baseline.md`](docs/rebuild_baseline.md) together and explain why.
3. The decision is recorded in [`docs/decisions.md`](docs/decisions.md) if it affects semantics, modeling or reproducibility.

## Known pitfalls

- `bronze.load_bronze` and `silver.load_silver` catch errors and only print them: `sqlcmd` can exit 0 after a failed load. Trust [`validate.ps1`](scripts/validate.ps1), not the exit code of a load.
- `BULK INSERT` silently drops a final CSV line that has no line terminator and ends with an empty field ([decision 6](docs/decisions.md#6-source-csv-line-terminators-and-completeness-of-bronze-ingestion)). Check row counts after replacing any source file.
- `COUNT(DISTINCT order_date)` ignores NULLs. 19 fact lines have a NULL `order_date`.
- Surrogate keys (`customer_key`, `product_key`) come from `ROW_NUMBER()` in views and are not stable ([decision 1](docs/decisions.md#1-implementing-the-gold-layer-with-views), [decision 2](docs/decisions.md#2-surrogate-keys-in-the-dimensions)). Never hardcode them; use `customer_id` / `product_number` to refer to specific entities.
- `gold.dim_products` holds current product versions only (`prd_end_dt IS NULL`): 295 of 397 Silver rows ([`scripts/gold/ddl.sql`](scripts/gold/ddl.sql)).
- After a join, compare row counts before and after to catch fan-out.

## Where knowledge lives

| File | Contents | Update when |
|---|---|---|
| [`docs/decisions.md`](docs/decisions.md) | Architecture, modeling and analytical decisions with justification | A decision affects semantics, modeling, methodology or reproducibility |
| [`docs/rebuild_baseline.md`](docs/rebuild_baseline.md) | Expected counts and totals per layer | An expected value changes on purpose (together with [`scripts/validate.sql`](scripts/validate.sql)) |
| [`analysis/findings.md`](analysis/findings.md) | Results and how far each can be taken | Each analysis is completed |
| [`analysis/output/`](analysis/output/) | Saved output of each analysis script (evidence for findings) | Each analysis is run with [`run_analysis.ps1`](scripts/run_analysis.ps1) |
| This file, [Current status](#current-status) and [Known pitfalls](#known-pitfalls) | Where the project is, and traps worth remembering | End of every task / when a new trap is found |

When the author corrects a mistake, record the lesson where it will prevent a repeat: a pitfall in [Known pitfalls](#known-pitfalls), a convention in [decision 7](docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling), or a check in [`scripts/validate.sql`](scripts/validate.sql).

## Working rules

- Ask before decisions that change architecture, analytical scope, data semantics, existing pipeline behavior, technology choices, or that are destructive or a large refactor. Otherwise act without asking about small details.
- Fix data problems at the layer where they originate (source, ingestion, transformation, modeling, or documentation); do not mask them downstream.
- Do not rewrite working components only because another approach exists. Change them when they block reproducibility, give wrong results, or depend on the author's machine.
- Gold is the source for business analysis. Bypassing it needs a documented reason.
- SQL first. Python or visualization only when they add something SQL cannot, and Power BI only to communicate findings.
- Point out issues, inconsistencies or better alternatives, but do not expand scope without a reason.
- In results, separate what the data shows, what can be inferred, what is uncertain, and what needs more data. No unsupported business claims.

## Conventions

- SQL: readable, one logical responsibility per script, `/* ... */` block comments that explain why. Make the question and metric definitions easy to find in analytical SQL.
- English for documentation, filenames and code.
- Git: no commits unless asked. Check `git status` before significant changes. Keep changes focused. Commit messages describe the actual change.
