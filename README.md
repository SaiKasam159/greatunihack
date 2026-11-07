# FinancialFriday

FinancialFriday is a native iPhone app that turns a bundled year of synthetic transaction data into personalised spending insights, weekly financial checkpoints, recovery plans, and on-device purchase guidance.

The app is written entirely in SwiftUI. It does not use a WebView, a cloud AI service, or a live bank connection.

## Current features

- Five-step onboarding for goals, financial situation, account preferences, calculated red zones, and plan selection.
- Home dashboard with a data-driven forecast, current check-in streak, and weekly checkpoints.
- Spending red-zone heatmap calculated from transaction weekday and time patterns.
- Dynamic Friday alerts, event budgets, upcoming spending windows, and Saturday recovery suggestions.
- Plan comparison and five-year projections based on the selected plan and analysed cash flow.
- Financial overview with income, expenses, cash flow, category breakdowns, trends, and spending insights.
- SwiftData persistence for onboarding choices, plan selection, budgets, goals, repair state, and check-in activity.
- On-device AI Coach for purchase decisions and conversational follow-up questions.

## AI Coach

The AI Coach uses Apple's Foundation Models framework and `SystemLanguageModel.default`. Purchase evaluations are generated as typed `@Generable` output and presented as native SwiftUI components:

- Final verdict: `BUY`, `WAIT`, or `SKIP`
- Short verdict explanation
- Relevant balance figures when they can be calculated reliably
- Five expandable perspectives: Financial, Research, Devil's Advocate, Lifestyle, and Future

Follow-up messages use a separate structured response type and are displayed as normal conversational text. The model receives the calculated financial context and the previous purchase evaluation. There is no cloud fallback.

The rest of the app supports iOS 18 or later. The AI Coach requires:

- iOS 26 or later
- An Apple Intelligence-compatible device
- Apple Intelligence enabled and its on-device model ready

On unsupported devices, the financial features remain available and the Coach tab explains why AI is unavailable.

## Data

The app bundles [`financialfriday_synthetic_1user_1year.csv`](financialfriday_synthetic_1user_1year.csv). It contains one year of synthetic transactions with this schema:

```text
timestamp,merchant,category,amount_gbp,type,channel,user_id
```

At launch, the CSV is parsed locally and used to calculate the financial summary, heatmap, red zones, streak, forecasts, event budgets, alerts, checkpoints, and repair suggestions. Figures described as balances are calculated from the synthetic transaction history; they are not live bank balances.

The onboarding connection controls are demo preferences. They do not connect to a bank account or calendar.

## Technology

- Swift 6
- SwiftUI
- SwiftData
- Charts
- Foundation Models (`@Generable` structured output)
- Local CSV parsing and financial analysis

## Project layout

```text
FinancialFriday/
├── Models/       Data, SwiftData, chat, and AI response models
├── Services/     CSV loading, calculations, context, and AI service
├── ViewModels/   App and AI Coach state
├── Views/        SwiftUI screens and reusable components
└── Assets.xcassets/

FinancialFriday.xcodeproj/
financialfriday_synthetic_1user_1year.csv
greatunihack/     Original HTML design-reference files
monte-carlo/      Original prototype simulation from the base repository
ui/               Original clickable prototype from the base repository
```

## Run the app

1. Install Xcode 26 or later.
2. Open `FinancialFriday.xcodeproj`.
3. Select the `FinancialFriday` scheme.
4. Choose an iPhone target and run.

For the complete AI Coach experience, use a physical Apple Intelligence-compatible iPhone. The app target uses automatic signing, so select your own development team if Xcode requests it.

## Command-line build

```bash
xcodebuild \
  -project FinancialFriday.xcodeproj \
  -scheme FinancialFriday \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Privacy and scope

- All included financial data is synthetic.
- Financial analysis and AI generation run locally.
- The app does not move money or connect to a financial institution.
- Outputs are educational guidance, not regulated financial advice.
