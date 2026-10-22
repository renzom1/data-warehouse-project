# Q2 plan: product mix and the decline in AOV

**Status: approved and implemented** (`02_product_mix.sql`, results in `findings.md`). Changes made at approval: section E also shows subcategories by year (E2); a simple like-for-like unit price table was added as section I; control totals became section J. Sections G1-G4 and the layout in section 5 below otherwise stand. This file is kept as the review record.

---

## 1. Business question

Could changes in the product mix help explain the decline in average order value (AOV) seen in Q1? Does the mix change at the same time as the AOV steps?

This is the Q1 hypothesis ([`findings.md`](findings.md#hypothesis-not-established)). It is **not established**: mix changes may explain part of the decline, not necessarily all of it. A mix effect is an association, not a cause.

## 2. Starting point (Q1, [`output/01_revenue_trends.txt`](output/01_revenue_trends.txt))

| Year | Orders | Lines per order | Revenue per line | AOV |
|---|---|---|---|---|
| 2011 | 2,216 | 1.00 | 3,192.73 | 3,192.73 |
| 2012 | 3,269 | 1.04 | 1,719.82 | 1,787.16 |
| 2013 | 21,287 | 2.48 | 309.67 | 768.07 |

AOV = lines per order x revenue per line (identity, not an explanation). Revenue per line fell about 46% (2011 to 2012) and about 82% (2012 to 2013), derived from the table. Q2 asks what sits behind the fall in revenue per line, product-wise.

## 3. Data and limits

* Source: `gold.fact_sales` joined to `gold.dim_products` (`category`, `subcategory`, `product_line`). Gold only; Silver cost versions are not used (cost is not price).
* Exploratory check (read-only, `DataWarehouse_Test`): all 60,398 fact lines match a product (no orphans). By raw `order_date`, 2011 sells Bikes only; Accessories (106 lines) and Clothing (22) first appear in 2012; in 2013 Accessories 34,393, Clothing 8,685 and Bikes 9,704 lines. These figures are a reason for the design below, **not findings**; they will be produced by the script and checked against its saved output.
* Product attributes are the current version only. Price is the realized price (`sales_amount / quantity`); list price and discounts cannot be separated. Volumes are uneven (2011 and 2012 are small), so every share is shown next to its counts.

## 4. Conventions and definitions

Decision 7 applies without change: window 2011-2013 (7.1), order date = `MIN(order_date) OVER (PARTITION BY order_number)` with the 2 undated orders in their own row (7.2), revenue/order/AOV as in `CLAUDE.md`, read-only `SELECT`, no surrogate keys reported. Row counts are compared after each join (fan-out check).

Q2-specific metrics: lines, units, revenue; orders containing a category (not additive across categories); revenue per line; average unit price = revenue / units; lines per order; share of the year's lines / units / revenue; share change in percentage points against the true previous year (zero rows are generated for years without sales); distinct products sold (counted, never reported by key); contribution of a category to the change in lines or revenue between consecutive years.

Lines are the base for the AOV factorization; units for prices (almost identical in this dataset; stated, not assumed).

**Order classes** (new definition, fixed now because the exploration shows only three categories exist): each order is classified by the categories in its lines as `Bikes only`, `Bikes + other`, or `No bikes`. No other convention is needed: no weighting scheme is used in this scope.

## 5. Method and script sections (`analysis/02_product_mix.sql`)

Structure copied from [`01_revenue_trends.sql`](01_revenue_trends.sql). The header contains: business question, data required, grain, definitions, method, caveats, control totals and run command. One block comment per section.

| Section | Content | Grain |
|---|---|---|
| A | AOV factorization: lines per order and revenue per line, by year and by month (main window) | year; month |
| B | Category summary, whole dataset: lines, orders containing, units, revenue, share, revenue per line, average unit price, products sold vs products in the dimension | category |
| C | Category mix by year, with shares, counts and share change (pp) | category x year |
| D | Contribution of each category to the change in lines and in revenue between consecutive years | category x transition |
| E | Subcategory ranking, whole dataset | subcategory |
| F | Product-line mix by year | product line x year |
| G | Assortment and timing: distinct products per year and category; first month of sales per category; monthly category mix around the AOV breaks (Dec 2011 to Jan 2012; Dec 2012 to Feb 2013) | year x category; category; month x category |
| H | Order composition: order class share, AOV and lines per order by year | order class x year |
| I | Control totals: `OK` / `MISMATCH` against **60,398 lines / 27,659 orders / revenue 29,356,250 / units 60,423**; category, class and period totals must add up, undated orders in their own row | check |

Questions each section answers, and what it cannot answer:

| Explanation | Addressed by | Limit |
|---|---|---|
| Product mix | B-G | Association, not cause |
| Order structure (more lines per order) | A, H | Separates "different kinds of orders" from "same orders worth less" |
| Price change on the same products | G, partly (average unit price by category and year) | Only an indication: a product-level price/mix split is not in this scope |
| Customer or country mix | Not Q2 | Later geography / demographics analyses |
| How the dataset was produced (categories appearing abruptly) | G (timing) | Observation only; cannot be tested |

## 6. Scope decisions for the author

| # | Decision | Proposal |
|---|---|---|
| 1 | **Stage 2** (product-level price/mix decomposition, order-class shift-share) | **Out of this Q2.** Done only as a separately approved extension if sections A-H leave the price-vs-mix question open. Keeps one defensible analysis, as the project goal asks. |
| 2 | Order classes (section 4) | Use the three classes above. |
| 3 | Lines for AOV, units for price | Yes. |
| 4 | Q1 "Needs additional data" item ("Product and price history") | Narrow to list price, discounts and price history in the Q2 findings, since realized price is available. |
| 5 | New convention in decision 7 | Only the order-class definition (as 7.8), written **before** the script is run. |

Inherited and already decided: window, order dating, database, read-only, no new objects, no Python or visualization.

## 7. Definition of done (from `CLAUDE.md`)

1. `analysis/02_product_mix.sql` has the standard header.
2. It ends with the control-totals section (section I), printing `OK` / `MISMATCH`; every section ties back to the control totals.
3. Run with `scripts\run_analysis.ps1 -Script analysis\02_product_mix.sql -DatabaseName DataWarehouse_Test`; it passes and `analysis/output/02_product_mix.txt` is saved.
4. [`findings.md`](findings.md) gets a Q2 section: Observations / Inferences / Hypotheses / Uncertainty / Needs additional data. Every number appears in the saved output or is derived from it with the arithmetic shown.
5. Updated: decision 7 (new 7.8, order classes), the README analysis table, and "Current status" in `CLAUDE.md`.

Out of scope: changes to Silver or Gold, new database objects, any use of `DataWarehouse`.
