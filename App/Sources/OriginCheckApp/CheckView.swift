import SwiftUI
import UniformTypeIdentifiers
import OriginCheckEngine

struct CheckView: View {
    @Environment(AppState.self) private var appState
    @State private var mode: Mode = .text
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var isTargeted = false

    enum Mode: String, CaseIterable, Identifiable {
        case text
        case file
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 20) {
            Picker("Check", selection: $mode) {
                Text("Paste text").tag(Mode.text)
                Text("Verify a file").tag(Mode.file)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .text {
                textInput(appState: appState)
            } else {
                fileDrop
            }

            HStack(spacing: 12) {
                if mode == .text {
                    Button("Check text") {
                        run()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(appState.isAnalyzing)
                }

                if appState.isAnalyzing {
                    ProgressView().controlSize(.small)
                }
                if let message = appState.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let verdict = appState.lastTextVerdict {
                VerdictPanel(display: VerdictDisplay.text(verdict))
            } else if let report = appState.lastBatchReport {
                BatchReportView(report: report)
            } else if let verdict = appState.lastFileVerdict {
                VerdictPanel(display: VerdictDisplay.file(verdict))
            } else {
                emptyState
            }
        }
        .padding(24)
    }

    private func textInput(appState: AppState) -> some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $appState.textInput)
                .font(.body)
                .frame(minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary)
                )
            Text("Minimum reliable length: \(appState.thresholdPreset.minimumTextLength) characters. Shorter passages report inconclusive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fileDrop: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .frame(maxWidth: .infinity, minHeight: 160)
                .overlay(
                    Text(isTargeted ? "Drop to verify" : "Drop an image, video, audio, or PDF file here")
                        .foregroundStyle(.secondary)
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }

            Text("Supported: \(supportedFormatsSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Choose a file") {
                    showImporter = true
                }
                .keyboardShortcut("o", modifiers: [.command])
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: supportedContentTypes
                ) { result in
                    if case .success(let url) = result {
                        Task { @MainActor in
                            await appState.verifyFile(url)
                        }
                    }
                }

                Button("Verify a folder") {
                    showFolderImporter = true
                }
                .fileImporter(
                    isPresented: $showFolderImporter,
                    allowedContentTypes: [.folder]
                ) { result in
                    if case .success(let url) = result {
                        Task { @MainActor in
                            await appState.verifyFolder(url)
                        }
                    }
                }
            }

            Text("A folder scan verifies every supported file it contains and reports a per-file card. Unsupported files are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Paste a passage or drop a file to get a provenance verdict.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private func run() {
        Task { @MainActor in
            if mode == .text {
                await appState.analyzeText(appState.textInput)
            }
        }
    }

    /// Content types derived from the engine's format list, so the picker
    /// never drifts from what verification supports. Any-file (.data) stays
    /// as a fallback; unsupported types get an honest no-manifest verdict.
    private var supportedContentTypes: [UTType] {
        var seen = Set<String>()
        var types: [UTType] = []
        for format in MediaFormat.allCases {
            guard let type = UTType(filenameExtension: format.rawValue) else { continue }
            if seen.insert(type.identifier).inserted {
                types.append(type)
            }
        }
        types.append(.data)
        return types
    }

    /// Every format the engine can verify, deduplicated by display name
    /// (jpg and jpeg share a name, as do tif and tiff, heic and heif).
    private var supportedFormatsSummary: String {
        var names: [String] = []
        for format in MediaFormat.allCases {
            if !names.contains(format.displayName) {
                names.append(format.displayName)
            }
        }
        return names.joined(separator: ", ")
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        // Every dropped file is verified, one after another. Checking only
        // the first item would silently drop the rest, and firing them all
        // at once would trip the overlapping-analysis guard.
        Task { @MainActor in
            var checked = 0
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    await appState.verifyFile(url)
                    checked += 1
                }
            }
            // The panel only keeps the last verdict, so a multi-file drop
            // would otherwise look like a single check. Say what happened.
            if checked > 1 {
                appState.statusMessage = "Checked \(checked) files. Each result is in History."
            }
        }
    }

    /// Bridges the completion-based NSItemProvider API into async/await.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url)
            }
        }
    }
}
