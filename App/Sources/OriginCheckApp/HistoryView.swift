import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OriginCheckEngine

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var records: [HistoryRecord] = []
    @State private var searchText = ""
    @State private var selected: HistoryRecord?
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Search history", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Toggle("Store raw content", isOn: $appState.storeRawContent)
                    .toggleStyle(.checkbox)
                Button("Export JSON") { export() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(filtered.isEmpty)
                Button("Delete all") { showDeleteConfirmation = true }
                    .disabled(filtered.isEmpty)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(records.isEmpty
                        ? "No checks yet. Every verdict you make is kept here with its evidence."
                        : "No history entries match the search.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.verdictKind.historyTitle)
                                .font(.headline)
                            Text("\(record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let summary = record.batchSummary {
                            // A folder scan has counts, not a confidence
                            // percentage; percent would be a made-up number.
                            Text("\(summary.watermarked) watermarked · \(summary.failed) failed")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(record.confidenceValue.formatted(.percent.precision(.fractionLength(0))))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = record }
                }
            }
        }
        .padding(24)
        .task { await reload() }
        // History is shared with the Check tab and the menu bar; reload
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
        .sheet(item: $selected) { record in
            RecordDetailView(record: record)
        }
        .confirmationDialog(
            "Delete all history?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all records", role: .destructive) { deleteAll() }
        } message: {
            Text("This removes every stored check. There is no undo.")
        }
    }

    private var filtered: [HistoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return records }
        return records.filter { record in
            record.inputType.lowercased().contains(query)
                || record.verdictKind.rawValue.lowercased().contains(query)
                || record.verdictKind.historyTitle.lowercased().contains(query)
                || record.inputHash.lowercased().contains(query)
        }
    }

    private func reload() async {
        let loaded = (try? await appState.history.allRecords()) ?? []
        // Newest first: the check you just made is the one you want to see.
        records = loaded.sorted { $0.date > $1.date }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OriginCheck-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(filtered) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func deleteAll() {
        Task { @MainActor in
            try? await appState.history.deleteAll()
            await reload()
        }
    }
}

struct RecordDetailView: View {
    let record: HistoryRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.verdictKind.historyTitle)
                        .font(.title2.weight(.semibold))
                    Text("\(record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let summary = record.batchSummary {
                        Text("\(summary.watermarked) watermarked · \(summary.failed) failed")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(record.confidenceValue.formatted(.percent.precision(.fractionLength(0)))) confidence")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Done") { dismiss() }
                }
            }

            if let summary = record.batchSummary {
                // The same factual counts as the report card, so the record
                // reads as a scan without pretending to be a single verdict.
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

            if let rawText = record.rawText {
                // Long passages must scroll inside the sheet instead of
                // pushing the evidence list out of the fixed-size window.
                ScrollView {
                    Text(rawText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            List(record.evidence) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.summary)
                    Text("\(item.source) · \(item.kind)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 480)
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
