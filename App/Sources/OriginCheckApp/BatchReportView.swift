import SwiftUI
import OriginCheckEngine

/// Renders a folder scan as a report card. Counts are factual; the caveat
/// footer keeps every result honest about what a missing manifest does and
/// does not prove.
struct BatchReportView: View {
    let report: BatchReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if report.toolMissing {
                toolMissingBanner
            }
            summaryGrid
            // When the tool is missing, every supported file fails with the
            // same cause; the banner above already says it, so listing all of
            // them would only repeat it. Per-file failures are shown only
            // when the scan actually ran.
            if !report.toolMissing && !report.failures.isEmpty {
                failuresSection
            }
            if !report.verdicts.isEmpty {
                fileList
            }
            caveat
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder scan")
                    .font(.title2.weight(.semibold))
                Text(report.directoryName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(report.scannedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var toolMissingBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("c2patool is not installed or not reachable.")
                .font(.subheadline.weight(.semibold))
            Text("No file was verified. Install it once with cargo install c2patool, or set the tool path in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            countCard(label: "Watermarked", value: report.summary.watermarked, color: .green)
            countCard(label: "No manifest", value: report.summary.noManifest, color: .gray)
            countCard(label: "Inconclusive", value: report.summary.inconclusive, color: .yellow)
            countCard(label: "Failed", value: report.summary.failed, color: .red)
            countCard(label: "Skipped", value: report.summary.unsupportedSkipped, color: .secondary)
            countCard(label: "Files scanned", value: report.summary.totalFiles, color: .primary)
        }
    }

    private func countCard(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var failuresSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Failures")
                .font(.subheadline.weight(.semibold))
            ForEach(report.failures.prefix(20)) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.fileName)
                        .font(.subheadline)
                    Text(failure.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if report.failures.count > 20 {
                Text("+ \(report.failures.count - 20) more failures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per file")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(report.verdicts.enumerated()), id: \.offset) { _, verdict in
                row(for: verdict)
            }
        }
    }

    private func row(for verdict: FileVerdict) -> some View {
        let display = VerdictDisplay.file(verdict)
        return HStack(spacing: 10) {
            Circle()
                .fill(display.color)
                .frame(width: 8, height: 8)
            Text(verdict.fileName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(display.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verdict.confidence.value.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var caveat: some View {
        Text(Caveats.general)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
