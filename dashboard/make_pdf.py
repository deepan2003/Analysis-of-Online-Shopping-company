from pathlib import Path

from PIL import Image

d = Path(__file__).resolve().parent / "screenshots"
imgs = [Image.open(d / f"page{i}.png").convert("RGB") for i in (1, 2, 3)]
out = d.parent / "Olist_Dashboard.pdf"
imgs[0].save(out, save_all=True, append_images=imgs[1:], resolution=150)
print(f"wrote {out} ({len(imgs)} pages, {imgs[0].size[0]}x{imgs[0].size[1]} px)")
