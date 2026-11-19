"""
export_views.py
Connects to the local ecommerce_analytics database and exports every
dashboard view to CSV (UTF-8) for Power BI, Excel or the HTML report.

Usage:  python sql/export_views.py
"""
import csv
from pathlib import Path

import pymysql

OUT = Path(__file__).resolve().parent.parent / "exports"
OUT.mkdir(parents=True, exist_ok=True)

VIEWS = [
    "vw_order_facts",
    "vw_monthly_revenue",
    "vw_customer_rfm",
    "vw_rfm_segment_summary",
    "vw_cohort_retention",
    "vw_delivery_facts",
    "vw_delivery_by_state",
    "vw_delivery_monthly",
]


def main() -> None:
    conn = pymysql.connect(
        host="127.0.0.1", port=3307, user="root", password="root",
        database="ecommerce_analytics", charset="utf8mb4",
    )
    try:
        with conn.cursor() as cur:
            for view in VIEWS:
                cur.execute(f"SELECT * FROM {view}")
                cols = [d[0] for d in cur.description]
                rows = cur.fetchall()
                path = OUT / f"{view}.csv"
                with path.open("w", newline="", encoding="utf-8") as fh:
                    writer = csv.writer(fh)
                    writer.writerow(cols)
                    writer.writerows(rows)
                print(f"{view:<26} {len(rows):>7,} rows -> {path.name}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
