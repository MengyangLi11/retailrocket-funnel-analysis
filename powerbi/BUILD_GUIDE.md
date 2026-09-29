# Power BI Dashboard: Build Guide

Everything needed to build the dashboard is in this folder. The target layout is in [`dashboard_mockup.png`](dashboard_mockup.png).

| File | What it is |
|---|---|
| `data/fact_visitor_cohort.csv` | Main fact table: one row per first-seen date × items viewed × new/returning (2,926 rows, covers all 1,407,580 visitors) |
| `data/weekly_funnel.csv` | Distinct viewers, carters and buyers per ISO week |
| `data/daily_events.csv` | Event volume per day and type |
| `data/ab_scenarios.csv` | The four lift scenarios from `sql/05` |
| `measures.dax` | Every DAX measure, with the expected value noted beside each one |

The CSVs come from `sql/06_powerbi_exports.sql` (MySQL) or `scripts/build_outputs.py` (Python). Both give identical numbers.

> **On a Mac?** Power BI Desktop is Windows-only. Options include a Windows machine, a Windows VM or cloud PC, or authoring directly in the Power BI Service (app.powerbi.com) if your account supports it. Save the result as `RetailRocket_Funnel.pbix` in this folder.

---

## 1. Load and model (about 10 minutes)

1. **Get data > Text/CSV** and load all four CSVs.
2. In Power Query, set types:
   - `fact_visitor_cohort`: `first_seen_date` = Date; all counts = Whole number
   - `weekly_funnel`: `week_start` = Date
   - `daily_events`: `event_date` = Date
3. Create the **Date** table, the **Depth Buckets** table and a **_Measures** table from `measures.dax`.
4. Relationships (Model view):
   - `Date[Date]` 1 → * `fact_visitor_cohort[first_seen_date]`
   - `Depth Buckets[depth_bucket]` 1 → * `fact_visitor_cohort[depth_bucket]`
5. Mark `Date` as the date table. Set `Depth Buckets[depth_bucket]` to **Sort by column → Sort**.
6. Add all measures from `measures.dax`, then the three What-if parameters (**Reach**, **Causal Share**, **Target Lift**).

**Check before building visuals.** Put these on a card and compare them with the values in the comments: Viewers **1,404,179**, Carters **37,722**, View to Cart % **2.69%**, Single-Item Share % **79.6%**.

---

## 2. Page 1: Funnel Overview (matches the mockup)

| Visual | Fields |
|---|---|
| 5 KPI cards | Viewers · View to Cart % · Cart to Purchase % · View to Purchase % · Single-Item Share % |
| Funnel chart | A small table with Stage/Value (Viewed, Added to cart, Purchased) or three measures in a funnel visual |
| Clustered column | X: `fact_visitor_cohort[items_viewed_capped]` (filter out 0) · Y: **Cart Rate (viewers)**. Highlight the "1" bar in orange. |
| Line chart | X: `weekly_funnel[week_start]` · Y: **Weekly View to Cart %** (filter `days_in_week = 7`) |
| Slicers | `Date[Date]` (between), `Depth Buckets[depth_bucket]`, `fact_visitor_cohort[is_returning]` |

**Title:** *"2.7% of viewers add to cart, and 80% of viewers leave after one product."*

## 3. Page 2: Why it leaks (browse depth)

- Table: depth_bucket · Viewers · % of viewers · Cart Rate (viewers) · carters share
- Card: **Multi vs Single Multiplier** (~5.2x)
- Card: **Avg Items Viewed** for buyers vs non-buyers. Use the SQL result (9.61 vs 1.45) as a text box, because buyer-level depth is not in the cohort fact.
- Donut: Returning Visitor % and Repeat Buyer %

## 4. Page 3: A/B test planner

- Slicers for the **Reach** and **Causal Share** parameters
- Cards: **Projected Extra Carters**, **Projected Relative Lift %**, **Projected View to Cart %**
- Clustered bar from `ab_scenarios.csv`: scenario vs relative_lift_pct
- **Target Lift** slicer, plus cards for **Sample Size per Arm** and **Test Days at Full Traffic**
- Text box summarizing the hypothesis, primary metric, guardrails and success criteria from `experiment/ab_test_plan.md`

At the defaults (reach 17%, causal 100%) the page should show **+18.7%** and **3.19%**. With a 19% target lift, it should show **17,202 per arm**.

---

## 5. Publish to the repo

1. Save `RetailRocket_Funnel.pbix` into `powerbi/`.
2. Export a screenshot of each page to `images/powerbi_page1.png` (and page2, page3).
3. In the README, replace the mockup image link with `images/powerbi_page1.png`.
4. Optional: **Publish to web** in the Power BI Service and add the public link to the README.
