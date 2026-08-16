import Foundation

public enum ProviderSignal: Sendable, Equatable {
    case detected
    case notDetected
    case insufficient
    case unavailable
    /// A provider ran but its signal did not resolve either way. Newer than
    /// the original four signals, so the combiner must handle it explicitly
    /// (it produces an inconclusive verdict, never a fabricated pass or fail).
    case inconclusive
}

public struct ProviderResult: Sendable, Equatable {
    public var source: String
    public var signal: ProviderSignal
    public var confidence: Confidence
    public var evidence: [EvidenceItem]
    /// An optional verdict caveat from the provider. The combiner prefers it
    /// over the generic caveat when the provider has something more specific
    /// to say (for example the local analyzer's honest heuristic disclaimer).
    public var caveatText: String

    public init(
        source: String,
        signal: ProviderSignal,
        confidence: Confidence,
        evidence: [EvidenceItem],
        caveatText: String = ""
    ) {
        self.source = source
        self.signal = signal
        self.confidence = confidence
        self.evidence = evidence
        self.caveatText = caveatText
    }
}

public protocol TextWatermarkProvider: Sendable {
    var source: String { get }
    func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult
}

/// The local analyzer is a statistical heuristic, the same family of
/// signals the first generation of AI-text detectors used: AI generated
/// prose tends to have more uniform sentence lengths (low burstiness) and
/// more repeated phrases than human writing.
///
/// It is honest about what it is. Anthropic's official watermark detector
/// has not been released, so this analyzer never claims to detect the
/// watermark itself. It reports AI-typical *patterns* with a confidence
/// ceiling of moderate, and every verdict carries evidence showing the raw
/// statistics behind the score.
public struct LocalStatisticalAnalyzer: TextWatermarkProvider {
    public var source: String { "LocalAnalyzer" }

    /// Score at or above this is reported as an AI-typical pattern.
    public let detectedThreshold: Double = 0.60
    /// Score at or below this is reported as no AI-typical pattern.
    public let notDetectedThreshold: Double = 0.42
    /// The local heuristic never claims high confidence: without the real
    /// watermark parameters, a ceiling keeps the product honest.
    public let confidenceCeiling: Double = 0.80

    public init() {}

    public func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult {
        let stats = TextStatistics(text: text)

        guard stats.sentenceCount >= 3, stats.wordCount >= 40 else {
            return ProviderResult(
                source: source,
                signal: .insufficient,
                confidence: ConfidenceRules.shortTextConfidence,
                evidence: [
                    EvidenceItem(
                        source: source,
                        kind: "insufficient_text",
                        summary: "Too little text for a reliable statistical signal.",
                        detail: "\(stats.wordCount) words across \(stats.sentenceCount) sentences; the heuristic needs at least 40 words in 3 sentences."
                    )
                ]
            )
        }

        let score = stats.aiTypicalityScore
        var evidence = stats.evidenceItems
        evidence.append(EvidenceItem(
            source: source,
            kind: "heuristic_score",
            summary: "AI-typical score: \(String(format: "%.2f", score)).",
            detail: "Combines sentence-length uniformity and phrase repetition. Higher means more AI-typical. This is a heuristic, not the released Anthropic watermark detector."
        ))

        if score >= detectedThreshold {
            let rawConfidence = 0.55 + 0.25 * (score - detectedThreshold) / (1 - detectedThreshold)
            let confidence = ConfidenceRules.capConfidence(rawConfidence, at: confidenceCeiling)
            evidence.append(EvidenceItem(
                source: source,
                kind: "decision",
                summary: "AI-typical statistical pattern found."
            ))
            return ProviderResult(
                source: source,
                signal: .detected,
                confidence: confidence,
                evidence: evidence,
                caveatText: Caveats.textPositiveHeuristic(confidenceLabel: confidence.label.rawValue)
            )
        }

        if score <= notDetectedThreshold {
            let rawConfidence = 0.55 - 0.30 * (notDetectedThreshold - score) / notDetectedThreshold
            let confidence = ConfidenceRules.confidence(max(rawConfidence, 0.25))
            evidence.append(EvidenceItem(
                source: source,
                kind: "decision",
                summary: "No AI-typical statistical pattern found."
            ))
            return ProviderResult(
                source: source,
                signal: .notDetected,
                confidence: confidence,
                evidence: evidence,
                caveatText: Caveats.textNegativeHeuristic
            )
        }

        evidence.append(EvidenceItem(
            source: source,
            kind: "decision",
            summary: "The statistical signals are mixed and do not resolve to a clear pattern."
        ))
        return ProviderResult(
            source: source,
            signal: .inconclusive,
            confidence: ConfidenceRules.confidence(0.5),
            evidence: evidence
        )
    }
}

/// The raw statistics behind a local analysis. Kept internal and immutable
/// so the analyzer and its tests reason about the same numbers.
struct TextStatistics {
    let wordCount: Int
    let uniqueWordCount: Int
    let sentenceCount: Int
    let sentenceLengths: [Int]
    /// Coefficient of variation of sentence lengths (std dev / mean). Lower
    /// means more uniform sentence lengths, the classic AI-writing signature.
    let burstiness: Double
    /// Fraction of bigram positions that repeat an earlier bigram.
    let repeatedBigramRate: Double
    /// 0...1, higher is more AI-typical. Weighted toward burstiness, the
    /// strongest local signal, with repetition as a mild secondary signal.
    let aiTypicalityScore: Double

    init(text: String) {
        let words = Self.tokenizeWords(text)
        let sentences = Self.splitSentences(text)
        let lengths = sentences
            .map { Self.tokenizeWords($0).count }
            .filter { $0 >= 2 }

        self.wordCount = words.count
        self.uniqueWordCount = Set(words).count
        self.sentenceCount = lengths.count
        self.sentenceLengths = lengths
        self.burstiness = Self.burstiness(of: lengths)
        self.repeatedBigramRate = Self.repeatedBigramRate(of: words)
        self.aiTypicalityScore = Self.score(
            burstiness: burstiness,
            repeatedBigramRate: repeatedBigramRate
        )
    }

    var evidenceItems: [EvidenceItem] {
        [
            EvidenceItem(
                source: "LocalAnalyzer",
                kind: "burstiness",
                summary: "Sentence-length burstiness: \(String(format: "%.2f", burstiness)).",
                detail: "The coefficient of variation of sentence lengths. Human writing is usually bursty (0.7 and up); AI-generated prose tends to be uniform (below 0.6)."
            ),
            EvidenceItem(
                source: "LocalAnalyzer",
                kind: "repetition",
                summary: "Repeated phrases: \(String(format: "%.1f", repeatedBigramRate * 100))% of word pairs repeat.",
                detail: "Fraction of adjacent word pairs that appeared earlier in the text. AI output repeats phrases more often than most human writing."
            ),
            EvidenceItem(
                source: "LocalAnalyzer",
                kind: "lexical_diversity",
                summary: "\(wordCount) words, \(uniqueWordCount) unique, across \(sentenceCount) sentences.",
                detail: "Lexical diversity (type-token ratio): \(String(format: "%.2f", wordCount > 0 ? Double(uniqueWordCount) / Double(wordCount) : 0))."
            ),
        ]
    }

    // MARK: - Feature computation

    private static func burstiness(of lengths: [Int]) -> Double {
        guard lengths.count >= 2 else { return 0 }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        guard mean > 0 else { return 0 }
        let variance = lengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(lengths.count)
        return sqrt(variance) / mean
    }

    private static func repeatedBigramRate(of words: [String]) -> Double {
        guard words.count >= 3 else { return 0 }
        var seen = Set<String>()
        var repeats = 0
        var total = 0
        var previous = ""
        for word in words {
            if !previous.isEmpty {
                let bigram = previous + "\u{0}" + word
                if seen.contains(bigram) {
                    repeats += 1
                } else {
                    seen.insert(bigram)
                }
                total += 1
            }
            previous = word
        }
        guard total > 0 else { return 0 }
        return Double(repeats) / Double(total)
    }

    private static func score(burstiness: Double, repeatedBigramRate: Double) -> Double {
        // Uniform sentence lengths (burstiness 0.3 or less) are strongly
        // AI-typical; at a coefficient of variation of 1.0 the text looks
        // human-bursty and the uniformity term reaches zero.
        let uniformity = 1 - min(max(burstiness - 0.3, 0) / 0.7, 1)
        let repetition = min(repeatedBigramRate * 5, 1)
        return 0.75 * uniformity + 0.25 * repetition
    }

    private static func tokenizeWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    /// Splits on sentence-ending punctuation and line breaks. A period
    /// between two digits is a decimal point, not a sentence end, so numbers
    /// like 3.14 do not split mid-sentence.
    static func splitSentences(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var current = ""
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            let isDecimal = ch == "."
                && index > 0 && chars[index - 1].isNumber
                && index + 1 < chars.count && chars[index + 1].isNumber
            if !isDecimal && (ch == "." || ch == "!" || ch == "?" || ch == "\n" || ch == "\r") {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            } else {
                current.append(ch)
            }
            index += 1
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }
        return sentences
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
