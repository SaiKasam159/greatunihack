"""Predict on which days spending goes abnormally high, then forecast the next year.

Model: two tiny gradient-boosted trees on calendar + event features
  1. classifier -> P(day total > training P90) = "abnormal spending day"
  2. regressor  -> expected day total, used for the charts and the ranking

Run:  python src/model.py
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor
from sklearn.inspection import permutation_importance
from sklearn.metrics import average_precision_score, roc_auc_score

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "reports"
DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
TRAIN_END = "2025-12-31"
TEST_START = "2026-01-01"
FORECAST_START = "2026-11-01"
FORECAST_END = "2027-10-31"
SPLIT = 0.90  # anomaly = day total above the 90th percentile of training days

ANNUAL = {"birthday": (3, 14), "ceremony": (2, 18), "anniversary": (8, 9),
          "christmas": (12, 25), "black_friday": None}  # black friday filled per year


# --------------------------------------------------------------------------- #
# Calendar features (all known in advance -> no leakage into the future)
# --------------------------------------------------------------------------- #
def days_to(d: pd.Timestamp, md: tuple[int, int]) -> int:
    """Signed day distance to the nearest occurrence of a month/day."""
    cands = [pd.Timestamp(d.year + k, *md) for k in (-1, 0, 1)]
    t = min(cands, key=lambda c: abs((d - c).days))
    return int((t - d).days)


def black_friday(year: int) -> pd.Timestamp:
    import calendar as cal

    th = [w[cal.THURSDAY] for w in cal.monthcalendar(year, 11) if w[cal.THURSDAY]]
    return pd.Timestamp(year=year, month=11, day=th[3] + 1)


def features(dates: pd.Series, events: pd.DataFrame) -> pd.DataFrame:
    x = pd.DataFrame({"date": pd.to_datetime(dates)})
    dt = x["date"]
    x["dow"] = dt.dt.day_of_week
    x["month"] = dt.dt.month
    x["day"] = dt.dt.day
    x["is_weekend"] = (x["dow"] >= 5).astype(int)
    x["days_to_birthday"] = dt.map(lambda d: days_to(d, ANNUAL["birthday"]))
    x["days_to_ceremony"] = dt.map(lambda d: days_to(d, ANNUAL["ceremony"]))
    x["days_to_anniversary"] = dt.map(lambda d: days_to(d, ANNUAL["anniversary"]))
    x["days_to_christmas"] = dt.map(lambda d: days_to(d, (12, 25)))
    x["days_to_black_friday"] = dt.map(lambda d: days_to(d, (black_friday(d.year).month,
                                                             black_friday(d.year).day)))
    x["days_to_payday"] = dt.dt.day - 25
    x["days_to_month_end"] = -(dt.dt.days_in_month - dt.dt.day)
    # event windows from the known calendar (trips, ceremonies, ...)
    in_event = pd.Series(0, index=x.index, dtype=int)
    planned = pd.Series(0.0, index=x.index)
    for _, e in events.iterrows():
        mask = (x["date"] >= e["date"] - pd.Timedelta(days=1)) & (x["date"] <= e["end_date"] + pd.Timedelta(days=1))
        in_event |= mask.astype(int)
        planned += (x["date"] == e["date"]).astype(float) * float(e.get("planned_amount", 0.0))
    x["in_event_window"] = in_event
    x["planned_amount"] = planned  # budgeted, known before the day (e.g. a wedding)
    return x.drop(columns="date")


FEATURES_CAL = ["dow", "month", "day", "is_weekend", "days_to_birthday", "days_to_ceremony",
                "days_to_anniversary", "days_to_christmas", "days_to_black_friday",
                "days_to_payday", "days_to_month_end", "in_event_window"]
# the classifier may use the budget of a planned event (zero vs non-zero split),
# but the spend regressor must not: trees cannot extrapolate to an unseen amount,
# so planned budget is added on top of the calendar prediction instead.
FEATURES_CLF = FEATURES_CAL + ["planned_amount"]
CATEGORICAL = ["dow", "month"]


def occasions(dates: pd.Series, events: pd.DataFrame) -> pd.Series:
    """Plain-language label for why a day is special (used for charts/labels)."""
    labels = []
    for d in pd.to_datetime(dates):
        label = "Ordinary day"
        rows = events[(events["date"] <= d) & (events["end_date"] >= d)]
        if len(rows):
            ev = rows.sort_values("event").iloc[0]["event"]
            label = {"Christmas": "Christmas", "Black Friday": "Black Friday",
                     "Holiday trip": "Holiday trip", "New Year": "New Year",
                     "Birthday": "Birthday", "Anniversary": "Anniversary",
                     "Family ceremony": "Family ceremony"}.get(ev, ev)
        elif abs(days_to(d, ANNUAL["birthday"])) <= 2:
            label = "Birthday"
        elif abs(days_to(d, ANNUAL["ceremony"])) <= 1:
            label = "Family ceremony"
        elif abs(days_to(d, ANNUAL["anniversary"])) <= 1:
            label = "Anniversary"
        elif d.day in (24, 25, 26, 31) and d.month == 12:
            label = "Christmas"
        elif d.day == 25:
            label = "Payday"
        elif d.day in (5, 12, 15, 20):
            label = "Bills day"
        elif d.day_of_week >= 5:
            label = "Weekend"
        labels.append(label)
    return pd.Series(labels, index=range(len(labels)))


# --------------------------------------------------------------------------- #
# Data
# --------------------------------------------------------------------------- #
def load() -> tuple[pd.DataFrame, pd.DataFrame]:
    daily = pd.read_csv(DATA / "daily_spend.csv", parse_dates=["date"])
    events = pd.read_csv(DATA / "events.csv", parse_dates=["date", "end_date"])
    daily = daily.sort_values("date").reset_index(drop=True)
    return daily, events


def build_xy(daily: pd.DataFrame, events: pd.DataFrame, threshold: float) -> tuple[pd.DataFrame, pd.Series, pd.Series]:
    X = features(daily["date"], events)
    y_spend = daily["total"]
    y_bad = (daily["total"] > threshold).astype(int)
    return X, y_spend, y_bad


# --------------------------------------------------------------------------- #
# Evaluation
# --------------------------------------------------------------------------- #
def evaluate(daily: pd.DataFrame, events: pd.DataFrame) -> dict:
    train = daily[daily["date"] <= TRAIN_END].reset_index(drop=True)
    test = daily[daily["date"] >= TEST_START].reset_index(drop=True)
    threshold = float(train["total"].quantile(SPLIT))

    Xtr = features(train["date"], events)
    Xte = features(test["date"], events)
    ytr = (train["total"] > threshold).astype(int)
    yte = (test["total"] > threshold).astype(int)

    clf = HistGradientBoostingClassifier(
        max_iter=200, learning_rate=0.08, max_depth=3, min_samples_leaf=20,
        l2_regularization=1.0, categorical_features=CATEGORICAL, random_state=0,
    ).fit(Xtr[FEATURES_CLF], ytr)
    p = clf.predict_proba(Xte[FEATURES_CLF])[:, 1]

    # baseline: rank days by "expected spend" from a simple historical table
    # (weekday x month average of the training period)
    table = train.assign(dow=train["date"].dt.day_of_week, month=train["date"].dt.month)
    tbl = table.groupby(["dow", "month"])["total"].mean()
    base_score = test.assign(dow=test["date"].dt.day_of_week, month=test["date"].dt.month) \
        .apply(lambda r: tbl.get((r["dow"], r["month"]), table["total"].mean()), axis=1).to_numpy()

    def topk(scores: np.ndarray, k: int) -> float:
        idx = np.argsort(-scores)[:k]
        return float(yte.to_numpy()[idx].mean())

    n_pos = int(yte.sum())
    metrics = {
        "threshold_gbp": round(threshold, 2),
        "train_days": int(len(train)),
        "test_days": int(len(test)),
        "abnormal_days_test": n_pos,
        "base_rate_test": round(float(yte.mean()), 3),
        "roc_auc": round(float(roc_auc_score(yte, p)), 3),
        "average_precision": round(float(average_precision_score(yte, p)), 3),
        "precision_at_10": round(topk(p, 10), 3),
        "precision_at_25": round(topk(p, 25), 3),
        "baseline_precision_at_10": round(topk(base_score, 10), 3),
        "baseline_precision_at_25": round(topk(base_score, 25), 3),
    }

    imp = permutation_importance(clf, Xte[FEATURES_CLF], yte, n_repeats=5, random_state=0, scoring="roc_auc")
    order = np.argsort(-imp.importances_mean)
    metrics["top_drivers"] = [FEATURES_CLF[i] for i in order[:6]]

    reg = HistGradientBoostingRegressor(
        max_iter=300, learning_rate=0.06, max_depth=3, min_samples_leaf=15,
        categorical_features=CATEGORICAL, random_state=0,
    ).fit(Xtr[FEATURES_CAL], train["total"])
    y_hat_spend = reg.predict(Xte[FEATURES_CAL]) + Xte["planned_amount"].to_numpy()
    mae = float(np.mean(np.abs(y_hat_spend - test["total"])))
    metrics["spend_mae_gbp"] = round(mae, 2)
    metrics["spend_median_abs_error_gbp"] = round(float(np.median(np.abs(y_hat_spend - test["total"]))), 2)
    metrics["spend_mae_pct_of_mean"] = round(100 * mae / test["total"].mean(), 2)
    metrics["spend_forecast_total_gbp"] = round(float(y_hat_spend.sum()), 2)
    metrics["spend_actual_total_gbp"] = round(float(test["total"].sum()), 2)
    return metrics


# --------------------------------------------------------------------------- #
# Fit on everything, forecast the next 12 months
# --------------------------------------------------------------------------- #
def forecast(daily: pd.DataFrame, events: pd.DataFrame) -> tuple[pd.DataFrame, object, object]:
    threshold = float(daily["total"].quantile(SPLIT))

    X = features(daily["date"], events)
    y_bad = (daily["total"] > threshold).astype(int)

    clf = HistGradientBoostingClassifier(
        max_iter=200, learning_rate=0.08, max_depth=3, min_samples_leaf=20,
        l2_regularization=1.0, categorical_features=CATEGORICAL, random_state=0,
    ).fit(X[FEATURES_CLF], y_bad)
    reg = HistGradientBoostingRegressor(
        max_iter=300, learning_rate=0.06, max_depth=3, min_samples_leaf=15,
        categorical_features=CATEGORICAL, random_state=0,
    ).fit(X[FEATURES_CAL], daily["total"])

    future = pd.date_range(FORECAST_START, FORECAST_END, freq="D")
    Xf = features(pd.Series(future), events)
    fc = pd.DataFrame({"date": future, "dow": future.day_of_week})
    fc["dow_name"] = fc["dow"].map(dict(enumerate(DOW)))
    fc["p_abnormal"] = clf.predict_proba(Xf[FEATURES_CLF])[:, 1].round(4)
    # planned budget is added on top: a tree cannot invent an unseen ceremony cost
    fc["expected_spend"] = (reg.predict(Xf[FEATURES_CAL]) + Xf["planned_amount"].to_numpy()).round(2)
    fc["occasion"] = occasions(pd.Series(future), events).values
    fc["abnormal"] = (fc["p_abnormal"] >= 0.5).astype(int)
    return fc, clf, reg


# --------------------------------------------------------------------------- #
# Charts
# --------------------------------------------------------------------------- #
def pie_category(tx: pd.DataFrame, path: Path) -> pd.DataFrame:
    s = tx.groupby("category")["amount"].sum().sort_values(ascending=False)
    fig, ax = plt.subplots(figsize=(8, 6))
    colors = plt.cm.tab20(np.linspace(0, 1, len(s)))
    wedges, _text, auto = ax.pie(
        s, labels=None, autopct=lambda p: f"{p:.1f}%" if p >= 2.0 else "", pctdistance=0.78,
        colors=colors, startangle=110, counterclock=False,
        wedgeprops={"width": 0.42, "edgecolor": "white", "linewidth": 2},
        textprops={"fontsize": 9},
    )
    ax.legend(wedges, [f"{k}  GBP {v:,.0f}" for k, v in s.items()],
              loc="center left", bbox_to_anchor=(1.0, 0.5), frameon=False, fontsize=9)
    ax.set_title("Where the money goes - share of total spend by category", fontsize=12, pad=14)
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return s


def pie_occasion(fc_all: pd.DataFrame, path: Path) -> pd.Series:
    s = fc_all.groupby("occasion")["expected_spend"].sum().sort_values(ascending=False)
    s = s[s > 0]
    fig, ax = plt.subplots(figsize=(8, 6))
    colors = plt.cm.Set2(np.linspace(0, 1, len(s)))
    wedges, _text, _auto = ax.pie(
        s, autopct=lambda p: f"{p:.1f}%" if p >= 2.5 else "", pctdistance=0.78, colors=colors,
        startangle=120, counterclock=False,
        wedgeprops={"width": 0.42, "edgecolor": "white", "linewidth": 2},
        textprops={"fontsize": 9},
    )
    ax.legend(wedges, [f"{k}  GBP {v:,.0f}" for k, v in s.items()],
              loc="center left", bbox_to_anchor=(1.0, 0.5), frameon=False, fontsize=9)
    ax.set_title("Where next year's money goes - share by occasion", fontsize=12, pad=14)
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return s


def weekday_bar(profile: pd.DataFrame, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(9, 5))
    top = profile["mean_spend"].idxmax()
    colors = ["#c0392b" if i == top else "#4a7fa5" for i in profile.index]
    ax.bar(profile["dow"], profile["mean_spend"], color=colors)
    for i, v in enumerate(profile["mean_spend"]):
        ax.annotate(f"GBP {v:,.0f}", (i, v), ha="center", va="bottom", fontsize=9)
    ax.set_title(f"Average spend by weekday - you spend most on {profile.loc[top, 'dow']}")
    ax.set_ylabel("GBP per day")
    ax.grid(axis="y", alpha=0.3)
    ax.set_ylim(0, profile["mean_spend"].max() * 1.18)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def calendar_heatmap(fc: pd.DataFrame, path: Path) -> None:
    d = fc.assign(month=fc["date"].dt.strftime("%b"), day=fc["date"].dt.day)
    order = ["Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct"]
    piv = d.pivot(index="month", columns="day", values="p_abnormal").reindex(order)
    fig, ax = plt.subplots(figsize=(13, 5.2))
    cmap = LinearSegmentedColormap.from_list("risk", ["#f4f8fb", "#8fc1dd", "#f2b134", "#c0392b"])
    im = ax.imshow(piv, aspect="auto", cmap=cmap, vmin=0, vmax=max(0.6, float(np.nanmax(piv))))
    ax.set_xticks(range(piv.shape[1]))
    ax.set_xticklabels([str(c + 1) for c in range(piv.shape[1])], fontsize=7)
    ax.set_yticks(range(len(piv)))
    ax.set_yticklabels(piv.index)
    ax.set_xlabel("day of month")
    ax.set_title("Risk calendar - probability that a day is an abnormal spending day\n(forecast Nov 2026 - Oct 2027)")
    for i in range(len(piv)):
        for j in range(piv.shape[1]):
            v = piv.iat[i, j]
            if pd.notna(v) and v >= 0.5:
                ax.text(j, i, "!", ha="center", va="center", color="white", fontsize=8, weight="bold")
    ax.set_xticks(np.arange(-0.5, piv.shape[1], 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(piv), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=1.2)
    ax.tick_params(which="minor", length=0)
    fig.colorbar(im, ax=ax, label="P(abnormal)")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def forecast_timeline(daily: pd.DataFrame, fc: pd.DataFrame, path: Path) -> None:
    hist = daily[daily["date"] >= "2026-06-01"]
    fut = fc[fc["date"] <= "2027-02-28"]
    fig, ax = plt.subplots(figsize=(13, 5.5))
    ax.plot(hist["date"], hist["total"], color="#333", lw=1.2, label="actual spend")
    ax.plot(fut["date"], fut["expected_spend"], color="#2f6f8f", lw=1.4, ls="--", label="forecast spend")
    sc = ax.scatter(fut["date"], fut["expected_spend"], c=fut["p_abnormal"], cmap="YlOrRd",
                    vmin=0, vmax=1, s=26, zorder=3, edgecolor="none")
    ax.axvline(daily["date"].max(), color="grey", ls=":", lw=1)

    # one callout for the biggest predicted day; the full list lives in the CSV
    top = fut.loc[fut["expected_spend"].idxmax()]
    ax.annotate(f"{top['occasion']}\nGBP {top['expected_spend']:,.0f}",
                (top["date"], top["expected_spend"]),
                textcoords="offset points", xytext=(0, 14), fontsize=8, ha="center",
                color="#7b241c",
                arrowprops={"arrowstyle": "-", "lw": 0.7, "color": "#7b241c"})

    ax.set_ylim(0, fut["expected_spend"].max() * 1.18)
    ax.set_title("Actual spend (recent) vs forecast - point colour = probability of an abnormal day")
    ax.set_ylabel("GBP per day")
    ax.legend(frameon=False, loc="upper left")
    ax.grid(alpha=0.3)
    fig.colorbar(sc, ax=ax, label="P(abnormal)")
    fig.autofmt_xdate(rotation=25)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def upcoming_bar(fc: pd.DataFrame, path: Path) -> pd.DataFrame:
    top = fc.sort_values("p_abnormal", ascending=False).head(12).sort_values("p_abnormal")
    fig, ax = plt.subplots(figsize=(10, 5.5))
    labels = [f"{r.date:%d %b %Y}  {r.dow_name}" for r in top.itertuples()]
    ax.barh(labels, top["p_abnormal"], color="#c0392b")
    for y, (p, occ) in enumerate(zip(top["p_abnormal"], top["occasion"])):
        ax.annotate(f"{p:.0%}  {occ}", (p, y), va="center", ha="left", fontsize=9,
                    xytext=(4, 0), textcoords="offset points")
    ax.set_xlim(0, 1.15)
    ax.set_xlabel("probability of an abnormal spending day")
    ax.set_title("Top 12 days most likely to blow the budget (next 12 months)")
    ax.grid(axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return top.sort_values("p_abnormal", ascending=False)


# --------------------------------------------------------------------------- #
def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    daily, events = load()
    tx = pd.read_csv(DATA / "transactions_fake.csv", parse_dates=["date"])

    metrics = evaluate(daily, events)
    fc, _clf, _reg = forecast(daily, events)
    fc.to_csv(OUT / "forecast_next_12_months.csv", index=False)

    profile = (daily.assign(dow=daily["date"].dt.day_of_week).groupby("dow")["total"]
               .agg(days="size", mean_spend="mean", median_spend="median"))
    profile["dow"] = [DOW[i] for i in profile.index]
    profile["index_vs_avg"] = profile["mean_spend"] / daily["total"].mean()
    profile["share_of_week"] = (profile["mean_spend"] * profile["days"]) / daily["total"].sum()
    profile.reset_index(drop=True).round(2).to_csv(OUT / "weekday_profile.csv", index=False)

    last12 = tx[tx["date"] >= daily["date"].max() - pd.Timedelta(days=365)]
    cat_share = pie_category(last12, OUT / "pie_by_category.png")
    occ_share = pie_occasion(fc, OUT / "pie_by_occasion.png")
    weekday_bar(profile.reset_index(drop=True), OUT / "weekday_spend.png")
    calendar_heatmap(fc, OUT / "risk_calendar.png")
    forecast_timeline(daily, fc, OUT / "forecast_timeline.png")
    top = upcoming_bar(fc, OUT / "top_upcoming_days.png")

    summary = {
        **metrics,
        "data_days": int(len(daily)),
        "mean_daily_spend": round(float(daily["total"].mean()), 2),
        "forecast_window": [FORECAST_START, FORECAST_END],
        "forecast_total": round(float(fc["expected_spend"].sum()), 2),
        "days_flagged_abnormal": int(fc["abnormal"].sum()),
        "top_weekday": profile.loc[profile["mean_spend"].idxmax(), "dow"],
        "category_share": {k: round(100 * v / cat_share.sum(), 1) for k, v in cat_share.items()},
        "occasion_share": {k: round(100 * v / occ_share.sum(), 1) for k, v in occ_share.items()},
        "top_upcoming_days": [
            {"date": f"{r.date:%Y-%m-%d}", "weekday": r.dow_name,
             "p_abnormal": round(float(r.p_abnormal), 3),
             "expected_spend": float(r.expected_spend), "occasion": r.occasion}
            for r in top.itertuples()
        ],
    }
    (OUT / "metrics.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps({k: summary[k] for k in
                      ["threshold_gbp", "roc_auc", "average_precision", "precision_at_10",
                       "baseline_precision_at_10", "precision_at_25", "spend_mae_gbp",
                       "top_weekday", "forecast_total", "days_flagged_abnormal"]}, indent=2))
    print("\nTop upcoming high-spend days:")
    print(top.head(8)[["date", "dow_name", "p_abnormal", "expected_spend", "occasion"]].to_string(index=False))
    print(f"\nreports -> {OUT}")


if __name__ == "__main__":
    main()
