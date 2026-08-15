import SwiftUI
import AppKit
import OriginCheckEngine

struct VerdictPanel: View {
    let display: VerdictDisplay
    @State private var showEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(display.color)
                    .frame(width: 10, height: 10)
                Text(display.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(display.confidenceLabel) confidence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: display.confidenceValue)
                .tint(display.color)

            Text(display.detail)
                .foregroundStyle(.secondary)

            DisclosureGroup("Evidence (\(display.evidence.count))", isExpanded: $showEvidence) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(display.evidence) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.summary)
                                .font(.subheadline)
                            Text("\(item.source) · \(item.kind)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            Text(display.caveat)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(display.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}
