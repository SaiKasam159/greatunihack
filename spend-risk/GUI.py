"""Desktop GUI for the spending-risk model.

All charts live in one window as tabs, drawn with matplotlib inside Tkinter
(no images, no browser). Reads the CSVs produced by src/generate_data.py and
src/model.py.

    python GUI.py            # open the app
    python GUI.py --smoke    # render every tab to reports/gui_*.png and exit
"""

from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

import matplotlib

matplotlib.use("TkAgg")
import numpy as np
import pandas as pd
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.figure import Figure

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
REPORTS = ROOT / "reports"
DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
ACCENT = "#c0392b"
BLUE = "#2f6f8f"
RISK_CMAP = LinearSegmentedColormap.from_list("risk", ["#f4f8fb", "#8fc1dd", "#f2b134", "#c0392b"])


# --------------------------------------------------------------------------- #
# Data
# --------------------------------------------------------------------------- #
def load_all() -> dict[str, pd.DataFrame]:
    missing = [p for p in (DATA / "daily_spend.csv", DATA / "transactions_fake.csv",
                           REPORTS / "forecast_next_12_months.csv") if not p.exists()]
    if missing:
        raise FileNotFoundError(
            "Missing files:\n  " + "\n  ".join(str(p) for p in missing)
            + "\n\nRun run.ps1 (or the two scripts in src/) first."
        )
    daily = pd.read_csv(DATA / "daily_spend.csv", parse_dates=["date"])
    tx = pd.read_csv(DATA / "transactions_fake.csv", parse_dates=["date"])
    fc = pd.read_csv(REPORTS / "forecast_next_12_months.csv", parse_dates=["date"])
    return {"daily": daily, "tx": tx, "fc": fc}


# --------------------------------------------------------------------------- #
# Chart builders - each one draws into a supplied Figure
# --------------------------------------------------------------------------- #
def fig_pie_category(d: dict) -> Figure:
    tx = d["tx"]
    last = tx[tx["date"] >= tx["date"].max() - pd.Timedelta(days=365)]
    s = last.groupby("category")["amount"].sum().sort_values(ascending=False)

    fig = Figure(figsize=(9, 5.4), dpi=100)
    ax = fig.add_subplot(111)
    colors = plt_tab20(len(s))
    wedges, *_ = ax.pie(
        s, autopct=lambda p: f"{p:.1f}%" if p >= 2 else "", pctdistance=0.78,
        colors=colors, startangle=110, counterclock=False,
        wedgeprops={"width": 0.42, "edgecolor": "white", "linewidth": 2},
        textprops={"fontsize": 9},
    )
    ax.legend(wedges, [f"{k}  GBP {v:,.0f}" for k, v in s.items()],
              loc="center left", bbox_to_anchor=(1.0, 0.5), frameon=False, fontsize=9)
    ax.set_title("Share of last-12-months spend by category", fontsize=12, pad=12)
    fig.tight_layout()
    return fig


def fig_pie_occasion(d: dict) -> Figure:
    fc = d["fc"]
    s = fc.groupby("occasion")["expected_spend"].sum()
    s = s[s > 0].sort_values(ascending=False)

    fig = Figure(figsize=(9, 5.4), dpi=100)
    ax = fig.add_subplot(111)
    colors = plt_set2(len(s))
    wedges, *_ = ax.pie(
        s, autopct=lambda p: f"{p:.1f}%" if p >= 2.5 else "", pctdistance=0.78,
        colors=colors, startangle=120, counterclock=False,
        wedgeprops={"width": 0.42, "edgecolor": "white", "linewidth": 2},
        textprops={"fontsize": 9},
    )
    ax.legend(wedges, [f"{k}  GBP {v:,.0f}" for k, v in s.items()],
              loc="center left", bbox_to_anchor=(1.0, 0.5), frameon=False, fontsize=9)
    ax.set_title("Forecast year: share of spend by occasion", fontsize=12, pad=12)
    fig.tight_layout()
    return fig


def fig_weekday(d: dict) -> Figure:
    daily = d["daily"]
    prof = daily.assign(dow=daily["date"].dt.day_of_week).groupby("dow")["total"].mean()
    names = [DOW[i] for i in prof.index]
    top = int(np.argmax(prof.to_numpy()))

    fig = Figure(figsize=(9, 5.0), dpi=100)
    ax = fig.add_subplot(111)
    colors = [ACCENT if i == top else "#4a7fa5" for i in range(len(prof))]
    bars = ax.bar(names, prof.to_numpy(), color=colors)
    for b in bars:
        ax.annotate(f"GBP {b.get_height():,.0f}", (b.get_x() + b.get_width() / 2, b.get_height()),
                    ha="center", va="bottom", fontsize=9)
    ax.set_ylim(0, prof.max() * 1.18)
    ax.set_ylabel("GBP per day")
    ax.set_title(f"Average spend by weekday - highest on {names[top]}", fontsize=12)
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    return fig


def fig_risk_calendar(d: dict) -> Figure:
    fc = d["fc"].copy()
    fc["m"] = fc["date"].dt.strftime("%b")
    fc["d"] = fc["date"].dt.day
    order = list(dict.fromkeys(fc["m"]))
    piv = fc.pivot_table(index="m", columns="d", values="p_abnormal").reindex(order)

    fig = Figure(figsize=(11, 5.2), dpi=100)
    ax = fig.add_subplot(111)
    im = ax.imshow(piv.to_numpy(), aspect="auto", cmap=RISK_CMAP, vmin=0, vmax=1)
    ax.set_xticks(range(piv.shape[1]))
    ax.set_xticklabels([str(c) for c in piv.columns], fontsize=7)
    ax.set_yticks(range(len(piv)))
    ax.set_yticklabels(piv.index)
    vals = piv.to_numpy()
    for i in range(vals.shape[0]):
        for j in range(vals.shape[1]):
            if np.isfinite(vals[i, j]) and vals[i, j] >= 0.5:
                ax.text(j, i, "!", ha="center", va="center", color="white",
                        fontsize=8, weight="bold")
    ax.set_xticks(np.arange(-0.5, piv.shape[1], 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(piv), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=1.2)
    ax.tick_params(which="minor", length=0)
    ax.set_xlabel("day of month")
    ax.set_title("Risk calendar - P(abnormal spending day)", fontsize=12)
    fig.colorbar(im, ax=ax, label="P(abnormal)")
    fig.tight_layout()
    return fig


def fig_timeline(d: dict) -> Figure:
    daily, fc = d["daily"], d["fc"]
    hist = daily[daily["date"] >= daily["date"].max() - pd.Timedelta(days=150)]

    fig = Figure(figsize=(11, 4.8), dpi=100)
    ax = fig.add_subplot(111)
    ax.plot(hist["date"], hist["total"], color="#333", lw=1.2, label="actual spend")
    ax.plot(fc["date"], fc["expected_spend"], color=BLUE, lw=1.4, ls="--", label="forecast spend")
    sc = ax.scatter(fc["date"], fc["expected_spend"], c=fc["p_abnormal"], cmap="YlOrRd",
                    vmin=0, vmax=1, s=24, edgecolor="none", zorder=3)
    ax.axvline(daily["date"].max(), color="grey", ls=":", lw=1)

    i = int(fc["expected_spend"].idxmax())
    ax.annotate(f"{fc.loc[i, 'occasion']}\nGBP {fc.loc[i, 'expected_spend']:,.0f}",
                (fc.loc[i, "date"], fc.loc[i, "expected_spend"]),
                textcoords="offset points", xytext=(0, 14), fontsize=8, ha="center",
                color="#7b241c",
                arrowprops={"arrowstyle": "-", "lw": 0.7, "color": "#7b241c"})
    ax.set_ylim(0, fc["expected_spend"].max() * 1.2)
    ax.set_ylabel("GBP per day")
    ax.set_title("Recent actuals vs forecast (point colour = risk)", fontsize=12)
    ax.legend(frameon=False, loc="upper left")
    ax.grid(alpha=0.3)
    fig.colorbar(sc, ax=ax, label="P(abnormal)")
    fig.autofmt_xdate(rotation=25)
    fig.tight_layout()
    return fig


def fig_top_days(d: dict) -> Figure:
    fc = d["fc"]
    top = fc.sort_values("p_abnormal", ascending=False).head(12).sort_values("p_abnormal")

    fig = Figure(figsize=(9.5, 5.6), dpi=100)
    ax = fig.add_subplot(111)
    labels = [f"{r.date:%d %b %Y}  {r.dow_name}" for r in top.itertuples()]
    ax.barh(labels, top["p_abnormal"], color=ACCENT)
    for y, (p, occ) in enumerate(zip(top["p_abnormal"], top["occasion"])):
        ax.annotate(f"{p:.0%}  {occ}", (p, y), va="center", ha="left", fontsize=9,
                    xytext=(4, 0), textcoords="offset points")
    ax.set_xlim(0, 1.2)
    ax.set_xlabel("probability of an abnormal spending day")
    ax.set_title("Top 12 days most likely to blow the budget", fontsize=12)
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()
    return fig


def plt_tab20(n: int):
    return matplotlib.colormaps["tab20"](np.linspace(0, 1, n))


def plt_set2(n: int):
    return matplotlib.colormaps["Set2"](np.linspace(0, 1, n))


CHART_TABS = [
    ("Category pie", fig_pie_category),
    ("Occasion pie", fig_pie_occasion),
    ("Weekday", fig_weekday),
    ("Risk calendar", fig_risk_calendar),
    ("Forecast", fig_timeline),
    ("Top days", fig_top_days),
]


# --------------------------------------------------------------------------- #
# GUI
# --------------------------------------------------------------------------- #
class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Spend Risk Explorer")
        self.geometry("1320x900")
        self.minsize(1000, 700)
        self.data: dict[str, pd.DataFrame] = {}
        self.figures: dict[str, Figure] = {}

        self._build_header()
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=(0, 8))
        self.reload()

    # -- chrome ------------------------------------------------------------ #
    def _build_header(self) -> None:
        bar = ttk.Frame(self, padding=(10, 8))
        bar.pack(fill="x")
        ttk.Label(bar, text="Spend Risk Explorer",
                  font=("Segoe UI", 16, "bold")).pack(side="left")
        self.status = ttk.Label(bar, text="", foreground="#555")
        self.status.pack(side="left", padx=16)
        ttk.Button(bar, text="Reload data", command=self.reload).pack(side="right")

    # -- data + tabs ------------------------------------------------------- #
    def reload(self) -> None:
        try:
            self.data = load_all()
        except FileNotFoundError as exc:
            messagebox.showerror("Missing data", str(exc))
            return

        for tab in self.notebook.tabs():
            self.notebook.forget(tab)
        self.figures.clear()

        for name, builder in CHART_TABS:
            try:
                fig = builder(self.data)
            except Exception as exc:  # a broken chart must not kill the app
                fig = Figure(figsize=(6, 3), dpi=100)
                fig.text(0.5, 0.5, f"{name} failed:\n{exc}", ha="center", va="center", wrap=True)
            self.figures[name] = fig
            self.notebook.add(self._canvas_tab(fig), text=name)

        self.notebook.add(self._table_tab(), text="Table")

        fc = self.data["fc"]
        self.status.config(
            text=(f"{len(self.data['daily']):,} days  |  "
                  f"{fc['abnormal'].sum()} risky days in {fc['date'].min():%b %Y}-{fc['date'].max():%b %Y}  |  "
                  f"forecast GBP {fc['expected_spend'].sum():,.0f}")
        )

    def _canvas_tab(self, fig: Figure) -> ttk.Frame:
        frame = ttk.Frame(self.notebook)
        canvas = FigureCanvasTkAgg(fig, master=frame)
        canvas.draw()
        toolbar = NavigationToolbar2Tk(canvas, frame, pack_toolbar=False)
        toolbar.update()
        toolbar.pack(side="bottom", fill="x")
        canvas.get_tk_widget().pack(fill="both", expand=True)
        return frame

    def _table_tab(self) -> ttk.Frame:
        frame = ttk.Frame(self.notebook)
        cols = ("date", "weekday", "p", "spend", "occasion")
        tree = ttk.Treeview(frame, columns=cols, show="headings", height=20)
        heads = {"date": ("Date", 110), "weekday": ("Weekday", 90), "p": ("P(abnormal)", 110),
                 "spend": ("Expected spend", 130), "occasion": ("Occasion", 200)}
        for key, (label, width) in heads.items():
            tree.heading(key, text=label,
                         command=lambda k=key: self._sort_tree(tree, k))
            tree.column(key, width=width, anchor="w")

        fc = self.data["fc"].sort_values("p_abnormal", ascending=False)
        for r in fc.itertuples():
            tree.insert("", "end", values=(
                f"{r.date:%Y-%m-%d}", r.dow_name, f"{r.p_abnormal:.0%}",
                f"GBP {r.expected_spend:,.0f}", r.occasion))

        scroll = ttk.Scrollbar(frame, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scroll.set)
        tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        return frame

    @staticmethod
    def _sort_tree(tree: ttk.Treeview, col: str) -> None:
        rows = [(tree.set(k, col), k) for k in tree.get_children("")]
        reverse = getattr(tree, "_sort_rev", {}).get(col, False)
        rows.sort(key=lambda t: t[0], reverse=reverse)
        tree._sort_rev = {col: not reverse}
        for i, (_, k) in enumerate(rows):
            tree.move(k, "", i)


def smoke() -> None:
    """Headless-ish check: build every figure, save a PNG, no mainloop."""
    data = load_all()
    out_dir = REPORTS / "gui_preview"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, builder in CHART_TABS:
        fig = builder(data)
        out = out_dir / f"{name.lower().replace(' ', '_')}.png"
        fig.savefig(out, dpi=120, bbox_inches="tight")
        print("wrote", out)
    print("smoke OK")


def main() -> None:
    try:  # crisp text on Windows
        import ctypes

        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass
    App().mainloop()


if __name__ == "__main__":
    if "--smoke" in sys.argv:
        smoke()
    else:
        main()
