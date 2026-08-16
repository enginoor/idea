import SwiftUI
import AppKit
import OriginCheckEngine

/// The result card shown after a text or file check. Reads top to bottom:
/// a verdict header with icon, the confidence readout and bar, the evidence
/// list, the honest caveat, and a copy action.
struct VerdictPanel: View {
    let display: VerdictDisplay
    @State private var showEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let fileName = display.fileName {
                Label(fileName, systemImage: "doc")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fileName)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: display.icon)
                    .font(.title3)
                    .foregroundStyle(display.color)
                    .frame(width: 30, height: 30)
                    .background(display.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.title)
                        .font(.title3.weight(.semibold))
                    Text(display.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(display.confidenceValue.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(display.confidenceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: display.confidenceValue)
                .tint(display.color)

            if !display.evidence.isEmpty {
                DisclosureGroup("Evidence (\(display.evidence.count))", isExpanded: $showEvidence) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(display.evidence) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(display.color)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
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
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }

            if !display.caveat.isEmpty {
                Text(display.caveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(display.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button {
                    copySummary()
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy a one-line summary of this verdict")
                Spacer()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(display.color.opacity(0.22))
        )
    }

    private func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(display.summaryText, forType: .string)
    }
}
