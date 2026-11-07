import Foundation
import SwiftData

@Model
final class CoachProfile {
    var dataDefaultsConfigured = false
    var onboardingComplete = false
    var walkthroughComplete = false

    var wantsNights = false
    var wantsPayday = false
    var wantsEmergency = false
    var wantsBigPurchase = false
    var wantsInvesting = false
    var wantsDebt = false

    var payFrequency = ""
    var monthFeeling = ""
    var savingsLevel = ""
    var debtLevel = ""

    var currentLinked = false
    var cardLinked = false
    var savingsLinked = false
    var calendarLinked = false
    var selectedPlan = "Sweep it"
    var eventBudgetMinorUnits: Int64 = 0
    var eventBudgetSet = false
    var forecastRepaired = false
    var lastCheckInAt: Date?

    init() {}

    var eventBudget: Decimal {
        get { Decimal(eventBudgetMinorUnits) / 100 }
        set { eventBudgetMinorUnits = NSDecimalNumber(decimal: newValue * 100).int64Value }
    }
}
