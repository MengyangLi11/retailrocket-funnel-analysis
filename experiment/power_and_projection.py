"""
Sample size, test duration and minimum detectable effect for the
product-discovery A/B test. Standard library only.

Inputs come from experiment/key_numbers.json (written by
scripts/build_outputs.py), so every number traces back to the data.

    python experiment/power_and_projection.py
"""
import json
import math
from pathlib import Path
from statistics import NormalDist

HERE = Path(__file__).resolve().parent
k = json.loads((HERE / "key_numbers.json").read_text())

ALPHA, POWER = 0.05, 0.80          # two-sided test, 80% power
SPLIT = 0.5                        # 50/50 control vs variant
z = NormalDist().inv_cdf
Z_A, Z_B = z(1 - ALPHA / 2), z(POWER)

p0 = k["carters"] / k["viewers"]           # baseline view-to-cart (2.69%)
weekly_traffic = k["new_viewers_per_week"]   # ~71.8k new viewers/week


def n_per_arm(p1: float, rel_lift: float) -> int:
    """Two-proportion z-test sample size per arm."""
    p2 = p1 * (1 + rel_lift)
    pbar = (p1 + p2) / 2
    num = (Z_A * math.sqrt(2 * pbar * (1 - pbar))
           + Z_B * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))) ** 2
    return math.ceil(num / (p2 - p1) ** 2)


def mde_for_n(p1: float, n: int) -> float:
    """Smallest relative lift detectable with n visitors per arm (bisection)."""
    lo, hi = 0.001, 2.0
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (lo, mid) if n_per_arm(p1, mid) <= n else (mid, hi)
    return hi


print(f"Baseline view-to-cart: {p0:.3%}   |   traffic: {weekly_traffic:,.0f} new viewers/week\n")

print("Scenario projections (from sql/05 section 5.3)")
for s in k["scenarios"]:
    print(f"  {s['scenario']:<13} reach {s['reach']:.0%}  causal {s['causal_share']:.0%}"
          f"  ->  +{s['relative_lift_pct']:.1f}%  ({s['baseline_pct']:.2f}% -> {s['projected_pct']:.2f}%)")

print("\nSample size per arm (alpha 0.05 two-sided, power 0.80)")
print(f"  {'rel. lift':>9} {'target':>8} {'n / arm':>9} {'total':>9} {'days @100% traffic':>19}")
for rel in (0.05, 0.09, 0.10, 0.15, 0.19):
    n = n_per_arm(p0, rel)
    days = 2 * n / (weekly_traffic / 7)
    print(f"  {rel:>9.0%} {p0*(1+rel):>8.2%} {n:>9,} {2*n:>9,} {days:>19.1f}")

n14 = int(weekly_traffic * 2 * SPLIT)
print(f"\nFixed 14-day run: ~{n14:,} viewers per arm -> MDE = {mde_for_n(p0, n14):.1%} relative")
print("  => 14 days detects the Central scenario (~19%) with >99% power and")
print("     the Conservative scenario (~9%) at ~80% power.")

# power achieved for the central scenario at 14 days
p2 = p0 * 1.187
se = math.sqrt(p0 * (1 - p0) / n14 + p2 * (1 - p2) / n14)
print(f"  Power for +18.7% at 14 days: {NormalDist().cdf((p2 - p0) / se - Z_A):.4f}")
