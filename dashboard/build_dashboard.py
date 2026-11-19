"""
build_dashboard.py
Renders the three-page dashboard (Executive / Customers / Logistics)
from the CSV exports of the MySQL views.

All charts are rendered at a fixed pixel geometry (helper `fig_ax`), so
every card has identical font scaling - the same behaviour as sizing a
visual to a fixed frame in Power BI.

Outputs
  dashboard/page1.html .. page3.html
  dashboard/assets/*.png
"""
from __future__ import annotations

import base64
import io
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
EXP = ROOT / "exports"
OUT = ROOT / "dashboard"
ASSETS = OUT / "assets"
ASSETS.mkdir(parents=True, exist_ok=True)

NAVY, INK, MUTED = "#0B2545", "#1F2933", "#6B7A8F"
TEAL, AMBER, RED = "#13A89E", "#F2A541", "#E4572E"
GRID = "#E4E9F0"

DPI = 150
SCALE = DPI / 100.0          # figure inches = css_px / 100

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 9,
    "axes.edgecolor": GRID,
    "axes.labelcolor": MUTED,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "figure.facecolor": "white",
    "axes.facecolor": "white",
})

STATES = {
    "AC": (-8.77, -70.55), "AL": (-9.62, -36.82), "AM": (-3.47, -62.22),
    "AP": (1.41, -51.77), "BA": (-13.29, -41.71), "CE": (-5.20, -39.53),
    "DF": (-15.83, -47.86), "ES": (-19.19, -40.34), "GO": (-15.98, -49.86),
    "MA": (-5.42, -45.44), "MG": (-18.10, -44.38), "MS": (-20.51, -54.54),
    "MT": (-12.64, -55.42), "PA": (-3.79, -52.48), "PB": (-7.28, -36.72),
    "PE": (-8.38, -37.86), "PI": (-6.60, -42.28), "PR": (-24.89, -51.55),
    "RJ": (-22.25, -42.66), "RN": (-5.81, -36.59), "RO": (-10.83, -63.34),
    "RR": (1.99, -61.33), "RS": (-30.17, -53.50), "SC": (-27.45, -50.95),
    "SE": (-10.57, -37.45), "SP": (-22.19, -48.79), "TO": (-10.25, -48.25),
}


def fig_ax(w: int, h: int, margins=(0.10, 0.975, 0.18, 0.86)):
    """margins = (left, right, bottom, top) in figure fractions."""
    left, right, bottom, top = margins
    fig = plt.figure(figsize=(w / 100, h / 100), dpi=DPI)
    ax = fig.add_axes([left, bottom, right - left, top - bottom])
    return fig, ax


def to_b64(fig, name: str) -> str:
    fig.savefig(ASSETS / f"{name}.png", dpi=DPI, facecolor="white")
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=DPI, facecolor="white")
    plt.close(fig)
    return base64.b64encode(buf.getvalue()).decode()


def brl(x: float) -> str:
    if abs(x) >= 1_000_000:
        return f"R$ {x/1_000_000:.2f}M"
    if abs(x) >= 1_000:
        return f"R$ {x/1_000:.1f}k"
    return f"R$ {x:,.0f}"


def load():
    r = lambda n: pd.read_csv(EXP / f"{n}.csv")
    return dict(facts=r("vw_order_facts"), rev=r("vw_monthly_revenue"),
                rfm=r("vw_customer_rfm"), seg=r("vw_rfm_segment_summary"),
                cohort=r("vw_cohort_retention"), deliv=r("vw_delivery_facts"),
                state=r("vw_delivery_by_state"), dmonth=r("vw_delivery_monthly"),
                geo=r("vw_geo_zip"))


def style(ax, title: str, ylab: str = None, xlab: str = None) -> None:
    ax.set_title(title, loc="left", fontsize=10.5, color=INK,
                 fontweight="bold", pad=10)
    if ylab:
        ax.set_ylabel(ylab, fontsize=8.5)
    if xlab:
        ax.set_xlabel(xlab, fontsize=8.5)
    ax.spines[["top", "right"]].set_visible(False)
    ax.tick_params(labelsize=8)


# ------------------------------------------------------------------ page 1
def chart_revenue(rev, w, h):
    d = rev[(rev.purchase_month >= "2017-01") & (rev.purchase_month <= "2018-08")]
    fig, ax = fig_ax(w, h, (0.075, 0.985, 0.17, 0.87))
    x = np.arange(len(d))
    ax.plot(x, d.revenue / 1000, color=NAVY, lw=2.2, marker="o", ms=3.2, zorder=3)
    ax.fill_between(x, d.revenue / 1000, color=TEAL, alpha=0.13, zorder=2)
    ax.set_xticks(x[::2])
    ax.set_xticklabels([m[2:] for m in d.purchase_month[::2]], fontsize=8)
    style(ax, "Monthly revenue, Jan 2017 - Aug 2018", "Revenue (R$ thousands)")
    ax.set_ylim(0, d.revenue.max() / 1000 * 1.2)
    peak = d.revenue.idxmax()
    i = list(d.index).index(peak)
    ax.annotate(f"Peak {d.loc[peak,'purchase_month']}  {brl(d.loc[peak,'revenue'])}",
                xy=(i, d.loc[peak, "revenue"] / 1000),
                xytext=(i - 5.2, d.loc[peak, "revenue"] / 1000 * 1.06),
                fontsize=8, color=INK,
                arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
    ax.axhline(d.revenue.mean() / 1000, color=AMBER, ls="--", lw=1)
    ax.text(len(x) - 0.5, d.revenue.mean() / 1000 + 25, "monthly average",
            fontsize=7.5, color=AMBER, ha="right")
    return to_b64(fig, "chart_revenue")


def chart_mom(rev, w, h):
    d = rev[(rev.purchase_month >= "2017-02") & (rev.purchase_month <= "2018-08")]
    fig, ax = fig_ax(w, h, (0.14, 0.96, 0.17, 0.87))
    x = np.arange(len(d))
    ax.bar(x, d.mom_growth_pct, color=[TEAL if v >= 0 else RED for v in d.mom_growth_pct],
           width=0.72)
    ax.axhline(0, color=MUTED, lw=0.9)
    ax.set_xticks(x[::3])
    ax.set_xticklabels([m[2:] for m in d.purchase_month[::3]], fontsize=8)
    style(ax, "Month-over-month growth", "MoM growth (%)")
    ax.grid(axis="x", visible=False)
    return to_b64(fig, "chart_mom")


# ------------------------------------------------------------------ page 2
def chart_rfm(seg, w, h):
    d = seg.sort_values("customers")
    colors = [TEAL if s in ("Champions", "Loyal Customers", "Potential Loyalists")
              else AMBER if s in ("New Customers", "Promising") else RED
              for s in d.rfm_segment]
    fig, ax = fig_ax(w, h, (0.21, 0.97, 0.13, 0.88))
    bars = ax.barh(d.rfm_segment, d.customers, color=colors, height=0.64)
    for b, c, rv in zip(bars, d.customers, d.pct_of_revenue):
        ax.text(b.get_width() + max(d.customers) * 0.015,
                b.get_y() + b.get_height() / 2,
                f"{c:,}  ·  {rv:.0f}% rev" if rv >= 1 else f"{c:,}  ·  {rv:.1f}% rev",
                va="center", fontsize=8, color=INK)
    ax.set_xlim(0, max(d.customers) * 1.42)
    style(ax, "Customers per RFM segment", xlab="Customers")
    ax.grid(axis="y", visible=False)
    ax.tick_params(axis="y", labelsize=8.5)
    return to_b64(fig, "chart_rfm")


def chart_cohort(cohort, w, h):
    d = cohort[(cohort.month_index >= 1) & (cohort.month_index <= 5)]
    piv = d.pivot_table(index="cohort_month", columns="month_index",
                        values="retention_pct", aggfunc="first")
    piv = piv.loc[(piv.index >= "2017-01") & (piv.index <= "2018-07")]
    fig, ax = fig_ax(w, h, (0.13, 0.90, 0.14, 0.87))
    data = piv.values.copy()
    im = ax.imshow(data, cmap="BuGn", aspect="auto", vmin=0,
                   vmax=max(1.0, np.nanmax(data)))
    ax.set_xticks(range(piv.shape[1]))
    ax.set_xticklabels([f"M{c}" for c in piv.columns], fontsize=8)
    ax.set_yticks(range(len(piv)))
    ax.set_yticklabels(piv.index, fontsize=7.5)
    for i in range(data.shape[0]):
        for j in range(data.shape[1]):
            v = data[i, j]
            if np.isnan(v):
                continue
            ax.text(j, i, f"{v:.1f}" if v >= 1 else f"{v:.2f}",
                    ha="center", va="center", fontsize=6.8, color=INK)
    ax.grid(False)
    style(ax, "Cohort retention (% of first-month buyers still active)",
          xlab="Months since first purchase  (month 0 = 100% by definition)")
    cb = fig.colorbar(im, ax=ax, shrink=0.85, pad=0.02)
    cb.set_label("% retained (M1+)", fontsize=8)
    cb.ax.tick_params(labelsize=7)
    return to_b64(fig, "chart_cohort")


def chart_repeat(cohort, w, h):
    d = cohort[(cohort.month_index == 1) & (cohort.cohort_month >= "2017-01")].sort_values("cohort_month")
    fig, ax = fig_ax(w, h, (0.13, 0.97, 0.24, 0.84))
    x = np.arange(len(d))
    ax.bar(x, d.retention_pct, color=NAVY, width=0.72)
    ax.set_xticks(x[::3])
    ax.set_xticklabels([m[2:] for m in d.cohort_month[::3]], rotation=45, ha="right", fontsize=7.5)
    style(ax, "Month-1 retention by cohort", "% active in month 1")
    ax.grid(axis="x", visible=False)
    return to_b64(fig, "chart_repeat")


def chart_rev_mix(seg, w, h):
    d = seg.sort_values("total_revenue", ascending=False)
    top = d.head(5)
    other = d.total_revenue.sum() - top.total_revenue.sum()
    labels = list(top.rfm_segment) + ["Other segments"]
    vals = list(top.total_revenue) + [other]
    colors = [TEAL, AMBER, RED, "#8B98A9", "#C7D2DE", "#E4E9F0"]
    fig, ax = fig_ax(w, h, (0.02, 0.62, 0.04, 0.84))
    wedges, _ = ax.pie(vals, colors=colors, startangle=90,
                       wedgeprops=dict(width=0.62, edgecolor="white", linewidth=1.5))
    
    pcts = [v / sum(vals) * 100 for v in vals]
    ax.legend(wedges, [f"{l}  {p:.0f}%" for l, p in zip(labels, pcts)],
              loc="center left", bbox_to_anchor=(0.98, 0.5), frameon=False,
              fontsize=7.4, handlelength=1.1, labelspacing=0.7)
    ax.set_title(f"Revenue by RFM segment  |  {brl(d.total_revenue.sum())} total", loc="left", fontsize=10.5,
                 color=INK, fontweight="bold", pad=6)
    return to_b64(fig, "chart_rev_mix")


# ------------------------------------------------------------------ page 3
def chart_map(state, geo, w, h):
    d = state.copy()
    d["lat"] = d.customer_state.map(lambda s: STATES.get(s, (np.nan, np.nan))[0])
    d["lng"] = d.customer_state.map(lambda s: STATES.get(s, (np.nan, np.nan))[1])
    d = d.dropna(subset=["lat"])
    fig, ax = fig_ax(w, h, (0.02, 0.97, 0.05, 0.87))
    g = geo[(geo.lat.between(-34, 6)) & (geo.lng.between(-74, -34))]
    ax.scatter(g.lng, g.lat, s=1.6, color="#D5DDE8", alpha=0.65, linewidths=0, zorder=1)
    sizes = 20 + (d.delivered_orders / d.delivered_orders.max()) * 1500
    sc = ax.scatter(d.lng, d.lat, s=sizes, c=d.late_pct, cmap="YlOrRd",
                    edgecolors="white", linewidths=1.1, alpha=0.95,
                    vmin=0, vmax=25, zorder=3)
    for _, r in d.iterrows():
        ax.annotate(r.customer_state, (r.lng, r.lat), fontsize=6.8, color=INK,
                    ha="center", va="center", zorder=4, fontweight="bold")
    ax.set_xlim(-75, -33)
    ax.set_ylim(-34.5, 6)
    ax.set_xticks([]); ax.set_yticks([])
    ax.grid(False)
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title("Late-delivery rate by state (bubble = order volume)", loc="left",
                 fontsize=10.5, color=INK, fontweight="bold", pad=8)
    cb = fig.colorbar(sc, ax=ax, shrink=0.55, pad=0.005)
    cb.set_label("% late", fontsize=7.5)
    cb.ax.tick_params(labelsize=7)
    return to_b64(fig, "chart_map")


def chart_late_states(state, w, h):
    d = state.sort_values("late_pct", ascending=False).head(10).iloc[::-1]
    fig, ax = fig_ax(w, h, (0.13, 0.97, 0.16, 0.87))
    bars = ax.barh(d.customer_state, d.late_pct, color=RED, height=0.66)
    for b, v, n in zip(bars, d.late_pct, d.delivered_orders):
        ax.text(b.get_width() + 0.3, b.get_y() + b.get_height() / 2,
                f"{v:.1f}%  ({n:,})", va="center", fontsize=7.5, color=INK)
    ax.set_xlim(0, d.late_pct.max() * 1.35)
    style(ax, "Worst 10 states by late rate", xlab="% of delivered orders late")
    ax.grid(axis="y", visible=False)
    return to_b64(fig, "chart_late_states")


def chart_gauge(on_time, w, h):
    fig = plt.figure(figsize=(w / 100, h / 100), dpi=DPI)
    ax = fig.add_axes((0.03, 0.02, 0.94, 0.94), aspect="equal")
    theta = np.linspace(np.pi, 0, 200)
    ax.plot(np.cos(theta), np.sin(theta), color=GRID, lw=16, solid_capstyle="round")
    end = np.pi * (1 - on_time / 100)
    t2 = np.linspace(np.pi, end, 200)
    ax.plot(np.cos(t2), np.sin(t2), color=TEAL, lw=16, solid_capstyle="round")
    ax.text(0, 0.16, f"{on_time:.1f}%", ha="center", va="center",
            fontsize=19, color=NAVY, fontweight="bold")
    ax.text(0, -0.05, "on time", ha="center", va="center", fontsize=9.5, color=MUTED)
    ax.set_xlim(-1.22, 1.22)
    ax.set_ylim(-0.3, 1.15)
    ax.axis("off")
    return to_b64(fig, "chart_gauge")


def chart_delivery_hist(deliv, w, h):
    d = deliv.dropna(subset=["delivery_days", "estimated_days"])
    d = d.sample(n=min(8000, len(d)), random_state=42)
    fig, ax = fig_ax(w, h, (0.15, 0.97, 0.22, 0.86))
    ax.hist(d.estimated_days.clip(0, 60), bins=30, color="#DCE3EC", label="Promised")
    ax.hist(d.delivery_days.clip(0, 60), bins=30, color=TEAL, alpha=0.8, label="Actual")
    style(ax, "Promised vs actual delivery days", "Orders", "Days from purchase")
    ax.legend(frameon=False, fontsize=7.5, loc="upper right")
    return to_b64(fig, "chart_delivery_hist")


def chart_on_time_trend(dmonth, w, h):
    d = dmonth[(dmonth.purchase_month >= "2017-01") & (dmonth.purchase_month <= "2018-08")]
    fig, ax = fig_ax(w, h, (0.15, 0.97, 0.24, 0.86))
    x = np.arange(len(d))
    ax.plot(x, d.on_time_pct, color=NAVY, lw=2.1, marker="o", ms=2.8)
    ax.set_ylim(80, 100)
    ax.set_xticks(x[::3])
    ax.set_xticklabels([m[2:] for m in d.purchase_month[::3]], rotation=45,
                       ha="right", fontsize=7.5)
    style(ax, "On-time rate by purchase month", "On-time (%)")
    return to_b64(fig, "chart_on_time_trend")


# ------------------------------------------------------------------ HTML
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#DDE3EC;color:#1F2933}
.page{width:1600px;height:1000px;background:#F6F8FB;padding:24px 34px 0;
      display:flex;flex-direction:column;position:relative;overflow:hidden}
.top{display:flex;justify-content:space-between;align-items:flex-end;
     border-bottom:3px solid #0B2545;padding-bottom:10px;margin-bottom:14px}
.brand{display:flex;align-items:center;gap:12px}
.logo{width:38px;height:38px;border-radius:10px;background:#0B2545;color:#fff;
      display:flex;align-items:center;justify-content:center;font-weight:700;font-size:18px}
h1{font-size:22px;color:#0B2545;letter-spacing:.2px}
.sub{font-size:11.5px;color:#6B7A8F;margin-top:3px}
.tag{font-size:11.5px;color:#6B7A8F;text-align:right;line-height:1.5}
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin-bottom:14px}
.kpi{background:#fff;border:1px solid #E4E9F0;border-radius:11px;padding:12px 15px;height:92px;
     box-shadow:0 1px 2px rgba(16,24,40,.05)}
.kpi .lbl{font-size:10px;color:#6B7A8F;text-transform:uppercase;letter-spacing:.7px}
.kpi .val{font-size:23px;font-weight:700;color:#0B2545;margin-top:5px;line-height:1.1}
.kpi .note{font-size:10.5px;margin-top:5px;color:#6B7A8F}
.up{color:#0F8B7E}.down{color:#E4572E}
.row{display:grid;gap:14px}
.card{background:#fff;border:1px solid #E4E9F0;border-radius:11px;padding:13px 15px 10px;
      box-shadow:0 1px 2px rgba(16,24,40,.05);overflow:hidden}
.card img{width:100%;display:block}
.insight{background:#fff;border-left:4px solid #13A89E;border-radius:9px;
         padding:11px 16px;font-size:12.2px;line-height:1.52;color:#334155}
.insight b{color:#0B2545}
.foot{position:absolute;bottom:12px;left:34px;right:34px;display:flex;
      justify-content:space-between;font-size:10px;color:#8B98A9;
      border-top:1px solid #E4E9F0;padding-top:7px}
.playbook li{font-size:11.2px;color:#334155;margin:0 0 6px 14px;line-height:1.35}
.playbook b{color:#0B2545}
.card h3{font-size:12px;color:#0B2545;margin-bottom:7px}
"""


def page_html(title, subtitle, body, n) -> str:
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<style>{CSS}</style></head><body><div class="page">
 <div class="top"><div class="brand"><div class="logo">O</div>
   <div><h1>{title}</h1><div class="sub">{subtitle}</div></div></div>
   <div class="tag">Olist E-Commerce Analytics &middot; Sep 2016 - Aug 2018<br>
   MySQL + Power BI portfolio project</div></div>
 {body}
 <div class="foot"><span>Source: olist_orders, order_payments, customers, order_items, geolocation</span>
 <span>Page {n} of 3</span></div>
</div></body></html>"""


def main() -> None:
    D = load()
    facts, rev, seg, cohort = D["facts"], D["rev"], D["seg"], D["cohort"]
    deliv, state = D["deliv"], D["state"]

    total_rev = facts.order_revenue.sum()
    orders = len(facts)
    aov = total_rev / orders
    customers = facts.customer_unique_id.nunique()
    steady = rev[(rev.purchase_month >= "2017-01") & (rev.purchase_month <= "2018-08")]
    latest, prev = steady.iloc[-1], steady.iloc[-2]
    mom = (latest.revenue - prev.revenue) / prev.revenue * 100
    y2017 = steady[steady.purchase_month < "2018-01"].revenue.sum()
    y2018 = steady[steady.purchase_month >= "2018-01"].revenue.sum()
    on_time = deliv.is_on_time.mean() * 100
    late_orders = int((deliv.is_on_time == 0).sum())
    repeat = int((D["rfm"].frequency > 1).sum())
    repeat_pct = repeat / len(D["rfm"]) * 100
    at_risk = seg[seg.rfm_segment == "At Risk"].iloc[0]

    # ---------------------------------------------------------- page 1
    body1 = f"""
  <div class="kpis">
    <div class="kpi"><div class="lbl">Total revenue</div><div class="val">{brl(total_rev)}</div>
      <div class="note">98,206 paid orders</div></div>
    <div class="kpi"><div class="lbl">Orders</div><div class="val">{orders:,}</div>
      <div class="note">Sep 2016 - Aug 2018</div></div>
    <div class="kpi"><div class="lbl">Average order value</div><div class="val">R$ {aov:,.2f}</div>
      <div class="note">Narrow R$ 148-170 band</div></div>
    <div class="kpi"><div class="lbl">Unique customers</div><div class="val">{customers:,}</div>
      <div class="note">27 states, 1,000+ cities</div></div>
    <div class="kpi"><div class="lbl">MoM growth (Aug 2018)</div>
      <div class="val {'down' if mom < 0 else 'up'}">{mom:+.1f}%</div>
      <div class="note">vs Jul 2018 &middot; {brl(prev.revenue)}</div></div>
  </div>
  <div class="row" style="grid-template-columns:990px 528px;margin-bottom:14px">
    <div class="card"><img src="data:image/png;base64,{chart_revenue(rev, 960, 592)}"></div>
    <div class="card"><img src="data:image/png;base64,{chart_mom(rev, 498, 592)}"></div>
  </div>
  <div class="insight">
    <b>What the numbers say:</b> revenue rose from {brl(y2017)} in 2017 to {brl(y2018)} in the first
    8 months of 2018 - a <b>{y2018/y2017*100-100:.0f}% increase</b>. Growth comes from order volume,
    not basket size: AOV stayed between R$ 148 and R$ 170 while monthly orders grew from 787 to 7,187.
    Nov 2017 is the clear peak ({brl(rev[rev.purchase_month=='2017-11'].revenue.iloc[0])}, Black Friday);
    the December drop is a normal post-peak correction, not a demand problem.
  </div>"""

    # ---------------------------------------------------------- page 2
    body2 = f"""
  <div class="kpis">
    <div class="kpi"><div class="lbl">Repeat purchase rate</div><div class="val">{repeat_pct:.2f}%</div>
      <div class="note">{repeat:,} of {len(D['rfm']):,} customers</div></div>
    <div class="kpi"><div class="lbl">Champions</div><div class="val">18</div>
      <div class="note">4+ orders, recent, top spend</div></div>
    <div class="kpi"><div class="lbl">At-risk revenue</div><div class="val">{brl(at_risk.total_revenue)}</div>
      <div class="note">{at_risk.pct_of_revenue:.0f}% of revenue, 6+ months quiet</div></div>
    <div class="kpi"><div class="lbl">Month-1 retention</div><div class="val">0.4%</div>
      <div class="note">Average across cohorts</div></div>
    <div class="kpi"><div class="lbl">Orders per customer</div><div class="val">1.03</div>
      <div class="note">One-and-done marketplace</div></div>
  </div>
  <div class="row" style="grid-template-columns:757px 757px;margin-bottom:14px">
    <div class="card"><img src="data:image/png;base64,{chart_rfm(seg, 727, 402)}"></div>
    <div class="card"><img src="data:image/png;base64,{chart_cohort(cohort, 727, 402)}"></div>
  </div>
  <div class="row" style="grid-template-columns:505px 505px 494px;margin-bottom:14px">
    <div class="card"><img src="data:image/png;base64,{chart_repeat(cohort, 475, 176)}"></div>
    <div class="card"><img src="data:image/png;base64,{chart_rev_mix(seg, 475, 176)}"></div>
    <div class="card playbook"><h3>Segment playbook</h3>
      <ul>
        <li><b>At Risk (22.6k):</b> win-back email + 15% coupon</li>
        <li><b>Hibernating (23.6k):</b> low-cost reactivation only</li>
        <li><b>Loyal (107) / Champions (18):</b> loyalty tier, early access</li>
        <li><b>New (17.1k):</b> second-purchase nudge within 30 days</li>
      </ul>
    </div>
  </div>
  <div class="insight">
    <b>What the numbers say:</b> this is a <b>one-and-done marketplace</b> - only {repeat_pct:.1f}% of buyers
    ever order twice, so retention is the biggest untapped lever. Value is concentrated:
    <b>23.8% of customers (At Risk) hold 43% of revenue</b> but have not ordered in 6+ months.
    A win-back campaign aimed at those 22,563 lapsed high-value buyers is the cheapest revenue available.
  </div>"""

    # ---------------------------------------------------------- page 3
    body3 = f"""
  <div class="kpis">
    <div class="kpi"><div class="lbl">Delivered orders</div><div class="val">{len(deliv):,}</div>
      <div class="note">of 98,206 paid orders</div></div>
    <div class="kpi"><div class="lbl">On-time rate</div><div class="val up">{on_time:.1f}%</div>
      <div class="note">{late_orders:,} late deliveries</div></div>
    <div class="kpi"><div class="lbl">Avg actual delivery</div><div class="val">{deliv.delivery_days.mean():.1f} days</div>
      <div class="note">vs {deliv.estimated_days.mean():.1f} days promised</div></div>
    <div class="kpi"><div class="lbl">Avg vs promise</div><div class="val">-11.9 days</div>
      <div class="note">Early on average, long tail</div></div>
    <div class="kpi"><div class="lbl">Worst state</div><div class="val">AL 23.9%</div>
      <div class="note">Alagoas late rate</div></div>
  </div>
  <div class="row" style="grid-template-columns:698px 428px 384px;margin-bottom:14px">
    <div class="card"><img src="data:image/png;base64,{chart_map(state, D['geo'], 668, 592)}"></div>
    <div class="card"><img src="data:image/png;base64,{chart_late_states(state, 398, 592)}"></div>
    <div class="card" style="padding-bottom:4px">
      <img src="data:image/png;base64,{chart_gauge(on_time, 354, 250)}">
      <img src="data:image/png;base64,{chart_delivery_hist(deliv, 354, 322)}" style="margin-top:6px">
    </div>
  </div>
  <div class="insight">
    <b>What the numbers say:</b> the network is <b>{on_time:.1f}% on time</b> and delivers 12 days early
    on average, yet {late_orders:,} orders arrived late - and when late they are late by <b>8.9 days</b>.
    Geography drives the risk: SP delivers in 8.7 days with 94.1% on-time, while AL, MA and PI take
    19-25 days and miss 16-24% of promises. The North-East corridor is where a logistics fix pays back fastest.
  </div>"""

    (OUT / "page1.html").write_text(page_html(
        "Executive overview", "Revenue, orders and growth | Sep 2016 - Aug 2018", body1, 1), encoding="utf-8")
    (OUT / "page2.html").write_text(page_html(
        "Customer intelligence", "RFM segmentation and cohort retention", body2, 2), encoding="utf-8")
    (OUT / "page3.html").write_text(page_html(
        "Logistics performance", "Delivery times, on-time rate and regional delays", body3, 3), encoding="utf-8")

    print("wrote page1.html page2.html page3.html")
    print(f"revenue={total_rev:,.2f} orders={orders:,} aov={aov:.2f} "
          f"customers={customers:,} on_time={on_time:.2f}% repeat={repeat_pct:.2f}%")


if __name__ == "__main__":
    main()
