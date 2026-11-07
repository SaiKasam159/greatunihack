import SwiftData
import SwiftUI

@main
struct FinancialFridayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [FinancialGoal.self, CoachProfile.self])
    }
}
