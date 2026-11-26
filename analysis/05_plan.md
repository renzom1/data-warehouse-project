# Q5 plan: geography

**Status: approved by the author** (after review by the `conclusions-reviewer` subagent). Script: `analysis/05_geography.sql`. No sections beyond those listed in section 6.

## 1. Business question

Proposed wording (approved in form by the author; the register row, the script header and the findings heading quote it):

"How are customers, orders and revenue distributed across countries, and do the direction of the AOV changes 2011→2012 and 2012→2013 and the 2013 share of No bikes orders hold in each country?"

Register "Why it would matter": "Shows whether the Q1-Q2 patterns (the fall in AOV, the 2013 No bikes orders) appear in each country or only in some. Q3 (repeat purchasing) is left out on purpose: this question covers the AOV and the No bikes share only."

Claims are descriptive. No claim about markets, demand or why a country differs. Findings avoid "drive", "depend", "rely on", "key".

## 2. Data and grain

* `gold.fact_sales` (order line), `gold.dim_customers` (18,484 rows; `country`), `gold.dim_products` (category, for the order class).
* Customers per country (read-only `SELECT` on the dimension in `DataWarehouse_Test`, before the plan; section A reproduces it in the saved output): United States 7,482; Australia 3,591; United Kingdom 1,913; France 1,810; Germany 1,780; Canada 1,571; `N/A` 337. They add to 18,484.
* Country: ERP `loc_a101`, normalised in Silver (DE -> Germany; US / USA -> United States; empty -> `N/A`). In Gold it comes from a `LEFT JOIN` without `COALESCE`, so a NULL is possible; the Q0 profile shows 0 NULL and 337 `N/A`; section E checks it again.
* `N/A` is its own category, never imputed, and is not a country: it is printed in every table, flagged "not a country", included in the totals, and excluded from the count of countries used in the "most" rule (section 4).
* Order year: 7.1 / 7.2. Years 2011, 2012, 2013. The 2010 tail, January 2014 and the 2 undated orders are context rows in the reconciliation only. An order belongs to the country of its customer (check: no order has more than one `customer_key`).
* Order class: 7.8. Customer group: 7.10.

## 3. Definitions

* Per country-year: active customers, orders (distinct `order_number`), lines, units, revenue = `SUM(sales_amount)`; AOV = revenue / orders. Customers are `customer_key` inside the query, never reported or hardcoded.
* Shares are shares of the year's total (six countries plus `N/A`); they add to 100% per year.
* The `N/A` share of customers, orders and revenue is shown by year; if it varies, it moves the shares of the countries (reviewer point 9).
* **Reading rule (declared before the run).** The currency is unknown.
  * Across countries, only **customer shares and order shares** are read.
  * **Revenue shares and AOV levels across countries are printed but flagged** "comparable only if amounts are in one currency, which the data cannot show". They are not interpreted.
  * **Within-country AOV changes are read**, assuming each country's amounts are in one unit over time. That assumption cannot be checked.
  * The total AOV is printed next to the countries so a change in the country mix is not read as a change inside countries; no counterfactual or decomposition is computed.
* **"Same pattern" criterion (fixed before the run).** For each step (2011→2012 and 2012→2013): the pattern holds in a country if its AOV change has the same sign as the total AOV change; it is reported for every interpretable country. For the 2013 No bikes share (of orders, and of revenue as flagged above), the range across interpretable countries is reported next to the total, with no threshold for "same".
* **Section D, "price-list consistency (not a currency test)".** For each product and month (order-level date, 7.2), the realized unit price per line = `1.0 * sales_amount / quantity`, in decimal so the division does not truncate. This is the Q2 section I definition (realized price = revenue / units, `1.0 *` cast, `NULLIF` on units), kept so that Q5 and Q2 use one definition of price; the fact table's `price` column is not used (it is not the Q2 definition, and whether it equals the realized price is not checked here). It is computed per line (the average used in Q2 I would hide variation inside a month). Output: lines, product-months, product-months with more than one distinct price, and the largest relative gap (max / min - 1). **No country is joined.** If prices do not vary within a product-month, no country can differ within that month; if they do, the variation is reported and Q5 stops there (no country join). Under any outcome the currency stays unknown.

## 4. Minimum sizes (declared before the run; Q5-specific, not in decision 7)

Reason: the data are the population, not a sample, so the rule is about **sensitivity**: a ratio built on few orders moves a lot with one order. In 2011 an order has one line and the AOV of a country is an average of bike prices (Q4 section A, 2011: mean 3,192.73, maximum 3,578, p10 699, median 3,578), so a few orders of a cheap or an expensive model move it.

* AOV of a country-year: interpreted only if the country-year has **at least 100 orders**.
* **A within-country AOV change is interpreted only if both years pass** the 100-order minimum.
* 2013 class figures: the share of No bikes orders (of orders and of revenue) and the No bikes AOV need **at least 30 No bikes orders** in the country; the Bike-order AOV of a country in 2013 needs **at least 30 Bike orders**; both also need the country-year to have 100 orders.
* Smaller cells are printed with "not interpreted", never dropped.
* **"Most":** if in some year more than half of the six countries (4 or more) fail a minimum, the table is not interpreted and I stop and ask the author before writing findings.
* I have not seen the cell sizes. (Reviewer inference, unverified: the 100-order rule probably matters only for 2011, 2012 and `N/A`.)

## 5. Method and performance

* Chain per section: `o` (lines to one row per order: customer_key, order date, revenue, units, Bike-line flag) -> `cy` (to customer-year-class) -> join `gold.dim_customers` **once**, on the small aggregate, with `OPTION (HASH JOIN)` -> aggregate to country-year. Each CTE built on the Gold views is referenced once; no temp tables or objects; `SELECT` only; `DataWarehouse_Test` only.
* `gold.fact_sales` already expands the customer dimension view internally, and the join to bring the country expands it again in every section. So section A is **timed first**, and a **10-minute stop applies to every section**: if one exceeds it, I stop and tell the author before continuing.
* Section D has no country join, so it reads only the fact and the product dimension.

## 6. Sections

| Section | Content | Grain |
|---|---|---|
| A | Customers in the dimension per country (and `N/A`); per country-year: active customers, orders, lines, units, revenue, with shares of the year's totals (revenue shares flagged); `N/A` share by year | country x year |
| B | Side by side: order share and AOV by country and year, the total next to it; AOV change 2011→2012 and 2012→2013 (absolute, %) with the sign compared to the total; minimum flags (both years); AOV levels across countries flagged | country x year |
| C | 2013: order classes by country (Bike and No bikes orders, revenue, No bikes share of orders and of revenue, AOV by class) with the total and the flags; customers by group (7.10) by country on **two bases**: the whole-data partition (9,132 / 9,352) and the customers active in 2013 (8,583 / 8,844, Q4 C1). 2011 and 2012 have no No bikes orders (Q2 section H); stated once, not tabulated | country x class |
| D | Price-list consistency (not a currency test), by product and month, no country (section 3) | product-month |
| E | Control totals (OK / MISMATCH) | check |

No section beyond A-E.

**Control totals (OK / MISMATCH):** lines 60,398; orders 27,659; revenue 29,356,250; units 60,423; customers 18,484; the sum over countries (including `N/A`) of orders, revenue and units for 2011 / 2012 / 2013 = 7,075,088 / 5,842,231 / 16,349,836 revenue (Q1 A) with the 2010 tail 43,419, January 2014 45,642 and the 2 undated orders 34; active customers by year = 2,216 / 3,255 / 17,427 (Q4 A); customers with NULL country = 0 and customers by country add to 18,484; orders with more than one `customer_key` = 0; fact lines with no match in `gold.dim_customers` = 0; customer groups by country, whole-data basis: 9,132 + 9,352 = 18,484 and overlap = 0; customer groups by country, 2013-active basis: 8,583 and 8,844 (Q4 C1); Q4 C1 counted these groups, so they are tied to its output.

## 7. Caveats the findings must carry

* **Country** is the customer's location in the source extract, at an unknown date. The data has no history, so a customer who moved is attributed to one country for all orders. This cannot be checked. It is the customer's country, not a ship-to country.
* **Country differences in 2013 (AOV, No bikes share) may reflect when in the year each country's customers started buying** (2013 has 12,521 first-time customers, Q3 A; there is no No bikes order before 2013, Q2 H).
* The currency is unknown; D does not test it (reading rule, section 3).
* A within-country AOV change 2011→2012 contains the model mix and the price changes within Bikes (Q2 section I). A 2013 change contains the Bike / No bikes class mix within the country (section C shows it, B does not separate it).
* Country is one attribute; no model tests it against product or class. No causal claim.

## 8. Decisions

Approved by the author: the plan; the reworded question and the register row (including "Why it would matter"; Q3 left out on purpose); decision 7.11 (first and third bullets merged by the author); the script name `analysis/05_geography.sql`; the reading rule; the "same pattern" criterion; the minimum sizes with the both-years rule and the "most" rule; no sections beyond section 6.

Reviewer-driven changes (`conclusions-reviewer` report on the draft): the country-mix counterfactual is dropped in favour of the side-by-side table of order share and AOV by country and year with the total (point 3); section D is reduced to a price-list consistency check by product and month with no country join, named "price-list consistency (not a currency test)", on the Q2 section I definition of price; if prices vary, the variation is reported and Q5 stops there (points 2, 10); the reading rule for currency (point 1); a criterion for "same pattern" fixed before the run (point 4); two bases for the customer groups, each with its check (point 5); the snapshot caveat and the timing caveat (point 6); minimum sizes with the reason stated as sensitivity, the both-years rule, 30 Bike orders for the Bike AOV and "most" = more than half of the countries (point 7); the 2011-2012 model-mix caveat (point 8); the NULL-country check and the `N/A` share by year (point 9); Q4 section A figures cited (point 11); section A timed first and a 10-minute stop for every section (point 11). The decision is recorded as decision 7.11 in `docs/decisions.md`.

Post-run addition (author's request, after the output was read): the findings add two derived counts, orders per customer in 2013 by country (observation 6) and orders per active customer within each customer group (observation 8). They are computed from sections A2, C1 and C2 and need no new query. They are labelled in the findings as derived after the run, counts only, and not a repeat-purchase measure. Decision 7.11 is not changed.

If a section E check is not OK, or the "most" rule applies, or a section exceeds 10 minutes, work stops and the author is told before any findings are written.

## 9. Definition of done (from `CLAUDE.md`)

Header, control totals with OK/MISMATCH, run with `scripts\run_analysis.ps1 -Script analysis\05_geography.sql -DatabaseName DataWarehouse_Test`, saved output, a Q5 section in `findings.md` checked by `findings-verifier` (at most 3 passes), and the register row, README table, Current status and decision 7 (7.11) updated. No commits unless asked.

