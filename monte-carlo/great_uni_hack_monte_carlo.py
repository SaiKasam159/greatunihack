"""Personalised Monte Carlo simulator for Finance Your Friday (GreatUniHack). See monte-carlo/README.md."""

# =============================================================================
#  Personalised Monte Carlo simulator - "Finance Your Friday" (GreatUniHack)
#  "Financial time travel": how each plan the agents suggest changes YOUR future
# =============================================================================
#
#  Quick start
#  -----------
#      python great_uni_hack_monte_carlo.py                  # demo (Maya + Sam): charts, HTML report, ui_data.json
#      python great_uni_hack_monte_carlo.py --persona maya
#      python great_uni_hack_monte_carlo.py --test           # self-tests
#      python great_uni_hack_monte_carlo.py --transactions spend-risk/data/transactions_fake.csv \
#             --income '{"monthly": 2100, "payday": 28}' --balances '{"current": 400, "emergency": 150}'
#
#  Python API (for the agents / Streamlit UI)
#  ------------------------------------------
#      tx      = load_transactions("transactions.csv")         # accepts the team schemas (see below)
#      profile = build_profile(tx, balances, income=None)      # habits + personal comfort profile
#      results = simulate(profile, plans, horizon_months=60, n_sims=1000, seed=42)
#      summary = summarise(results)                            # plain-language headlines (JSON-safe)
#      ui      = ui_payload(results)                           # exactly what the UI screens show
#      figs    = make_charts(results, out_dir="charts")        # presentable matplotlib figures
#      make_report(results, summary, "report.html")            # one-page HTML for the demo
#      checkin_forecast(profile, plan, overspend=85)           # Saturday "repair your forecast"
#
#  Transactions accepted
#  ---------------------
#    * README schema:      timestamp, amount, category, merchant[, balance]
#    * spend-risk schema:  date, time, category, merchant, amount[, note, payment_method]
#  Sign: negative = money out. If every amount is positive, they are treated as
#  spending (income categories excepted). Spend-only data has no salary, so pass
#  income={"monthly": ..., "payday": ...} (otherwise it is estimated, with a warning).
#  If a "balance" column exists, the latest balance becomes the current account.
#
#  Accounts / the fund ladder (README section 5)
#  ---------------------------------------------
#    current   - day-to-day account
#    emergency - easy access; target = emergency_target_months x essential costs. Always first.
#    savings   - short / medium-term goals
#    growth    - stocks & shares ISA / index fund; stochastic returns.
#                LOCKED until the emergency fund hits its target: any contribution aimed
#                at growth goes to the emergency fund until then (enforced per simulated future).
#  If the current account goes negative it is topped up from emergency, then savings
#  ("dipping into savings"); if both are empty the person is overdrawn.
#
#  Plans (what the agents hand over) - list of dicts:
#      {"id": "sweep", "label": "Sweep it", "tagline": "...", "how": "...", "actions": [...]}
#  Actions:
#      reduce_category     {"category": "dining" | [..] | "*", "pct": 0.25,
#                           "when": {"weekdays": ["Fri","Sat"], "night": true},   # optional
#                           "start_day": 0, "days": 7}                            # optional time limit
#      cap_window          {"cap": 40, "category": [..], "when": {...}, "adherence": 0.8}
#                           # budget per red-zone day/night; honoured with probability `adherence`
#      recurring_transfer  {"to": "emergency"|"savings"|"growth", "amount": 30,
#                           "freq": "monthly"|"weekly", "day": 28, "weekday": "Fri", "start_month": 0}
#      sweep_surplus       {"to": "growth", "keep": 150}   # day before payday, move what's left above `keep`
#                           # (default keep = their personal comfort floor)
#      lump_sum_transfer   {"to": "emergency", "amount": 15, "day_offset": 0}
#      one_off_purchase    {"amount": 400, "date": "2026-12-01"} or {"amount": 400, "day_offset": 6}
#      cancel_subscription {"merchant": "Netflix"}
#      reduce_bill         {"merchant": "OctoEnergy", "pct": 0.15}
#  A baseline plan ("If you keep overspending" = carry on as you are) is always added.
#
#  How the simulation works
#  ------------------------
#  * Habits are learned per (category, weekday, day/night) window: how often the
#    person spends in it and an empirical pool of what they actually spent. Futures
#    are bootstrapped from those pools, so real Friday-night spikes and fat tails
#    survive (no smoothing into a normal distribution).
#  * Unusually large one-offs (> Q3 + 3*IQR in a category) are modelled as rare
#    shocks, so "the occasional big night" appears in every future.
#  * Income, bills, subscriptions and standing transfers are detected and scheduled.
#  * All plans see the same random futures (common random numbers), so differences
#    come from the decision, not luck.
#
#  "Comfortable" is personal - nothing here is a fixed number
#  ----------------------------------------------------------
#  From each person's own history: essentials; the lifestyle they value (non-essential
#  categories they spend on in at least half of all weeks, plus subscriptions); and a
#  personal comfort floor = 3 days of their own normal outgoings (ex rent).
#  A month is comfortable if they never drop below their floor and never raid savings.
#      comfort_score = 100 * P(comfortable month) * min(1, lifestyle_kept / 0.8)
#  (further scaled down if a plan keeps < 60% of the lifestyle they value).
#  Guidance, not regulated advice: illustrative returns, fund types not products.
# =============================================================================

from __future__ import annotations

import argparse
import base64
import io
import json
import math
import os
import sys
import warnings

import numpy as np
import pandas as pd

WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
ESSENTIAL_CATEGORIES = {"rent", "bills", "groceries", "transport", "health"}
RECURRING_CATEGORIES = {"rent", "bills", "subscriptions", "savings_transfer",
                        "emergency_transfer", "investment_transfer"}
TRANSFER_CATEGORIES = {"savings_transfer": "savings", "emergency_transfer": "emergency",
                       "investment_transfer": "growth"}
INCOME_CATEGORIES = {"salary", "income", "wages"}
SUBSCRIPTION_HINTS = ("netflix", "spotify", "icloud", "disney", "prime", "gym", "youtube",
                      "apple music", "now tv", "xbox", "playstation", "kindle")
CATEGORY_ALIASES = {
    "eating out": "dining", "restaurants": "dining", "restaurant": "dining",
    "takeaways": "takeaway", "food delivery": "takeaway",
    "bars": "entertainment", "nightlife": "entertainment", "pubs": "entertainment", "going out": "entertainment",
    "grocery": "groceries", "travel": "transport", "utilities": "bills",
    "subscription": "subscriptions", "pay": "salary", "wage": "salary",
}
FUND_ALIASES = {"growth": "growth", "investments": "growth", "investment": "growth", "isa": "growth",
                "emergency": "emergency", "savings": "savings"}
NIGHT_START_HOUR = 18   # 18:00 onwards counts as "night"
NIGHT_END_HOUR = 4      # spending before 04:00 belongs to the previous night
DAYS_PER_MONTH = 365.25 / 12
WEEKS_PER_MONTH = DAYS_PER_MONTH / 7
PERCENTILES = [10, 25, 50, 75, 90]

DEFAULT_ASSUMPTIONS = {
    "savings_rate": 0.04,             # AER on emergency + savings
    "invest_return": 0.07,            # illustrative growth-fund return
    "invest_vol": 0.15,               # illustrative growth-fund volatility
    "emergency_target_months": 1.0,   # README: 1-3 months of essential costs
    "emergency_target": None,         # or a fixed £ amount
    "ladder": True,                   # growth locked until emergency target is met
    "comfort_floor_days": 3,
    "lifestyle_ok": 0.6,
    "lifestyle_full": 0.8,
    "valued_weeks_active": 0.5,
    "short_term_days": 90,
    "shock_amount": 300.0,            # "Probability you can cover a surprise £300 bill next month"
}
DEFAULT_BALANCES = {"current": 500.0, "emergency": 0.0, "savings": 0.0, "growth": 0.0}

# UI design tokens (ui/README.md)
UI = {"text": "#16181D", "text2": "#5F6475", "tile": "#F4F5F7", "accent": "#1A73E8",
      "red": "#D9480F", "red_text": "#B93A0B", "red_tint": "#FFF4EC", "plan_tint": "#EAF2FD",
      "success": "#1E7B38", "success_tint": "#E6F4EA", "grid": "#DADDE3"}
PLAN_COLOURS = ["#1A73E8", "#1E7B38", "#7B4DD8", "#0B8A8A", "#B26B00", "#C2185B"]


# -----------------------------------------------------------------------------
#  Helpers
# -----------------------------------------------------------------------------
def _weekday_index(x) -> int:
    if isinstance(x, (int, np.integer)):
        return int(x) % 7
    s = str(x).strip().lower()[:3]
    for i, n in enumerate(WEEKDAY_NAMES):
        if n.lower() == s:
            return i
    raise ValueError(f"Unknown weekday: {x!r}")


def window_label(weekday: int, night: bool) -> str:
    return f"{WEEKDAY_NAMES[weekday]} {'night' if night else 'daytime'}"


def _effective_day_and_night(ts: pd.Series):
    """02:00 on Saturday still counts as Friday night."""
    hour = ts.dt.hour
    early = hour < NIGHT_END_HOUR
    eff = ts.dt.normalize() - pd.to_timedelta(early.astype(int), unit="D")
    night = (hour >= NIGHT_START_HOUR) | early
    return eff, night


def _money(x: float) -> str:
    return f"-£{abs(x):,.0f}" if x < 0 else f"£{x:,.0f}"


def _money_k(x: float) -> str:
    """UI style: £13.2k, £950."""
    sign = "-" if x < 0 else ""
    x = abs(x)
    return f"{sign}£{x / 1000:.1f}k" if x >= 1000 else f"{sign}£{x:,.0f}"


def _pct_dict(arr: np.ndarray, axis=0) -> dict:
    vals = np.percentile(arr, PERCENTILES, axis=axis)
    return {f"p{p}": v for p, v in zip(PERCENTILES, vals)}


def _fund(name) -> str:
    f = FUND_ALIASES.get(str(name or "savings").lower())
    if not f:
        raise ValueError(f"Unknown fund {name!r} (use emergency, savings or growth)")
    return f


# -----------------------------------------------------------------------------
#  Loading the team's transaction formats
# -----------------------------------------------------------------------------
def load_transactions(source) -> pd.DataFrame:
    """CSV path or DataFrame in either team schema -> timestamp, amount, merchant, category[, balance]."""
    df = pd.read_csv(source) if isinstance(source, (str, os.PathLike)) else source.copy()
    df.columns = [str(c).strip().lower() for c in df.columns]
    if "timestamp" not in df.columns:
        if "date" not in df.columns:
            raise ValueError("Need a 'timestamp' column, or 'date' (+ optional 'time').")
        t = df["time"].fillna("12:00").astype(str) if "time" in df.columns else "12:00"
        df["timestamp"] = pd.to_datetime(df["date"].astype(str) + " " + t)
    df["timestamp"] = pd.to_datetime(df["timestamp"])
    df["merchant"] = df.get("merchant", pd.Series("unknown", index=df.index)).fillna("unknown").astype(str)
    cat = df.get("category", pd.Series("other", index=df.index)).fillna("other").astype(str).str.strip().str.lower()
    df["category"] = cat.map(lambda c: CATEGORY_ALIASES.get(c, c))
    # subscriptions hiding inside "bills" (spend-risk data puts Netflix/Spotify/Gym there)
    hint_text = (df["merchant"] + " " + df.get("note", pd.Series("", index=df.index)).fillna("").astype(str)).str.lower()
    is_sub = hint_text.apply(lambda s: any(h in s for h in SUBSCRIPTION_HINTS))
    df.loc[is_sub & df["category"].isin({"bills", "entertainment", "other"}), "category"] = "subscriptions"
    df["amount"] = df["amount"].astype(float)
    if (df["amount"] >= 0).all():
        income = df["category"].isin(INCOME_CATEGORIES)
        df.loc[~income, "amount"] = -df.loc[~income, "amount"]
    cols = ["timestamp", "amount", "merchant", "category"] + (["balance"] if "balance" in df.columns else [])
    return df[cols].sort_values("timestamp").reset_index(drop=True)


# -----------------------------------------------------------------------------
#  Synthetic demo personas (no real personal data in the repo)
# -----------------------------------------------------------------------------
_ALL_DAYS = [0, 1, 2, 3, 4, 5, 6]
PERSONAS = {
    "maya": {
        "name": "Maya",
        "description": "24, retail worker, paid monthly, no real buffer, Friday nights out",
        "employer": "High Street Retail Ltd", "salary": 1760.0, "payday": 28,
        "balances": {"current": 1050.0, "emergency": 180.0, "savings": 0.0, "growth": 0.0},
        # merchant, category, amount, noise std, day of month
        "recurring": [
            ("Landlord", "rent", 650, 0, 1),
            ("OctoEnergy", "bills", 62, 10, 5),
            ("PhoneCo", "bills", 20, 0, 12),
            ("Netflix", "subscriptions", 10.99, 0, 15),
            ("Spotify", "subscriptions", 11.99, 0, 20),
            ("Emergency pot", "emergency_transfer", 15, 0, 29),
        ],
        # category, merchants, weekdays, (from hour, to hour; >24 = after midnight), prob, mean £, sigma
        "habits": [
            ("groceries", ["Tesco", "Aldi"], [2, 6], (17, 20), 0.9, 29, 0.3),
            ("transport", ["Bus"], [0, 1, 2, 3, 4], (7, 9), 0.8, 2.6, 0.1),
            ("coffee", ["Greggs", "Costa"], [0, 1, 2, 3, 4], (8, 10), 0.45, 3.2, 0.2),
            ("entertainment", ["The Bar", "Club XS", "The Crown"], [4], (20, 26), 0.85, 52, 0.5),
            ("entertainment", ["The Bar", "Club XS", "The Crown"], [5], (20, 26), 0.5, 38, 0.5),
            ("entertainment", ["The Crown"], [2], (19, 23), 0.2, 20, 0.4),   # sports night
            ("takeaway", ["Deliveroo", "Uber Eats"], [4, 5], (23, 27), 0.45, 16, 0.3),
            ("dining", ["Nando's", "Wagamama"], [3, 6], (18, 21), 0.2, 24, 0.3),
            ("shopping", ["ASOS", "Primark"], _ALL_DAYS, (12, 22), 0.09, 30, 0.7),
        ],
        "anomaly": {"category": "entertainment", "merchants": ["Club XS", "Birthday drinks"],
                    "weekdays": [4, 5], "rate_per_week": 0.18, "mean": 115, "sigma": 0.3},
    },
    "sam": {
        "name": "Sam",
        "description": "27, homebody, climbing and books, already has a buffer",
        "employer": "Widget Co", "salary": 2600.0, "payday": 25,
        "balances": {"current": 1900.0, "emergency": 1800.0, "savings": 1700.0, "growth": 1200.0},
        "recurring": [
            ("Landlord", "rent", 900, 0, 1),
            ("OctoEnergy", "bills", 70, 10, 5),
            ("PhoneCo", "bills", 18, 0, 10),
            ("The Climbing Wall", "subscriptions", 45, 0, 2),
            ("Kindle Unlimited", "subscriptions", 9.49, 0, 18),
            ("Savings pot", "savings_transfer", 250, 0, 26),
        ],
        "habits": [
            ("groceries", ["Sainsbury's", "Lidl"], [1, 4, 6], (17, 20), 0.85, 28, 0.3),
            ("transport", ["Trainline"], [0, 1, 2, 3, 4], (7, 9), 0.6, 4.2, 0.15),
            ("hobbies", ["Waterstones", "Climbing Shop"], [1, 6], (11, 19), 0.5, 21, 0.45),
            ("coffee", ["Local Cafe"], [5, 6], (9, 12), 0.5, 4.0, 0.2),
            ("entertainment", ["Cinema", "The Crown"], [5], (19, 23), 0.2, 30, 0.4),
            ("takeaway", ["Deliveroo"], [4], (19, 22), 0.3, 22, 0.3),
            ("shopping", ["Amazon"], _ALL_DAYS, (12, 22), 0.07, 30, 0.6),
        ],
        "anomaly": {"category": "shopping", "merchants": ["Climbing Shop"],
                    "weekdays": [5, 6], "rate_per_week": 0.05, "mean": 180, "sigma": 0.3},
    },
}


def generate_demo_transactions(persona: str = "maya", months: int = 12,
                               start: str = "2025-11-01", seed: int = 7) -> pd.DataFrame:
    """Realistic synthetic transaction history for a demo persona (README schema)."""
    spec = PERSONAS[persona]
    rng = np.random.default_rng(seed)
    start_ts = pd.Timestamp(start)
    end_ts = start_ts + pd.DateOffset(months=months) - pd.Timedelta(days=1)
    rows = []

    def add(ts, amount, merchant, category):
        rows.append((ts, round(float(amount), 2), str(merchant), category))

    def lognormal(mean, sigma):
        return rng.lognormal(math.log(mean) - sigma ** 2 / 2, sigma)

    for day in pd.date_range(start_ts, end_ts, freq="D"):
        dim, wd = day.days_in_month, day.weekday()
        if day.day == min(spec["payday"], dim):
            add(day + pd.Timedelta(hours=6), spec["salary"], spec["employer"], "salary")
        for merchant, cat, amount, noise, dom in spec["recurring"]:
            if day.day == min(dom, dim):
                amt = amount + (rng.normal(0, noise) if noise else 0.0)
                add(day + pd.Timedelta(hours=9), -max(0.0, amt), merchant, cat)
        for cat, merchants, wds, (lo, hi), p, mean, sigma in spec["habits"]:
            if wd in wds and rng.random() < p:
                add(day + pd.Timedelta(hours=rng.uniform(lo, hi)), -lognormal(mean, sigma),
                    rng.choice(merchants), cat)
        a = spec.get("anomaly")
        if a and wd in a["weekdays"] and rng.random() < a["rate_per_week"] / len(a["weekdays"]):
            add(day + pd.Timedelta(hours=rng.uniform(21, 26)), -lognormal(a["mean"], a["sigma"]),
                rng.choice(a["merchants"]), a["category"])

    df = pd.DataFrame(rows, columns=["timestamp", "amount", "merchant", "category"])
    return df.sort_values("timestamp").reset_index(drop=True)


# -----------------------------------------------------------------------------
#  Profile: learn habits + the personal comfort profile from history
# -----------------------------------------------------------------------------
def build_profile(transactions: pd.DataFrame, balances: dict | None = None, name: str = "user",
                  income: dict | None = None, assumptions: dict | None = None) -> dict:
    a = {**DEFAULT_ASSUMPTIONS, **(assumptions or {})}
    tx = load_transactions(transactions)

    first, last = tx.timestamp.min().normalize(), tx.timestamp.max().normalize()
    calendar = pd.date_range(first, last, freq="D")
    n_days = len(calendar)
    weekday_counts = np.bincount(calendar.weekday, minlength=7).astype(float)
    n_weeks = max(1, calendar.to_period("W").nunique())
    n_months = max(1, calendar.to_period("M").nunique())

    # --- recurring bills, subscriptions, standing transfers ------------------
    out = tx[tx.amount < 0].copy()
    out["spend"] = -out.amount
    out["eff_day"], out["night"] = _effective_day_and_night(out.timestamp)
    out["weekday"] = out.eff_day.dt.weekday
    used = pd.Series(False, index=out.index)
    recurring = []
    for (merchant, cat), g in out[out.category.isin(RECURRING_CATEGORIES)].groupby(["merchant", "category"]):
        months_seen = g.timestamp.dt.to_period("M").nunique()
        if months_seen >= max(2, 0.5 * n_months):
            per_month = g.groupby(g.timestamp.dt.to_period("M")).spend.sum()
            recurring.append({
                "merchant": merchant, "category": cat,
                "amount": float(per_month.mean()), "std": float(per_month.std(ddof=0)),
                "day": int(g.timestamp.dt.day.mode().iloc[0]),
                "transfer_to": TRANSFER_CATEGORIES.get(cat),
            })
            used.loc[g.index] = True

    # --- discretionary habits + anomalies -------------------------------------
    disc = out[~used & ~out.category.isin(TRANSFER_CATEGORIES)]
    is_anom = pd.Series(False, index=disc.index)
    anomalies = {}
    for cat, g in disc.groupby("category"):
        if len(g) < 8:
            continue
        q1, q3 = g.spend.quantile([0.25, 0.75])
        flag = g.spend > q3 + 3 * (q3 - q1)
        if flag.any():
            ga = g[flag]
            is_anom.loc[ga.index] = True
            anomalies[cat] = {
                "rate_per_day": len(ga) / n_days,
                "pool": ga.spend.to_numpy(),
                "windows": list(zip(ga.weekday.astype(int).tolist(), ga.night.astype(bool).tolist())),
                "count": int(len(ga)),
            }
    regular = disc[~is_anom]
    keys = []
    daily = regular.groupby(["category", "weekday", "night", "eff_day"]).spend.sum()
    for (cat, wd, night), s in daily.groupby(level=[0, 1, 2]):
        pool = s.to_numpy()
        keys.append({"category": cat, "weekday": int(wd), "night": bool(night),
                     "p": float(min(1.0, len(s) / weekday_counts[int(wd)])),
                     "pool": pool, "mean": float(pool.mean())})

    cat_monthly: dict[str, float] = {}
    for k in keys:
        cat_monthly[k["category"]] = cat_monthly.get(k["category"], 0) + k["p"] * k["mean"] * WEEKS_PER_MONTH
    for cat, an in anomalies.items():
        cat_monthly[cat] = cat_monthly.get(cat, 0) + an["rate_per_day"] * an["pool"].mean() * DAYS_PER_MONTH
    rec_spend = [r for r in recurring if not r["transfer_to"]]
    rec_by_cat: dict[str, float] = {}
    for r in rec_spend:
        rec_by_cat[r["category"]] = rec_by_cat.get(r["category"], 0) + r["amount"]
    total_spend_monthly = sum(rec_by_cat.values()) + sum(cat_monthly.values())

    # --- income ---------------------------------------------------------------
    inc = tx[tx.amount > 0]
    salary = inc[inc.category.isin(INCOME_CATEGORIES)]
    if salary.empty:
        salary = inc
    if income:
        income_p = {"monthly_mean": float(income.get("monthly", income.get("monthly_mean"))),
                    "monthly_std": float(income.get("monthly_std", 0.0)),
                    "payday": int(income.get("payday", 28))}
    elif not salary.empty:
        by_month = salary.timestamp.dt.to_period("M")
        monthly_income = salary.groupby(by_month).amount.sum()
        biggest = salary.loc[salary.groupby(by_month).amount.idxmax()]
        income_p = {"monthly_mean": float(monthly_income.median()),
                    "monthly_std": float(monthly_income.std(ddof=0)) if len(monthly_income) > 1 else 0.0,
                    "payday": int(biggest.timestamp.dt.day.mode().iloc[0])}
    else:
        transfers = sum(r["amount"] for r in recurring if r["transfer_to"])
        est = 1.03 * (total_spend_monthly + transfers)
        warnings.warn(f"No income in transactions; assuming £{est:,.0f}/month paid on the 28th. "
                      "Pass income={'monthly': ..., 'payday': ...} for real numbers.")
        income_p = {"monthly_mean": est, "monthly_std": 0.0, "payday": 28, "estimated": True}

    # --- personal comfort profile ---------------------------------------------
    weeks_active = disc.groupby("category").eff_day.apply(lambda s: s.dt.to_period("W").nunique() / n_weeks)
    essentials_monthly = sum(v for c, v in rec_by_cat.items() if c in ESSENTIAL_CATEGORIES) + \
        sum(v for c, v in cat_monthly.items() if c in ESSENTIAL_CATEGORIES)
    valued = []
    for cat, m in sorted(cat_monthly.items(), key=lambda kv: -kv[1]):
        if cat in ESSENTIAL_CATEGORIES:
            continue
        wa = float(weeks_active.get(cat, 0.0))
        if wa >= a["valued_weeks_active"] and m >= 10:
            ck = [k for k in keys if k["category"] == cat]
            fav = max(ck, key=lambda k: k["p"] * k["mean"]) if ck else None
            valued.append({
                "category": cat, "monthly": float(m), "weeks_active": wa,
                "times_per_month": float(sum(k["p"] for k in ck) * WEEKS_PER_MONTH),
                "favourite_window": window_label(fav["weekday"], fav["night"]) if fav else None,
            })
    subscriptions = [{"merchant": r["merchant"], "monthly": r["amount"]}
                     for r in rec_spend if r["category"] == "subscriptions"]
    lifestyle_monthly = sum(v["monthly"] for v in valued) + sum(s["monthly"] for s in subscriptions)
    daily_outgoings = (total_spend_monthly - rec_by_cat.get("rent", 0.0)) / DAYS_PER_MONTH
    emergency_target = a["emergency_target"] or round(a["emergency_target_months"] * essentials_monthly, -1)
    comfort = {
        "essentials_monthly": float(essentials_monthly),
        "valued": valued,
        "subscriptions": subscriptions,
        "lifestyle_monthly": float(lifestyle_monthly),
        "comfortable_monthly": float(essentials_monthly + lifestyle_monthly),
        "total_spend_monthly": float(total_spend_monthly),
        "comfort_floor": float(a["comfort_floor_days"] * daily_outgoings),
    }

    # --- red zones / risk windows (the "Friday night effect") ------------------
    windows: dict[tuple, dict] = {}
    for k in keys:
        if k["category"] in ESSENTIAL_CATEGORIES:
            continue
        w = windows.setdefault((k["weekday"], k["night"]), {"weekly": 0.0, "categories": set()})
        w["weekly"] += k["p"] * k["mean"]
        w["categories"].add(k["category"])
    for cat, an in anomalies.items():
        if cat in ESSENTIAL_CATEGORIES:
            continue
        per_event = an["rate_per_day"] * 7 * an["pool"].mean() / an["count"]
        for wd, nt in an["windows"]:
            w = windows.setdefault((wd, nt), {"weekly": 0.0, "categories": set()})
            w["weekly"] += per_event
            w["categories"].add(cat)
    risk_windows = sorted(
        ({"label": window_label(wd, nt), "weekday": wd, "night": nt, "weekly": v["weekly"],
          "monthly": v["weekly"] * WEEKS_PER_MONTH, "categories": sorted(v["categories"])}
         for (wd, nt), v in windows.items()),
        key=lambda w: -w["weekly"])[:3]

    bal = dict(DEFAULT_BALANCES)
    if "balance" in tx.columns and tx["balance"].notna().any():
        bal["current"] = float(tx["balance"].dropna().iloc[-1])
    for k, v in (balances or {}).items():
        bal["growth" if k in ("investments", "investment", "isa") else k] = float(v)

    return {
        "name": name,
        "history": {"start": str(first.date()), "end": str(last.date()), "days": n_days, "months": n_months},
        "balances": bal,
        "income": income_p,
        "recurring": recurring,
        "keys": keys,
        "anomalies": anomalies,
        "category_monthly": cat_monthly,
        "recurring_monthly": rec_by_cat,
        "comfort": comfort,
        "emergency_target": float(emergency_target),
        "risk_windows": risk_windows,
        "assumptions": a,
    }


def describe_profile(profile: dict) -> str:
    c = profile["comfort"]
    b = profile["balances"]
    lines = [
        f"{profile['name']}: {profile['history']['months']} months of history "
        f"({profile['history']['start']} to {profile['history']['end']})",
        f"  Income ~{_money(profile['income']['monthly_mean'])}/month, paid on day {profile['income']['payday']}"
        + (" (estimated)" if profile["income"].get("estimated") else ""),
        f"  Balances: current {_money(b['current'])}, emergency {_money(b['emergency'])}, "
        f"savings {_money(b['savings'])}, growth {_money(b['growth'])}",
        f"  Essentials ~{_money(c['essentials_monthly'])}/month; valued lifestyle ~{_money(c['lifestyle_monthly'])}/month",
        f"  Comfortable living for them: ~{_money(c['comfortable_monthly'])}/month; personal floor "
        f"{_money(c['comfort_floor'])}; emergency target {_money(profile['emergency_target'])}",
    ]
    for v in c["valued"]:
        lines.append(f"    enjoys {v['category']}: ~{v['times_per_month']:.0f}x/month, {_money(v['monthly'])}/month, "
                     f"usually {v['favourite_window']}")
    for w in profile["risk_windows"]:
        lines.append(f"  Red zone {w['label']}: ~{_money(w['weekly'])}/week ({', '.join(w['categories'])})")
    return "\n".join(lines)


# -----------------------------------------------------------------------------
#  Plan actions -> multipliers
# -----------------------------------------------------------------------------
def _action_categories(act: dict) -> set:
    c = act.get("category", act.get("categories", "*"))
    if c in ("*", "all"):
        return {"*"}
    return {c.lower()} if isinstance(c, str) else {str(x).lower() for x in c}


def _when_matches(when: dict | None, weekday: int, night: bool) -> bool:
    if not when:
        return True
    wds = when.get("weekdays", when.get("weekday"))
    if wds is not None:
        wds = wds if isinstance(wds, (list, tuple)) else [wds]
        if weekday not in {_weekday_index(w) for w in wds}:
            return False
    nt = when.get("night")
    if nt is None and "hours" in when:
        nt = True
    return nt is None or bool(nt) == night


def _matches(act: dict, cat: str, weekday: int, night: bool) -> bool:
    cats = _action_categories(act)
    if "*" in cats and cat in ESSENTIAL_CATEGORIES and not act.get("include_essentials"):
        return False
    return ("*" in cats or cat in cats) and _when_matches(act.get("when"), weekday, night)


def _key_factor_days(cat, weekday, night, actions, day_idx: np.ndarray) -> np.ndarray:
    """Per-day spend multiplier from reduce_category actions (supports time limits)."""
    f = np.ones(len(day_idx))
    for act in actions:
        if act.get("type") == "reduce_category" and _matches(act, cat, weekday, night):
            s, n = int(act.get("start_day", 0)), act.get("days")
            mask = (day_idx >= s) & ((day_idx < s + int(n)) if n is not None else True)
            f[mask] *= 1.0 - float(act.get("pct", 0.0))
    return np.maximum(f, 0.0)


def _key_factor(cat, weekday, night, actions) -> float:
    """Long-run multiplier (ignores time-limited actions)."""
    f = 1.0
    for act in actions:
        if act.get("type") == "reduce_category" and act.get("days") is None and _matches(act, cat, weekday, night):
            f *= 1.0 - float(act.get("pct", 0.0))
    return max(0.0, f)


def _cap_ratio(pool: np.ndarray, factor: float, cat, weekday, night, actions) -> float:
    """Expected share of spend kept under cap_window actions."""
    r = 1.0
    for act in actions:
        if act.get("type") == "cap_window" and _matches(act, cat, weekday, night):
            x = pool * factor
            if x.mean() > 0:
                adh = float(act.get("adherence", 0.8))
                r *= adh * np.minimum(x, float(act["cap"])).mean() / x.mean() + (1 - adh)
            break
    return r


def _recurring_factor(r: dict, actions: list) -> float:
    f = 1.0
    for act in actions:
        t = act.get("type")
        m = str(act.get("merchant", "")).lower()
        if t in ("cancel_subscription", "reduce_bill") and m and m in r["merchant"].lower():
            f *= 0.0 if t == "cancel_subscription" else 1.0 - float(act.get("pct", 0.0))
    return max(0.0, f)


def _expected_lifestyle(profile: dict, actions: list) -> dict:
    """Expected monthly spend on each valued category (+ subscriptions) under a plan."""
    valued = {v["category"] for v in profile["comfort"]["valued"]}
    res = {c: 0.0 for c in valued}
    for k in profile["keys"]:
        if k["category"] in valued:
            f = _key_factor(k["category"], k["weekday"], k["night"], actions)
            res[k["category"]] += k["p"] * k["mean"] * WEEKS_PER_MONTH * f * \
                _cap_ratio(k["pool"], f, k["category"], k["weekday"], k["night"], actions)
    for cat, an in profile["anomalies"].items():
        if cat in valued:
            fs = [_key_factor(cat, wd, nt, actions) * _cap_ratio(an["pool"], _key_factor(cat, wd, nt, actions),
                                                                 cat, wd, nt, actions)
                  for wd, nt in an["windows"]]
            res[cat] += an["rate_per_day"] * an["pool"].mean() * DAYS_PER_MONTH * float(np.mean(fs))
    subs = [r for r in profile["recurring"] if r["category"] == "subscriptions"]
    if subs:
        res["subscriptions"] = sum(r["amount"] * _recurring_factor(r, actions) for r in subs)
    return res


# -----------------------------------------------------------------------------
#  Simulation
# -----------------------------------------------------------------------------
def _run_plan(profile: dict, plan: dict, days: pd.DatetimeIndex, month_idx: np.ndarray,
              n_sims: int, seed: int) -> dict:
    a = profile["assumptions"]
    n, D, M = n_sims, len(days), int(month_idx[-1]) + 1
    wd = np.asarray(days.weekday)
    dom = np.asarray(days.day)
    dim = np.asarray(days.days_in_month)
    all_days = np.arange(D)
    actions = plan.get("actions", [])
    target = profile["emergency_target"]
    floor = profile["comfort"]["comfort_floor"]

    def rng(*k):  # same stream per component across plans -> fair comparisons
        return np.random.default_rng([seed, *k])

    delta = np.zeros((n, D))                                     # net change to current account
    to_fund = {f: np.zeros(D) for f in ("emergency", "savings", "growth")}
    to_growth_gated = np.zeros(D)                                # growth contributions behind the ladder

    inc = profile["income"]
    pay_idx = np.flatnonzero(dom == np.minimum(inc["payday"], dim))
    delta[:, pay_idx] += np.maximum(rng(1).normal(inc["monthly_mean"], inc["monthly_std"], (n, len(pay_idx))), 0)

    for i, r in enumerate(profile["recurring"]):
        idx = np.flatnonzero(dom == np.minimum(r["day"], dim))
        draws = rng(2, i).normal(r["amount"], r["std"], (n, len(idx)))
        f = _recurring_factor(r, actions)
        if r["transfer_to"]:
            delta[:, idx] -= r["amount"] * f
            to_fund[r["transfer_to"]][idx] += r["amount"] * f
        else:
            delta[:, idx] -= np.maximum(draws, 0) * f

    caps = [(act, np.zeros((n, D))) for act in actions if act.get("type") == "cap_window"]

    def spend(cat, weekday, night, idx, amounts):
        for act, acc in caps:
            if _matches(act, cat, weekday, night):
                acc[:, idx] += amounts
                return
        delta[:, idx] -= amounts

    for i, k in enumerate(profile["keys"]):
        idx = np.flatnonzero(wd == k["weekday"])
        r = rng(3, i)
        hit = r.random((n, len(idx))) < k["p"]
        amt = k["pool"][r.integers(0, len(k["pool"]), (n, len(idx)))]
        f = _key_factor_days(k["category"], k["weekday"], k["night"], actions, idx)
        spend(k["category"], k["weekday"], k["night"], idx, hit * amt * f)

    for j, (cat, an) in enumerate(sorted(profile["anomalies"].items())):
        r = rng(4, j)
        hit = r.random((n, D)) < an["rate_per_day"]
        amt = an["pool"][r.integers(0, len(an["pool"]), (n, D))]
        uniq = sorted(set(an["windows"]))
        weights = np.array([an["windows"].count(w) for w in uniq], float)
        w_choice = r.choice(len(uniq), size=(n, D), p=weights / weights.sum())   # which kind of night it was
        for wi, (w_wd, w_nt) in enumerate(uniq):
            sel = hit & (w_choice == wi)
            if sel.any():
                f = _key_factor_days(cat, w_wd, w_nt, actions, all_days)
                spend(cat, w_wd, w_nt, all_days, np.where(sel, amt, 0.0) * f)

    for ci, (act, acc) in enumerate(caps):
        comply = rng(6, ci).random((n, D)) < float(act.get("adherence", 0.8))
        delta -= np.where(comply, np.minimum(acc, float(act["cap"])), acc)

    sweep_days, sweeps = {}, []
    for act in actions:
        t = act.get("type")
        if t == "recurring_transfer":
            amt = float(act["amount"])
            if act.get("freq", "monthly") == "weekly":
                idx = np.flatnonzero(wd == _weekday_index(act.get("weekday", "Fri")))
            else:
                idx = np.flatnonzero(dom == np.minimum(int(act.get("day", inc["payday"])), dim))
            idx = idx[month_idx[idx] >= int(act.get("start_month", 0))]
            delta[:, idx] -= amt
            dest = _fund(act.get("to"))
            (to_growth_gated if dest == "growth" and a["ladder"] else to_fund[dest])[idx] += amt
        elif t == "lump_sum_transfer":
            d = int(act.get("day_offset", 0))
            if 0 <= d < D:
                delta[:, d] -= float(act["amount"])
                dest = _fund(act.get("to"))
                (to_growth_gated if dest == "growth" and a["ladder"] else to_fund[dest])[d] += float(act["amount"])
        elif t == "sweep_surplus":
            keep = act.get("keep", "floor")
            keep = floor if keep in (None, "floor") else float(keep)
            pay_day_of_month = np.minimum(inc["payday"], dim)
            idx = np.flatnonzero(dom == np.maximum(pay_day_of_month - 1, 1))
            sweeps.append((idx, keep, _fund(act.get("to", "growth"))))
        elif t == "one_off_purchase":
            d = (pd.Timestamp(act["date"]) - days[0]).days if "date" in act else int(act.get("day_offset", 0))
            if 0 <= d < D:
                delta[:, d] -= float(act["amount"])
        elif t not in ("reduce_category", "cap_window", "cancel_subscription", "reduce_bill"):
            raise ValueError(f"Unknown action type: {t!r} in plan {plan.get('id')}")
    for si, (idx, keep, dest) in enumerate(sweeps):
        for d in idx:
            sweep_days.setdefault(int(d), []).append((keep, dest))

    bal = profile["balances"]
    cur = np.full(n, bal["current"])
    emg = np.full(n, bal["emergency"])
    sav = np.full(n, bal["savings"])
    gro = np.full(n, bal["growth"])
    sav_f = (1 + a["savings_rate"]) ** (1 / 12)
    sig = a["invest_vol"] / math.sqrt(12)
    mu = math.log(1 + a["invest_return"]) / 12 - sig ** 2 / 2
    inv_f = np.exp(rng(5).normal(mu, sig, (n, M)))
    is_month_end = np.r_[month_idx[1:] != month_idx[:-1], True]

    def to_growth(x):
        nonlocal emg, gro
        if a["ladder"]:
            to_e = np.minimum(x, np.maximum(target - emg, 0.0))
            emg = emg + to_e
            gro = gro + (x - to_e)
        else:
            gro = gro + x

    S = min(D, int(a["short_term_days"]))
    rec = {k: np.zeros((n, M)) for k in ("current", "emergency", "savings", "growth")}
    min_cur = np.full((n, M), np.inf)
    min_liq = np.full((n, M), np.inf)
    rescue = np.zeros((n, M), bool)
    overdrawn = np.zeros((n, M), bool)
    short_daily = np.zeros((n, S))
    short_min = np.full(n, np.inf)
    short_rescue = np.zeros(n, bool)
    short_over = np.zeros(n, bool)

    for d in range(D):
        m = month_idx[d]
        cur += delta[:, d]
        if to_fund["emergency"][d]:
            emg += to_fund["emergency"][d]
        if to_fund["savings"][d]:
            sav += to_fund["savings"][d]
        if to_fund["growth"][d]:
            gro += to_fund["growth"][d]
        if to_growth_gated[d]:
            to_growth(np.full(n, to_growth_gated[d]))
        for keep, dest in sweep_days.get(d, ()):
            excess = np.maximum(cur - keep, 0.0)
            cur -= excess
            if dest == "growth":
                to_growth(excess)
            elif dest == "emergency":
                emg += excess
            else:
                sav += excess
        min_cur[:, m] = np.minimum(min_cur[:, m], cur)
        min_liq[:, m] = np.minimum(min_liq[:, m], cur + emg + sav)
        if d < S:
            short_min = np.minimum(short_min, cur)
        neg = cur < 0
        if neg.any():
            need = np.where(neg, -cur, 0.0)
            from_e = np.minimum(need, np.maximum(emg, 0.0))
            from_s = np.minimum(need - from_e, np.maximum(sav, 0.0))
            emg -= from_e
            sav -= from_s
            cur += from_e + from_s
            rescued, over = (from_e + from_s) > 0, cur < -0.005
            rescue[:, m] |= rescued
            overdrawn[:, m] |= over
            if d < S:
                short_rescue |= rescued
                short_over |= over
        if d < S:
            short_daily[:, d] = cur
        if is_month_end[d]:
            emg *= sav_f
            sav *= sav_f
            gro *= inv_f[:, m]
            rec["current"][:, m], rec["emergency"][:, m] = cur, emg
            rec["savings"][:, m], rec["growth"][:, m] = sav, gro

    funds = rec["emergency"] + rec["savings"] + rec["growth"]
    full = rec["emergency"] >= target - 0.5
    unlock = np.where(full.any(axis=1), full.argmax(axis=1) + 1, np.inf)   # 1-based month
    if bal["emergency"] >= target:
        unlock[:] = 0
    return {**rec, "funds": funds, "net_worth": funds + rec["current"], "min_current": min_cur,
            "min_liquid": min_liq, "rescue": rescue, "overdrawn": overdrawn, "unlock_month": unlock,
            "short_daily": short_daily, "short_min": short_min, "short_rescue": short_rescue,
            "short_over": short_over}


def simulate(profile: dict, plans: list | None = None, horizon_months: int = 60,
             n_sims: int = 1000, seed: int = 42, start_date: str | None = None) -> dict:
    """Run every plan (plus the baseline) through the same set of simulated futures."""
    plans = [dict(p) for p in (plans or [])]
    if not any(p.get("id") == "baseline" for p in plans):
        plans.insert(0, {"id": "baseline", "label": "If you keep overspending",
                         "tagline": "Carry on as you are", "actions": []})
    start = pd.Timestamp(start_date) if start_date else pd.Timestamp(profile["history"]["end"]) + pd.Timedelta(days=1)
    bounds = pd.DatetimeIndex([start + pd.DateOffset(months=k) for k in range(horizon_months + 1)])
    days = pd.date_range(start, bounds[-1] - pd.Timedelta(days=1), freq="D")
    month_idx = np.searchsorted(bounds.values, days.values, side="right") - 1   # months since start
    M = int(month_idx[-1]) + 1
    month_ends = bounds[1:] - pd.Timedelta(days=1)
    a = profile["assumptions"]
    floor = profile["comfort"]["comfort_floor"]
    base_life = _expected_lifestyle(profile, [])
    b0 = profile["balances"]
    start_funds = b0["emergency"] + b0["savings"] + b0["growth"]

    raws, out_plans = {}, {}
    for plan in plans:
        pid = plan.get("id") or f"plan_{len(raws)}"
        raw = _run_plan(profile, plan, days, month_idx, n_sims, seed)
        raws[pid] = raw

        comfortable = (~raw["rescue"]) & (~raw["overdrawn"]) & (raw["min_current"] >= floor - 0.01)
        life = _expected_lifestyle(profile, plan.get("actions", []))
        retention = {k: (life[k] / base_life[k] if base_life[k] > 0 else 1.0) for k in base_life}
        total_base = sum(base_life.values())
        kept = sum(life.values()) / total_base if total_base > 0 else 1.0
        p_month = float(comfortable.mean())
        score = 100 * p_month * min(1.0, kept / a["lifestyle_full"])
        if kept < a["lifestyle_ok"]:
            score *= kept / a["lifestyle_ok"]
        unlock = raw["unlock_month"]
        p_unlock = float(np.isfinite(unlock).mean())
        med_unlock = float(np.median(unlock))

        checkpoints = sorted({m for m in (12, 24, 36, 60, 120) if m <= M} | {M})
        out_plans[pid] = {
            "id": pid,
            "label": plan.get("label", pid),
            "tagline": plan.get("tagline"),
            "how": plan.get("how"),
            "actions": plan.get("actions", []),
            "monthly": {k: _pct_dict(raw[k]) for k in
                        ("current", "emergency", "savings", "growth", "funds", "net_worth")},
            "short_term": {
                "days": raw["short_daily"].shape[1],
                "p_overdrawn": float(raw["short_over"].mean()),
                "p_dip_into_savings": float(raw["short_rescue"].mean()),
                "p_below_floor": float((raw["short_min"] < floor - 0.01).mean()),
                "p_cover_shock_next_month": float((raw["min_liquid"][:, 0] >= a["shock_amount"]).mean()),
                "lowest_balance": {k: float(v) for k, v in _pct_dict(raw["short_min"]).items()},
                "daily_current": _pct_dict(raw["short_daily"]),
            },
            "long_term": {
                "checkpoints": {
                    str(m): {k: {q: float(v) for q, v in _pct_dict(raw[k][:, m - 1]).items()}
                             for k in ("net_worth", "funds", "growth")}
                    for m in checkpoints},
                "final_months": M,
            },
            "ladder": {
                "emergency_target": profile["emergency_target"],
                "p_emergency_full": p_unlock,
                "median_unlock_month": None if not math.isfinite(med_unlock) else int(med_unlock),
            },
            "comfort": {
                "p_comfortable_month": p_month,
                "p_comfortable_first_year": float(comfortable[:, :min(12, M)].all(axis=1).mean()),
                "monthly_comfortable": comfortable.mean(axis=0),
                "lifestyle_kept": float(kept),
                "lifestyle_retention": {k: float(v) for k, v in retention.items()},
                "lifestyle_ok": bool(kept >= a["lifestyle_ok"]),
                "comfort_score": float(score),
            },
        }

    for pid, r in out_plans.items():
        d_nw = raws[pid]["net_worth"] - raws["baseline"]["net_worth"]
        d_f = raws[pid]["funds"] - raws["baseline"]["funds"]
        r["vs_baseline"] = {"net_worth_gain": _pct_dict(d_nw), "funds_gain": _pct_dict(d_f),
                            "final_median_gain": float(np.median(d_nw[:, -1])),
                            "final_median_funds_gain": float(np.median(d_f[:, -1]))}

    snowball = None
    if profile["risk_windows"]:
        w = profile["risk_windows"][0]
        r_m = (1 + a["invest_return"]) ** (1 / 12) - 1
        val, series = 0.0, []
        for _ in range(M):
            val = val * (1 + r_m) + w["monthly"]
            series.append(val)
        snowball = {"window": w["label"], "monthly_cost": float(w["monthly"]), "categories": w["categories"],
                    "invested_value": np.array(series), "cash_spent": np.arange(1, M + 1) * w["monthly"]}

    return {
        "profile": profile,
        "n_sims": n_sims, "seed": seed, "horizon_months": M,
        "start": str(days[0].date()), "start_funds": start_funds,
        "month_ends": [str(d.date()) for d in month_ends],
        "short_days": [str(d.date()) for d in days[:out_plans["baseline"]["short_term"]["days"]]],
        "plans": out_plans,
        "snowball": snowball,
        "_raw": raws,
    }


def repeat_cost(extra_per_event: float, events_per_year: float = 12, years: int = 5,
                annual_return: float = DEFAULT_ASSUMPTIONS["invest_return"]) -> float:
    """What repeating an overspend costs the growth fund (e.g. Friday alert "£3.6k less")."""
    r_m = (1 + annual_return) ** (1 / 12) - 1
    val = 0.0
    for _ in range(int(years * 12)):
        val = val * (1 + r_m) + extra_per_event * events_per_year / 12
    return float(val)


def checkin_forecast(profile: dict, plan: dict, overspend: float, recovery_actions: list | None = None,
                     horizon_months: int = 60, n_sims: int = 1000, seed: int = 42) -> dict:
    """Saturday check-in: forecast after last night's overspend, before vs after the one-tap repair.
    Default repair (README copy): move £15 to the emergency fund today, skip takeaways this week,
    keep next Friday lighter."""
    if recovery_actions is None:
        recovery_actions = [
            {"type": "lump_sum_transfer", "to": "emergency", "amount": 15, "day_offset": 0},
            {"type": "reduce_category", "category": ["takeaway", "dining"], "pct": 1.0, "start_day": 0, "days": 7},
            {"type": "reduce_category", "category": ["entertainment"], "pct": 0.5, "start_day": 0, "days": 7},
        ]
    base_actions = list(plan.get("actions", []))
    hit = {"type": "one_off_purchase", "amount": float(overspend), "day_offset": 0}
    plans = [
        {"id": "on_plan", "label": "Before last night", "actions": base_actions},
        {"id": "not_repaired", "label": "After last night", "actions": base_actions + [hit]},
        {"id": "repaired", "label": "After the repair", "actions": base_actions + [hit] + list(recovery_actions)},
    ]
    res = simulate(profile, plans, horizon_months=horizon_months, n_sims=n_sims, seed=seed)
    M = res["horizon_months"]
    med = {pid: res["plans"][pid]["long_term"]["checkpoints"][str(M)]["funds"]["p50"] for pid in
           ("on_plan", "not_repaired", "repaired")}
    return {
        "overspend": float(overspend),
        "funds_5y": med,
        "funds_5y_text": {k: _money_k(v) for k, v in med.items()},
        "repaired_by": float(med["repaired"] - med["not_repaired"]),
        "share_recovered": float(min(1.0, max(0.0, (med["repaired"] - med["not_repaired"]) /
                                              max(med["on_plan"] - med["not_repaired"], 1e-9)))),
        "yearly": {pid: _yearly(res, pid, "funds") for pid in ("on_plan", "not_repaired", "repaired")},
    }


# -----------------------------------------------------------------------------
#  Summary (JSON-safe) + exactly what the UI screens need
# -----------------------------------------------------------------------------
def _horizon_text(months: int) -> str:
    if months == 12:
        return "1 year"
    return f"{months // 12} years" if months % 12 == 0 else f"{months} months"


def _yearly(results: dict, pid: str, key: str = "funds") -> dict:
    """Now, 1y, 2y, ... percentiles (UI graph points)."""
    M = results["horizon_months"]
    mon = results["plans"][pid]["monthly"][key]
    raw0 = results["profile"]["balances"]
    start = (raw0["emergency"] + raw0["savings"] + raw0["growth"]) if key == "funds" else \
        sum(raw0.values()) if key == "net_worth" else raw0.get(key, 0.0)
    years = list(range(0, M // 12 + 1))
    out = {"years": years}
    for q in ("p10", "p25", "p50", "p75", "p90"):
        out[q] = [float(start)] + [float(mon[q][12 * y - 1]) for y in years[1:]]
    return out


def summarise(results: dict) -> dict:
    prof = results["profile"]
    c = prof["comfort"]
    M = results["horizon_months"]
    H = _horizon_text(M)
    shock = prof["assumptions"]["shock_amount"]
    valued_names = [v["category"] for v in c["valued"]] + (["subscriptions"] if c["subscriptions"] else [])
    plans_out = []
    for pid, r in results["plans"].items():
        fin = r["long_term"]["checkpoints"][str(M)]
        st, cf, ld = r["short_term"], r["comfort"], r["ladder"]
        lines = [f"Funds in {H}: {_money(fin['funds']['p50'])} likely "
                 f"(range {_money(fin['funds']['p10'])} to {_money(fin['funds']['p90'])})"]
        if pid != "baseline":
            g = r["vs_baseline"]["final_median_gain"]
            lines.append(f"Net worth {'+' if g >= 0 else '-'}{_money(abs(g))} vs if you keep overspending")
        if ld["median_unlock_month"] == 0:
            lines.append("Emergency fund already full - growth fund unlocked")
        elif ld["median_unlock_month"] is not None:
            lines.append(f"Emergency fund full by month {ld['median_unlock_month']}, then growth fund unlocks")
        else:
            lines.append(f"Emergency fund ({_money(ld['emergency_target'])}) probably not full within {H}")
        lines.append(f"{st['p_cover_shock_next_month']:.0%} chance you can cover a surprise {_money(shock)} bill next month")
        lines.append(f"Comfortable in {cf['p_comfortable_month']:.0%} of months (never below your own "
                     f"{_money(c['comfort_floor'])} floor, no raiding savings)")
        lines.append(f"Keeps ~{cf['lifestyle_kept']:.0%} of the lifestyle you enjoy ({', '.join(valued_names)})"
                     + ("" if cf["lifestyle_ok"] else " - hard to stick to"))
        plans_out.append({
            "id": pid, "label": r["label"], "tagline": r["tagline"], "how": r["how"],
            "median_funds_final": float(fin["funds"]["p50"]),
            "funds_range_final": [float(fin["funds"]["p10"]), float(fin["funds"]["p90"])],
            "median_net_worth_final": float(fin["net_worth"]["p50"]),
            "median_gain_vs_baseline": float(r["vs_baseline"]["final_median_gain"]),
            "unlock_month": ld["median_unlock_month"],
            "p_cover_shock_next_month": round(st["p_cover_shock_next_month"], 3),
            "comfort_score": round(cf["comfort_score"], 1),
            "p_comfortable_month": round(cf["p_comfortable_month"], 3),
            "lifestyle_kept": round(cf["lifestyle_kept"], 3),
            "p_dip_into_savings_3m": round(st["p_dip_into_savings"], 3),
            "p_overdrawn_3m": round(st["p_overdrawn"], 3),
            "headlines": lines,
        })

    # Recommendation: best long-term outcome among plans (nearly) as comfortable as the most comfortable one
    best_score = max(p["comfort_score"] for p in plans_out)
    shortlist = [p for p in plans_out if p["comfort_score"] >= 0.9 * best_score]
    recommended = max(shortlist, key=lambda p: p["median_net_worth_final"])["id"]

    snow = results["snowball"]
    snow_line = None
    if snow:
        snow_line = (f"Your {snow['window']} red zone (~{_money(snow['monthly_cost'])}/month on "
                     f"{', '.join(snow['categories'])}) would be worth {_money(snow['invested_value'][-1])} "
                     f"in {H} if it went into your growth fund instead")
    return {
        "user": prof["name"], "horizon": H, "n_sims": results["n_sims"],
        "comfort_profile": {
            "essentials_monthly": round(c["essentials_monthly"], 2),
            "lifestyle_monthly": round(c["lifestyle_monthly"], 2),
            "comfortable_monthly": round(c["comfortable_monthly"], 2),
            "comfort_floor": round(c["comfort_floor"], 2),
            "emergency_target": prof["emergency_target"],
            "valued": [{k: (round(v, 2) if isinstance(v, float) else v) for k, v in x.items()} for x in c["valued"]],
            "red_zones": [{"label": w["label"], "weekly": round(w["weekly"], 2), "categories": w["categories"]}
                          for w in prof["risk_windows"]],
        },
        "snowball": snow_line,
        "recommended_plan": recommended,
        "plans": plans_out,
    }


def _svg_points(xs, ys, y0=145.0, top=11.0, vmax=1.0):
    k = (y0 - top) / vmax if vmax > 0 else 0
    return " ".join(f"{x:g},{y0 - v * k:.1f}" for x, v in zip(xs, ys))


def ui_payload(results: dict, plan_ids: list | None = None, chosen: str | None = None) -> dict:
    """Data for ui/screens: Home (graph), Plans (3 plans), checkpoints, resilience.
    Values are formatted like the mock-ups (e.g. "£13.2k") and raw numbers are included too.
    svg.* are ready-made point lists for the 326x160 Home chart (x: 0..280, y: 145 = £0)."""
    summary = summarise(results)
    by_id = {p["id"]: p for p in summary["plans"]}
    plan_ids = plan_ids or [p for p in results["plans"] if p != "baseline"][:3]
    chosen = chosen or max(plan_ids, key=lambda p: by_id[p]["median_funds_final"])
    M = results["horizon_months"]
    H = _horizon_text(M)
    over = _yearly(results, "baseline")
    mine = _yearly(results, chosen)
    xs = [round(280 * y / max(1, over["years"][-1]), 1) for y in over["years"]]
    vmax = max(max(mine["p90"]), max(over["p50"]), 1.0)
    prof = results["profile"]
    emg_now = prof["balances"]["emergency"]
    target = prof["emergency_target"]
    chosen_r = results["plans"][chosen]

    def plan_card(pid):
        p = by_id[pid]
        um = p["unlock_month"]
        unlock = ("Emergency fund already full, growth fund unlocked" if um == 0 else
                  f"Emergency fund full by month {um}, then growth fund unlocks" if um is not None else
                  f"Emergency fund not full within {H}")
        return {"id": pid, "name": p["label"], "tagline": p["tagline"], "how": p["how"],
                "outcome": _money_k(p["median_funds_final"]), "outcome_value": round(p["median_funds_final"], 2),
                "outcome_range": [round(v, 2) for v in p["funds_range_final"]],
                "unlock": unlock, "unlock_month": um,
                "comfort_score": p["comfort_score"], "lifestyle_kept": p["lifestyle_kept"],
                "p_cover_shock_next_month": p["p_cover_shock_next_month"], "headlines": p["headlines"]}

    snow = results["snowball"]
    return {
        "user": prof["name"], "n_sims": results["n_sims"], "horizon_years": M // 12,
        "overspending": {"outcome": _money_k(by_id["baseline"]["median_funds_final"]),
                         "outcome_value": round(by_id["baseline"]["median_funds_final"], 2),
                         "label": f"If you keep overspending in your red zones: {_money_k(by_id['baseline']['median_funds_final'])} in {H}"},
        "plans": [plan_card(p) for p in plan_ids],
        "recommended_plan": summary["recommended_plan"],
        "home": {
            "plan_id": chosen, "plan_name": by_id[chosen]["label"],
            "bigNum": {"both": _money(mine["p50"][-1]), "plan": _money(mine["p50"][-1]), "over": _money(over["p50"][-1])},
            "bigSub": {"both": f"likely in {H}", "plan": f"likely in {H}", "over": f"in {H} if nothing changes"},
            "series": {"years": over["years"], "plan": {k: mine[k] for k in ("p10", "p50", "p90")},
                       "overspending": {k: over[k] for k in ("p10", "p50", "p90")}},
            "svg": {
                "plan_line": _svg_points(xs, mine["p50"], vmax=vmax),
                "plan_band": _svg_points(xs + xs[::-1], mine["p90"] + mine["p10"][::-1], vmax=vmax),
                "over_line": _svg_points(xs, over["p50"], vmax=vmax),
                "plan_end_label": _money_k(mine["p50"][-1]), "over_end_label": _money_k(over["p50"][-1]),
                "gridlines": [{"value": v, "y": round(145 - v * (134 / vmax), 1), "label": _money_k(v)}
                              for v in _nice_ticks(vmax)],
            },
            "aria": (f"Monte Carlo projection over {H}. On your plan the likely range grows to around "
                     f"{_money_k(mine['p50'][-1])}. If you keep overspending in your red zones, "
                     f"savings stay around {_money_k(over['p50'][-1])}."),
            "legend": f"Your plan, likely range ({results['n_sims']:,} simulations)",
        },
        "checkpoints": {
            "emergency_fund": {"now": round(emg_now, 2), "target": round(target, 2),
                               "pct": round(100 * min(1.0, emg_now / target), 0) if target else 100,
                               "label": f"Emergency fund: {_money(emg_now)} of {_money(target)}"},
        },
        "resilience": {
            "p_cover_shock_next_month": round(chosen_r["short_term"]["p_cover_shock_next_month"], 3),
            "label": (f"{chosen_r['short_term']['p_cover_shock_next_month']:.0%} chance you can cover a surprise "
                      f"{_money(prof['assumptions']['shock_amount'])} bill next month"),
        },
        "red_zone_snowball": None if not snow else {
            "window": snow["window"], "monthly_cost": round(snow["monthly_cost"], 2),
            "five_year_cost": _money_k(snow["invested_value"][min(59, M - 1)]),
        },
    }


def _nice_ticks(vmax: float) -> list:
    step = 10 ** math.floor(math.log10(max(vmax, 1) / 2))
    for m in (1, 2, 2.5, 5, 10):
        if vmax / (m * step) <= 3:
            step *= m
            break
    return [step * i for i in range(1, int(vmax // step) + 1)]


def _jsonable(x):
    if isinstance(x, dict):
        return {str(k): _jsonable(v) for k, v in x.items() if not str(k).startswith("_")}
    if isinstance(x, (list, tuple)):
        return [_jsonable(v) for v in x]
    if isinstance(x, np.ndarray):
        return np.round(x, 2).tolist() if x.dtype.kind == "f" else x.tolist()
    if isinstance(x, np.floating):
        return None if not math.isfinite(float(x)) else float(x)
    if isinstance(x, float) and not math.isfinite(x):
        return None
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.bool_):
        return bool(x)
    if isinstance(x, set):
        return sorted(x)
    return x


def results_to_json(results: dict) -> dict:
    """Everything except the raw simulated paths, safe for json.dumps."""
    r = dict(results)
    prof = dict(r["profile"])
    prof["keys"] = [{k: v for k, v in key.items() if k != "pool"} for key in prof["keys"]]
    prof["anomalies"] = {c: {k: v for k, v in an.items() if k != "pool"} for c, an in prof["anomalies"].items()}
    r["profile"] = prof
    return _jsonable(r)


# -----------------------------------------------------------------------------
#  Presentable charts (matplotlib, UI design tokens)
# -----------------------------------------------------------------------------
def _plan_colours(results):
    cols, i = {}, 0
    for pid in results["plans"]:
        if pid == "baseline":
            cols[pid] = UI["red"]
        else:
            cols[pid] = PLAN_COLOURS[i % len(PLAN_COLOURS)]
            i += 1
    return cols


def _style(ax, money=True):
    import matplotlib.ticker as mticker
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color(UI["grid"])
    ax.tick_params(colors=UI["text2"], length=0)
    ax.grid(axis="y", color=UI["grid"], lw=0.8)
    ax.set_axisbelow(True)
    if money:
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: _money_k(v)))


def make_charts(results: dict, out_dir: str | None = None, show: bool = False) -> dict:
    import matplotlib
    if not show:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager

    installed = {f.name for f in font_manager.fontManager.ttflist}
    family = next((f for f in ("Inter", "Segoe UI", "Helvetica", "Arial") if f in installed), "DejaVu Sans")
    plt.rcParams.update({"font.size": 10, "axes.titleweight": "bold", "figure.dpi": 110,
                         "font.family": family, "text.color": UI["text"],
                         "axes.titlecolor": UI["text"], "axes.labelcolor": UI["text2"]})
    prof = results["profile"]
    cols = _plan_colours(results)
    x = pd.to_datetime(results["month_ends"])
    plans = results["plans"]
    base = plans["baseline"]
    others = [p for p in plans if p != "baseline"] or ["baseline"]
    M = results["horizon_months"]
    figs = {}

    # 1. Fan chart per plan vs "if you keep overspending" (funds = emergency + savings + growth)
    ncol = 2 if len(others) > 1 else 1
    nrow = math.ceil(len(others) / ncol)
    fig, axes = plt.subplots(nrow, ncol, figsize=(6.2 * ncol, 3.5 * nrow), squeeze=False, sharey=True)
    bm = base["monthly"]["funds"]
    for ax, pid in zip(axes.flat, others):
        pm = plans[pid]["monthly"]["funds"]
        ax.fill_between(x, pm["p10"], pm["p90"], color=cols[pid], alpha=0.14, lw=0, label="Likely range (10-90%)")
        ax.fill_between(x, pm["p25"], pm["p75"], color=cols[pid], alpha=0.22, lw=0)
        ax.plot(x, pm["p50"], color=cols[pid], lw=2.4, label="Your plan (median)")
        ax.plot(x, bm["p50"], color=UI["red"], ls=(0, (6, 5)), lw=2, label="If you keep overspending")
        ax.set_title(plans[pid]["label"], fontsize=10, loc="left")
        _style(ax)
    for ax in list(axes.flat)[len(others):]:
        ax.axis("off")
    axes.flat[0].legend(loc="upper left", fontsize=8, frameon=False)
    fig.suptitle(f"{prof['name']}'s financial future: {results['n_sims']:,} simulated futures",
                 fontweight="bold", x=0.01, ha="left")
    fig.tight_layout()
    figs["fan_chart"] = fig

    # 2. Short term: current account over the next ~90 days
    fig, ax = plt.subplots(figsize=(10, 4))
    xs = pd.to_datetime(results["short_days"])
    for pid, r in plans.items():
        dcur = r["short_term"]["daily_current"]
        ax.fill_between(xs, dcur["p10"], dcur["p90"], color=cols[pid], alpha=0.07, lw=0)
        ax.plot(xs, dcur["p50"], color=cols[pid], lw=1.8, label=r["label"],
                ls=(0, (6, 5)) if pid == "baseline" else "-")
    ax.axhline(prof["comfort"]["comfort_floor"], color=UI["red_text"], ls=":", lw=1.4,
               label=f"Your comfort floor ({_money(prof['comfort']['comfort_floor'])})")
    ax.axhline(0, color=UI["text"], lw=0.8)
    ax.set_title(f"Next {len(xs)} days: {prof['name']}'s current account (median + likely range)", loc="left")
    ax.legend(fontsize=8, frameon=False, ncol=2)
    _style(ax)
    fig.tight_layout()
    figs["short_term"] = fig

    # 3. Side-by-side comparison
    labels = [plans[p]["label"] for p in plans]
    colours = [cols[p] for p in plans]
    metrics = [
        (f"Can cover a surprise {_money(prof['assumptions']['shock_amount'])} bill\nnext month",
         [plans[p]["short_term"]["p_cover_shock_next_month"] * 100 for p in plans], "%"),
        (f"Funds in {_horizon_text(M)} (median)",
         [plans[p]["long_term"]["checkpoints"][str(M)]["funds"]["p50"] for p in plans], "£"),
        ("Comfort score (0-100)", [plans[p]["comfort"]["comfort_score"] for p in plans], ""),
    ]
    fig, axes = plt.subplots(1, 3, figsize=(14, 0.55 * len(labels) + 1.8), sharey=True)
    for ax, (title, vals, unit) in zip(axes, metrics):
        y = np.arange(len(labels))
        ax.barh(y, vals, color=colours, height=0.65)
        for yi, v in zip(y, vals):
            ax.text(v, yi, f" {_money_k(v)}" if unit == "£" else f" {v:.0f}{unit}", va="center", fontsize=8,
                    color=UI["text"])
        ax.set_yticks(y, labels)
        ax.invert_yaxis()
        ax.set_title(title, fontsize=10, loc="left")
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.tick_params(length=0)
        ax.set_xticks([])
        ax.margins(x=0.3)
    fig.suptitle(f"{prof['name']}: how each decision compares", fontweight="bold", x=0.01, ha="left")
    fig.tight_layout()
    figs["comparison"] = fig

    # 4. Fund ladder for the plan with the most funds
    best = max(others, key=lambda p: plans[p]["long_term"]["checkpoints"][str(M)]["funds"]["p50"])
    fig, ax = plt.subplots(figsize=(10, 4))
    mm = plans[best]["monthly"]
    stack = [np.asarray(mm[k]["p50"]) for k in ("emergency", "savings", "growth")]
    ax.stackplot(x, *stack, colors=[UI["success"], "#7FB0F0", UI["accent"]], alpha=0.85,
                 labels=["Emergency fund", "Savings fund", "Growth fund"])
    ax.axhline(prof["emergency_target"], color=UI["success"], ls=":", lw=1.2,
               label=f"Emergency target ({_money(prof['emergency_target'])})")
    um = plans[best]["ladder"]["median_unlock_month"]
    if um:
        ax.axvline(x[min(um, M) - 1], color=UI["text2"], lw=1, ls="--")
        ax.text(x[min(um, M) - 1], ax.get_ylim()[1] * 0.92, f"  growth unlocks (month {um})", fontsize=8,
                color=UI["text2"])
    ax.set_title(f"The fund ladder: {plans[best]['label']} (median)", loc="left")
    ax.legend(fontsize=8, frameon=False, loc="upper left")
    _style(ax)
    fig.tight_layout()
    figs["fund_ladder"] = fig

    # 5. Snowball
    fig, ax = plt.subplots(figsize=(10, 4))
    for pid in plans:
        if pid != "baseline":
            ax.plot(x, plans[pid]["vs_baseline"]["net_worth_gain"]["p50"], color=cols[pid], lw=2,
                    label=plans[pid]["label"])
    snow = results["snowball"]
    if snow:
        ax.plot(x, snow["invested_value"], color=UI["red"], ls=(0, (6, 5)), lw=1.8,
                label=f"Your {snow['window']} red zone, if invested instead")
        ax.plot(x, snow["cash_spent"], color=UI["red"], ls=":", lw=1.2, alpha=0.7, label="...vs the cash spent on it")
    ax.axhline(0, color=UI["text"], lw=0.8)
    ax.set_title("The snowball: extra net worth vs keeping on overspending (median)", loc="left")
    ax.legend(fontsize=8, frameon=False)
    _style(ax)
    fig.tight_layout()
    figs["snowball"] = fig

    # 6. Comfort: how much of the lifestyle they enjoy each plan keeps
    cats = list(base["comfort"]["lifestyle_retention"].keys())
    fig, ax = plt.subplots(figsize=(10, 4))
    if cats:
        width = 0.8 / len(plans)
        xi = np.arange(len(cats))
        for i, pid in enumerate(plans):
            ret = plans[pid]["comfort"]["lifestyle_retention"]
            ax.bar(xi + i * width - 0.4 + width / 2, [ret[c] * 100 for c in cats], width,
                   color=cols[pid], label=plans[pid]["label"])
        ax.set_xticks(xi, cats)
        ax.axhline(prof["assumptions"]["lifestyle_ok"] * 100, color=UI["red_text"], ls=":", lw=1.2,
                   label="Below this, hard to stick to")
        ax.set_ylim(0, 118)
        ax.set_ylabel("% of usual spend kept")
        ax.legend(fontsize=8, frameon=False, ncol=3)
    ax.set_title(f"What {prof['name']} keeps of the lifestyle they enjoy", loc="left")
    _style(ax, money=False)
    fig.tight_layout()
    figs["comfort"] = fig

    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        for k, f in figs.items():
            f.savefig(os.path.join(out_dir, f"{k}.png"), bbox_inches="tight")
    if show:
        plt.show()
    return figs


def make_report(results: dict, summary: dict, path: str, figs: dict | None = None) -> str:
    """Self-contained HTML page with headlines + charts, styled with the UI tokens."""
    import html
    figs = figs or make_charts(results)

    def img(f):
        buf = io.BytesIO()
        f.savefig(buf, format="png", bbox_inches="tight")
        return base64.b64encode(buf.getvalue()).decode()

    cp = summary["comfort_profile"]
    valued = "".join(f"<li>{html.escape(v['category'])}: ~{v['times_per_month']:.0f}x a month, "
                     f"{_money(v['monthly'])}/month, usually {html.escape(str(v['favourite_window']))}</li>"
                     for v in cp["valued"])
    cards = ""
    for p in summary["plans"]:
        rec = "<span class='rec'>Recommended</span>" if p["id"] == summary["recommended_plan"] else ""
        cls = "card over" if p["id"] == "baseline" else "card"
        items = "".join(f"<li>{html.escape(h)}</li>" for h in p["headlines"])
        tag = f"<p class='tag'>{html.escape(p['tagline'])}</p>" if p.get("tagline") else ""
        cards += (f"<div class='{cls}'><div class='row'><h3>{html.escape(p['label'])}</h3>"
                  f"<span class='big'>{_money_k(p['median_funds_final'])}</span></div>{tag}{rec}"
                  f"<div class='score'>Comfort score {p['comfort_score']:.0f}/100</div><ul>{items}</ul></div>")
    charts = "".join(f"<img src='data:image/png;base64,{img(f)}' alt='{k}'>" for k, f in figs.items())
    page = f"""<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>Finance Your Friday - {html.escape(summary['user'])}</title>
<link rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap'>
<style>
body{{font-family:Inter,system-ui,sans-serif;margin:0;background:#fff;color:{UI['text']}}}
main{{max-width:1100px;margin:0 auto;padding:24px 16px}}
.label{{font-size:12px;font-weight:600;letter-spacing:.06em;color:{UI['text2']};text-transform:uppercase}}
h1{{margin:4px 0;font-size:26px;font-weight:600;letter-spacing:-.01em}} .sub{{color:{UI['text2']};margin-bottom:18px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px}}
.card{{background:{UI['tile']};border-radius:16px;padding:14px 16px}}
.card.over{{background:{UI['red_tint']}}}
.row{{display:flex;justify-content:space-between;align-items:baseline;gap:8px}}
.card h3{{margin:0;font-size:17px;font-weight:600}} .big{{font-size:18px;font-weight:600}}
.tag{{margin:4px 0;font-size:14px;color:#2B2E36}}
.rec{{display:inline-block;font-size:12px;font-weight:600;color:{UI['success']};background:{UI['success_tint']};border-radius:8px;padding:2px 8px}}
.score{{font-weight:600;color:{UI['accent']};margin:6px 0 4px;font-size:14px}} li{{margin:3px 0;font-size:13px;color:#2B2E36}}
.snow{{background:{UI['red_tint']};color:#3F4350;border-radius:12px;padding:10px 14px;margin:14px 0;font-size:14px}}
img{{width:100%;border-radius:16px;margin-top:14px;border:1px solid #ECEDF1}}
</style></head><body><main>
<div class='label'>Your financial future</div>
<h1>{html.escape(summary['user'])}'s futures</h1>
<div class='sub'>{summary['n_sims']:,} simulated futures over {summary['horizon']}, built from their own transaction history.</div>
<div class='card'><div class='label'>What comfortable means for {html.escape(summary['user'])}</div><ul>
<li>Essentials ~{_money(cp['essentials_monthly'])}/month; the lifestyle they enjoy ~{_money(cp['lifestyle_monthly'])}/month</li>
<li>Comfortable living: ~{_money(cp['comfortable_monthly'])}/month; personal floor {_money(cp['comfort_floor'])};
emergency fund target {_money(cp['emergency_target'])}</li>
{valued}</ul></div>
{f"<div class='snow'>{html.escape(summary['snowball'])}</div>" if summary['snowball'] else ''}
<div class='grid'>{cards}</div>
{charts}
<p class='sub' style='margin-top:16px'>Guidance, not regulated advice. Illustrative returns ({DEFAULT_ASSUMPTIONS['invest_return']:.0%} mean, {DEFAULT_ASSUMPTIONS['invest_vol']:.0%} volatility).</p>
</main></body></html>"""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(page)
    return path


# -----------------------------------------------------------------------------
#  Demo plans: the three on ui/screens/Plans + the extra decisions from the coach
# -----------------------------------------------------------------------------
RED_ZONE = {"weekdays": ["Fri", "Sat"], "night": True}
GOING_OUT = ["entertainment", "takeaway", "dining"]
DEMO_PLANS = [
    {"id": "cap", "label": "Cap it",
     "tagline": "A budget for every red zone, with a heads-up before each one starts.",
     "how": "Limits per event · warning 2 hours before",
     "actions": [{"type": "cap_window", "cap": 40, "category": GOING_OUT, "when": RED_ZONE, "adherence": 0.8},
                 {"type": "sweep_surplus", "to": "growth"}]},
    {"id": "sweep", "label": "Sweep it",
     "tagline": "Move money out of reach before a red zone arrives.",
     "how": "Auto-save £30 before payday weekends and big events",
     "actions": [{"type": "recurring_transfer", "to": "growth", "amount": 30, "freq": "weekly", "weekday": "Fri"},
                 {"type": "reduce_category", "category": GOING_OUT, "pct": 0.25, "when": RED_ZONE},
                 {"type": "sweep_surplus", "to": "growth"}]},
    {"id": "swap", "label": "Swap it",
     "tagline": "Keep the plans, change what they cost.",
     "how": "Cheaper alternatives suggested the day before",
     "actions": [{"type": "reduce_category", "category": GOING_OUT, "pct": 0.2},
                 {"type": "sweep_surplus", "to": "growth"}]},
]
EXTRA_DECISIONS = [
    {"id": "stop_going_out", "label": "Stop going out completely",
     "actions": [{"type": "reduce_category", "category": GOING_OUT, "pct": 1.0},
                 {"type": "sweep_surplus", "to": "growth"}]},
    {"id": "buy_jacket", "label": "Buy the £400 jacket this week",
     "actions": [{"type": "one_off_purchase", "amount": 400, "day_offset": 6}]},
]


def run_demo(personas=("maya", "sam"), out_dir="great_uni_hack_output", n_sims=1000,
             horizon_months=60, seed=42, show=False) -> dict:
    payloads = {}
    for persona in personas:
        spec = PERSONAS[persona]
        profile = build_profile(generate_demo_transactions(persona), spec["balances"], name=spec["name"])
        print("\n" + describe_profile(profile))
        results = simulate(profile, DEMO_PLANS + EXTRA_DECISIONS, horizon_months=horizon_months,
                           n_sims=n_sims, seed=seed)
        summary = summarise(results)
        _print_summary(summary)
        pdir = os.path.join(out_dir, persona)
        figs = make_charts(results, out_dir=pdir)
        report = make_report(results, summary, os.path.join(pdir, "report.html"), figs)
        ui = ui_payload(results, plan_ids=[p["id"] for p in DEMO_PLANS])
        ui["checkin"] = checkin_forecast(profile, DEMO_PLANS[1], overspend=85, horizon_months=horizon_months,
                                         n_sims=min(n_sims, 1000), seed=seed)
        payloads[persona] = ui
        for fname, obj in (("summary.json", summary), ("ui_data.json", ui)):
            with open(os.path.join(pdir, fname), "w", encoding="utf-8") as fh:
                json.dump(_jsonable(obj), fh, indent=2)
        c = ui["checkin"]
        print(f"\n  Saturday check-in: £85 over -> 5y funds {c['funds_5y_text']['on_plan']} -> "
              f"{c['funds_5y_text']['not_repaired']}; after the repair {c['funds_5y_text']['repaired']} "
              f"({c['share_recovered']:.0%} of the damage undone)")
        print(f"  -> report, charts, summary.json, ui_data.json in {os.path.abspath(pdir)}")
        if show:
            import matplotlib.pyplot as plt
            plt.show()
    return payloads


def _print_summary(summary: dict):
    if summary["snowball"]:
        print("  " + summary["snowball"])
    for p in summary["plans"]:
        star = "  <- recommended" if p["id"] == summary["recommended_plan"] else ""
        print(f"\n  [{p['label']}] comfort score {p['comfort_score']:.0f}/100{star}")
        for h in p["headlines"]:
            print(f"    - {h}")


# -----------------------------------------------------------------------------
#  Self-tests
# -----------------------------------------------------------------------------
def run_self_tests(spend_risk_csv: str | None = None):
    maya = build_profile(generate_demo_transactions("maya"), PERSONAS["maya"]["balances"], "Maya")
    sam = build_profile(generate_demo_transactions("sam"), PERSONAS["sam"]["balances"], "Sam")
    kw = dict(horizon_months=24, n_sims=300, seed=1)

    # personal comfort profiles differ
    assert maya["comfort"]["comfortable_monthly"] != sam["comfort"]["comfortable_monthly"]
    mv = {v["category"] for v in maya["comfort"]["valued"]}
    sv = {v["category"] for v in sam["comfort"]["valued"]}
    assert "entertainment" in mv and "entertainment" not in sv, (mv, sv)
    assert "hobbies" in sv, sv
    # Friday night effect detected
    assert maya["risk_windows"][0]["label"] == "Fri night", maya["risk_windows"]
    # reproducible
    r1 = simulate(maya, DEMO_PLANS[:1], **kw)
    r2 = simulate(maya, DEMO_PLANS[:1], **kw)
    assert np.allclose(r1["plans"]["cap"]["monthly"]["funds"]["p50"], r2["plans"]["cap"]["monthly"]["funds"]["p50"])
    # sensible ordering
    res = simulate(maya, DEMO_PLANS + EXTRA_DECISIONS, **kw)
    P = res["plans"]
    for pid in ("cap", "sweep", "swap"):
        assert P[pid]["vs_baseline"]["final_median_gain"] > 0, pid
        assert P[pid]["long_term"]["checkpoints"]["24"]["funds"]["p50"] > \
            P["baseline"]["long_term"]["checkpoints"]["24"]["funds"]["p50"], pid
    assert P["buy_jacket"]["vs_baseline"]["final_median_gain"] < -300
    assert not P["stop_going_out"]["comfort"]["lifestyle_ok"]
    assert P["stop_going_out"]["comfort"]["lifestyle_kept"] < P["cap"]["comfort"]["lifestyle_kept"]
    # fund ladder: growth stays ~0 until emergency is full
    raw = res["_raw"]["sweep"]
    no_ladder = {**maya, "assumptions": {**maya["assumptions"], "ladder": False}}
    raw_off = simulate(no_ladder, [DEMO_PLANS[1]], **kw)["_raw"]["sweep"]
    assert np.median(raw["growth"][:, 0]) == 0 < np.median(raw_off["growth"][:, 0])
    assert np.median(raw["emergency"][:, 3]) > np.median(raw_off["emergency"][:, 3])
    # cutting Friday nights matters much less for Sam
    rs = simulate(sam, DEMO_PLANS[:1], **kw)
    assert rs["plans"]["cap"]["vs_baseline"]["final_median_gain"] < P["cap"]["vs_baseline"]["final_median_gain"] / 2
    # UI payload + check-in
    ui = ui_payload(res, plan_ids=["cap", "sweep", "swap"])
    assert len(ui["plans"]) == 3 and ui["home"]["svg"]["plan_line"]
    ci = checkin_forecast(maya, DEMO_PLANS[1], overspend=85, horizon_months=24, n_sims=300)
    assert ci["funds_5y"]["repaired"] > ci["funds_5y"]["not_repaired"]
    json.dumps(_jsonable(ui))
    json.dumps(results_to_json(res))
    # spend-risk CSV format (date,time,...,positive amounts, no income)
    df = pd.DataFrame({"date": ["2026-01-02", "2026-01-02", "2026-01-03"], "time": ["21:30", "01:10", "12:00"],
                       "category": ["Dining", "Entertainment", "Bills"], "merchant": ["Nando's", "Club", "Netflix"],
                       "amount": [20.0, 35.0, 10.99], "note": ["", "", "Netflix"], "payment_method": ["card"] * 3})
    t = load_transactions(df)
    assert (t.amount < 0).all() and t.category.tolist() == ["entertainment", "dining", "subscriptions"]
    if spend_risk_csv and os.path.exists(spend_risk_csv):
        prof = build_profile(spend_risk_csv, {"current": 400}, name="spend-risk",
                             income={"monthly": 2100, "payday": 28})
        simulate(prof, DEMO_PLANS, horizon_months=12, n_sims=200)
    print("All self-tests passed.")


# -----------------------------------------------------------------------------
#  CLI
# -----------------------------------------------------------------------------
def main(argv=None):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Personalised Monte Carlo simulator (Finance Your Friday)")
    ap.add_argument("--test", action="store_true", help="run self-tests")
    ap.add_argument("--persona", choices=sorted(PERSONAS), help="run the demo for one persona")
    ap.add_argument("--transactions", help="CSV of transactions (README or spend-risk schema)")
    ap.add_argument("--plans", help="JSON file with a list of plans (defaults to Cap / Sweep / Swap)")
    ap.add_argument("--balances", help='JSON, e.g. {"current": 400, "emergency": 150, "savings": 0, "growth": 0}')
    ap.add_argument("--income", help='JSON, e.g. {"monthly": 2100, "payday": 28} (needed for spend-only data)')
    ap.add_argument("--name", default="You")
    ap.add_argument("--sims", type=int, default=1000)
    ap.add_argument("--months", type=int, default=60)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", default="great_uni_hack_output")
    ap.add_argument("--show", action="store_true", help="open the charts in a window")
    args = ap.parse_args(argv)

    if args.test:
        run_self_tests(args.transactions)
        return
    if args.transactions:
        plans = json.load(open(args.plans, encoding="utf-8")) if args.plans else DEMO_PLANS
        profile = build_profile(args.transactions, json.loads(args.balances) if args.balances else None,
                                name=args.name, income=json.loads(args.income) if args.income else None)
        print(describe_profile(profile))
        results = simulate(profile, plans, horizon_months=args.months, n_sims=args.sims, seed=args.seed)
        summary = summarise(results)
        _print_summary(summary)
        figs = make_charts(results, out_dir=args.out, show=args.show)
        report = make_report(results, summary, os.path.join(args.out, "report.html"), figs)
        for fname, obj in (("summary.json", summary), ("ui_data.json", ui_payload(results))):
            with open(os.path.join(args.out, fname), "w", encoding="utf-8") as fh:
                json.dump(_jsonable(obj), fh, indent=2)
        print(f"\nReport: {os.path.abspath(report)}")
        return
    run_demo(personas=(args.persona,) if args.persona else ("maya", "sam"), out_dir=args.out,
             n_sims=args.sims, horizon_months=args.months, seed=args.seed, show=args.show)


if __name__ == "__main__":
    main()
