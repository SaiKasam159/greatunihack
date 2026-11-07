"""Generate a realistic-looking FAKE personal transaction dataset.

Everything here is synthetic. It mimics one person's card spending from
2023-01-01 to 2026-10-31, with recognisable annual events (birthday, Christmas,
family ceremony, anniversary), a one-off wedding, holiday trips, paydays and
random splurges. The point is a playground where "unusually big spending day"
is predictable from the calendar.

Outputs
  data/transactions_fake.csv   one row per transaction
  data/daily_spend.csv         daily totals (+ per-category columns)
  data/events.csv              event calendar (recurring + one-off, incl. future)
"""

from __future__ import annotations

import calendar
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
SEED = 42
START, END = "2023-01-01", "2026-10-31"

# --- the person ------------------------------------------------------------- #
BIRTHDAY = (3, 14)          # annual
ANNIVERSARY = (8, 9)        # annual
CEREMONY = (2, 18)          # annual family ceremony / festival
ONE_OFF = {
    "2025-06-21": ("Wedding", 1500.0),
    "2026-12-12": ("Wedding ceremony", 1200.0),  # future, already known
}
TRIPS = [
    ("2023-07-15", "2023-07-29"),
    ("2024-07-20", "2024-08-03"),
    ("2025-07-12", "2025-07-26"),
    ("2026-08-01", "2026-08-15"),
]

CATEGORIES = {
    # name        median GBP  sigma  chance/day  merchants
    "Groceries": (17.0, 0.45, 0.75, ["Tesco", "Sainsbury's", "Lidl", "Aldi", "Co-op", "M&S Food"]),
    "Dining": (11.5, 0.60, 0.55, ["Pret", "Nando's", "Wagamama", "Deliveroo", "The Crown", "Dishoom"]),
    "Transport": (3.4, 0.55, 0.85, ["TfL", "First Bus", "Uber", "Trainline", "Shell"]),
    "Shopping": (22.0, 0.75, 0.35, ["Amazon", "ASOS", "Zara", "Argos", "Decathlon", "IKEA"]),
    "Entertainment": (14.0, 0.55, 0.16, ["Odeon", "The Fleece", "Bristol Museum", "Bowling", "Steam"]),
    "Health": (9.0, 0.55, 0.10, ["Boots", "Pharmacy", "Dentist", "Physio"]),
    "Gifts": (24.0, 0.55, 0.05, ["John Lewis", "Etsy", "Florist", "Card Factory", "Waterstones"]),
}

# category -> relative volume by weekday (Mon..Sun)
WEEKDAY = {
    "Groceries": [0.85, 0.80, 0.90, 0.95, 1.35, 1.55, 1.15],
    "Dining": [0.75, 0.80, 0.90, 1.05, 1.65, 1.80, 1.25],
    "Transport": [1.25, 1.25, 1.25, 1.20, 1.15, 0.60, 0.55],
    "Shopping": [0.85, 0.85, 0.90, 1.00, 1.20, 1.45, 1.05],
    "Entertainment": [0.55, 0.60, 0.75, 0.90, 1.70, 1.85, 0.90],
    "Health": [1.10, 1.00, 0.95, 0.95, 1.00, 0.75, 0.60],
    "Gifts": [1.00, 1.00, 1.00, 1.05, 1.15, 1.25, 1.00],
}

# extra transactions triggered by an event, as (category, amount)
def event_extras(d: pd.Timestamp) -> list[tuple[str, float, str]]:
    out: list[tuple[str, float, str]] = []
    md = (d.month, d.day)
    iso = d.isoformat()

    if (d.month, d.day) == BIRTHDAY:
        out += [("Dining", 95.0, "Birthday dinner")]
    if d.month == 3 and 12 <= d.day <= 16:
        out += [("Gifts", 85.0, "Birthday gifts")]
    if (d.month, d.day) == ANNIVERSARY:
        out += [("Dining", 110.0, "Anniversary dinner"), ("Gifts", 75.0, "Anniversary gift")]
    if (d.month, d.day) == CEREMONY:
        out += [("Gifts", 70.0, "Family ceremony gift"), ("Transport", 45.0, "Family ceremony travel")]

    # Christmas run-up and the days themselves
    if d.month == 12 and 10 <= d.day <= 23:
        out += [("Gifts", 45.0 + 9.0 * (d.day - 10), "Christmas shopping")]
    if d.month == 12 and d.day in (24, 26):
        out += [("Groceries", 65.0, "Christmas food")]
    if d.month == 12 and d.day in (25, 26):
        out += [("Dining", 60.0, "Christmas meal")]
    if d.month == 12 and d.day == 31:
        out += [("Dining", 85.0, "New Year's Eve"), ("Entertainment", 45.0, "New Year's Eve")]

    # Black Friday window
    if d.month == 11:
        bf = _black_friday(d.year)
        if abs((d - bf).days) <= 3:
            out += [("Shopping", 175.0, "Black Friday")]

    # payday
    if d.day == 25:
        out += [("Shopping", 55.0, "Payday treat"), ("Dining", 32.0, "Payday dinner")]

    # holiday trips
    for s, e in TRIPS:
        if pd.Timestamp(s) <= d <= pd.Timestamp(e):
            out += [("Dining", 48.0, "Holiday meal"), ("Transport", 28.0, "Holiday travel"),
                    ("Shopping", 30.0, "Holiday shopping")]

    # one-off planned events (weddings etc.)
    if iso in ONE_OFF:
        label, amount = ONE_OFF[iso]
        out += [("Gifts", amount * 0.55, label), ("Transport", amount * 0.15, label),
                ("Dining", amount * 0.18, label), ("Shopping", amount * 0.12, label)]
    return out


def _black_friday(year: int) -> pd.Timestamp:
    """Day after the 4th Thursday of November."""
    nov = calendar.monthcalendar(year, 11)
    thursdays = [w[calendar.THURSDAY] for w in nov if w[calendar.THURSDAY]]
    return pd.Timestamp(year=year, month=11, day=thursdays[3] + 1)


def _season(cat: str, d: pd.Timestamp) -> float:
    if cat == "Shopping":
        if d.month == 12:
            return 1.6
        if d.month == 11:
            return 1.25
    if cat == "Dining" and d.month in (6, 7, 8):
        return 1.15
    if cat == "Groceries" and d.month == 12:
        return 1.3
    return 1.0


def _bills(d: pd.Timestamp) -> list[tuple[str, float, str]]:
    out = []
    if d.day == 5:
        out += [("Bills", 62.0, "Energy bill"), ("Bills", 34.0, "Water bill")]
    if d.day == 12:
        out += [("Bills", 12.99, "Netflix"), ("Bills", 11.99, "Spotify"), ("Bills", 2.99, "iCloud")]
    if d.day == 20:
        out += [("Bills", 22.0, "Mobile")]
    if d.day == 15:
        out += [("Bills", 28.0, "Insurance")]
    if d.day == 3:
        out += [("Health", 42.0, "Gym membership")]
    return out


def build() -> pd.DataFrame:
    rng = np.random.default_rng(SEED)
    rows = []
    for day in pd.date_range(START, END, freq="D"):
        dow = day.day_of_week
        trip = any(pd.Timestamp(s) <= day <= pd.Timestamp(e) for s, e in TRIPS)

        for cat, (median, sigma, chance, merchants) in CATEGORIES.items():
            lam = chance * WEEKDAY[cat][dow] * _season(cat, day)
            if trip:
                lam *= 1.3
            n = rng.poisson(lam)
            for _ in range(n):
                amount = float(rng.lognormal(np.log(median), sigma))
                rows.append((day, cat, rng.choice(merchants), round(amount, 2), "", _method(rng)))

        for cat, amount, note in event_extras(day):
            jitter = 1.0 + rng.normal(0, 0.12)
            rows.append((day, cat, _merchant_for(cat, rng), round(amount * jitter, 2), note, _method(rng)))

        for cat, amount, note in _bills(day):
            rows.append((day, cat, "Direct debit" if cat == "Bills" else "Gym", round(amount, 2), note, "direct debit"))

    # a few random big purchases per year
    days = pd.date_range(START, END, freq="D")
    for year in (2023, 2024, 2025, 2026):
        for _ in range(rng.integers(3, 6)):
            d = pd.Timestamp(year=year, month=int(rng.integers(1, 13)), day=int(rng.integers(1, 28)))
            rows.append((d, "Shopping", str(rng.choice(["Currys", "John Lewis", "Apple", "IKEA"])),
                         round(float(rng.uniform(180, 750)), 2), "One-off purchase", _method(rng)))

    tx = pd.DataFrame(rows, columns=["date", "category", "merchant", "amount", "note", "payment_method"])
    tx["date"] = pd.to_datetime(tx["date"])
    tx = tx.sort_values(["date", "category"]).reset_index(drop=True)
    # plausible time of day
    hours = rng.integers(7, 23, size=len(tx))
    minutes = rng.integers(0, 60, size=len(tx))
    tx["time"] = [f"{h:02d}:{m:02d}" for h, m in zip(hours, minutes)]
    return tx[["date", "time", "category", "merchant", "amount", "note", "payment_method"]]


def _method(rng) -> str:
    return str(rng.choice(["card", "contactless", "contactless", "apple pay"]))


def _merchant_for(cat: str, rng) -> str:
    return str(rng.choice(CATEGORIES[cat][3]))


def event_calendar() -> pd.DataFrame:
    """Every event the person knows about, including ones in the future."""
    rows = []
    for year in range(2023, 2029):
        rows.append((pd.Timestamp(year, *BIRTHDAY), pd.Timestamp(year, *BIRTHDAY), "Birthday", "annual", 0.0))
        rows.append((pd.Timestamp(year, *ANNIVERSARY), pd.Timestamp(year, *ANNIVERSARY), "Anniversary", "annual", 0.0))
        rows.append((pd.Timestamp(year, *CEREMONY), pd.Timestamp(year, *CEREMONY), "Family ceremony", "annual", 0.0))
        bf = _black_friday(year)
        rows.append((bf, bf, "Black Friday", "annual", 0.0))
        rows.append((pd.Timestamp(year, 12, 20), pd.Timestamp(year, 12, 26), "Christmas", "annual", 0.0))
        rows.append((pd.Timestamp(year, 12, 31), pd.Timestamp(year, 12, 31), "New Year", "annual", 0.0))
    for s, e in TRIPS:
        rows.append((pd.Timestamp(s), pd.Timestamp(e), "Holiday trip", "one-off", 0.0))
    # planned, budgeted one-offs: the amount is known before the day arrives
    for iso, (label, amount) in ONE_OFF.items():
        rows.append((pd.Timestamp(iso), pd.Timestamp(iso), label, "one-off", float(amount)))
    ev = pd.DataFrame(rows, columns=["date", "end_date", "event", "recurrence", "planned_amount"])
    return ev.drop_duplicates().sort_values("date").reset_index(drop=True)


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    tx = build()
    tx.to_csv(DATA / "transactions_fake.csv", index=False)

    daily = tx.groupby("date")["amount"].sum().rename("total").to_frame()
    daily = daily.reindex(pd.date_range(START, END, freq="D"), fill_value=0.0)
    by_cat = tx.pivot_table(index="date", columns="category", values="amount", aggfunc="sum")
    daily = daily.join(by_cat.reindex(daily.index).fillna(0.0))
    daily.index.name = "date"
    daily.round(2).to_csv(DATA / "daily_spend.csv")

    event_calendar().to_csv(DATA / "events.csv", index=False)

    print(f"transactions : {len(tx):,}")
    print(f"days         : {len(daily):,}")
    print(f"total spend  : GBP {tx['amount'].sum():,.0f}")
    print(f"mean/day     : GBP {daily['total'].mean():,.2f}")
    print(f"p90/day      : GBP {daily['total'].quantile(0.90):,.2f}")
    print(tx.groupby("category")["amount"].sum().sort_values(ascending=False).round(0).to_string())


if __name__ == "__main__":
    main()
