# Rebuild baseline

State of the `DataWarehouse` database captured **before** the Phase 0 clean-rebuild test.

The sections up to and including "Known issue present in this baseline" record the behavior of the original pipeline and are kept unchanged as evidence. A rebuild from the repository scripts and the CSV files as they were at capture time reproduced every number in them (confirmed in `DataWarehouse_Test`, 2026-10-06). The last section describes the corrected rebuild after the source CSV fix.

- Captured: 2026-10-05
- Instance: `.\SQLEXPRESS` (SQL Server Express 17.0), collation `Latin1_General_CI_AS`, `SIMPLE` recovery
- Silver last loaded: 2026-09-15 14:55
- Database contents: only the objects defined in this repository (6 Bronze tables, 6 Silver tables, `bronze.load_bronze`, `silver.load_silver`, 3 Gold views)

## Row counts

| Layer | Object | Rows |
|---|---|---|
| Bronze | `bronze.crm_cust_info` | 18,493 |
| Bronze | `bronze.crm_prd_info` | 397 |
| Bronze | `bronze.crm_sales_details` | 60,398 |
| Bronze | `bronze.erp_cust_az12` | 18,483 |
| Bronze | `bronze.erp_loc_a101` | 18,484 |
| Bronze | `bronze.erp_px_cat_g1v2` | 37 |
| Silver | `silver.crm_cust_info` | 18,484 |
| Silver | `silver.crm_prd_info` | 397 |
| Silver | `silver.crm_sales_details` | 60,398 |
| Silver | `silver.erp_cust_az12` | 18,483 |
| Silver | `silver.erp_loc_a101` | 18,484 |
| Silver | `silver.erp_px_cat_g1v2` | 37 |
| Gold | `gold.dim_customers` | 18,484 |
| Gold | `gold.dim_products` | 295 |
| Gold | `gold.fact_sales` | 60,398 |

## Fact table totals

| Measure | Value |
|---|---|
| `SUM(sales_amount)` | 29,356,250 |
| `SUM(quantity)` | 60,423 |
| Earliest `order_date` | 2010-12-29 |
| Latest `order_date` | 2014-01-28 |

## Known issue present in this baseline

Two source files lose their last row when loaded into Bronze:

| File | CSV data rows | Bronze rows | Missing row |
|---|---|---|---|
| `datasets/source_crm/cust_info.csv` | 18,494 | 18,493 | `,A01Ass,,,,,` (junk row, no customer ID; Silver would discard it anyway) |
| `datasets/source_erp/cust_az12.csv` | 18,484 | 18,483 | `AW00029483,1965-06-06,` (real customer; `birthdate` is `NULL` for customer 29483 in `gold.dim_customers`) |

Both files end without a line break and with an empty last field. The other four files load completely.
`BULK INSERT` discards such a final row without raising an error. The rebuild test is expected to reproduce this
exactly; fixing it is tracked as a separate step.

## Corrected rebuild (after the source CSV fix)

The issue above was resolved by appending the missing final line terminator (CRLF) to `cust_info.csv` and `cust_az12.csv`
(see decision 6 in [`decisions.md`](decisions.md)). Each file grew by exactly 2 bytes; all earlier bytes are unchanged.
No `BULK INSERT` configuration or SQL script was changed for this fix.

- Performed: 2026-10-06, in `DataWarehouse_Test`. Bronze and Silver were reloaded and the Gold views and both quality-check scripts were rerun on the existing test database.
- The original `DataWarehouse` was **not** modified. Its row counts and Silver load timestamp (2026-09-15 14:55:33) were checked afterwards and still match the baseline above, including the `NULL` birthdate for customer 29483.

### Expected differences from the baseline

| Object | Baseline | Corrected rebuild | Reason |
|---|---|---|---|
| `bronze.crm_cust_info` | 18,493 | 18,494 | Row `,A01Ass,,,,,` is now loaded. |
| `bronze.erp_cust_az12` | 18,483 | 18,484 | Row `AW00029483` is now loaded. |
| `silver.erp_cust_az12` | 18,483 | 18,484 | The new row passes through Silver unchanged. |
| `gold.dim_customers`, customer `29483`, `birthdate` | `NULL` | `1965-06-06` | The ERP row now matches `cst_key = AW00029483`. |

### Everything else matches the baseline

- `silver.crm_cust_info` stays at 18,484: the `A01Ass` row has a `NULL` customer ID and is filtered out in Silver.
- All other Bronze and Silver tables, `gold.dim_customers` (18,484), `gold.dim_products` (295) and `gold.fact_sales` (60,398) keep their baseline counts.
- `SUM(sales_amount)` (29,356,250), `SUM(quantity)` (60,423) and the order date range (2010-12-29 to 2014-01-28) are unchanged.

### Quality checks

Results are the same as in the baseline rebuild. The Gold checks return no rows. The Silver birthdate check still returns the same 15 birthdates
(1916-02-10 to 1923-11-16, before the 1924-01-01 lower bound); these are unchanged and are a separate data-quality question.
