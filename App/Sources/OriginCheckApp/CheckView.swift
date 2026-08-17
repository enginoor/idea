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
    /// Rotates through the bundled sample passages so repeated taps show
    /// different model styles instead of the same text every time.
    @State private var sampleIndex = 0
    private var bundledSamples: [SamplePassages.Passage] {
        (try? SamplePassages.bundled()) ?? []
    }

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
                    .help("Run the text check (Command-Return)")
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
                textActionsRow
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

    /// One row of quick actions under the editor: paste the clipboard, load
    /// a sample passage, or clear. Each gets the user to a verdict with one
    /// click instead of leaving them staring at an empty editor.
    private var textActionsRow: some View {
        HStack(spacing: 8) {
            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .controlSize(.small)
            .disabled(appState.isAnalyzing)
            .help("Paste the clipboard and check it")

            Button {
                loadSample()
            } label: {
                Label("Sample", systemImage: "text.quote")
            }
            .controlSize(.small)
            .disabled(appState.isAnalyzing || bundledSamples.isEmpty)
            .help("Load a bundled sample passage to try the detector")

            Button {
                appState.textInput = ""
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .controlSize(.small)
            .disabled(appState.textInput.isEmpty || appState.isAnalyzing)
            .help("Clear the editor")

            Spacer()
        }
    }

    /// Loads the next bundled sample passage. The passages are deliberately
    /// AI-typical (uniform sentence rhythm, common vocabulary, model-family
    /// phrasing) so a first-time user sees the detector work without hunting
    /// for machine text. Bundled data: no network involved.
    private func loadSample() {
        guard !bundledSamples.isEmpty else {
            appState.statusMessage = "No bundled sample passages were found in the app."
            return
        }
        let passage = bundledSamples[sampleIndex % bundledSamples.count]
        sampleIndex += 1
        appState.textInput = passage.text
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            appState.statusMessage = "The clipboard does not contain any text."
            return
        }
        appState.textInput = text
        run()
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
                if appState.checkMode == .file, let name = appState.lastFileName {
                    Text("Verifying \(name)...")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(appState.checkMode == .text ? "Analyzing text..." : "Verifying...")
                        .font(.subheadline)
                }
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
                Text("Paste text to run the AI-pattern heuristic, or drop a media file to verify its C2PA provenance. The result appears here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                capabilityRow(
                    icon: "text.quote",
                    title: "Text analysis",
                    detail: "Ready. Paste text or load a sample to detect AI-typical patterns across ChatGPT, Claude, Gemini, and other models. Runs fully offline.",
                    color: .green
                )
                capabilityRow(
                    icon: "checkmark.seal",
                    title: "File provenance (C2PA)",
                    detail: AppState.toolIsReachable(appState.c2paToolPath)
                        ? "Ready. Drop a file or choose one to verify its signed metadata."
                        : "\(StandaloneC2PAReader.supportedDisplayNames) files work out of the box. Other formats need c2patool; install it once with cargo install c2patool, then set the path in Settings.",
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

    /// Text checks run through the local multi-model detector. There is no
    /// released watermark detector for any model, so the banner says what the
    /// result actually is before the user types, instead of surprising them
    /// with the verdict after the fact.
    private var textAvailabilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Text checks run entirely on this Mac: the local detector fuses sentence rhythm, vocabulary, and phrasing patterns that appear across AI-generated prose (ChatGPT, Claude, Gemini, and others). It is a heuristic, not an official watermark detector, so treat results as a signal, not proof. File checks work out of the box for \(StandaloneC2PAReader.supportedDisplayNames); other formats use c2patool when installed.")
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
            Text("c2patool is not reachable at \"\(appState.c2paToolPath)\". \(StandaloneC2PAReader.supportedDisplayNames) files are still verified by the built-in readers; other formats need the tool. Install it once with \u{201C}cargo install c2patool\u{201D} or set the path in Settings.")
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

    /// Loads a dropped file URL reliably on every macOS version the app
    /// supports.
    ///
    /// `loadObject(ofClass: URL.self)` reads the public.file-url type
    /// directly and is the API Apple recommends on macOS 13+; it handles the
    /// common NSURL case. The fallback keeps the older bookmark-Data and
    /// path-string cases working, because some drag sources (and sandboxed
    /// apps) deliver the URL as security-scoped bookmark Data or as a raw
    /// path. Both paths run off the main actor through async/await.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        // The async/await overload of loadObject(ofClass:) is not present in
        // every SDK this package is built against, so the completion-handler
        // form is bridged through a continuation instead. This path handles
        // the common NSURL case Finder delivers in a non-sandboxed app.
        let objectURL: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: object as? URL)
            }
        }
        if objectURL != nil {
            return objectURL
        }
        // Fallback for bookmark-Data and path-string drag sources: some drag
        // sources (and sandboxed apps) deliver the URL as security-scoped
        // bookmark Data or as a raw path.
        return await withCheckedContinuation { continuation in
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
