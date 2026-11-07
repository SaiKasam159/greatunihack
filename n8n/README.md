# n8n workflows (GreatUniHack backend)

Instance: https://shalev787.app.n8n.cloud/

Two workflows, built as **unpublished drafts**, run on **Gateway credits** (no AI key needed). Each is a web form ending in a CSV download, and each now also exposes a **POST webhook returning JSON** so the app can call it directly. The old Form Trigger and CSV download still work next to the webhook.

Nothing is published yet. Until you publish, the webhook paths answer **404 "webhook not registered"**, and the production URLs do not exist.

---

## Endpoints

| Workflow | ID | Webhook (after publishing) |
|---|---|---|
| Product Image Price Finder | `MWZPSMDBFffpwAO0` | `POST /webhook/product-price` |
| Calendar Spending Analysis | `bBzOW9QXmA2lbGNj` | `POST /webhook/calendar-spend` |

Base: `https://shalev787.app.n8n.cloud`

### 1. Product Image Price Finder

Request:

```json
{ "image": "<base64 or data URL>", "country": "uk" }
```

- `image` is required; decoded to a file for the existing AI step.
- Images over **4 MB** return `{"ok":false,"error":"image too large"}`; bad input returns 400.
- `country` defaults to `uk`. Currency is inferred from the price symbol, falling back to the country.

Response:

```json
{
  "ok": true,
  "rows": [
    { "kind": "exact",       "title": "...", "manufacturer": "...", "model": "...",
      "shop": "...", "price": 279, "currency": "GBP", "link": "https://...", "notes": "..." },
    { "kind": "same-brand",  "...": "..." },
    { "kind": "similar",     "...": "..." }
  ],
  "meta": { "product": "Sony WH-1000XM5", "country": "uk", "searches": 2 }
}
```

Tested sample output (simulated AI + search): WH-1000XM5 at 279 (exact), WH-CH720N at 99 (same-brand), Bose QC45 at 229 (similar).

### 2. Calendar Spending Analysis

Request:

```json
{ "daysAhead": 90, "currency": "GBP" }
```

- `daysAhead` defaults to 90 and is clamped to 1–365; a non-number returns 400.
- `currency` must be three letters; otherwise 400.
- Both values feed the calendar query and the AI prompt.
- The AI prompt now also asks for `estimated_spend_value` (a number), which becomes an extra CSV column.

Response:

```json
{
  "ok": true,
  "rows": [
    { "date": "2026-12-12", "title": "...", "type": "...",
      "spendingLevel": "High", "bigSpending": true,
      "estimatedSpend": 180, "estimated_spend_value": 180,
      "costDrivers": "...", "confidence": "high", "tip": "..." }
  ],
  "meta": { "daysAhead": 90, "currency": "GBP", "occasions": 7, "ignored": 41 }
}
```

**Not yet verified:** verification stops at the calendar node with "Not a valid Google Calendar ID". Select the calendar in the setup panel and the JSON output can be tested.

### CORS

Every JSON response carries `Content-Type: application/json`, `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: POST, OPTIONS` and `Access-Control-Allow-Headers: Content-Type`. Preflight is delegated to n8n itself (allowed origins set to `*`); a live `OPTIONS` check has not been run.

---

## Client 1: the HTML UI (`ui/`)

`fetch()` from a static page needs the CORS headers above, and the page must be served over http(s) — `file://` cannot call a webhook. Not needed if the app is the native client.

## Client 2: the iOS app (`FinancialFriday/`)

Native `URLSession` is not subject to CORS, so the iOS client only needs the JSON contract.

| File | Role |
|---|---|
| `Models/N8nModels.swift` | Tolerant decoding: snake_case/camelCase keys, `£120.50` as a string, `Yes`/`No` booleans, several date formats, bare arrays or `{ok, rows, meta}` |
| `Services/N8nClient.swift` | Async POST, one retry on transport errors, 404 → "not published", `ok:false` → the workflow's own message |
| `ViewModels/N8nViewModels.swift` | Loading/loaded/failed state, 30/90/180-day window, sample fallback for the calendar |
| `Views/CalendarInsightsView.swift` | Workflow 2: occasion cards with level, estimate, drivers, confidence and tip |
| `Views/PriceCheckView.swift` | Workflow 1: PhotosPicker → downscale to ≤1600 px → base64 → results grouped by kind |
| `Support/N8nDemoData.swift` | Labelled sample data so an unpublished workflow never leaves an empty screen |

Entry points: **Home → Calendar insights**, **Red zones → From your calendar**, **Weekly check-in → Check a price before you buy**.

Override the instance without a rebuild:

```
UserDefaults.standard.set("https://your-tunnel.example", forKey: "N8nBaseURL")
```

### Demo script once published

1. Publish both workflows, add the SerpAPI key and the Google Calendar.
2. `curl -i -X POST https://shalev787.app.n8n.cloud/webhook/calendar-spend -H "Content-Type: application/json" -d '{"daysAhead":90,"currency":"GBP"}'`
3. In the app: Home → Calendar insights → pull to refresh. The orange "Sample data" banner disappears when live rows arrive.
4. Red zones → From your calendar; Weekly check-in → Check a price.

If the banner stays, the error under it names the cause (not published, HTTP status, or timeout).
