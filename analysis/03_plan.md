# Q3 plan: repeat purchasing

**Status: approved by the author** (after review by the `conclusions-reviewer` subagent). Script: `analysis/03_repeat_purchasing.sql`. No sections beyond those listed in section 4.

---

## 1. Business question

Do customers place a second order, how quickly, and does that differ by the year of their first order or by the kind of first order? Are the 2013 "No bikes" orders (11,581, decision 7.8) first orders of customers, or later orders of customers who already bought a Bike?

The second part tests the open Q2 hypothesis ([`findings.md`](findings.md), Q2 "Hypotheses") as a statement about the **sequence of orders**, not about types of customers or about why customers bought. Whatever it shows, it does not apportion the AOV decline (Q2 already described the composition of that decline).

## 2. Data and grain

* `gold.fact_sales` (order lines) joined once to `gold.dim_customers` (`customer_id`, never `customer_key`) and once to `gold.dim_products` (category, for the order class).
* Check made on `DataWarehouse_Test` (read-only): all 27,659 orders map to exactly one customer; no line lacks a customer; 18,484 customers exist in the dimension and 18,484 distinct customers in the fact table.
* **Grain: lines are collapsed once to one row per order** (`customer_id`, order date, order class, revenue). First order, second order, gaps and classes are derived from that small result with `ROW_NUMBER` / `LEAD` / window functions. Each CTE built on Gold is referenced once (Known pitfalls). No temp tables, nothing created.

## 3. Definitions

Inherited and applied unchanged: order date = `MIN(order_date) OVER (PARTITION BY order_number)` (7.2); the 2 undated orders (3 lines, revenue 34) are outside every cohort and the order sequence, and are reported separately; window 2011-2013 (7.1); repeat-purchase cohorts and eligibility (7.6); order classes Bikes only / Bikes + other / No bikes (7.8); `create_date` not used (7.4).

* **First order** = earliest dated order of the customer. Ties on the same date are broken by `order_number`, which is arbitrary (nothing shows it reflects the sequence within a day); the customers with more than one order on their first date are counted and used in a sensitivity check (D, E). **Cohort** = year of the first order: 2011, 2012, 2013. First orders in the 2010 tail (29-31 Dec) are context, not a cohort.
* **End of data** = `MAX(order date)` in the data (expected 2014-01-28), computed in the script.
* **Second order within N days** (N = 90, 180, 365): the customer's second distinct `order_number` has a date at most N days after the first order's date (`DATEDIFF(day)`, inclusive). **Eligible** = first order date <= end of data - N days. Eligible count and number of customers who reordered are shown next to every rate.
* **Same-day second order:** a distinct `order_number` on the same date as the first counts as a second order (0 days); the number of such customers is reported. It may be a split basket or a real repeat; the data cannot tell.
* **Follow-up in January 2014** counts as a second order. It affects follow-up only, never cohort membership, and is an exception to 7.1 for follow-up purposes. January 2014 is unexplained in Q1 (AOV 52.40), so a sensitivity is shown in B.
* **Minimum group size:** a rate, median or band share is shown only where the eligible count is at least 100; below that only the counts. Differences between groups close to the threshold are not interpreted.
* **Order class** = decision 7.8. First-order class and second-order class are the classes of those orders.
* Revenue = `SUM(sales_amount)`; order = distinct `order_number`.

**Decision 7.9** records: end of data = last dated order; inclusive eligibility rule and `DATEDIFF(day)`; same-day distinct orders count as repeat; January 2014 follow-up counts (exception to 7.1, with a pointer added in 7.1); tie-break by `order_number` with the affected customers counted; minimum group size 100; customers with no dated order; the rules of section F. It is written before the script is run.

## 4. Script sections

Structure copied from [`02_product_mix.sql`](02_product_mix.sql) (standard header, block comment per section, control totals last). The 2013 No bikes section is F and the control totals are G, so that control totals stay last.

| Section | Content | Grain |
|---|---|---|
| A | Customers, orders and orders per customer by cohort (2011, 2012, 2013), plus 2010-tail first orders and customers with no dated order. Reconciled to 18,484 customers. The 6,865 / 11,619 split (7.6) is descriptive context only; it can differ slightly because undated orders are outside the sequence. Orders per customer is labelled as not comparable across cohorts (different follow-up) | cohort |
| B | Second order within 90 / 180 / 365 days by cohort: eligible customers, customers who reordered, **of which same-day (0 days)**, rate (if eligible >= 100) and the rate excluding same-day reorders. N = 365 covers only first orders on or before 2013-01-28: the 2011 and 2012 cohorts and the first 28 days of the 2013 cohort. Also: **B2** second orders by calendar quarter and cohort (to see whether a cohort difference is a calendar jump); **B3** sensitivity at N = 90 with end of data = 2013-12-31 (no January 2014 follow-up). Cohort differences are not cohort effects: see section 5 | cohort x N; cohort x quarter |
| C | Days to second order for customers who reordered within 365 days, restricted to customers eligible for 365 days (same window for every cohort): median and bands (0 = same day, 1-30, 31-90, 91-180, 181-365), by cohort. **The output states how many 2013-cohort customers are eligible at N = 365 (first orders 2013-01-01 to 2013-01-28).** Minimum group size applies | cohort x band |
| D | Second order within 90 / 180 days by first-order class, **restricted to customers whose first order is on or after 2012-12-01**, the period in which all three classes exist for the whole follow-up window (the pooled 2011-2013 table is dropped: 2011 is 100% Bikes only and 2012 98.1%, so pooling compares catalogs). Also by quarter of the first order where counts allow, with eligible counts. Sensitivity: the same table excluding customers with more than one order on their first date. Link to Q2: do customers whose first order was a low-value No bikes order reorder differently? | class (x quarter) x N |
| E | Class of the second order against class of the first order (counts and row shares): customers eligible at N = 180 **who reordered within 180 days**, same population as D, with the same tie sensitivity | first class x second class |
| F | The 11,581 No bikes orders of 2013, assigned by rules applied in this order: (a) first order of the customer; (b) later order on the same date as the customer's first order; (c) later date, the customer has a Bike in an order dated earlier; (d) later date, no Bike earlier but a Bike in another order on the same date (counted apart); (e) later date, no Bike in any earlier-dated or same-date order. A sixth row, "unclassified", is a defensive catch-all and must be 0. Counts and shares add up to 11,581. **Shares are of orders, not customers**: distinct customers per category are shown too, and the reverse denominator: of the customers with a Bike in an order dated before 2013, how many placed a No bikes order in 2013. Observation only | category |
| G | Control totals: OK / MISMATCH against 60,398 lines / 27,659 orders / revenue 29,356,250 / units 60,423; customers = 18,484 as a partition (cohorts + 2010-tail first orders + customers with no dated order); orders of those groups = 27,659; section F = 11,581 and its "unclassified" row = 0 | check |

Note on F (e): this category is not a leftover that should be empty. It holds later No bikes orders of customers whose earlier orders had no Bike (for example earlier No bikes orders), so its size is a result. Exhaustiveness is checked by the "unclassified" row.

## 5. What the analysis can and cannot say (caveats)

| Question | Addressed by | Limit |
|---|---|---|
| Reorder rate and speed | B, C | Customers are observed from 29 Dec 2010: a "first order in the data" may not be the customer's first order ever. The bias is not even across cohorts: 2011 is the cohort most likely to contain customers with earlier history misclassified as new, in a direction that cannot be checked with this data |
| Differences between cohorts | B, B2, B3, C | **Cohort is confounded with calendar, not only with class.** Accessories and Clothing appear from December 2012 (Q2), so the 2012 cohort's follow-up window falls largely in 2013 with a different catalog, while 2011's falls mostly in the Bikes-only period. Cohort differences in B are not read as cohort effects. Another possibility the data cannot rule out: reorders concentrate after December 2012 because of the new catalog, whatever the age of the customer (B2 shows the timing) |
| Differences by first-order class | D, E | Class is confounded with cohort and calendar; the population is limited to first orders from 2012-12-01, and for N = 180 to first orders up to 2013-07-31. The mix still changes within 2013 (non-Bike share of lines 70.1% in January and 86.9% in February, Q2 section G3), hence the quarter split |
| 2013 No bikes orders: first orders or later orders | F | Sequence only. A customer whose first order is No bikes may buy a Bike later, so F does not separate "new type of customer" from "existing Bike customer". A Bike bought before December 2010 is not visible. F does not change Q2's description of the AOV composition |
| January 2014 and same-day orders | B, B3 | Whether they are real purchases or artefacts of how the data was produced is unknown; the plan shows results with and without them |

Findings separate Observations / Inferences / Hypotheses / Uncertainty / Needs additional data, make no causal claim about why customers reorder, and prefer narrowing a claim to adding one.

## 6. Cautions

* The 2011 and 2012 cohorts are small against 2013; compare with 2013 only where eligible counts allow.
* No confidence intervals (SQL only, simple tables); small groups are handled by the minimum group size and by showing the counts.
* Gaps are measured in days between order dates, so patterns in the source dates are carried through.

## 7. Decisions

Approved by the author: minimum eligible count 100; decision 7.9 recorded before running (with a pointer line in 7.1); tie-break by `order_number` with the affected customers counted; D and E restricted to first orders from 2012-12-01; no sections beyond section 4. Added after the `conclusions-reviewer` pass: B2 and B3; tie sensitivity in D and E; section F rules in a fixed order, customers and the reverse denominator; G control written as a customer partition; threshold also applies to C.

If the "unclassified" row of F is not 0, work stops and the author is told before any findings are written.

## 8. Definition of done (from `CLAUDE.md`)

1. `analysis/03_repeat_purchasing.sql` has the standard header.
2. It ends with the control-totals section (G), printing `OK` / `MISMATCH`.
3. Run with `scripts\run_analysis.ps1 -Script analysis\03_repeat_purchasing.sql -DatabaseName DataWarehouse_Test`; it passes and `analysis/output/03_repeat_purchasing.txt` is saved.
4. [`findings.md`](findings.md) gets a Q3 section; every number appears in the saved output or is derived from it with the arithmetic shown. The `findings-verifier` runs on it (at most 3 passes) and its last report goes to the author.
5. README analysis table and Current status are updated, and decision 7 (new 7.9).

Out of scope: changes to Silver or Gold, new database objects, Python or visualization, any use of `DataWarehouse`.
