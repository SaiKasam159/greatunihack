import SwiftUI

struct SpendingInsightsView: View {
    let insights: [SpendingInsight]

    var body: some View {
        SectionCard("Insights", subtitle: "Patterns supported by your history") {
            VStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: insight.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accent)
                            .frame(width: 30, height: 30)
                            .background(Color.accent.opacity(0.1), in: Circle())
                        Text(insight.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    if index < insights.count - 1 { Divider().padding(.leading, 43) }
                }
            }
        }
    }
}
