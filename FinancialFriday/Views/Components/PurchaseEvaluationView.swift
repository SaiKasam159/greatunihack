import SwiftUI

@available(iOS 26.0, *)
struct PurchaseEvaluationView: View {
    let evaluation: PurchaseEvaluation
    @State private var expandedPerspectives: Set<PerspectiveKind> = []

    var body: some View {
        VStack(spacing: 12) {
            verdictCard
            if evaluation.currentBalance != nil || evaluation.balanceAfterPurchase != nil {
                financialFigures
            }
            perspectivesCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: verdictIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(verdictColor)
                    .frame(width: 38, height: 38)
                    .background(verdictColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("FINAL VERDICT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(evaluation.verdict.uppercased())
                        .font(.title2.weight(.bold))
                        .foregroundStyle(verdictColor)
                }
                Spacer()
            }
            Text(evaluation.verdictExplanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(verdictColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var financialFigures: some View {
        HStack(spacing: 10) {
            if let currentBalance = evaluation.currentBalance {
                figure("Current balance", value: currentBalance, icon: "sterlingsign.circle")
            }
            if let balanceAfterPurchase = evaluation.balanceAfterPurchase {
                figure("After purchase", value: balanceAfterPurchase, icon: "arrow.right.circle")
            }
        }
    }

    private func figure(_ title: String, value: Decimal, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(AppFormatting.currency(value))
                .font(.headline.monospacedDigit())
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var perspectivesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(perspectives.enumerated()), id: \.element.kind) { index, item in
                DisclosureGroup(isExpanded: binding(for: item.kind)) {
                    Text(item.evaluation.reasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.leading, 42)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.kind.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accent)
                            .frame(width: 31, height: 31)
                            .background(Color.accent.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.evaluation.shortVerdict)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .tint(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if index < perspectives.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var perspectives: [(kind: PerspectiveKind, evaluation: PerspectiveEvaluation)] {
        [
            (.financial, evaluation.financial),
            (.research, evaluation.research),
            (.devilsAdvocate, evaluation.devilsAdvocate),
            (.lifestyle, evaluation.lifestyle),
            (.future, evaluation.future)
        ]
    }

    private func binding(for kind: PerspectiveKind) -> Binding<Bool> {
        Binding(
            get: { expandedPerspectives.contains(kind) },
            set: { isExpanded in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedPerspectives.insert(kind) }
                    else { expandedPerspectives.remove(kind) }
                }
            }
        )
    }

    private var verdictColor: Color {
        switch evaluation.verdict.uppercased() {
        case "BUY": .income
        case "WAIT": .orange
        default: .expense
        }
    }

    private var verdictIcon: String {
        switch evaluation.verdict.uppercased() {
        case "BUY": "checkmark.circle.fill"
        case "WAIT": "clock.fill"
        default: "xmark.circle.fill"
        }
    }
}

@available(iOS 26.0, *)
private enum PerspectiveKind: String, Hashable {
    case financial
    case research
    case devilsAdvocate
    case lifestyle
    case future

    var title: String {
        switch self {
        case .financial: "Financial"
        case .research: "Research"
        case .devilsAdvocate: "Devil's Advocate"
        case .lifestyle: "Lifestyle"
        case .future: "Future"
        }
    }

    var icon: String {
        switch self {
        case .financial: "sterlingsign.circle"
        case .research: "magnifyingglass"
        case .devilsAdvocate: "exclamationmark.triangle"
        case .lifestyle: "figure.walk"
        case .future: "clock.arrow.circlepath"
        }
    }
}
