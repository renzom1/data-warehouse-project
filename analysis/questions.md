# Business questions

The register of the questions this analytical layer sets out to answer. Each question is worded once, here; the header of the analysis script and the heading of its section in [`findings.md`](findings.md) quote it.

* **Status:** `answered` (script run, findings written and verified), `open` (not started), `proposed` (candidate, scope not confirmed with the author).
* **Answer in one line:** only what the data shows, at the same level of certainty as `findings.md`. Anything inferred or hypothetical is marked as such, and the full qualification is in the findings section.
* Before writing a new script, add or pick its question here, then present the plan ([`CLAUDE.md`, Definition of done](../CLAUDE.md#definition-of-done)).

## Answered

| ID | Business question | Script | Findings | Answer in one line |
|---|---|---|---|---|
| Q0 | Which data-quality facts and control totals does every other analysis depend on? (Not a business question; it fixes the conventions.) | [`00_data_profile.sql`](00_data_profile.sql) | [decision 7](../docs/decisions.md#7-analytical-conventions-established-by-the-data-profiling) | Conventions for the analysis window, order dating and cohorts; no business result. |
| Q1 | How have revenue, units and orders changed over time, and is there seasonality? Is revenue growth driven by more orders or by higher order value? | [`01_revenue_trends.sql`](01_revenue_trends.sql) | [Q1](findings.md#q1-how-have-revenue-units-and-orders-changed-over-time) | Orders and revenue diverge: orders grew in both year-over-year steps while AOV fell, so orders are not a stand-in for revenue. The cause of the AOV decline is not known. |
| Q2 | Could changes in the product mix help explain the decline in AOV, and does the mix change at the same time as the AOV steps? | [`02_product_mix.sql`](02_product_mix.sql) | [Q2](findings.md#q2-does-product-mix-help-explain-the-decline-in-aov) | The 2012→2013 AOV decline coincides with a large shift in product mix, but the category mix does not account for all of it; the 2011→2012 step is not a category-mix effect. An association, not a cause. The customer question left open in Q2 is answered in Q3. |
| Q3 | Do customers place a second order, how quickly, and does that differ by first-order year or by kind of first order? Are the 2013 No bikes orders first orders, or later orders of customers who already bought a Bike? | [`03_repeat_purchasing.sql`](03_repeat_purchasing.sql) | [Q3](findings.md#q3-do-customers-place-a-second-order-how-quickly-and-who-buys-the-2013-no-bikes-orders) | No customer has both a Bike order and a No bikes order, so the 2013 No bikes orders are not follow-on orders of Bike customers. Cohort differences are not read as cohort effects, because no second order occurs before Q4 2012. |

## Proposed

Candidates, not commitments. Each needs its scope confirmed with the author before a plan is written.

| ID | Business question | Why it would matter |
|---|---|---|
| Q4 | Concentration: what share of revenue depends on a small group of customers or products? | Shows whether the totals and the AOV depend on a few buyers or items. |
| Q5 | Geography: how are customers and revenue distributed across countries? | Shows whether the Q1–Q3 patterns hold everywhere or come from one place. |
| Q6 | Demographics: do spending patterns differ by gender, marital status or age? | Uses the customer attributes in `gold.dim_customers` (birthdate conventions in [decision 7.3](../docs/decisions.md#73-suspicious-historical-birthdates)). |
| Q7 | Recurrence: how can customers be segmented with an RFM analysis? | Builds on Q3, with the limits Q3 found (few second orders, short history). |
| Q8 | Composition: which categories, subcategories and products drive revenue and units sold? | Original question 2. Q2 describes the mix only in service of the AOV question, so this one is not answered as such. |

## Original questions and what happened to them

The project started from six questions (wording translated from the author's Spanish list). The register above replaces that list; this table keeps the mapping so nothing is lost.

| # | Original question | Now |
|---|---|---|
| 1 | Sales evolution: is revenue growth due to more orders or a higher average value per order? | Q1, answered. |
| 2 | Composition: which categories, subcategories and products drive revenue and units sold? | Q8, proposed. Q2 covers the mix by category and subcategory only as it relates to AOV. |
| 3 | Concentration: what share of revenue depends on a small group of customers or products? | Q4, proposed. |
| 4 | Geography: how are customers and revenue distributed across countries? | Q5, proposed. |
| 5 | Demographics: are there differences in spending patterns by gender, marital status or age? | Q6, proposed. |
| 6 | Recurrence: how many customers buy again, and how can they be segmented with RFM? | The first half became Q3, answered; RFM is Q7, proposed. |

Two questions in the register were not in the original list. Q2 came from the hypothesis Q1 left open (product mix and the fall in AOV). Q3 was reworded on purpose: the original "how many customers buy again" became a stronger question about the time to the second order by cohort and about the sequence of the 2013 No bikes orders, which tests the Q2 hypothesis.

## Maintenance

* New question: add the row here first, with status `proposed` or `open`.
* Analysis done: move the row to Answered with its script and findings link, and write the one-line answer from the findings.
* A later analysis changes what an earlier answer can claim: mark it `Under revision` in the answer cell until its findings section is updated.
