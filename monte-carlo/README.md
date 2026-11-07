# Monte Carlo engine: "financial time travel"

`great_uni_hack_monte_carlo.py` simulates how each plan the agents recommend changes the user's future, short and long term, using **their own transaction history**: real Friday-night spikes, payday timing, bills and occasional big nights.

It follows the README's fund ladder (emergency → savings → growth, with growth locked until the emergency fund hits its target) and produces exactly the numbers the `ui/` screens show.

```bash
pip install -r monte-carlo/requirements.txt       # numpy, pandas, matplotlib
python monte-carlo/great_uni_hack_monte_carlo.py  # demo: Maya + Sam -> great_uni_hack_output/
python monte-carlo/great_uni_hack_monte_carlo.py --test
python monte-carlo/great_uni_hack_monte_carlo.py --transactions spend-risk/data/transactions_fake.csv \
       --income '{"monthly": 2100, "payday": 28}' --balances '{"current": 400, "emergency": 150}'
```

The demo writes `report.html` (one-page summary with every chart), PNG charts, `summary.json` and `ui_data.json` for each persona.

## What it gives each screen

| Screen | Field in `ui_payload(results)` |
|---|---|
| 5 Pick your plan | `plans[]`: `name`, `tagline`, `how`, `outcome` ("£18.9k"), `unlock` ("Emergency fund full by month 3, then growth fund unlocks"); `overspending.label` |
| 7 Home graph | `home.bigNum` / `home.bigSub` (keyed by view: `both`/`plan`/`over`), `home.series` (yearly p10/p50/p90), `home.svg` (ready-made points for the 326×160 SVG), `home.aria`, `home.legend` |
| 7 Home checkpoints | `checkpoints.emergency_fund` ("Emergency fund: £180 of £990") |
| 8 Red zone alert | `red_zone_snowball.five_year_cost`; `repeat_cost(extra, events_per_year)` for one event |
| 9 Check-in | `checkin_forecast(profile, plan, overspend=85)`: 5-year funds before/after the repair, % of damage undone |
| Resilience headline | `resilience.label` ("95% chance you can cover a surprise £300 bill next month") |

## For the agents

Agents send plans as JSON (`reduce_category`, `cap_window`, `recurring_transfer`, `sweep_surplus`, `lump_sum_transfer`, `one_off_purchase`, `cancel_subscription`, `reduce_bill`; see the header of the .py file). `summarise(results)` returns plain-language headlines, a comfort score and a recommended plan for each option.

## "Comfortable" is personal

Nothing is a fixed number. From each person's history the engine learns:

- **Essentials:** what they need every month.
- **The lifestyle they value:** what they spend on in most weeks.
- **A personal floor:** 3 days of their own normal outgoings.

A plan is scored on how often they stay above their floor without raiding savings, and on how much of the lifestyle they enjoy it keeps. A plan that saves the most but cuts everything they enjoy scores low, because people don't stick to it.

Guidance, not regulated advice. Returns are illustrative (7% mean, 15% volatility).
