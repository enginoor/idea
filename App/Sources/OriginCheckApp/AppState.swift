import Foundation
import AppKit
import Observation
import OriginCheckEngine

@MainActor
@Observable
final class AppState {
    /// Private set so views cannot swap the engine behind its own state.
    /// Rebuilt when the c2patool path changes.
    private(set) var engine: OriginCheckEngine
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
    /// Path to the c2patool binary. Defaults to the name alone, which works
    /// when the tool is on PATH. Editable in Settings; the batch banner
    /// points there when the tool cannot be launched.
    var c2paToolPath = "c2patool"
    /// Whether a key is stored in the Keychain. This is observable state,
    /// not a computed read: Observation cannot track the Keychain, so the
    /// Settings caption and button would otherwise never refresh after a
    /// save or a removal.
    var anthropicKeyStored = false

    init() {
        self.keyStore = KeychainKeyStore()
        self.history = JSONHistoryStore(fileURL: Self.historyURL())
        self.c2paToolPath = defaults.string(forKey: "c2paToolPath") ?? "c2patool"
        self.engine = OriginCheckEngine(c2paToolPath: self.c2paToolPath, keyStore: self.keyStore)
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

    /// True when the check ran. The drop zone uses the answer to avoid
    /// claiming a check happened while another one was still running.
    @discardableResult
    func analyzeText(_ text: String) async -> Bool {
        guard !isAnalyzing else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Paste some text first."
            return false
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
            // A failed history write must not masquerade as a failed check:
            // the verdict is on screen and correct, only the record is missing.
            do {
                try await history.add(record)
            } catch {
                statusMessage = "The verdict is shown, but it could not be saved to history: \(error.localizedDescription)"
            }
            return true
        } catch {
            statusMessage = "Analysis failed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func verifyFile(_ url: URL) async -> Bool {
        guard !isAnalyzing else { return false }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let verdict = try await engine.verifyFile(at: url, options: options)
            lastFileVerdict = verdict
            lastTextVerdict = nil
            lastBatchReport = nil
            statusMessage = nil
            // Hashing a large video on the main actor would freeze the UI
            // for the duration of the read, so the record is built on a
            // background task; only the (cheap) JSON write runs here.
            let record = await Task.detached {
                HistoryRecorder.record(
                    forFileVerdict: verdict,
                    fileURL: url,
                    storeRawContent: storeRawContent
                )
            }.value
            do {
                try await history.add(record)
            } catch {
                statusMessage = "The verdict is shown, but it could not be saved to history: \(error.localizedDescription)"
            }
            return true
        } catch {
            statusMessage = "Verification failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Verifies every supported media file in a folder. A batch has no single
    /// verdict, so it is not written to history; the report card is the record.
    @discardableResult
    func verifyFolder(_ url: URL) async -> Bool {
        guard !isAnalyzing else { return false }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let report = try await FolderVerifier(c2paToolPath: engine.c2paVerifier.toolPath)
                .verifyDirectory(at: url)
            lastBatchReport = report
            lastTextVerdict = nil
            lastFileVerdict = nil
            statusMessage = nil
            // A folder scan is a record of counts, not a single verdict, so
            // it is stored with kind .batchScan. Building the record only
            // hashes the path string, so it is cheap enough for the main
            // actor; no file contents are read.
            let record = HistoryRecorder.record(forBatchReport: report, directoryPath: url.path)
            do {
                try await history.add(record)
            } catch {
                statusMessage = "The report is shown, but it could not be saved to history: \(error.localizedDescription)"
            }
            return true
        } catch {
            statusMessage = "Folder scan failed: \(error.localizedDescription)"
            return false
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

    /// Points the engine at a different c2patool binary. The engine is a
    /// small value type, so it is rebuilt with the new path rather than
    /// mutating its internals.
    func setC2PAToolPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != c2paToolPath else { return }
        c2paToolPath = trimmed
        engine = OriginCheckEngine(c2paToolPath: trimmed, keyStore: keyStore)
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
