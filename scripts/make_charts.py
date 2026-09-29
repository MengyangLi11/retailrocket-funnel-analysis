"""
Draw the README charts and the Power BI dashboard mockup from the
outputs of build_outputs.py.

    python scripts/make_charts.py
"""
import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.patches import FancyBboxPatch

ROOT = Path(__file__).resolve().parents[1]
IMG = ROOT / "images"
IMG.mkdir(exist_ok=True)
k = json.loads((ROOT / "experiment" / "key_numbers.json").read_text())
fact = pd.read_csv(ROOT / "powerbi" / "data" / "fact_visitor_cohort.csv")
weekly = pd.read_csv(ROOT / "powerbi" / "data" / "weekly_funnel.csv")

# palette (validated reference palette, light mode)
SURFACE, INK, INK2, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#8a8984", "#e6e5e1"
BLUE, BLUE_LIGHT, ORANGE = "#2a78d6", "#86b6ef", "#eb6834"

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 11, "axes.edgecolor": GRID,
    "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "axes.spines.top": False, "axes.spines.right": False,
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
})


def title(ax, t, sub):
    ax.set_title(t, loc="left", fontsize=14, fontweight="bold", color=INK, pad=26)
    ax.text(0, 1.02, sub, transform=ax.transAxes, fontsize=10.5, color=INK2, va="bottom")


# ---------------------------------------------------------------- depth data
viewers = fact[fact.viewers > 0]
depth = (viewers.groupby("items_viewed_capped")[["viewers", "carters_with_view"]].sum())
depth["rate"] = 100 * depth.carters_with_view / depth.viewers
labels = [str(i) for i in depth.index[:-1]] + ["10+"]


def draw_funnel(ax):
    stages = ["Viewed a product", "Added to cart", "Purchased"]
    vals = [k["viewers"], k["carters"], k["buyers"]]
    ax.barh(stages[::-1], vals[::-1], color=BLUE, height=0.35)
    notes = ["100%", f"{k['view_to_cart_pct']:.1f}% of viewers", f"{k['cart_to_buy_pct']:.0f}% of carters"]
    for i, (v, n) in enumerate(zip(vals[::-1], notes[::-1])):
        ax.text(v + vals[0] * 0.015, i, f"{v:,}  ·  {n}", va="center", color=INK, fontsize=10.5)
    ax.set_xlim(0, vals[0] * 1.45)
    ax.xaxis.set_visible(False)
    ax.spines["bottom"].set_visible(False)
    ax.tick_params(axis="y", length=0)


def draw_depth(ax, annotate=True):
    colors = [ORANGE] + [BLUE] * (len(depth) - 1)
    ax.bar(labels, depth.rate, color=colors, width=0.6)
    for x, r in zip(labels, depth.rate):
        if x in ("1", "2", "5", "10+"):
            ax.text(x, r + 0.6, f"{r:.1f}%", ha="center", color=INK, fontsize=10)
    ax.set_xlabel("Distinct products viewed")
    ax.set_ylabel("Add-to-cart rate (%)")
    ax.yaxis.grid(True, color=GRID, linewidth=1)
    ax.set_axisbelow(True)
    ax.set_ylim(0, depth.rate.max() * 1.18)
    if annotate:
        ax.annotate(f"{k['single_item_share_pct']:.0f}% of viewers\nstop at one product",
                    xy=(0.1, depth.rate.iloc[0] + 1.6), xytext=(0.4, 24), color=INK, fontsize=10.5,
                    arrowprops=dict(arrowstyle="-", color=MUTED, lw=1))


# 1. funnel + depth (hero chart for README)
fig, (a1, a2) = plt.subplots(1, 2, figsize=(13, 4.8), gridspec_kw={"width_ratios": [1, 1.15]})
draw_funnel(a1)
title(a1, "The leak is view → cart", "Unique visitors, May–Sep 2015 · 2.75M events")
draw_depth(a2)
title(a2, "Conversion climbs with every product viewed",
      f"1 product: {k['single_item_v2c_pct']:.1f}%  ·  2+ products: {k['multi_item_v2c_pct']:.1f}%")
fig.tight_layout(w_pad=4)
fig.savefig(IMG / "funnel_and_depth.png", dpi=160)
plt.close(fig)

# 2. weekly trend
wk = weekly[weekly.days_in_week == 7].copy()
wk["rate"] = 100 * wk.carters / wk.viewers
wk["week_start"] = pd.to_datetime(wk.week_start)
fig, ax = plt.subplots(figsize=(11, 3.8))
ax.plot(wk.week_start, wk.rate, color=BLUE, lw=2, marker="o", ms=5,
        markeredgecolor=SURFACE, markeredgewidth=2)
ax.axhspan(wk.rate.min(), wk.rate.max(), color=BLUE, alpha=0.08, lw=0)
ax.set_ylim(0, 4)
ax.set_ylabel("View-to-cart (%)")
ax.yaxis.grid(True, color=GRID)
ax.set_axisbelow(True)
ax.text(wk.week_start.iloc[-1], wk.rate.iloc[-1] + 0.35, f"{wk.rate.iloc[-1]:.1f}%", ha="center", color=INK)
title(ax, "It's structural: 19 weeks inside a 2.3–3.0% band",
      f"Weekly viewers moved {wk.viewers.min()/1000:.0f}k–{wk.viewers.max()/1000:.0f}k; the rate didn't")
fig.tight_layout()
fig.savefig(IMG / "weekly_trend.png", dpi=160)
plt.close(fig)

# 3. A/B projection scenarios
sc = pd.DataFrame(k["scenarios"]).sort_values("relative_lift_pct")
fig, ax = plt.subplots(figsize=(10, 3.6))
cols = [BLUE if s == "Central" else BLUE_LIGHT for s in sc.scenario]
ax.barh(sc.scenario, sc.relative_lift_pct, color=cols, height=0.5)
for i, r in enumerate(sc.itertuples()):
    ax.text(r.relative_lift_pct + 0.5, i,
            f"+{r.relative_lift_pct:.1f}%   ({r.baseline_pct:.2f}% → {r.projected_pct:.2f}%)   "
            f"reach {r.reach:.0%}, causal {r.causal_share:.0%}", va="center", color=INK, fontsize=10)
ax.axvline(9.1, color=MUTED, lw=1)
ax.text(9.1, -0.62, " 14-day test MDE 9.1%", color=INK2, fontsize=9.5, va="center")
ax.set_xlim(0, 50)
ax.set_ylim(-0.8, len(sc) - 0.5)
ax.set_xlabel("Projected relative lift in view-to-cart (%)")
ax.tick_params(axis="y", length=0)
title(ax, "Projected lift from the product-discovery test",
      "Central case: 1 in 6 single-item visitors browse on and convert like 2–4-item browsers")
fig.tight_layout()
fig.savefig(IMG / "ab_projection.png", dpi=160)
plt.close(fig)

# 4. Power BI dashboard mockup (layout reference for the real .pbix)
fig = plt.figure(figsize=(16, 9))
fig.text(0.03, 0.95, "RetailRocket · Purchase Funnel", fontsize=20, fontweight="bold", color=INK)
fig.text(0.03, 0.915, "MOCKUP of Page 1 — build in Power BI with powerbi/BUILD_GUIDE.md",
         fontsize=10.5, color=ORANGE)
fig.text(0.70, 0.93, "[ Date slicer ]   [ Depth bucket ]   [ New / Returning ]", fontsize=10.5, color=INK2)
tiles = [("Viewers", f"{k['viewers']/1e6:.2f}M"), ("View → cart", f"{k['view_to_cart_pct']:.1f}%"),
         ("Cart → purchase", f"{k['cart_to_buy_pct']:.1f}%"), ("View → purchase", f"{k['view_to_buy_pct']:.2f}%"),
         ("Single-item viewers", f"{k['single_item_share_pct']:.0f}%")]
for i, (lab, val) in enumerate(tiles):
    x = 0.03 + i * 0.19
    fig.patches.append(FancyBboxPatch((x, 0.76), 0.175, 0.12, boxstyle="round,pad=0,rounding_size=0.01",
                                      transform=fig.transFigure, fc="white", ec=GRID))
    fig.text(x + 0.012, 0.845, lab, fontsize=11, color=INK2)
    fig.text(x + 0.012, 0.785, val, fontsize=24, fontweight="bold", color=INK)
a1 = fig.add_axes([0.13, 0.40, 0.30, 0.28]); draw_funnel(a1)
a1.set_title("Funnel (unique visitors)", loc="left", fontsize=12, fontweight="bold", color=INK)
a2 = fig.add_axes([0.53, 0.40, 0.44, 0.28]); draw_depth(a2, annotate=False)
a2.set_title("Add-to-cart rate by products viewed", loc="left", fontsize=12, fontweight="bold", color=INK)
a3 = fig.add_axes([0.06, 0.07, 0.91, 0.22])
a3.plot(wk.week_start, wk.rate, color=BLUE, lw=2, marker="o", ms=4, markeredgecolor=SURFACE)
a3.set_ylim(0, 4); a3.yaxis.grid(True, color=GRID); a3.set_axisbelow(True)
a3.set_ylabel("View → cart %")
a3.set_title("Weekly view-to-cart rate", loc="left", fontsize=12, fontweight="bold", color=INK)
fig.savefig(ROOT / "powerbi" / "dashboard_mockup.png", dpi=110)
plt.close(fig)
print("charts written")
