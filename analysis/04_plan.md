# Q4 plan: revenue concentration

**Status: approved by the author** (after review by the `conclusions-reviewer` subagent). Script: `analysis/04_revenue_concentration.sql`. No sections beyond those listed in section 6.

---

## 1. Business question

"How concentrated is revenue: what share of revenue is accounted for by the highest-revenue customers and products?"

This is the wording of Q4 in [`questions.md`](questions.md) (reworded on the author's approval: the earlier "depends on" implied a dependence that a share of revenue cannot show). The header of the script and the heading of the Q4 section of [`findings.md`](findings.md) quote it.

Claims are descriptive only: how much revenue the highest-revenue entities account for. No claim of dependence, no causal claim. If concentration is low, it is reported as low. Findings avoid "drive", "rely on", "key customers" and "dependence".

## 2. Data and grain

* `gold.fact_sales` (order line), joined to `gold.dim_products` (295 current versions; small, so the join is cheap).
* Customers are grouped by `gold.fact_sales.customer_key` inside one query and never reported or hardcoded (Known pitfalls; decision 7.9 rule 1). No customer is named. Products are named by `product_number`.
* Years 2011, 2012 and 2013 (7.1), by the order-level date (7.2). Context rows, never in the year comparisons: the 2010 tail (43,419), January 2014 (45,642) and the 2 undated orders (34). With 7,075,088 / 5,842,231 / 16,349,836 they add to 29,356,250 (Q1 section A).
* Each CTE built on the Gold views is referenced once. Customers: lines are collapsed once to one row per order (as in Q3), then to customer-year with window functions. Products: lines get the order-level date by window, are grouped by `product_key` and year, and only then joined to the 295-row dimension. No temp tables, nothing created, `SELECT` only, `DataWarehouse_Test` only.

## 3. Definitions

Inherited and applied unchanged: 7.1, 7.2, 7.8 (category is the current product version; Q2 product-identity caveat).

* **Entity-year:** one row per customer (or product) per year with revenue = `SUM(sales_amount)` in that year. An entity is **active** in a year if it has such a row. N = active entities in that year; it changes from year to year.
* **Customer top group:** the k highest-revenue active customers, for p in {1, 5, 10, 20}%. k = CEILING(p x N), in integer arithmetic: `(p x N + 99) / 100` (for example the 2011 top 1% is k = 23). Share = revenue of the top group / revenue of all active customers in the year. Every share is printed with k and N. If k = 0 under a rule, the row is printed without a share.
* **Product cuts:** rank-based: the top 1, 5, 10 and 20 products, with N. No top-p% for products. Also the ranked list of the 10 largest products per year (`product_number`, category, revenue, share of the year's revenue). Rank ties are broken by `product_number`; a tie at the 10th place is flagged.
* **Distribution per entity:** mean, median, P10, P25, P75, P90, P99, maximum and mean/median. No Gini or HHI.
* **Ties:** tied entities have equal revenue, so the revenue of the top k (the share) does not depend on which tied entities are picked. This holds for the share only. Section D varies the group rule instead: CEILING, FLOOR, and tie-inclusive (every entity tied with the k-th is in the group), with the number of entities tied at the boundary.
* **Minimum sizes (Q4-specific, declared before the script is run, not recorded in decision 7):** a customer statistic is interpreted only if the base is at least 100 active customers and the top group has at least 30. Reason: a percentage means little on a small base; the shares cover the whole population, so this is about meaning, not sampling noise. Smaller cases are printed with the flag "not interpreted". Example: the 2011 top 1% is 23 customers.
* **Customer group:** decision 7.10 (Bike customer / No bikes customer, as in Q3 section F2).
* Revenue = `SUM(sales_amount)` (currency unknown); order = distinct `order_number`.

**Decision 7.10** records the customer group. It is written before the script is run.

## 4. How the customer result is read

* In 2011 every customer has one order of one line (2,216 orders, lines and units in Q1 section A; 2,216 customers in the 2011 cohort, Q3 section A): revenue per customer is the price of one bike. 2012 is nearly the same. So for 2011 and 2012 the customer concentration says almost nothing beyond what Q2 says about prices. It is **context only** and is not compared across years as a trend in concentration.
* In 2013 the year mixes Bike orders (AOV 1,624.09) and No bikes orders (AOV 50.64) (Q2 section H), so total concentration reflects that mix.
* **The customer result of Q4 is 2013 within each customer group (section C).** Section B is context.

## 5. Method

One query per section. A line-level (or order-level) CTE assigns the order-level year and groups by `customer_key` (customers) or `product_key` (products) and year; the Bike flag of the customer is a window `MAX`. The small entity-year result is handled with window functions (`ROW_NUMBER`, `RANK`, `COUNT OVER`, `SUM OVER`, `PERCENTILE_CONT OVER`) and conditional aggregation. Each section repeats the chain, as in Q3.

## 6. Script sections

| Section | Content | Grain |
|---|---|---|
| A | Active customers and revenue by year: N, revenue, mean, median, percentiles, mean/median; customers by number of orders in the year (1 / 2 / 3+) with their revenue | year |
| B | Customer concentration, all customers: top 1 / 5 / 10 / 20% of active customers with k, N, revenue, share and the interpretable flag. **2011 and 2012 are context only** (section 4); 2013 as a whole mixes two customer groups | year x p |
| C | **Customer result.** Customer groups (7.10) for 2013 in full; 2011 and 2012 are one row each ("No bikes: 0 active customers; Bike = all"). Per group: active customers, revenue, share of the year's revenue, distribution, and top 1 / 5 / 10 / 20% inside the group (k, N, share, flag) | year x group x p |
| D | Sensitivity of B and C to the group rule: CEILING / FLOOR / tie-inclusive, with the number of entities tied at the boundary | year x p x rule |
| E | Products: active products, revenue, distribution; top 1 / 5 / 10 / 20 products with N and share; ranked list of the 10 largest per year | year x cut |
| F | Revenue share of each category by year (ties to Q2 section C) | year x category |
| G | Control totals, see below | check |

**Section G** prints OK / MISMATCH for: lines 60,398; orders 27,659; revenue 29,356,250; units 60,423; customers 18,484; revenue by year against Q1 section A (2011, 2012, 2013, with the context and undated rows); the revenue of the customer groups, of the products and of the categories each adding up to the year's revenue; customers in both groups = 0; Bike customers = 9,132; No bikes customers = 9,352; and their sum = 18,484 (the Q3 F2 partition).

Reviewer point 8 (orders per customer and AOV of the top group) is not included; F no longer shows the category makeup of the top product groups.

## 7. What the analysis can and cannot say (caveats)

* In 2011 revenue per customer equals the price of one bike; concentration among customers in 2011 and 2012 is context only. A revenue share reflects price, not popularity.
* A customer's yearly revenue depends on the months active. In 2013 there are 12,521 first-time customers (Q3 section A), and there is no No bikes order in 2011 or 2012 (Q2 section H). The top-share ranking partly reflects how early in the year a customer started.

  *Correction made after the run:* this caveat first said "No bikes customers exist only from December 2012". That was wrong: Q2 section H has no No bikes order in 2012, and Q4 section C1 shows 0 active No bikes customers in 2011 and 2012. The same correction was made in the header of the script (comment only; no query changed).
* Customers are not followed across years: the top group of 2013 is not the top group of 2011.
* Top-percent shares depend on N. The group rule (CEILING / FLOOR / ties) is in section D.
* Product means a distinct `product_number`, current version only (Q2): a relaunch under a new number counts as two products. Category is the current version's.
* Currency is unknown. The pattern may reflect how the data was generated.

Findings separate Observations / Inferences / Hypotheses / Uncertainty / Needs additional data, make no causal claim, and prefer narrowing a claim to adding one.

## 8. Decisions

Approved by the author: the reworded Q4 question and the register row (including "Why it would matter"); decision 7.10 as written (both customers with no dated order fall in No bikes); the minimum sizes (100 active customers, top group of 30) as a Q4-specific rule, not recorded in decision 7; rank-based cuts and the ranked list for products, no top-p% for products; the script name `analysis/04_revenue_concentration.sql`; no sections beyond section 6.

Reviewer-driven changes (`conclusions-reviewer` report on the draft): customer concentration of 2011 and 2012 is context only and 2013 within groups (C) is the customer result; customers by orders in the year in A; product cuts by rank and a ranked list instead of top-p%; the minimum-size rule stated with its reason and kept out of decision 7; customer group as in Q3 F2 with partition and no-overlap checks in G; C limited to 2013 for the group comparison; caveat on months active; invariance of the share under ties limited to the share, k = 0 handled and k in integer arithmetic; F reduced to category shares tied to Q2; wording ("highest-revenue", no "depend on"). Not applied: reviewer point 8 (optional).

If a section G check is not OK, work stops and the author is told before any findings are written.

## 9. Definition of done (from `CLAUDE.md`)

1. `analysis/04_revenue_concentration.sql` has the standard header.
2. It ends with the control-totals section (G), printing `OK` / `MISMATCH`.
3. Run with `scripts\run_analysis.ps1 -Script analysis\04_revenue_concentration.sql -DatabaseName DataWarehouse_Test`; it passes and `analysis/output/04_revenue_concentration.txt` is saved.
4. [`findings.md`](findings.md) gets a Q4 section; every number appears in the saved output or is derived from it with the arithmetic shown. The `findings-verifier` runs on it (at most 3 passes) and its last report goes to the author.
5. README analysis table, [`questions.md`](questions.md) and Current status are updated, and decision 7 (new 7.10).

Out of scope: changes to Silver or Gold, new database objects, Python or visualization, any use of `DataWarehouse`.
