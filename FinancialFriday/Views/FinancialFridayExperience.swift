import SwiftData
import SwiftUI

enum GU {
    static let ink = Color(red: 22/255, green: 24/255, blue: 29/255)
    static let secondary = Color(red: 95/255, green: 100/255, blue: 117/255)
    static let surface = Color(red: 244/255, green: 245/255, blue: 247/255)
    static let border = Color(red: 236/255, green: 237/255, blue: 241/255)
    static let blue = Color(red: 26/255, green: 115/255, blue: 232/255)
    static let paleBlue = Color(red: 234/255, green: 242/255, blue: 253/255)
    static let orange = Color(red: 217/255, green: 72/255, blue: 15/255)
    static let paleOrange = Color(red: 1, green: 244/255, blue: 236/255)
    static let green = Color(red: 30/255, green: 123/255, blue: 56/255)
    static let paleGreen = Color(red: 230/255, green: 244/255, blue: 234/255)
}

struct FinancialFridayExperience: View {
    let summary: FinancialSummary
    @Environment(\.modelContext) private var context
    @Query private var profiles: [CoachProfile]
    @State private var didResetSetupGoals = false

    var body: some View {
        Group {
            if let profile = profiles.first {
                Group {
                    if profile.onboardingComplete {
                        MainExperience(summary: summary, profile: profile)
                    } else {
                        OnboardingFlow(summary: summary, profile: profile)
                    }
                }
                .task { prepare(profile) }
            } else {
                ProgressView()
                    .task { context.insert(CoachProfile()) }
            }
        }
        .foregroundStyle(GU.ink)
    }

    private func prepare(_ profile: CoachProfile) {
        configureDefaults(profile)
        guard !profile.onboardingComplete, !didResetSetupGoals else { return }
        profile.wantsNights = false
        profile.wantsPayday = false
        profile.wantsEmergency = false
        profile.wantsBigPurchase = false
        profile.wantsInvesting = false
        profile.wantsDebt = false
        didResetSetupGoals = true
    }

    private func configureDefaults(_ profile: CoachProfile) {
        guard !profile.dataDefaultsConfigured else { return }
        let analysis = FinancialExperienceAnalysis.make(summary: summary)
        profile.payFrequency = analysis.inferredPayFrequency
        profile.monthFeeling = analysis.inferredMonthFeeling
        profile.savingsLevel = analysis.inferredSavingsLevel
        profile.debtLevel = analysis.inferredDebtLevel
        profile.currentLinked = !summary.transactions.isEmpty
        profile.wantsPayday = summary.averageMonthlyNetCashFlow < 0
        profile.wantsEmergency = summary.currentBalance < summary.averageMonthlyExpenses
        profile.wantsNights = analysis.peakWeekday.weekday == 6 || analysis.peakWeekday.weekday == 7
        profile.wantsDebt = analysis.inferredDebtLevel != "None"
        profile.eventBudget = analysis.budgetOptions.dropFirst().first ?? analysis.typicalEventSpend
        profile.dataDefaultsConfigured = true
    }
}

private struct OnboardingFlow: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: step + 1) { withAnimation { step -= 1 } }
                .padding(.horizontal, 24).padding(.top, 10)
            Group {
                switch step {
                case 0: GoalChoices(profile: profile)
                case 1: SituationChoices(profile: profile)
                case 2: ConnectionChoices(profile: profile)
                case 3: RedZonesView(summary: summary, onboarding: true)
                default: onboardingPlanPicker
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            PrimaryButton(step == 3 ? "Build my plans" : step == 4 ? "Go with \(profile.selectedPlan)" : step == 2 ? "Find my red zones" : "Continue") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if step == 4 { profile.onboardingComplete = true }
                    else { step += 1 }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 18)
        }
        .background(.white)
    }

    private var onboardingPlanPicker: some View {
        ScrollView {
            PlanPicker(summary: summary, profile: profile, onboarding: true)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }
}

private struct OnboardingHeader: View {
    let step: Int
    let back: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if step > 1 {
                Button(action: back) { Image(systemName: "chevron.left").frame(width: 44, height: 44).background(GU.surface, in: Circle()) }
                    .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(GU.border)
                    Capsule().fill(GU.blue).frame(width: geo.size.width * CGFloat(step) / 5)
                }
            }.frame(height: 4)
            Text("\(step) of 5").font(.system(size: 13, weight: .medium)).foregroundStyle(GU.secondary)
        }.frame(height: 44)
    }
}

private struct GoalChoices: View {
    @Bindable var profile: CoachProfile
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Intro(kicker: "YOUR COACH", title: "What do you want your money to do?", detail: "Pick everything that fits. Your plans get built around it.")
                VStack(spacing: 8) {
                    ToggleRow(icon: "wineglass", title: "Stop overspending on nights out and events", isOn: $profile.wantsNights)
                    ToggleRow(icon: "creditcard", title: "Stop running out before payday", isOn: $profile.wantsPayday)
                    ToggleRow(icon: "shield", title: "Build an emergency fund", isOn: $profile.wantsEmergency)
                    ToggleRow(icon: "target", title: "Save for something big", isOn: $profile.wantsBigPurchase)
                    ToggleRow(icon: "chart.line.uptrend.xyaxis", title: "Start investing for the long term", isOn: $profile.wantsInvesting)
                    ToggleRow(icon: "creditcard.and.123", title: "Pay off my debt", isOn: $profile.wantsDebt)
                }
            }.padding(24)
        }.scrollIndicators(.hidden)
    }
}

private struct SituationChoices: View {
    @Bindable var profile: CoachProfile
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Intro(kicker: nil, title: "Which best fits your situation?", detail: "This helps your coach keep every suggestion realistic.")
                ChoiceSection(title: "HOW OFTEN ARE YOU PAID?", choices: ["Monthly", "Weekly", "Irregular"], selection: $profile.payFrequency)
                ChoiceSection(title: "HOW DOES THE MONTH USUALLY FEEL?", choices: ["Comfortable", "Tight", "Struggling"], selection: $profile.monthFeeling)
                ChoiceSection(title: "SAVINGS RIGHT NOW", choices: ["None", "Under one month", "One month+"], selection: $profile.savingsLevel)
                ChoiceSection(title: "DEBT", choices: ["None", "Card / overdraft", "Loans"], selection: $profile.debtLevel)
            }.padding(24)
        }.scrollIndicators(.hidden)
    }
}

private struct ConnectionChoices: View {
    @Bindable var profile: CoachProfile
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Intro(kicker: nil, title: "Connect your accounts", detail: "Your coach reads the last 12 months to find your red zones, and your calendar to see the next ones coming.")
                Text("BANK ACCOUNTS").eyebrow()
                VStack(spacing: 8) {
                    LinkRow(icon: "creditcard", title: "Current account", detail: "Where your pay lands", linked: $profile.currentLinked)
                    LinkRow(icon: "creditcard.fill", title: "Credit card", detail: "Big nights often land here", linked: $profile.cardLinked)
                    LinkRow(icon: "shield", title: "Savings account", detail: "So your buffer is counted", linked: $profile.savingsLinked)
                }
                Text("REMINDERS").eyebrow()
                LinkRow(icon: "calendar", title: "Pattern reminders", detail: "Uses transaction history to flag upcoming high-spend weekdays", linked: $profile.calendarLinked)
                Label("Read-only connections. Your coach can see the bundled transaction history and events, but cannot move money.", systemImage: "lock")
                    .font(.system(size: 13)).foregroundStyle(GU.secondary)
            }.padding(24)
        }.scrollIndicators(.hidden)
    }
}

private struct MainExperience: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    @State private var selected = 0

    var body: some View {
        TabView(selection: $selected) {
            HomeView(summary: summary, profile: profile).tag(0)
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { RedZonesView(summary: summary, onboarding: false).navigationTitle("Red zones").navigationBarTitleDisplayMode(.inline) }.tag(1)
                .tabItem { Label("Red zones", systemImage: "flame") }
            NavigationStack { PlanHub(summary: summary, profile: profile).navigationTitle("Your plan").navigationBarTitleDisplayMode(.inline) }.tag(2)
                .tabItem { Label("Plan", systemImage: "checklist") }
            Group {
                if #available(iOS 26.0, *) { AICoachView(summary: summary) } else { AIUnsupportedView() }
            }
            .tag(3)
            .tabItem { Label("Coach", systemImage: "apple.intelligence") }
        }
        .tint(GU.blue)
    }
}

private struct HomeView: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    @State private var projection = "Compare"
    @State private var route: HomeRoute?
    enum HomeRoute: Hashable { case alert, checkin }
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { route = .checkin } label: { Label("\(analysis.weeklyStreak) weeks", systemImage: "flame.fill").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 12).frame(height: 40).background(GU.paleOrange, in: Capsule()).foregroundStyle(GU.orange) }
                        Spacer()
                        Text("Finance Your Friday").font(.system(size: 16, weight: .bold))
                        Spacer()
                        Button { route = .alert } label: { Image(systemName: "bell.badge.fill").font(.title3).frame(width: 40, height: 40).foregroundStyle(GU.ink) }
                    }
                    ForecastCard(summary: summary, plan: profile.selectedPlan, selection: $projection)
                    Checkpoints(summary: summary, profile: profile, alert: { route = .alert }, checkin: { route = .checkin })
                    NavigationLink { OverviewView(summary: summary) } label: {
                        Label("View full financial overview", systemImage: "chart.bar.xaxis").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(14).background(GU.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                    NavigationLink { CalendarInsightsView() } label: {
                        Label("Calendar insights", systemImage: "calendar.badge.clock").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(14).background(GU.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 18)
            }
            .background(.white)
            .navigationDestination(item: $route) { route in
                switch route {
                case .alert: FridayAlertView(summary: summary, profile: profile)
                case .checkin: SaturdayCheckinView(summary: summary, profile: profile)
                }
            }
        }
    }
}

private struct ForecastCard: View {
    let summary: FinancialSummary
    let plan: String
    @Binding var selection: String
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    private var planMultiplier: Decimal { plan == "Sweep it" ? Decimal(1) : plan == "Cap it" ? Decimal(string: "0.7")! : Decimal(string: "0.5")! }
    private var projected: Decimal { analysis.fiveYearPlanBase + analysis.recoverableFiveYearSpend * planMultiplier }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("YOUR FINANCIAL FUTURE").eyebrow(); Spacer(); Text("\(plan) plan").font(.caption).foregroundStyle(GU.secondary) }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppFormatting.compactCurrency(selection == "Overspending" ? analysis.fiveYearOverspending : projected)).font(.system(size: 28, weight: .semibold))
                Text(selection == "Overspending" ? "in 5 years if nothing changes" : "likely in 5 years").font(.caption).foregroundStyle(GU.secondary)
            }
            Segmented(options: ["Compare", "My plan", "Overspending"], selection: $selection)
            ProjectionChart(showPlan: selection != "Overspending", showOverspending: selection != "My plan", planEnd: projected, overspendingEnd: analysis.fiveYearOverspending)
                .frame(height: 156)
            Label("Your plan, likely range", systemImage: "minus").foregroundStyle(GU.blue)
            Label("If red-zone overspending continues", systemImage: "minus").foregroundStyle(GU.orange)
        }.font(.system(size: 12)).padding(16).background(GU.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ProjectionChart: View {
    let showPlan: Bool
    let showOverspending: Bool
    let planEnd: Decimal
    let overspendingEnd: Decimal
    var body: some View {
        Canvas { context, size in
            let grid = Path { p in for y in [0.2, 0.55, 0.9] { p.move(to: .init(x: 0, y: size.height*y)); p.addLine(to: .init(x: size.width, y: size.height*y)) } }
            context.stroke(grid, with: .color(GU.border), lineWidth: 1)
            let maximum = max(planEnd.doubleValue, overspendingEnd.doubleValue, 1)
            let planY = size.height * (0.9 - 0.78 * planEnd.doubleValue / maximum)
            let overY = size.height * (0.9 - 0.78 * overspendingEnd.doubleValue / maximum)
            let plan = Path { p in p.move(to: .init(x: 0, y: size.height * 0.9)); p.addCurve(to: .init(x: size.width, y: planY), control1: .init(x: size.width * 0.38, y: size.height * 0.72), control2: .init(x: size.width * 0.7, y: (planY + size.height * 0.72) / 2)) }
            context.opacity = showPlan ? 1 : 0.12; context.stroke(plan, with: .color(GU.blue), lineWidth: 3)
            let over = Path { p in p.move(to: .init(x: 0, y: size.height * 0.9)); p.addLine(to: .init(x: size.width, y: overY)) }
            context.opacity = showOverspending ? 1 : 0.12; context.stroke(over, with: .color(GU.orange), style: StrokeStyle(lineWidth: 3, dash: [6,5]))
        }
    }
}

private struct Checkpoints: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    let alert: () -> Void
    let checkin: () -> Void
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    private var checkedInThisWeek: Bool {
        guard let date = profile.lastCheckInAt else { return false }
        return Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 8 < 7
    }
    private var completed: Int {
        [summary.averageMonthlyNetCashFlow >= 0, analysis.latestWeekSpending <= summary.averageWeeklySpending, profile.eventBudgetSet, checkedInThisWeek].filter { $0 }.count
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text("THIS WEEK'S CHECKPOINTS").eyebrow(); Spacer(); Text("\(completed) of 4 done").font(.caption).foregroundStyle(GU.secondary) }
            Checkpoint(icon: summary.averageMonthlyNetCashFlow >= 0 ? "checkmark" : "arrow.up", title: "Positive monthly cash flow", detail: AppFormatting.currency(summary.averageMonthlyNetCashFlow), color: summary.averageMonthlyNetCashFlow >= 0 ? GU.paleGreen : GU.paleBlue)
            Checkpoint(icon: analysis.latestWeekSpending <= summary.averageWeeklySpending ? "checkmark" : "chart.line.downtrend.xyaxis", title: "Weekly spending baseline", detail: "Latest \(AppFormatting.currency(analysis.latestWeekSpending)) · average \(AppFormatting.currency(summary.averageWeeklySpending))", color: analysis.latestWeekSpending <= summary.averageWeeklySpending ? GU.paleGreen : GU.surface)
            Button(action: alert) { Checkpoint(icon: "calendar", title: "\(analysis.peakWeekday.name) spending budget", detail: profile.eventBudgetSet ? "\(AppFormatting.currency(profile.eventBudget)) set" : "Based on transaction pattern", color: GU.paleOrange) }.buttonStyle(.plain)
            Button(action: checkin) { Checkpoint(icon: checkedInThisWeek ? "checkmark" : "circle", title: "Weekly check-in", detail: checkedInThisWeek ? "Complete" : "Review the latest spending week", color: checkedInThisWeek ? GU.paleGreen : GU.surface) }.buttonStyle(.plain)
        }
    }
}

private struct Checkpoint: View {
    let icon: String, title: String, detail: String, color: Color
    var body: some View {
        HStack(spacing: 12) { Image(systemName: icon).frame(width: 36, height: 36).background(.white, in: Circle()).foregroundStyle(GU.blue); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.caption).foregroundStyle(GU.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(GU.secondary) }.padding(10).background(color, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RedZonesView: View {
    let summary: FinancialSummary
    let onboarding: Bool
    @State private var mode = "Each week"
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Intro(kicker: "\(summary.transactions.count) TRANSACTIONS · \(summary.monthlyCashFlow.count) MONTHS", title: "Your red zones", detail: "The moments where spending is consistently higher than your normal pattern.")
                Segmented(options: ["Each week", "Across the year"], selection: $mode)
                if mode == "Each week" { heatmap } else { yearBars }
                Text("WHAT COSTS YOU MOST").eyebrow()
                ForEach(Array(analysis.redZones.enumerated()), id: \.element.id) { index, zone in
                    RankedRow(rank: index + 1, title: zone.title, detail: zone.detail, level: zone.severity)
                }
                if !onboarding {
                    NavigationLink { CalendarInsightsView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 16)).frame(width: 40, height: 40).background(.white, in: Circle()).foregroundStyle(GU.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("From your calendar").font(.system(size: 15, weight: .semibold))
                                Text("Birthdays, ceremonies and trips with an estimated cost").font(.caption).foregroundStyle(GU.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(GU.secondary)
                        }
                        .padding(10).background(GU.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }.padding(onboarding ? 24 : 16)
        }.scrollIndicators(.hidden)
    }
    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Spacer(); ForEach(["6a","9a","12p","3p","6p","9p"], id: \.self) { Text($0).font(.caption2).frame(maxWidth: .infinity) } }
            ForEach(Array(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].enumerated()), id: \.offset) { row, day in
                HStack(spacing: 6) { Text(day).font(.caption).frame(width: 30, alignment: .leading); ForEach(0..<6) { col in RoundedRectangle(cornerRadius: 5).fill(heatColor(analysis.heatLevels[row][col])).frame(height: 31) } }
            }
            Text(analysis.heatmapSummary).font(.caption).foregroundStyle(GU.secondary).padding(.top, 5)
        }.padding(12).background(GU.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private var yearBars: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(analysis.monthlyExpenses.enumerated()), id: \.offset) { index, value in
                let maxValue = analysis.monthlyExpenses.max() ?? 1
                let height = maxValue > 0 ? max(4, value.doubleValue / maxValue.doubleValue * 130) : 4
                VStack { Spacer(); RoundedRectangle(cornerRadius: 4).fill(value == maxValue ? GU.orange : GU.blue.opacity(0.45)).frame(height: height); Text(summary.monthlyCashFlow[index].month.formatted(.dateTime.month(.narrow))).font(.caption2) }.frame(height: 165)
            }
        }.padding(12).background(GU.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func heatColor(_ level: Int) -> Color { [Color.white, Color(red: 0.98, green: 0.89, blue: 0.82), Color(red: 0.96, green: 0.73, blue: 0.56), Color(red: 0.93, green: 0.54, blue: 0.31), GU.orange][level] }
}

private struct PlanHub: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanPicker(summary: summary, profile: profile, onboarding: false)
                NavigationLink { GoalsView(summary: summary) } label: {
                    HStack { Image(systemName: "target").foregroundStyle(GU.blue); VStack(alignment: .leading) { Text("Savings goals").font(.headline); Text("Create and manage goals using your real cash-flow history").font(.caption).foregroundStyle(GU.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                        .padding(16).background(GU.paleBlue, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                NavigationLink { OverviewView(summary: summary) } label: {
                    Label("Financial analysis", systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity, alignment: .leading).padding(16).background(GU.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }.padding(16)
        }
    }
}

private struct PlanPicker: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    let onboarding: Bool
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    private var plans: [(String, String, String, String, String)] {
        let values: [(String, Decimal, String, String)] = [
            ("Cap it", Decimal(string: "0.7")!, "Set a budget for each high-spend window.", "Limit based on your typical peak-day spending"),
            ("Sweep it", Decimal(1), "Move the recoverable amount toward your goals first.", "Transfer before your highest-spend weekday"),
            ("Swap it", Decimal(string: "0.5")!, "Keep the activity, reduce its highest category cost.", "Use a lower-cost alternative in \(analysis.peakCategory)")
        ]
        return values.map { name, factor, tagline, how in
            let outcome = analysis.fiveYearPlanBase + analysis.recoverableFiveYearSpend * factor
            let monthlyGain = analysis.recoverableFiveYearSpend * factor / 60
            let emergencyGap = max(0, summary.averageMonthlyExpenses - max(0, summary.currentBalance))
            let months = monthlyGain > 0 ? Int(ceil(emergencyGap.doubleValue / monthlyGain.doubleValue)) : 0
            let milestone = emergencyGap == 0 ? "One-month expense buffer already covered" : monthlyGain > 0 ? "One-month expense buffer in about \(months) months" : "Needs positive cash flow before a buffer can grow"
            return (name, AppFormatting.compactCurrency(outcome), tagline, how, milestone)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Intro(kicker: "BUILT BY YOUR AI COACHING TEAM", title: "3 ways to handle your red zones", detail: "Pick the one that sounds most like you. You can switch any time.")
            HStack { Image(systemName: "line.diagonal").foregroundStyle(GU.orange); Text("Your recurring peak windows account for up to \(AppFormatting.compactCurrency(analysis.recoverableFiveYearSpend)) over five years.").font(.caption) }.padding(12).background(GU.paleOrange, in: RoundedRectangle(cornerRadius: 12))
            ForEach(plans, id: \.0) { plan in
                Button { profile.selectedPlan = plan.0 } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Image(systemName: profile.selectedPlan == plan.0 ? "largecircle.fill.circle" : "circle").foregroundStyle(GU.blue); Text(plan.0).font(.system(size: 17, weight: .semibold)); Spacer(); VStack(alignment: .trailing) { Text(plan.1).font(.system(size: 16, weight: .semibold)); Text("in 5 years").font(.caption2).foregroundStyle(GU.secondary) } }
                        Text(plan.2).font(.system(size: 14)); Text(plan.3).font(.caption).foregroundStyle(GU.secondary); Text(plan.4).font(.caption).foregroundStyle(GU.green)
                    }.padding(14).background(GU.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(profile.selectedPlan == plan.0 ? GU.blue : .clear, lineWidth: 2))
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct FridayAlertView: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    private var selectedBudget: Binding<Decimal> { Binding(get: { profile.eventBudget }, set: { profile.eventBudget = $0 }) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("TRANSACTION PATTERN · \(analysis.peakWeekday.name.uppercased())").eyebrow().foregroundStyle(GU.orange)
                    Text("\(analysis.peakCategory) spending window").font(.system(size: 22, weight: .semibold))
                    Text("Your historical \(analysis.peakWeekday.name) spend averages \(AppFormatting.currency(analysis.peakWeekday.average)). Set a limit before the next one.").font(.system(size: 14)).foregroundStyle(GU.secondary)
                    HStack { Tag("\(summary.transactions.count) transactions"); Tag("\(analysis.peakWeekday.name) pattern") }
                }.padding(16).background(GU.paleOrange, in: RoundedRectangle(cornerRadius: 16))
                Label("This recurring difference can total \(AppFormatting.compactCurrency(analysis.recoverableFiveYearSpend)) over five years.", systemImage: "chart.line.downtrend.xyaxis").font(.system(size: 13)).padding(14).background(GU.surface, in: RoundedRectangle(cornerRadius: 14))
                if profile.eventBudgetSet {
                    Label("\(AppFormatting.currency(profile.eventBudget)) set. Your 75% checkpoint is \(AppFormatting.currency(profile.eventBudget * Decimal(string: "0.75")!)).", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(GU.green).padding(16).background(GU.paleGreen, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("SET A BUDGET").eyebrow()
                    BudgetPicker(options: analysis.budgetOptions, value: selectedBudget)
                    PrimaryButton("Set \(AppFormatting.currency(profile.eventBudget)) budget") { profile.eventBudgetSet = true }
                }
                Text("COMING UP").eyebrow().padding(.top, 8)
                ForEach(analysis.upcomingWindows) { window in
                    CalendarRow(day: window.date.formatted(.dateTime.weekday(.abbreviated)).uppercased(), date: window.date.formatted(.dateTime.day()), title: window.title, detail: window.detail)
                }
            }.padding(16)
        }.navigationTitle("Red zone alert").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SaturdayCheckinView: View {
    let summary: FinancialSummary
    @Bindable var profile: CoachProfile
    private var analysis: FinancialExperienceAnalysis { .make(summary: summary) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Intro(kicker: "WEEKLY CHECK-IN", title: "Review your latest week", detail: "The suggestions below compare the latest transaction week with your historical weekly average.")
                HStack { Image(systemName: "flame.fill").foregroundStyle(GU.orange); VStack(alignment: .leading) { Text("\(analysis.weeklyStreak)-week data streak").font(.headline); Text("Weeks at or below your historical average").font(.caption).foregroundStyle(GU.secondary) } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(GU.paleOrange, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) { Text("LATEST DATA WEEK").eyebrow(); Text(AppFormatting.currency(analysis.latestWeekSpending)).font(.headline); Text("Historical weekly average: \(AppFormatting.currency(summary.averageWeeklySpending))").font(.caption).foregroundStyle(GU.secondary) }.padding(16).background(GU.surface, in: RoundedRectangle(cornerRadius: 16))
                if analysis.weeklyOverrun > 0 {
                    Text("DATA-BASED REPAIR").eyebrow()
                    Checkpoint(icon: "arrow.right", title: "Move \(AppFormatting.currency(analysis.repairTransfer)) toward a goal", detail: "40% of the calculated weekly overrun", color: GU.paleBlue)
                    Checkpoint(icon: "fork.knife", title: "Trim \(AppFormatting.currency(analysis.repairTrim)) from \(analysis.repairCategory)", detail: "The remaining calculated overrun", color: GU.surface)
                } else {
                    Label("No repair needed. The latest week is within your historical baseline.", systemImage: "checkmark.circle.fill").foregroundStyle(GU.green).font(.headline).padding(16).background(GU.paleGreen, in: RoundedRectangle(cornerRadius: 14))
                }
                if profile.forecastRepaired && analysis.weeklyOverrun > 0 {
                    Label("Repair acknowledged and saved.", systemImage: "checkmark.circle.fill").foregroundStyle(GU.green).font(.headline).padding(16).background(GU.paleGreen, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    if analysis.weeklyOverrun > 0 { PrimaryButton("Use this repair plan") { withAnimation { profile.forecastRepaired = true } } }
                }
                NavigationLink { PriceCheckView() } label: {
                    Label("Check a price before you buy", systemImage: "camera.viewfinder").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(14).background(GU.paleBlue, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }.padding(16)
        }.navigationTitle("Weekly check-in").navigationBarTitleDisplayMode(.inline)
            .onAppear { profile.lastCheckInAt = .now }
    }
}

private struct Intro: View {
    let kicker: String?, title: String, detail: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { if let kicker { Text(kicker).eyebrow() }; Text(title).font(.system(size: 26, weight: .semibold)); Text(detail).font(.system(size: 15)).foregroundStyle(GU.secondary).lineSpacing(3) } }
}

private struct ToggleRow: View {
    let icon: String, title: String
    @Binding var isOn: Bool
    var body: some View { Button { isOn.toggle() } label: { HStack(spacing: 14) { Image(systemName: icon).frame(width: 40, height: 40).background(.white, in: Circle()); Text(title).font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: isOn ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(isOn ? GU.blue : GU.secondary) }.padding(10).background(GU.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(isOn ? GU.blue : .clear, lineWidth: 1.5)) }.buttonStyle(.plain) }
}

private struct ChoiceSection: View {
    let title: String, choices: [String]
    @Binding var selection: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).eyebrow(); Segmented(options: choices, selection: $selection) } }
}

private struct Segmented: View {
    let options: [String]
    @Binding var selection: String
    var body: some View { HStack(spacing: 4) { ForEach(options, id: \.self) { option in Button(option) { withAnimation(.easeOut(duration: 0.15)) { selection = option } }.font(.system(size: 12, weight: selection == option ? .semibold : .medium)).foregroundStyle(selection == option ? GU.ink : GU.secondary).frame(maxWidth: .infinity, minHeight: 36).background(selection == option ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9)).shadow(color: selection == option ? .black.opacity(0.08) : .clear, radius: 2, y: 1) } }.padding(3).background(Color(red: 231/255, green: 233/255, blue: 238/255), in: RoundedRectangle(cornerRadius: 11)) }
}

private struct LinkRow: View {
    let icon: String, title: String, detail: String
    @Binding var linked: Bool
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).frame(width: 40, height: 40).background(.white, in: Circle()); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 15, weight: .semibold)); Text(detail).font(.caption).foregroundStyle(GU.secondary) }; Spacer(); Button(linked ? "Linked" : "Connect") { linked.toggle() }.font(.caption.weight(.semibold)).foregroundStyle(linked ? GU.green : GU.blue).padding(.horizontal, 12).frame(height: 40).background(linked ? GU.paleGreen : .white, in: Capsule()).overlay(Capsule().stroke(linked ? .clear : GU.blue, lineWidth: 1.5)) }.padding(10).background(GU.surface, in: RoundedRectangle(cornerRadius: 14)) }
}

private struct RankedRow: View {
    let rank: Int, title: String, detail: String, level: String
    var body: some View { HStack(spacing: 12) { Text("\(rank)").font(.headline).frame(width: 32, height: 32).background(GU.surface, in: Circle()); VStack(alignment: .leading) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.caption).foregroundStyle(GU.secondary) }; Spacer(); Text(level).font(.caption.weight(.semibold)).foregroundStyle(level == "High" ? GU.orange : GU.secondary) }.padding(.vertical, 5) }
}

private struct BudgetPicker: View {
    let options: [Decimal]
    @Binding var value: Decimal
    var body: some View { HStack(spacing: 4) { ForEach(options, id: \.self) { amount in Button(AppFormatting.compactCurrency(amount)) { value = amount }.font(.headline).frame(maxWidth: .infinity, minHeight: 44).background(value == amount ? .white : .clear, in: RoundedRectangle(cornerRadius: 9)).shadow(color: value == amount ? .black.opacity(0.08) : .clear, radius: 2) } }.padding(4).background(GU.surface, in: RoundedRectangle(cornerRadius: 12)) }
}

private struct CalendarRow: View {
    let day: String, date: String, title: String, detail: String
    var body: some View { HStack { VStack { Text(day).font(.caption2).foregroundStyle(GU.secondary); Text(date).font(.headline) }.frame(width: 42); Text(title).font(.system(size: 14, weight: .medium)); Spacer(); Text(detail).font(.caption).foregroundStyle(GU.secondary) }.padding(.vertical, 8).overlay(alignment: .bottom) { Divider() } }
}

private struct Tag: View { let text: String; init(_ text: String) { self.text = text }; var body: some View { Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 5).background(.white, in: Capsule()) } }

private struct PrimaryButton: View {
    let title: String, action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { Button(action: action) { Text(title).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(.white).background(GU.blue, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) }
}

extension Text {
    func eyebrow() -> some View { self.font(.system(size: 12, weight: .semibold)).tracking(0.7).foregroundStyle(GU.secondary) }
}
