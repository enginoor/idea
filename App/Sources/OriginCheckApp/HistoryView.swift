import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OriginCheckEngine

/// History follows the Mail pattern: a searchable record list on the left,
/// and the selected record's details in the pane on the right. No modal
/// sheets: the detail is always visible next to the list it came from.
enum HistoryCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case watermarked = "Watermarked"
    case clean = "No Signal"
    case inconclusive = "Inconclusive"
    case batch = "Folder Scans"

    var id: String { rawValue }
}

/// History follows the Mail pattern: a searchable record list on the left,
/// and the selected record's details in the pane on the right. No modal
/// sheets: the detail is always visible next to the list it came from.
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var records: [HistoryRecord] = []
    @State private var searchText = ""
    @State private var selectedFilter: HistoryCategoryFilter = .all
    @State private var selectedID: UUID?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 280, idealWidth: 350)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // A single child that switches internally: HSplitView lays out
            // a stable set of panes best, and the split divider never has to
            // re-anchor when the selection changes.
            detailPane
                .frame(minWidth: 380, idealWidth: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Export JSON...") { exportJSON() }
                    Button("Export CSV...") { exportCSV() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(filtered.isEmpty)
                .help("Export history records")

                Button {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
                .disabled(filtered.isEmpty)
                .help("Delete all history")
            }
        }
        .task { await reload() }
        // History is shared with the Check pane and the menu bar; reload
        // whenever a check completes so the list never shows stale records.
        .onChange(of: appState.lastTextVerdict) {
            Task { @MainActor in await reload() }
        }
        .onChange(of: appState.lastFileVerdict) {
            Task { @MainActor in await reload() }
        }
        .onChange(of: appState.lastBatchReport) {
            // Folder scans write a history record too; without this the list
            // would stay stale until the next text or file check.
            Task { @MainActor in await reload() }
        }
        .confirmationDialog(
            "Delete all history?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all records", role: .destructive) { deleteAll() }
        } message: {
            Text("This removes every stored check. There is no undo.")
        }
    }

    // MARK: List pane

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Picker("Filter", selection: $selectedFilter) {
                ForEach(HistoryCategoryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(records.isEmpty
                        ? "No checks yet. Every verdict you make is kept here with its evidence."
                        : "No history entries match the search or filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                List(selection: $selectedID) {
                    ForEach(filtered) { record in
                        HistoryRow(record: record)
                            .tag(record.id)
                            .contextMenu {
                                Button("Delete Record", role: .destructive) {
                                    delete(record.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let record = selectedRecord {
            RecordDetailPane(record: record)
                .id(record.id)
        } else {
            detailEmptyState
        }
    }

    private var detailEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Select a record")
                .font(.headline)
            Text("Choose a check on the left to see its verdict, evidence, and stored content.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var filtered: [HistoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .watermarked:
                matchesCategory = record.verdictKind == .watermarked
            case .clean:
                matchesCategory = record.verdictKind == .notWatermarked
            case .inconclusive:
                matchesCategory = record.verdictKind == .inconclusive || record.verdictKind == .insufficientInput || record.verdictKind == .notAvailable
            case .batch:
                matchesCategory = record.verdictKind == .batchScan
            }

            guard matchesCategory else { return false }
            if query.isEmpty { return true }

            return record.inputType.lowercased().contains(query)
                || (record.fileName?.lowercased().contains(query) ?? false)
                || record.verdictKind.rawValue.lowercased().contains(query)
                || record.verdictKind.historyTitle.lowercased().contains(query)
                || record.inputHash.lowercased().contains(query)
        }
    }

    private var selectedRecord: HistoryRecord? {
        guard let selectedID else { return nil }
        return filtered.first { $0.id == selectedID }
    }

    private func reload() async {
        let loaded = (try? await appState.history.allRecords()) ?? []
        // Newest first: the check you just made is the one you want to see.
        records = loaded.sorted { $0.date > $1.date }
        // Keep the selection valid: if the selected record disappeared (for
        // example after a delete), fall back to the newest record.
        if let selectedID, !records.contains(where: { $0.id == selectedID }) {
            self.selectedID = records.first?.id
        } else if selectedID == nil {
            self.selectedID = records.first?.id
        }
    }

    private func delete(_ id: UUID) {
        Task { @MainActor in
            try? await appState.history.delete(id: id)
            await reload()
        }
    }

    private func deleteAll() {
        Task { @MainActor in
            try? await appState.history.deleteAll()
            await reload()
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "OriginCheck-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(filtered) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "OriginCheck-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["ID,Date,InputType,FileName,VerdictKind,Title,Confidence,InputHash"]
        for record in filtered {
            let dateStr = record.date.formatted(.iso8601)
            let name = (record.fileName ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let title = record.verdictKind.historyTitle.replacingOccurrences(of: "\"", with: "\"\"")
            let line = "\"\(record.id.uuidString)\",\"\(dateStr)\",\"\(record.inputType)\",\"\(name)\",\"\(record.verdictKind.rawValue)\",\"\(title)\",\(record.confidenceValue),\"\(record.inputHash)\""
            lines.append(line)
        }
        let csvText = lines.joined(separator: "\n")
        try? csvText.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// One row in the history list: verdict color dot, title, input type and
/// date, and either a confidence percentage or the batch scan counts.
private struct HistoryRow: View {
    let record: HistoryRecord

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(verdictColor(for: record.verdictKind))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.verdictKind.historyTitle)
                    .font(.body.weight(.medium))
                Text("\(record.fileName ?? record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let summary = record.batchSummary {
                // A folder scan has counts, not a confidence percentage;
                // percent would be a made-up number.
                Text("\(summary.watermarked) watermarked · \(summary.failed) failed")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(record.confidenceValue.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Verdict color lives here so the history list and the detail pane agree
/// with the Check pane's panel without importing the display layer into the
/// row view.
private func verdictColor(for kind: VerdictKind) -> Color {
    switch kind {
    case .watermarked: .green
    case .notWatermarked: .gray
    case .insufficientInput: .yellow
    case .notAvailable: .yellow
    case .inconclusive: .yellow
    case .batchScan: .blue
    }
}

/// The detail pane for one history record. Scrolls independently of the
/// list, so long raw text and long evidence lists never clip.
struct RecordDetailPane: View {
    let record: HistoryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let summary = record.batchSummary {
                    // The same factual counts as the report card, so the
                    // record reads as a scan without pretending to be a
                    // single verdict.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        countItem("Watermarked", summary.watermarked)
                        countItem("No manifest", summary.noManifest)
                        countItem("Inconclusive", summary.inconclusive)
                        countItem("Failed", summary.failed)
                        countItem("Skipped", summary.unsupportedSkipped)
                        countItem("Files", summary.totalFiles)
                    }
                }

                Text(record.batchSummary == nil
                    ? "Input hash: \(record.inputHash)"
                    : "Folder path hash: \(record.inputHash)")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let rawText = record.rawText {
                    // Long passages must scroll inside the pane instead of
                    // pushing the evidence list out of view.
                    ScrollView {
                        Text(rawText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                evidenceSection

                HStack(spacing: 12) {
                    Button {
                        copySummary()
                    } label: {
                        Label("Copy summary", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.verdictKind.historyTitle)
                    .font(.title2.weight(.semibold))
                Text("\(record.fileName ?? record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let summary = record.batchSummary {
                Text("\(summary.watermarked) watermarked · \(summary.failed) failed")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("\(record.confidenceValue.formatted(.percent.precision(.fractionLength(0)))) confidence")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A preview of the verified image when the user opted to store raw
    /// content and the file is still on disk. Only image formats are
    /// previewed; audio, video, and PDF records get no fake icon. Loaded
    /// lazily by NSImage, so a huge photo does not decode until shown.
    private var thumbnailImage: NSImage? {
        guard let path = record.fileThumbnailPath,
              FileManager.default.fileExists(atPath: path),
              Self.isPreviewableImage(path)
        else { return nil }
        return NSImage(contentsOf: URL(fileURLWithPath: path))
    }

    private static func isPreviewableImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "webp", "avif", "tif", "tiff", "gif", "svg"].contains(ext)
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evidence (\(record.evidence.count))")
                .font(.subheadline.weight(.semibold))
            if record.evidence.isEmpty {
                Text("No evidence items were recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(record.evidence) { item in
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
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func countItem(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copySummary() {
        let summary: String
        if let batch = record.batchSummary {
            summary = "Folder scan: \(batch.totalFiles) files, \(batch.watermarked) watermarked, \(batch.noManifest) without manifest, \(batch.failed) failed."
        } else {
            summary = "\(record.verdictKind.historyTitle) - \(record.confidenceValue.formatted(.percent.precision(.fractionLength(0)))) confidence - \(record.inputType)."
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summary, forType: .string)
    }
}
