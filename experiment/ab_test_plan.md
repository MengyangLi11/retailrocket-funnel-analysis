# A/B Test Plan: "You may also like" on the product page

**Owner:** Gurmesh Singh  ·  **Status:** Designed, not yet run (the RetailRocket data is historical)
**Inputs:** [`sql/05_experiment_baseline_and_projection.sql`](../sql/05_experiment_baseline_and_projection.sql), [`power_and_projection.py`](power_and_projection.py), [`key_numbers.json`](key_numbers.json)

---

## 1. Problem

Only **2.7%** of product viewers ever add anything to cart, and the rate has stayed between 2.3% and 3.0% for 19 straight weeks. The driver is browsing depth:

| Items viewed | Share of viewers | View-to-cart |
|---|---|---|
| 1 item | 79.6% | 1.32% |
| 2 to 4 | 17.6% | 5.04% |
| 5 to 9 | 2.1% | 14.55% |
| 10+ | 0.7% | 30.69% |

Visitors who view 2+ items add to cart at 6.85%, about 5x the single-item rate. Because 4 in 5 viewers leave after one product (90% after a single page view), the blended rate collapses. Checkout is not the bottleneck: 31% of carters go on to buy.

## 2. Hypothesis

> **If** we add a "You may also like" strip of related products to the product page, **then** more single-item visitors will view a second product, **which will** raise the visitor-level view-to-cart rate from 2.69% to about 3.19% (+19% relative), **because** browsing depth is the strongest behavioral predictor of adding to cart in this store.

- **H0:** view-to-cart (variant) = view-to-cart (control)
- **H1:** view-to-cart (variant) ≠ view-to-cart (control), two-sided

## 3. Design

| | |
|---|---|
| Randomization unit | Visitor (`visitorid`, sticky assignment via hashed ID) |
| Who enters the test | Every visitor who loads a product page during the test window |
| Split | 50% control / 50% variant |
| Control (A) | Product page as today |
| Variant (B) | Same page plus a "You may also like" strip (6 to 8 related items, same category first) |
| Attribution window | Actions within 7 days of a visitor's first exposure |
| Duration | **14 days** (two full weekly cycles), fixed in advance, no early stopping |
| Traffic | ~71,800 new viewers per week, so ~71,800 visitors per arm over 14 days |

## 4. Metrics

**Primary metric (decides the test)**

| Metric | Definition | Baseline |
|---|---|---|
| View-to-cart conversion | Exposed visitors with ≥1 `addtocart` ÷ exposed visitors | 2.69% |

**Secondary metrics (explain the result)**

| Metric | Why | Baseline |
|---|---|---|
| Avg distinct items viewed per visitor | Checks that the mechanism worked: people browse more | 1.52 |
| Single-item visitor share | Should fall if the strip works | 79.6% |
| View-to-purchase conversion | Does the lift carry through to orders? | 0.83% |
| Strip click-through rate | Direct engagement with the module | New |

**Guardrail metrics (must not get worse)**

| Guardrail | Threshold that blocks launch |
|---|---|
| Cart-to-purchase rate | Relative drop of more than 5% (baseline 31.1%). Guards against extra carts that are low intent. |
| Product page load time (p75) | Increase of more than 200 ms |
| Sample ratio mismatch | Chi-square p < 0.001 on the 50/50 split, which invalidates the test |
| Bounce rate (single-page sessions) | Any statistically significant increase |

## 5. Sizing: why 14 days

α = 0.05 (two-sided), power = 0.80, baseline 2.69%.

| Relative lift to detect | Target rate | Visitors per arm | Days at full traffic |
|---|---|---|---|
| 19% (central projection) | 3.20% | 17,202 | 3.4 |
| 10% | 2.96% | 59,624 | 11.6 |
| 9% (conservative projection) | 2.93% | 73,270 | 14.3 |

A 14-day run gives ~71.8k visitors per arm, so the **minimum detectable effect is 9.1% relative**. The test would catch the central projection with near-certainty, and still has ~80% power if the true effect is only half as large. Running two full weeks also averages out day-of-week swings.

## 6. Where the 19% projection comes from

A scenario model built on observed conversion by browse depth ([`sql/05`](../sql/05_experiment_baseline_and_projection.sql), section 5.3):

```
extra carters = single-item viewers × reach × causal share × (rate 2-4 items − rate 1 item)
              = 1,118,109 × reach × causal share × (5.04% − 1.32%)
relative lift = extra carters ÷ 37,722 current carters
```

| Scenario | Reach (single-item visitors who browse on) | Causal share of the observed gap | Relative lift | View-to-cart |
|---|---|---|---|---|
| Conservative | 17% | 50% | +9.4% | 2.94% |
| Low reach | 10% | 100% | +11.0% | 2.98% |
| **Central** | **17% (about 1 in 6)** | **100%** | **+18.7% ≈ 19%** | **3.19%** |
| High reach | 25% | 100% | +27.5% | 3.43% |

**Assumptions to be honest about.** Visitors who browse more are partly more motivated to begin with, so not all of the 1.3% vs 5.0% gap is caused by browsing. The conservative row halves it. Reach of 1 in 6 is an assumption that the test itself validates through the secondary metric "single-item visitor share".

## 7. Success criteria (decided before launch)

| Outcome | Decision |
|---|---|
| Primary lift significant (p < 0.05), 95% CI lower bound > 0, and no guardrail breached | **Ship** to 100% |
| Primary lift significant but a guardrail breached | **Don't ship.** Fix the cause (e.g. page speed), then re-test. |
| Not significant, but items viewed and single-item share moved the right way | **Iterate** on the recommendation logic or placement, then re-test |
| Not significant and no movement in browsing depth | **Stop.** The discovery hypothesis is not supported, so revisit the diagnosis. |

## 8. Risks

- **Poor recommendations can hurt.** Pilot at 5% of traffic for 2 days to check for bugs and the SRM before the full 50/50.
- **Novelty effect.** Compare week 1 with week 2 of the variant. If the lift fades, report the week-2 number.
- **No revenue in the dataset.** Impact is framed in conversion, and average order value should be added as a guardrail in production.
