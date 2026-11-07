import SwiftData
import SwiftUI

struct RootView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                LoadingView()
            case .failed(let message):
                ContentUnavailableView(
                    "Unable to analyse transactions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded(let summary):
                FinancialFridayExperience(summary: summary)
            }
        }
        .task { await viewModel.load() }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sterlingsign.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accent)
            ProgressView("Analysing your finances…")
                .tint(Color.accent)
        }
    }
}

extension Color {
    static let accent = Color(red: 0.10, green: 0.45, blue: 0.91)
    static let income = Color(red: 0.08, green: 0.46, blue: 0.35)
    static let expense = Color(red: 0.85, green: 0.28, blue: 0.06)
}
