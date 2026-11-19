"""
screenshot.py
Renders dashboard/page1-3.html to PNG with headless Microsoft Edge, then
builds the combined PDF.

Usage: python dashboard/screenshot.py
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
SHOTS = ROOT / "screenshots"
SHOTS.mkdir(exist_ok=True)

CANDIDATES = [
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
]


def find_browser() -> Path:
    for c in CANDIDATES:
        if c.exists():
            return c
    sys.exit("Edge or Chrome not found - open page1.html manually and screenshot it.")


def main() -> None:
    browser = find_browser()
    for i in (1, 2, 3):
        html = (ROOT / f"page{i}.html").as_uri()
        png = SHOTS / f"page{i}.png"
        subprocess.run([
            str(browser), "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1", "--window-size=1600,1000",
            f"--screenshot={png}", html,
        ], check=False, capture_output=True)
        print(f"page{i}.png  {png.stat().st_size // 1024} KB")

    imgs = [Image.open(SHOTS / f"page{i}.png").convert("RGB") for i in (1, 2, 3)]
    pdf = ROOT / "Olist_Dashboard.pdf"
    imgs[0].save(pdf, save_all=True, append_images=imgs[1:], resolution=150)
    print(f"wrote {pdf}")


if __name__ == "__main__":
    main()
