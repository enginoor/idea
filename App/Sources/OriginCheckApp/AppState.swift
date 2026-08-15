import Foundation
import Observation
import OriginCheckEngine

@Observable
final class AppState {
    let engine: OriginCheckEngine
    let history: any HistoryStoring
    let keyStore: any KeyStoring

    var textInput = ""
    var lastTextVerdict: TextVerdict?
    var lastFileVerdict: FileVerdict?
    var isAnalyzing = false
    var statusMessage: String?
    var storeRawContent = false

    private let defaults = UserDefaults.standard

    init() {
        self.keyStore = KeychainKeyStore()
        self.engine = OriginCheckEngine(keyStore: keyStore)
        self.history = JSONHistoryStore(fileURL: Self.historyURL())
        self.storeRawContent = defaults.bool(forKey: "storeRawContent")
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

    // MARK: Settings backed by UserDefaults

    var thresholdPreset: ThresholdPreset {
        get { ThresholdPreset(rawValue: defaults.string(forKey: "thresholdPreset") ?? "") ?? .balanced }
        set { defaults.set(newValue.rawValue, forKey: "thresholdPreset") }
    }

    var localAnalyzerEnabled: Bool {
        get {
            if defaults.object(forKey: "localAnalyzerEnabled") == nil { return true }
            return defaults.bool(forKey: "localAnalyzerEnabled")
        }
        set { defaults.set(newValue, forKey: "localAnalyzerEnabled") }
    }

    var anthropicProviderEnabled: Bool {
        get { defaults.bool(forKey: "anthropicProviderEnabled") }
        set { defaults.set(newValue, forKey: "anthropicProviderEnabled") }
    }

    // MARK: Actions

    func analyzeText(_ text: String) async {
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
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let verdict = try await engine.verifyFile(at: url, options: options)
            lastFileVerdict = verdict
            lastTextVerdict = nil
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

    func saveAnthropicKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? keyStore.set(key, forKey: "anthropicApiKey")
    }

    func clearAnthropicKey() {
        keyStore.remove(forKey: "anthropicApiKey")
    }

    var hasAnthropicKey: Bool {
        !(keyStore.string(forKey: "anthropicApiKey") ?? "").isEmpty
    }
}
