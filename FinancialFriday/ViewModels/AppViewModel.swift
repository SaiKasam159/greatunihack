import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    enum LoadState {
        case loading
        case loaded(FinancialSummary)
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            let transactions = try await TransactionDataService.loadBundledTransactions()
            guard let summary = FinancialAnalysisService.analyse(transactions) else {
                state = .failed("The dataset does not contain any transactions.")
                return
            }
            state = .loaded(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
