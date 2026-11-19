"""
prep_reviews.py
Cleans olist_order_reviews_dataset.csv so MySQL LOAD DATA can ingest it.

Why this is needed:
  The review comments contain real line breaks and backslashes.
  Raw LOAD DATA either merges or skips those rows, so the file is
  normalised first: comments are flattened to a single line, the file
  is written as UTF-8 with LF line endings and quoted fields.

Output: exports/olist_order_reviews_clean.csv (99,224 rows)

Run:  python sql/prep_reviews.py
"""
from pathlib import Path

import pandas as pd

SRC = Path(r"D:\Analyst project 1\Dataset\olist_order_reviews_dataset.csv")
OUT = Path(__file__).resolve().parent.parent / "exports" / "olist_order_reviews_clean.csv"


def main() -> None:
    df = pd.read_csv(SRC, dtype=str)
    for col in ("review_comment_title", "review_comment_message"):
        df[col] = (
            df[col]
            .fillna("")
            .str.replace(r"[\r\n]+", " ", regex=True)
            .str.strip()
        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT, index=False, quoting=1, lineterminator="\n")
    print(f"wrote {len(df):,} rows to {OUT}")


if __name__ == "__main__":
    main()
