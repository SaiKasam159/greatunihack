import Foundation
import Observation

@MainActor
@Observable
final class CalendarInsightsViewModel {
    enum State {
        case idle
        case loading
        case loaded(CalendarSpendResult)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var liveError: String?
    var daysAhead: Int = 90
    var currency: String = "GBP"

    private let client: N8nClient
    private var hasLoaded = false

    init(client: N8nClient = N8nClient()) {
        self.client = client
    }

    var result: CalendarSpendResult? {
        if case .loaded(let result) = state { return result }
        return nil
    }

    var occasions: [CalendarOccasion] { result?.occasions ?? [] }
    var isDemo: Bool { result?.isDemo ?? false }
    var totalEstimated: Double { occasions.reduce(0) { $0 + $1.estimatedSpend } }
    var biggest: CalendarOccasion? {
        occasions.max { $0.estimatedSpend < $1.estimatedSpend }
    }

    func load(force: Bool = false) async {
        if hasLoaded && !force { return }
        hasLoaded = true
        state = .loading
        liveError = nil
        do {
            let result = try await client.calendarSpend(daysAhead: daysAhead, currency: currency)
            state = .loaded(result)
        } catch {
            // Draft workflows are unpublished during development, so keep the screen
            // useful and make the fallback unmistakable in the UI.
            liveError = error.localizedDescription
            state = .loaded(N8nDemoData.calendarResult(daysAhead: daysAhead, currency: currency))
        }
    }

    func select(daysAhead days: Int) {
        guard days != daysAhead else { return }
        daysAhead = days
        Task { await load(force: true) }
    }
}

@MainActor
@Observable
final class PriceCheckViewModel {
    enum State {
        case idle
        case loading
        case loaded(PriceFinderResult)
        case failed(String)
    }

    private(set) var state: State = .idle
    var country: String = "uk"

    private let client: N8nClient

    init(client: N8nClient = N8nClient()) {
        self.client = client
    }

    var result: PriceFinderResult? {
        if case .loaded(let result) = state { return result }
        return nil
    }

    var isSearching: Bool {
        if case .loading = state { return true }
        return false
    }

    func search(base64Image: String) async {
        state = .loading
        do {
            state = .loaded(try await client.priceFinder(
                base64Image: base64Image,
                country: country.isEmpty ? "uk" : country.lowercased()
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Explicit opt-in so sample prices are never shown as if they were the user's photo.
    func showSample() {
        state = .loaded(N8nDemoData.priceResult())
    }

    func reset() {
        state = .idle
    }
}
