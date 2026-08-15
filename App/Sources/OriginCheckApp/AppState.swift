import Foundation
import AppKit
import Observation
import OriginCheckEngine

@MainActor
@Observable
final class AppState {
    let engine: OriginCheckEngine
    let history: any HistoryStoring
    let keyStore: any KeyStoring

    var textInput = ""
    var lastTextVerdict: TextVerdict?
    var lastFileVerdict: FileVerdict?
    var lastBatchReport: BatchReport?
    var isAnalyzing = false
    var statusMessage: String?

    private let defaults = UserDefaults.standard

    /// Settings are stored observable properties, not computed ones: the
    /// Observation framework only tracks stored state, so a computed property
    /// backed by UserDefaults would leave the Settings UI blind to changes.
    /// Persistence happens in one place, in the app scene, via onChange.
    var thresholdPreset: ThresholdPreset = .balanced
    var localAnalyzerEnabled = true
    var anthropicProviderEnabled = false
    var storeRawContent = false
    /// Whether a key is stored in the Keychain. This is observable state,
    /// not a computed read: Observation cannot track the Keychain, so the
    /// Settings caption and button would otherwise never refresh after a
    /// save or a removal.
    var anthropicKeyStored = false

    init() {
        self.keyStore = KeychainKeyStore()
        self.engine = OriginCheckEngine(keyStore: keyStore)
        self.history = JSONHistoryStore(fileURL: Self.historyURL())
        self.thresholdPreset = ThresholdPreset(
            rawValue: defaults.string(forKey: "thresholdPreset") ?? ""
        ) ?? .balanced
        self.localAnalyzerEnabled = defaults.object(forKey: "localAnalyzerEnabled") == nil
            ? true
            : defaults.bool(forKey: "localAnalyzerEnabled")
        self.anthropicProviderEnabled = defaults.bool(forKey: "anthropicProviderEnabled")
        self.storeRawContent = defaults.bool(forKey: "storeRawContent")
        self.anthropicKeyStored = !(keyStore.string(forKey: "anthropicApiKey") ?? "").isEmpty
    }

    static func historyURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("OriginCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    var options: AnalysisOptions {
        AnalysisOptions(
            thresholdPreset: thresholdPreset,
            localAnalyzerEnabled: localAnalyzerEnabled,
            anthropicProviderEnabled: anthropicProviderEnabled
        )
    }

    // MARK: Actions

    func analyzeText(_ text: String) async {
        guard !isAnalyzing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Paste some text first."
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let verdict = try await engine.analyzeText(trimmed, options: options)
            lastTextVerdict = verdict
            lastFileVerdict = nil
            lastBatchReport = nil
            statusMessage = nil
            let record = HistoryRecorder.record(
                forTextVerdict: verdict,
                rawText: trimmed,
                storeRawText: storeRawContent
            )
            try await history.add(record)
        } catch {
            statusMessage = "Analysis failed: \(error.localizedDescription)"
        }
    }

    func verifyFile(_ url: URL) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let verdict = try await engine.verifyFile(at: url, options: options)
            lastFileVerdict = verdict
            lastTextVerdict = nil
            lastBatchReport = nil
            statusMessage = nil
            let record = HistoryRecorder.record(
                forFileVerdict: verdict,
                fileURL: url,
                storeRawContent: storeRawContent
            )
            try await history.add(record)
        } catch {
            statusMessage = "Verification failed: \(error.localizedDescription)"
        }
    }

    /// Verifies every supported media file in a folder. A batch has no single
    /// verdict, so it is not written to history; the report card is the record.
    func verifyFolder(_ url: URL) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let report = try await FolderVerifier(c2paToolPath: engine.c2paVerifier.toolPath)
                .verifyDirectory(at: url)
            lastBatchReport = report
            lastTextVerdict = nil
            lastFileVerdict = nil
            statusMessage = nil
        } catch {
            statusMessage = "Folder scan failed: \(error.localizedDescription)"
        }
    }

    func saveAnthropicKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try keyStore.set(key, forKey: "anthropicApiKey")
            anthropicKeyStored = true
        } catch {
            statusMessage = "Could not save the API key: \(error.localizedDescription)"
        }
    }

    func clearAnthropicKey() {
        keyStore.remove(forKey: "anthropicApiKey")
        anthropicKeyStored = false
    }

    // MARK: Menu actions

    /// Reads the clipboard and runs a text check. Shared by the menu bar
    /// extra and the Verify menu so every entry point behaves identically.
    func checkClipboardText() async {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        await analyzeText(text)
    }

    /// Shows the file picker and verifies the chosen file. The app is
    /// activated first: a panel launched from the menu bar or a menu
    /// command can otherwise open behind the frontmost application.
    func pickAndVerifyFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await verifyFile(url)
        }
    }
}
