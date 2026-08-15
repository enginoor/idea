import Foundation

public enum ProviderSignal: Sendable, Equatable {
    case detected
    case notDetected
    case insufficient
    case unavailable
}

public struct ProviderResult: Sendable, Equatable {
    public var source: String
    public var signal: ProviderSignal
    public var confidence: Confidence
    public var evidence: [EvidenceItem]

    public init(source: String, signal: ProviderSignal, confidence: Confidence, evidence: [EvidenceItem]) {
        self.source = source
        self.signal = signal
        self.confidence = confidence
        self.evidence = evidence
    }
}

public protocol TextWatermarkProvider: Sendable {
    var source: String { get }
    func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult
}

/// The local analyzer is the honest fallback. Anthropic has not published the
/// watermark detection parameters, so this provider reports unavailable and
/// explains why. It never guesses and it never infers.
public struct LocalStatisticalAnalyzer: TextWatermarkProvider {
    public var source: String { "LocalAnalyzer" }

    public init() {}

    public func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult {
        if text.count < options.thresholdPreset.minimumTextLength {
            return ProviderResult(
                source: source,
                signal: .insufficient,
                confidence: ConfidenceRules.shortTextConfidence,
                evidence: [
                    EvidenceItem(
                        source: source,
                        kind: "insufficient_text",
                        summary: "Too little text for a reliable signal.",
                        detail: "\(text.count) characters; the \(options.thresholdPreset.rawValue) preset requires at least \(options.thresholdPreset.minimumTextLength)."
                    )
                ]
            )
        }
        return ProviderResult(
            source: source,
            signal: .unavailable,
            confidence: ConfidenceRules.confidence(0),
            evidence: [
                EvidenceItem(
                    source: source,
                    kind: "parameters_not_published",
                    summary: "Anthropic has not published the watermark detection parameters.",
                    detail: "Until the detection API or the technical documentation ships, honest local detection is not possible. Nothing is inferred or guessed."
                )
            ]
        )
    }
}

/// The Anthropic detection API provider, scaffolded behind a feature flag.
/// It reads a key through a KeyStoring abstraction and reports unavailable
/// until Anthropic releases the API. No network call is made today.
public struct AnthropicDetectionAPIProvider: TextWatermarkProvider {
    public var source: String { "AnthropicAPI" }

    private let keyStore: any KeyStoring

    public init(keyStore: any KeyStoring) {
        self.keyStore = keyStore
    }

    public func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult {
        guard options.anthropicProviderEnabled else {
            return ProviderResult(
                source: source,
                signal: .unavailable,
                confidence: ConfidenceRules.confidence(0),
                evidence: [
                    EvidenceItem(
                        source: source,
                        kind: "provider_disabled",
                        summary: "The Anthropic detection API provider is turned off.",
                        detail: "Enable it in Settings if you want to use your own Claude API key."
                    )
                ]
            )
        }
        let key = options.anthropicAPIKey ?? keyStore.string(forKey: "anthropicApiKey")
        guard let key, !key.isEmpty else {
            return ProviderResult(
                source: source,
                signal: .unavailable,
                confidence: ConfidenceRules.confidence(0),
                evidence: [
                    EvidenceItem(
                        source: source,
                        kind: "missing_api_key",
                        summary: "No Anthropic API key is set.",
                        detail: "Add your key in Settings. It is stored in the macOS Keychain."
                    )
                ]
            )
        }
        return ProviderResult(
            source: source,
            signal: .unavailable,
            confidence: ConfidenceRules.confidence(0),
            evidence: [
                EvidenceItem(
                    source: source,
                    kind: "api_not_released",
                    summary: "Anthropic has announced a detection API but has not released it.",
                    detail: "This provider is scaffolded and will call the detection endpoint when it ships. No network call is made yet."
                )
            ]
        )
    }
}

public protocol KeyStoring: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func remove(forKey key: String)
}

/// A UserDefaults-backed key store for development and tests. The macOS app
/// ships a Keychain-backed store instead; this one exists so the engine stays
/// dependency free and testable on any platform.
public struct UserDefaultsKeyStore: KeyStoring {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        if let suiteName {
            return UserDefaults(suiteName: suiteName) ?? .standard
        }
        return .standard
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) throws {
        defaults.set(value, forKey: key)
    }

    public func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
