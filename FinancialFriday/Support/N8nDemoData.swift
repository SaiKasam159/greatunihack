import Foundation

/// Fallback content used when n8n is unreachable or still unpublished.
///
/// Both workflows are drafts, so the app must never show a blank screen at a demo.
/// Everything produced here is flagged `isDemo` and the UI shows a banner, so the
/// sample numbers are never mistaken for live results.
enum N8nDemoData {

    static func calendarResult(daysAhead: Int, currency: String) -> CalendarSpendResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func date(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: today) ?? today
        }

        let occasions: [CalendarOccasion] = [
            .demo(date: date(9), title: "Friday night out with friends", type: "Social",
                  level: .high, big: true, spend: 68, confidence: .medium,
                  drivers: "Group dinner, drinks, late taxi home",
                  tip: "Set a £50 cap before you leave and take one card."),
            .demo(date: date(16), title: "Amy's birthday", type: "Birthday",
                  level: .high, big: true, spend: 95, confidence: .high,
                  drivers: "Gift, card, birthday dinner",
                  tip: "Buy the gift this week, before payday pressure builds."),
            .demo(date: date(24), title: "Work payday", type: "Payday",
                  level: .medium, big: false, spend: 42, confidence: .low,
                  drivers: "Payday treat, subscriptions renew",
                  tip: "Move £40 to savings the moment the salary lands."),
            .demo(date: date(37), title: "Family ceremony", type: "Ceremony",
                  level: .high, big: true, spend: 180, confidence: .high,
                  drivers: "Travel, gift, outfit, meal",
                  tip: "Budget across two pay cycles instead of one."),
            .demo(date: date(55), title: "Christmas shopping window", type: "Festival",
                  level: .high, big: true, spend: 320, confidence: .medium,
                  drivers: "Gifts for six people, food, travel",
                  tip: "Make a list with a per-person limit before you shop."),
            .demo(date: date(68), title: "Concert tickets on sale", type: "Event",
                  level: .medium, big: false, spend: 75, confidence: .low,
                  drivers: "Tickets, booking fee, travel",
                  tip: "Decide the maximum bid now, not at checkout.")
        ]

        return CalendarSpendResult(
            occasions: occasions,
            daysAhead: daysAhead,
            currency: currency,
            ignoredCount: 41,
            isDemo: true
        )
    }

    static func priceResult() -> PriceFinderResult {
        let matches: [PriceMatch] = [
            .demo(kind: .exact, title: "Sony WH-1000XM5", manufacturer: "Sony", model: "WH-1000XM5",
                  shop: "Amazon UK", price: 279, currency: "GBP",
                  notes: "Cheapest exact match for the photographed model."),
            .demo(kind: .sameBrand, title: "Sony WH-CH720N", manufacturer: "Sony", model: "WH-CH720N",
                  shop: "Currys", price: 99, currency: "GBP",
                  notes: "Same manufacturer, cheaper tier, no auto noise cancelling."),
            .demo(kind: .similar, title: "Bose QuietComfort 45", manufacturer: "Bose", model: "QC45",
                  shop: "John Lewis", price: 229, currency: "GBP",
                  notes: "Same over-ear ANC category, slightly lighter, no LDAC.")
        ]
        return PriceFinderResult(matches: matches, product: "Sony WH-1000XM5", isDemo: true)
    }
}

private extension CalendarOccasion {
    static func demo(date: Date, title: String, type: String, level: SpendingLevel,
                     big: Bool, spend: Double, confidence: Confidence,
                     drivers: String, tip: String) -> CalendarOccasion {
        CalendarOccasion(
            date: date, title: title, type: type, level: level, bigSpending: big,
            estimatedSpend: spend, costDrivers: drivers, confidence: confidence, tip: tip
        )
    }
}

private extension PriceMatch {
    static func demo(kind: PriceMatchKind, title: String, manufacturer: String, model: String,
                     shop: String, price: Double, currency: String, notes: String) -> PriceMatch {
        PriceMatch(kind: kind, title: title, manufacturer: manufacturer, model: model,
                   shop: shop, price: price, currency: currency, link: nil, notes: notes)
    }
}
