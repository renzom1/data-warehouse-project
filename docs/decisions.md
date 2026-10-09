# Technical decisions

This document records the main decisions made while developing the Data Warehouse, together with their justification and the limitations of each approach.

Its purpose is to keep a record of the decisions that affect the architecture and to show the reasoning behind the modeling and processing of the data.

---

## 1. Implementing the Gold layer with views

### Decision

The Gold layer was implemented as SQL Server views built from the Silver layer tables.

The main Gold entities are:

* `gold.dim_customers`
* `gold.dim_products`
* `gold.fact_sales`

These views integrate and reorganize the data previously transformed in Silver to expose a dimensional model oriented to analysis.

### Justification

Silver holds data that is already cleaned and transformed, but it remains organized mainly around the different source systems.

Gold has a different purpose: to present the data through a dimensional model made up of dimensions and a logical fact table.

For this project, the model was built directly through queries on Silver, without materializing a second physical copy of the data.

This keeps a clear separation between:

* **Silver:** transformed and prepared data.
* **Gold:** model oriented to analytical consumption.

In addition, because views are used, Gold results are obtained from the current state of the Silver tables, with no extra process to physically load Gold.

### Consideration

This implementation fits the scope and learning goal of the project, but it should not be read as a universal strategy for production Data Warehouses.

In a larger environment there could be reasons to materialize the dimensions and the fact table, such as performance needs, key persistence, explicit control of loads, or history handling.

### Limitation

The surrogate keys used in this project's dimensions are generated dynamically with functions such as `ROW_NUMBER()`. Because they are part of a view, these keys are not stored as persistent identifiers.

The implementation therefore represents the dimensional model conceptually, but it does not reproduce every characteristic that a physical dimensional model would have in a production environment.

---

## 2. Surrogate keys in the dimensions

### Decision

Surrogate keys were used to identify the dimension records within the Data Warehouse:

* `customer_key` in `gold.dim_customers`
* `product_key` in `gold.dim_products`

These keys are independent of the identifiers coming from the source systems, such as `cst_id` and `prd_key`.

### Justification

The identifiers from the source systems belong to the operational systems that originate the data. The Data Warehouse, in contrast, needs identifiers of its own for its entities.

This decouples the dimensional model from CRM- and ERP-specific identifiers and makes it easier to integrate information coming from different sources.

In addition, surrogate keys make it possible to link the dimensions to the fact table through keys owned by the Data Warehouse.

### Implementation

The keys are generated dynamically with `ROW_NUMBER()`.

For customers:

```sql
ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key
```

For products:

```sql
ROW_NUMBER() OVER (
    ORDER BY prd_start_dt, prd_key
) AS product_key
```

### Limitation

Keys generated with `ROW_NUMBER()` are not persistent. If the set of records or the ordering criterion changes, the same record could receive a different key.

This is especially relevant because the Gold dimensions and fact table are implemented as views.

For this reason, this strategy is enough to represent the dimensional model in the context of this project, but a production implementation would need a mechanism to generate and persist surrogate keys so that the identity of each entity stays stable over time.


---

## 3. CRM as the primary source for customer information

### Decision

To build `gold.dim_customers`, the CRM was established as the primary (*master*) source of customer information, while the ERP is used as a complementary source.

The information from both sources is integrated through the available identifiers, and the attributes needed from each system are added to the dimensional model.

When equivalent information exists in both sources, the CRM value takes precedence for the attributes defined as owned by that source. For example, customer gender uses the CRM as its primary source.

### Justification

This decision sets an explicit precedence rule between the different information sources.

The CRM holds more information directly related to the customer entity, while the ERP provides additional attributes that complement it.

Defining a primary source prevents values coming from different systems from being treated as equally reliable without first establishing which one should prevail when they disagree.

### Consideration

Choosing the CRM as the primary source responds to the context and data structure of this project. In a real environment, defining a system as the master source should rest on business criteria, such as ownership of the data, the processes that generate it, and the data governance rules the organization has established.

### Limitation

The integration depends on the identifiers and attributes available in the sources provided for this project. A complete *Master Data Management* process or advanced rules for resolving conflicts between multiple sources were not implemented.

The precedence rule applied is therefore an adequate integration strategy for this model, but it is not by itself a general master data management system.


---

## 4. Design and responsibilities of the Bronze, Silver and Gold layers

### Decision

The Data Warehouse was organized into three layers with distinct responsibilities:

* **Bronze:** ingestion of the data coming from the sources, keeping its structure and content as close to the origin as practical.
* **Silver:** cleaning, validation and transformation of the data to obtain consistent information prepared for integration.
* **Gold:** organization of the transformed data in a dimensional model (star schema) oriented to analytical consumption.

### Bronze

The Bronze layer receives the data from the source files through a *full load*.

No transformations, business rules or cleaning processes are applied at this stage. This preserves a representation of the source data before any modification is applied to it.

This separation lets Bronze serve as the starting point for later transformations. If a transformation in Silver needs to be changed or corrected, the original data remains available in Bronze to be reprocessed.

### Silver

The Silver layer concentrates the transformations needed to improve the quality and consistency of the data.

Among other operations, it performs cleaning, standardization, validation, removal of duplicates, and handling of invalid values.

These operations are kept separate from Bronze to preserve the source data and to prevent the processing from altering the original representation of the data.

In addition, concentrating the transformations in Silver separates ingestion from processing and makes the flow traceable from the original data to the data prepared for analysis.

### Gold

The Gold layer presents the data through a dimensional model oriented to analytical consumption.

Gold does not introduce a new cleaning or transformation stage. Its operations mainly consist of relating the information already prepared in Silver and exposing it through the dimensions and the logical fact table of the model.

The Gold entities were implemented as SQL Server views. This makes it possible to obtain the information needed for analysis from the relationships between the Silver tables, without storing a new physical copy of that data.

This decision keeps a clear separation between the transformed data in Silver and its consumption-oriented representation in Gold, avoiding the physical duplication of information that is already available in the earlier layers.

### Consideration

The separation of responsibilities between the layers keeps the processing flow clear:

**Source → Bronze → Silver → Gold → Analytical consumption**

Each stage has a specific purpose, and the transformations are applied progressively, keeping the result of the earlier stages available.

---

## 5. Transformations and quality checks in Silver and Gold

### Decision

The transformations and quality checks were concentrated mainly in the Silver and Gold layers, but with different goals.

In **Silver**, the checks target the quality and consistency of the data before it is used in the analytical model.

In **Gold**, the checks target the integrity and coherence of the dimensional model built from the Silver data.

### Transformations and checks in Silver

The transformations done in Silver respond to problems identified in the source data and to the requirements for integrating it later.

The operations performed include:

* cleaning and normalization of values;
* handling of spaces and inconsistent values;
* date conversion and validation;
* removal of duplicate records according to defined criteria;
* handling of null or invalid values;
* application of business rules specific to each entity;
* validation of relationships and expected ranges for certain attributes.

The quality checks verify that these transformations produce consistent data. For example, they check for duplicates, null values, date ranges, invalid values and other conditions specific to each dataset.

In this way, Silver is the stage where the data coming from the sources becomes information prepared to be integrated and used by the later layers.

### Checks in Gold

The checks run on Gold have a different goal. Rather than focusing on cleaning the data, they verify that the dimensional model built is coherent.

The validations performed include:

* existence of the expected relationships between `fact_sales` and the dimensions;
* absence of fact records with no matching customer dimension record;
* absence of fact records with no matching product dimension record;
* uniqueness of the dimension surrogate keys.

These checks verify that the construction of `gold.fact_sales` and its relationship with `gold.dim_customers` and `gold.dim_products` produce a model that is consistent for analysis.

### Consideration

Separating the Silver and Gold checks makes it possible to detect problems at different stages of the flow.

A problem related to the quality or consistency of a source datum should be detected in Silver, while a problem related to the integration or the relationships of the dimensional model should be detected in Gold.

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


