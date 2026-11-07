import SwiftUI

/// Workflow 2 (Calendar Spending Analysis): upcoming occasions and what they will cost.
struct CalendarInsightsView: View {
    @State private var viewModel = CalendarInsightsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                windowPicker
                if viewModel.isDemo, let liveError = viewModel.liveError {
                    demoBanner(liveError)
                }
                switch viewModel.state {
                case .idle, .loading:
                    loadingCard
                case .failed(let message):
                    errorCard(message)
                case .loaded:
                    loadedContent
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(.white)
        .navigationTitle("Calendar insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(force: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FROM YOUR CALENDAR").eyebrow()
            Text("What is coming up").font(.system(size: 22, weight: .semibold))
            Text("Birthdays, festivals, ceremonies and nights out, with an estimated cost for each.")
                .font(.system(size: 14))
                .foregroundStyle(GU.secondary)
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: Binding(
            get: { viewModel.daysAhead },
            set: { viewModel.select(daysAhead: $0) }
        )) {
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("180 days").tag(180)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var loadedContent: some View {
        if viewModel.occasions.isEmpty {
            ContentUnavailableView(
                "Nothing unusual ahead",
                systemImage: "calendar",
                description: Text("No birthdays, ceremonies or festivals were found in this window.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            summaryCard
            LazyVStack(spacing: 10) {
                ForEach(viewModel.occasions) { occasion in
                    OccasionCard(occasion: occasion)
                }
            }
            Text("Estimates come from the Calendar Spending Analysis workflow, using the event title, description, location and guest count.")
                .font(.caption)
                .foregroundStyle(GU.secondary)
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ESTIMATED AHEAD").eyebrow()
                Text(AppFormatting.currency(Decimal(viewModel.totalEstimated)))
                    .font(.system(size: 26, weight: .semibold))
                Text("\(viewModel.occasions.count) occasions")
                    .font(.caption)
                    .foregroundStyle(GU.secondary)
            }
            Spacer()
            if let biggest = viewModel.biggest {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("BIGGEST").eyebrow()
                    Text(biggest.title)
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                    Text(AppFormatting.currency(Decimal(biggest.estimatedSpend)))
                        .font(.caption)
                        .foregroundStyle(GU.orange)
                }
                .frame(maxWidth: 150, alignment: .trailing)
            }
        }
        .padding(16)
        .background(GU.paleBlue, in: RoundedRectangle(cornerRadius: 18))
    }

    private func demoBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sample data - n8n not reachable", systemImage: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GU.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(GU.secondary)
            Text("Publish the workflow and pull to refresh for live results.")
                .font(.caption2)
                .foregroundStyle(GU.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(red: 1, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 14))
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Reading your calendar...")
                .font(.system(size: 14))
                .foregroundStyle(GU.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            ContentUnavailableView(
                "Calendar unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button("Try again") { Task { await viewModel.load(force: true) } }
                .buttonStyle(.borderedProminent)
                .tint(GU.blue)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct OccasionCard: View {
    let occasion: CalendarOccasion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                dateBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text(occasion.title)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        levelChip
                        Text(occasion.type)
                            .font(.caption)
                            .foregroundStyle(GU.secondary)
                        if occasion.bigSpending {
                            Text("BIG")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GU.paleOrange, in: Capsule())
                                .foregroundStyle(GU.orange)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(AppFormatting.currency(Decimal(occasion.estimatedSpend)))
                    .font(.system(size: 15, weight: .semibold))
            }

            if !occasion.costDrivers.isEmpty {
                Label(occasion.costDrivers, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(GU.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !occasion.tip.isEmpty {
                Text(occasion.tip)
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10))
                Text("\(occasion.confidence.rawValue.capitalized) confidence")
            }
            .font(.caption2)
            .foregroundStyle(GU.secondary)
        }
        .padding(14)
        .background(GU.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(occasion.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(GU.secondary)
            Text(occasion.date.formatted(.dateTime.day()))
                .font(.system(size: 18, weight: .semibold))
        }
        .frame(width: 44, height: 44)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var levelChip: some View {
        Text(occasion.level.label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(chipColor.opacity(0.16), in: Capsule())
            .foregroundStyle(chipColor)
    }

    private var chipColor: Color {
        switch occasion.level {
        case .high: GU.orange
        case .medium: Color(red: 0.72, green: 0.52, blue: 0.04)
        case .low: GU.green
        }
    }
}
