import SwiftUI
import UniformTypeIdentifiers
import OriginCheckEngine

/// The Check surface is split into two panes so the input never fights the
/// verdict for space: text or file input on the left, and the result on the
/// right. The divider is draggable, which is the macOS way to trade space
/// between the two.
struct CheckView: View {
    @Environment(AppState.self) private var appState
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var isTargeted = false

    var body: some View {
        @Bindable var appState = appState
        HSplitView {
            inputPane(appState: appState)
                .frame(minWidth: 340, idealWidth: 460)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            resultPane
                .frame(minWidth: 320, idealWidth: 430)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if appState.checkMode == .text {
                    Button {
                        run()
                    } label: {
                        Label("Check", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(
                        appState.isAnalyzing
                            || appState.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .help("Run the watermark check (Command-Return)")
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Verify File", systemImage: "arrow.up.doc")
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    .disabled(appState.isAnalyzing)
                    .help("Choose a file to verify (Command-O)")
                }
            }
        }
    }

    // MARK: Input pane

    private func inputPane(appState: AppState) -> some View {
        @Bindable var appState = appState
        return VStack(alignment: .leading, spacing: 14) {
            Picker("Check", selection: $appState.checkMode) {
                Text("Paste text").tag(CheckMode.text)
                Text("Verify a file").tag(CheckMode.file)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if appState.checkMode == .text {
                textAvailabilityBanner
                textEditor
                Text("Minimum reliable length: \(appState.thresholdPreset.minimumTextLength) characters. Shorter passages report inconclusive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !AppState.toolIsReachable(appState.c2paToolPath) {
                    toolMissingBanner
                }
                fileDrop
            }

            statusLine
        }
        .padding(20)
    }

    private var textEditor: some View {
        @Bindable var appState = appState
        return TextEditor(text: $appState.textInput)
            .font(.body)
            .frame(minHeight: 220, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary)
            )
    }

    private var fileDrop: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28))
                            .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                        Text(isTargeted ? "Drop to verify" : "Drop an image, video, audio, or PDF file here")
                            .foregroundStyle(.secondary)
                    }
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }

            HStack(spacing: 12) {
                Button("Choose a file") {
                    showImporter = true
                }
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

            Text("Supported: \(supportedFormatsSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("A folder scan verifies every supported file it contains and reports a per-file card. Unsupported files are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var statusLine: some View {
        Group {
            if let message = appState.statusMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Result pane

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.isAnalyzing {
                    progressCard
                } else if let verdict = appState.lastTextVerdict {
                    VerdictPanel(display: VerdictDisplay.text(verdict))
                } else if let report = appState.lastBatchReport {
                    BatchReportView(report: report)
                } else if let verdict = appState.lastFileVerdict {
                    VerdictPanel(display: VerdictDisplay.file(verdict))
                } else {
                    resultEmptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.checkMode == .text ? "Analyzing text..." : "Verifying...")
                    .font(.subheadline)
            }
            ProgressView()
                .progressViewStyle(.linear)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private var resultEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text("No check yet")
                    .font(.title3.weight(.semibold))
                Text("Paste text to check for a Claude watermark, or drop a media file to verify its C2PA provenance. The result appears here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                capabilityRow(
                    icon: "text.quote",
                    title: "Text watermark",
                    detail: "Not available yet: Anthropic has not published the detection API, so the app reports unavailable instead of guessing.",
                    color: .yellow
                )
                capabilityRow(
                    icon: "checkmark.seal",
                    title: "File provenance (C2PA)",
                    detail: AppState.toolIsReachable(appState.c2paToolPath)
                        ? "Ready. Drop a file or choose one to verify its signed metadata."
                        : "Needs c2patool. Install it once with cargo install c2patool, then set the path in Settings.",
                    color: .green
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func capabilityRow(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Banners

    /// Text watermark detection is honestly unavailable today: Anthropic has
    /// not published the detection parameters or API, so the engine reports
    /// unavailable instead of guessing. Say so before the user types instead
    /// of surprising them with the verdict after the fact.
    private var textAvailabilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Text watermark detection is not available yet: Anthropic has not published the detection API or parameters, so the app reports unavailable instead of guessing. File verification (C2PA) works when c2patool is installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var toolMissingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("c2patool is not reachable at \"\(appState.c2paToolPath)\". Install it once with \u{201C}cargo install c2patool\u{201D} or set the path in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    private func run() {
        Task { @MainActor in
            if appState.checkMode == .text {
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
            var verifiedFolder = false
            for provider in providers {
                guard let url = await loadFileURL(from: provider) else { continue }
                // A dropped folder may or may not carry a trailing slash, so
                // ask the file system instead of trusting the URL string.
                let isDirectory = url.hasDirectoryPath
                    || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDirectory {
                    // A dropped folder is a folder scan, not a single file:
                    // verifying a directory path with c2patool would only
                    // produce a bogus no-manifest verdict.
                    verifiedFolder = await appState.verifyFolder(url)
                } else if await appState.verifyFile(url) {
                    checked += 1
                }
            }
            if appState.isAnalyzing {
                appState.statusMessage = "A check is already running. Drop again when it finishes."
            } else if verifiedFolder {
                appState.statusMessage = "Folder scan complete. The report card shows every file."
            } else if checked > 1 {
                // The panel only keeps the last verdict, so a multi-file drop
                // would otherwise look like a single check. Say what happened.
                appState.statusMessage = "Checked \(checked) files. Each result is in History."
            } else if checked == 0 && appState.statusMessage == nil {
                // A failed check already set its own message; do not replace
                // it with a generic drop notice.
                appState.statusMessage = "The drop did not contain any file URLs."
            }
        }
    }

    /// Bridges the completion-based NSItemProvider API into async/await.
    ///
    /// A dropped file arrives as an NSURL in a non-sandboxed app (which
    /// OriginCheck is), as security-scoped bookmark Data in a sandboxed app,
    /// or rarely as a path string. Handle all three so a drop never silently
    /// turns into "no file URLs".
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let path = item as? String {
                    url = URL(fileURLWithPath: path)
                } else {
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }
}
