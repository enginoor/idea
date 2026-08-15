import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OriginCheckEngine

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var records: [HistoryRecord] = []
    @State private var searchText = ""
    @State private var selected: HistoryRecord?

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
                    .disabled(filtered.isEmpty)
                Button("Delete all") { deleteAll() }
                    .disabled(filtered.isEmpty)
            }

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No checks yet. Every verdict you make is kept here with its evidence.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.verdictKind.rawValue)
                                .font(.headline)
                            Text("\(record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.confidenceValue.formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = record }
                }
            }
        }
        .padding(24)
        .task { await reload() }
        .sheet(item: $selected) { record in
            RecordDetailView(record: record)
        }
    }

    private var filtered: [HistoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return records }
        return records.filter { record in
            record.inputType.lowercased().contains(query)
                || record.verdictKind.rawValue.lowercased().contains(query)
                || record.inputHash.lowercased().contains(query)
        }
    }

    private func reload() async {
        records = (try? await appState.history.allRecords()) ?? []
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.verdictKind.rawValue)
                        .font(.title2.weight(.semibold))
                    Text("\(record.inputType) · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(record.confidenceValue.formatted(.percent.precision(.fractionLength(0)))) confidence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Input hash: \(record.inputHash)")
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)

            if let rawText = record.rawText {
                Text(rawText)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
}
