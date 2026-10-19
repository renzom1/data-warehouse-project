# Findings

This document records the results of the analyses in this folder and how far each result can be taken. A section is added as each analysis is completed.

## How to read this document

* **Observation:** what the query output directly shows.
* **Inference:** what can reasonably be concluded from the observations, with the reasoning stated.
* **Hypothesis:** a possible explanation that has not been tested or confirmed.
* **Uncertainty:** what the available data cannot settle.
* **Needs additional data:** questions that cannot be answered with this dataset.

All results come from `DataWarehouse_Test`, the database rebuilt from the corrected source files (decisions 6 and 7 in [`docs/decisions.md`](../docs/decisions.md)). Revenue is the sum of `sales_amount`; the source does not state a currency. The analysis conventions (main window 2011–2013, order-level dating, treatment of undated orders) are defined in decision 7.

---

## Q1. How have revenue, units and orders changed over time?

Source: [`01_revenue_trends.sql`](01_revenue_trends.sql). Every section reconciles to the control totals of the fact table (60,398 lines, 27,659 orders, revenue 29,356,250).

| Year | Orders | Lines | Units | Revenue | AOV |
|---|---|---|---|---|---|
| 2011 | 2,216 | 2,216 | 2,216 | 7,075,088 | 3,192.73 |
| 2012 | 3,269 | 3,397 | 3,397 | 5,842,231 | 1,787.16 |
| 2013 | 21,287 | 52,798 | 52,823 | 16,349,836 | 768.07 |

AOV (average order value) is revenue divided by orders.

### Observations

1. **Orders and revenue diverge.**
   * 2011 to 2012: orders increased by 47.5% while revenue decreased by 17.4%. AOV fell by 44.0%.
   * 2012 to 2013: orders increased by 551.2% and revenue increased by 179.9%. AOV fell by 57.0%.
   * Orders genuinely increased in both transitions, but revenue did not grow at the same rate, because AOV declined. The cause of the decline in AOV is not known.
2. **AOV changes in steps.**
   * It falls from about 3,015 in December 2011 to about 1,966 in January 2012. Across the twelve months of 2012 it ranges from about 1,660 to about 1,966.
   * It falls again from about 1,759 in December 2012 to about 1,357 in January 2013 and about 543 in February 2013. From March to December 2013 it ranges from about 621 to about 855.
3. **The relationship between lines and orders changes in December 2012.**
   * In every month up to November 2012, the number of lines equals the number of orders.
   * December 2012 is the first month with more lines than orders (483 lines, 355 orders).
   * Lines per order are 1.00 in 2011, 1.04 in 2012 and 2.48 in 2013 (52,798 lines in 21,287 orders).
   * In this dataset, units and lines track each other closely: 2,216 units for 2,216 lines in 2011, 3,397 for 3,397 in 2012, and 52,823 units for 52,798 lines in 2013. This is specific to this dataset. It should not be read as a general rule that more lines per order means more units per order.
   * The relationship between lines and orders does not, by itself, explain the decline in AOV.
4. **January 2014 is incomplete and not comparable with full months or years.** It covers only 1–28 January, which is why it is kept out of annual comparisons and treated as context. It has 871 orders, 1,970 lines, revenue of 45,642 and an AOV of 52.40. Monthly revenue in 2013 never fell below 771,218, and monthly AOV never fell below 543.
   * Its short duration does not, by itself, explain the low AOV. AOV measures revenue relative to the number of orders, and the unusually low value remains unexplained.
5. **Seasonal shares vary across years.**
   * June holds a relatively high share of the year's revenue in all three years: 10.4% in 2011, 9.5% in 2012 and 10.0% in 2013.
   * The last quarter holds 28.8% of the year's revenue in 2011, 29.1% in 2012 and 32.6% in 2013.
   * January and February differ across years: 6.6% and 6.6% in 2011, 8.5% and 8.7% in 2012, 5.2% and 4.7% in 2013.
   * In 2013, monthly orders rise from 632 in January to 2,192 in December.
   * Three complete years, with structural differences between them, are not enough to establish a stable seasonal pattern.
6. **Undated orders are negligible and accounted for.** Two orders have no usable date: 3 lines and revenue of 34 (decision 7.2).
7. **2013 weighs heavily in the whole-period totals.** It accounts for 77.0% of orders, 87.4% of lines and 55.7% of revenue.

### Arithmetic decomposition (descriptive only)

The change in revenue between two years can be split exactly into an effect of the change in the number of orders and an effect of the change in AOV:

| Transition | Revenue change | Effect of more orders | Effect of higher AOV |
|---|---:|---:|---:|
| 2011 to 2012 | −1,232,857 | +3,361,944 | −4,594,801 |
| 2012 to 2013 | +10,507,605 | +32,201,076 | −21,693,471 |

This is a mathematical breakdown of the revenue change, not a causal explanation. It describes the size of each component, not why orders or AOV changed.

### Inferences

* In this dataset, the number of orders is not a reliable stand-in for revenue, because the two metrics moved at very different rates in both transitions.
* The step changes in AOV and the change in the relationship between lines and orders occurred within the period from December 2011 to February 2013. Their causes remain unknown and warrant further investigation.

### Hypothesis (not established)

* Changes in the product mix (what is sold, and in which combinations) may explain part of the decline in AOV and of the change in order structure. This has not been tested. Q2 will investigate it by comparing category and product-line shares by year, revenue per line, and each category's contribution to the year-over-year changes in lines and revenue. Even if product-mix changes are found, they will not necessarily explain the full decline in AOV.
* Price changes, and changes in how the dataset itself was produced, are other possible explanations. They are not established causes and cannot be ruled out with this data.

### Uncertainty

* The causes of the changes in AOV and in order structure.
* The cause of the unusually low AOV in January 2014.
* Whether a stable seasonal pattern exists, given the limited number of complete years and the effect of within-year growth, especially in 2013.

### Needs additional data

* Product and price history, to distinguish product-mix changes from price changes.
* Information about how the data was generated or extracted, to investigate the step changes and the January 2014 values.
* More complete years, to assess seasonality.

### Implications for later analyses

* Full-period aggregates remain valid descriptions of the dataset. Because 2013 accounts for most orders and lines and a large share of revenue, aggregate results are strongly shaped by 2013 and should be interpreted alongside year-level comparisons.
