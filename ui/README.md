# Finance Your Friday – UI

Clickable screens for the demo. **Open `index.html` in a browser** (double-click it) and tap through from Goals. No server or install needed.

Editable design canvas (Claude Design): https://claude.ai/artifact/NLDNZdM1K3cSHcKYyFAznK

## Folder

```
ui/
├── index.html            # list of all screens
└── screens/
    ├── support.js        # tiny viewer that makes each screen run standalone
    ├── Main.dc.html      # 1  Goals
    ├── Situation.dc.html # 2  Your situation
    ├── Connect.dc.html   # 3  Accounts & calendar
    ├── Anomalies.dc.html # 4  Your red zones
    ├── Plans.dc.html     # 5  Pick your plan
    ├── Walkthrough.dc.html # 6 Coach walkthrough (overlays Home)
    ├── Home.dc.html      # 7  Home
    ├── FridayAlert.dc.html # 8 Red zone alert (from calendar)
    └── SaturdayCheckin.dc.html # 9 Morning-after check-in
```

Each screen is one HTML file: the markup is plain HTML with inline styles (easy to copy into React/Streamlit components), and the small script at the bottom holds its state and demo data.

## What each screen needs from the backend

| Screen | Data it shows | Comes from |
|---|---|---|
| 4 Red zones | Weekly heatmap, monthly overspend, ranked red zones with £ over usual | Python anomaly model |
| 5 Pick your plan | 3 plans with 5-year outcome and fund-unlock month | Agents (+ Monte Carlo) |
| 7 Home – graph | Plan median + likely range, "keep overspending" line, 5 years | Monte Carlo engine |
| 7 Home – checkpoints | This week's checkpoints and progress | Agents (chosen plan) |
| 8 Red zone alert | Upcoming calendar event, predicted cost, reasons, coming-up list | n8n (calendar fetch + tag) → Python (predict) |
| 9 Check-in | Last night's spend vs budget, recovery move, repaired forecast | Python + agents |

## Design tokens

| Token | Value | Use |
|---|---|---|
| Background | `#FFFFFF` | Screens |
| Tile | `#F4F5F7` | Cards, list rows, segmented controls |
| Text | `#16181D` | Primary text |
| Text secondary | `#5F6475` | Labels, captions |
| Accent | `#1A73E8` | Buttons, your plan, selected states |
| Red zone | `#D9480F` (text `#B93A0B`) | Overspending, alerts, streak flame |
| Red zone tint | `#FFF4EC` | Alert and streak backgrounds |
| Plan tint | `#EAF2FD` | "The way back" card |
| Success | `#1E7B38` on `#E6F4EA` | Done, linked, repaired |
| Font | Inter 400/500/600/700 | Everything |
| Radius | 14px rows, 16–18px cards, 36px phone | |
| Section labels | 12px, 600, 0.06em tracking, uppercase | "YOUR FINANCIAL FUTURE" etc. |

## n8n backend

Two workflows live at https://shalev787.app.n8n.cloud/ (see `n8n/README.md` and `ui/n8n.html`):

- **Product Image Price Finder** (`MWZPSMDBFffpwAO0`) — photo + optional country code → Google Shopping exact/similar → CSV (shop, price, link). Needs a SerpAPI key in the setup panel.
- **Calendar Spending Analysis** (`bBzOW9QXmA2lbGNj`) — days ahead + currency → Google Calendar events → CSV (date, title, type, spending level, big spending, estimate, cost drivers, confidence, tip). Needs Google Calendar connected.

Both run on Gateway credits; neither has run against real data yet (only simulated). To test either, tell Shalev — Workflow 1 needs a product photo.
