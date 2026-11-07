# n8n workflows (GreatUniHack backend)

Instance: https://shalev787.app.n8n.cloud/

Two workflows are built as unpublished drafts and run on **Gateway credits** (no AI key needed from you). Neither has been run against real data yet — both were tested end to end with simulated shop results, calendar events and AI answers. Each workflow is a web form that ends with a downloadable CSV.

## 1. Product Image Price Finder

- **Workflow ID:** `MWZPSMDBFffpwAO0`
- **Form input:** a product photo (required) + an optional country code (defaults to `uk`)
- **Steps:** an AI step reads the image to get brand, model and visible text. Two Google Shopping searches follow — one for the exact product, one for similar products. Google Shopping aggregates many shops, so this is not a separate search per shop.
- **Output CSV rows:**
  - cheapest match for the exact product
  - other models from the same manufacturer, with prices
  - similar products from other brands, with notes on what they share and how the price differs
- Each row carries shop, price and link.
- **Still needed:** a SerpAPI key, added in the setup panel. SerpAPI is the service that runs the Google Shopping search.

## 2. Calendar Spending Analysis

- **Workflow ID:** `bBzOW9QXmA2lbGNj`
- **Form input:** how many days ahead to look (default 90) and a currency
- **Steps:** reads Google Calendar and keeps birthdays, festivals, ceremonies and special events; routine meetings are ignored. Spend figures are AI estimates based on the event title, description, location and guest count.
- **Output CSV:** one row per occasion with columns `date, title, type, spending level (Low/Medium/High), big spending (Yes/No), estimated spend, cost drivers, confidence, short tip`.
- **Still needed:** connect Google Calendar and pick the calendar in the setup panel. It currently points at the primary calendar.

## How the UI uses them

- Screen 4 (Your red zones) → Workflow 2: calendar events → ranked red zones with cost drivers.
- Screen 8 (Red zone alert) → Workflow 2: upcoming event, predicted cost, reasons, coming-up list.
- Screen 9 (Morning-after check-in) → Workflow 1: photo of last night's receipt → price comparison.

To test either workflow live, tell Shalev. Workflow 1 needs a product photo.
