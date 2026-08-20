import SwiftUI
import OriginCheckEngine

/// Renders a folder scan as a report card. Counts are factual; the caveat
/// footer keeps every result honest about what a missing manifest does and
/// does not prove.
enum BatchFileFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case watermarked = "Watermarked"
    case noManifest = "No Manifest"
    case inconclusive = "Inconclusive"

    var id: String { rawValue }
}

/// Renders a folder scan as a report card. Counts are factual; the caveat
/// footer keeps every result honest about what a missing manifest does and
/// does not prove.
struct BatchReportView: View {
    let report: BatchReport
    @State private var fileFilter: BatchFileFilter = .all

    var body: some View {
        // A scan of a large folder is far taller than the window. The card
        // scrolls so the per-file list is reachable instead of being clipped.
        ScrollView {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
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
            Menu {
                Button("Export JSON report...") { exportJSONReport() }
                Button("Export CSV report...") { exportCSVReport() }
            } label: {
                Label("Export report", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)

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

    private var filteredVerdicts: [FileVerdict] {
        switch fileFilter {
        case .all:
            return report.verdicts
        case .watermarked:
            return report.verdicts.filter { $0.kind == .watermarked }
        case .noManifest:
            return report.verdicts.filter { $0.kind == .notWatermarked }
        case .inconclusive:
            return report.verdicts.filter { $0.kind == .inconclusive }
        }
    }

    private var fileList: some View {
        // Capped like the failures list: a folder with thousands of files
        // must not build thousands of rows. The count cards already carry
        // the totals.
        let list = filteredVerdicts
        let shown = list.prefix(100)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Per file (\(list.count))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $fileFilter) {
                    ForEach(BatchFileFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            ForEach(Array(shown.enumerated()), id: \.offset) { _, verdict in
                row(for: verdict)
            }
            if list.count > 100 {
                Text("+ \(list.count - 100) more files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func exportJSONReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OriginCheck-folder-scan.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func exportCSVReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "OriginCheck-folder-scan.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["FileName,Format,VerdictKind,ManifestPresent,SignatureValid,Signer,SoftwareAgent,Confidence"]
        for verdict in report.verdicts {
            let name = verdict.fileName.replacingOccurrences(of: "\"", with: "\"\"")
            let signer = (verdict.signer ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let agent = (verdict.softwareAgent ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let sigValidStr = verdict.signatureValid.map { String($0) } ?? ""
            let line = "\"\(name)\",\"\(verdict.format)\",\"\(verdict.kind.rawValue)\",\(verdict.manifestPresent),\"\(sigValidStr)\",\"\(signer)\",\"\(agent)\",\(verdict.confidence.value)"
            lines.append(line)
        }
        let csvText = lines.joined(separator: "\n")
        try? csvText.write(to: url, atomically: true, encoding: .utf8)
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
