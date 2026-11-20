from pathlib import Path
import pandas as pd

# 根据脚本位置找到项目根目录
root = Path(__file__).resolve().parents[1]
df = pd.read_csv(root / "data" / "raw" / "events.csv")

print("原始数据前5行：")
print(df.head().to_string(index=False))

# 汇总为每个用户一行，记录全期是否发生过各类事件
flags = (
    df.assign(
        has_view=df["event"].eq("view"),
        carted=df["event"].eq("addtocart"),
        bought=df["event"].eq("transaction"),
    )
    .groupby("visitorid")[["has_view", "carted", "bought"]]
    .max()
)

viewers = int(flags["has_view"].sum())
carters = int(flags["carted"].sum())
buyers = int(flags["bought"].sum())

view_and_cart = int(
    (flags["has_view"] & flags["carted"]).sum()
)

print("\n用户级统计：")
print(f"事件行数：{len(df):,}")
print(f"全部用户数：{len(flags):,}")
print(f"浏览用户数：{viewers:,}")
print(f"加购用户数：{carters:,}")
print(f"购买用户数：{buyers:,}")
print(f"既浏览又加购的用户数：{view_and_cart:,}")

print(f"\n原版全期加购比值：{carters / viewers:.6%}")
print(f"浏览人群内全期加购比例：{view_and_cart / viewers:.6%}")
