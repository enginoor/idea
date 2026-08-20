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
    /// Soft style attributions (Claude-style, ChatGPT-style, ...) from the
    /// provider, if it makes any. Never proof of a specific model.
    public var familyHints: [ModelFamilyHint]
    /// Sentence-level statistical breakdown.
    public var sentenceAnalyses: [SentenceAnalysis]

    public init(
        source: String,
        signal: ProviderSignal,
        confidence: Confidence,
        evidence: [EvidenceItem],
        caveatText: String = "",
        familyHints: [ModelFamilyHint] = [],
        sentenceAnalyses: [SentenceAnalysis] = []
    ) {
        self.source = source
        self.signal = signal
        self.confidence = confidence
        self.evidence = evidence
        self.caveatText = caveatText
        self.familyHints = familyHints
        self.sentenceAnalyses = sentenceAnalyses
    }
}

public protocol TextWatermarkProvider: Sendable {
    var source: String { get }
    func analyze(_ text: String, options: AnalysisOptions) async throws -> ProviderResult
}

/// The local detector is a statistical heuristic, the same family of
/// signals the first generation of AI-text detectors used, extended to cover
/// any model family, not just Claude:
///
/// - **Burstiness**: the coefficient of variation of sentence lengths. AI
///   prose is uniform; human writing is bursty.
/// - **Phrase repetition**: how often word pairs repeat.
/// - **Perplexity**: how surprising the vocabulary choices are, measured
///   against a bundled English frequency dictionary. AI prose stays in the
///   common middle of the vocabulary; human writing reaches for rarer words.
/// - **Rare-word rate**: the same vocabulary signal expressed as a rate.
/// - **AI phrasing**: a bundled database of phrases that appear
///   disproportionately often in AI-generated prose, tagged by model family
///   (Claude, ChatGPT, Gemini, generic). Density of matches feeds the score
///   and produces soft style hints.
///
/// It is honest about what it is. Anthropic's official watermark detector
/// has not been released, and no local statistical detector can prove
/// authorship. The analyzer reports AI-typical *patterns* with a confidence
/// ceiling of moderate, and every verdict carries evidence showing the raw
/// statistics behind the score. It runs entirely on-device: the frequency
/// dictionary and phrase database ship inside the app, so detection needs no
/// network and no installed tools.
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
        let dictionary = try BundledResources.frequencyDictionary()
        let phrases = try BundledResources.phraseDatabase()
        let stats = TextStatistics(text: text, dictionary: dictionary, phrases: phrases)

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
            detail: "Combines sentence-length uniformity, phrase repetition, vocabulary surprisal, rare-word rate, and AI phrasing density. Higher means more AI-typical. This is a heuristic, not the released Anthropic watermark detector, and it covers any model family."
        ))
        let hints = phrases.familyHints(from: stats.phraseReport)

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
                caveatText: Caveats.textPositiveHeuristic(confidenceLabel: confidence.label.rawValue),
                familyHints: hints,
                sentenceAnalyses: stats.sentenceAnalyses
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
                caveatText: Caveats.textNegativeHeuristic,
                sentenceAnalyses: stats.sentenceAnalyses
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
            evidence: evidence,
            familyHints: hints,
            sentenceAnalyses: stats.sentenceAnalyses
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
    /// Vocabulary surprisal and rare-word stats from the frequency dictionary.
    let tokenStats: TokenStats
    /// Matched AI phrasing patterns and their family attributions.
    let phraseReport: AIPhraseDatabase.MatchReport
    /// 0...1, higher is more AI-typical.
    let aiTypicalityScore: Double
    /// Per-sentence statistical breakdown.
    let sentenceAnalyses: [SentenceAnalysis]

    /// Convenience initializer for tests and tooling where the bundled
    /// resources are guaranteed present. Production analysis goes through
    /// the explicit-resources initializer so missing data fails loudly.
    init(text: String) {
        let dictionary = try! BundledResources.frequencyDictionary()
        let phrases = try! BundledResources.phraseDatabase()
        self.init(text: text, dictionary: dictionary, phrases: phrases)
    }

    init(text: String, dictionary: FrequencyDictionary, phrases: AIPhraseDatabase) {
        let words = FrequencyDictionary.tokenize(text)
        let sentences = Self.splitSentences(text)
        let lengths = sentences
            .map { FrequencyDictionary.tokenize($0).count }
            .filter { $0 >= 2 }

        self.wordCount = words.count
        self.uniqueWordCount = Set(words).count
        self.sentenceCount = lengths.count
        self.sentenceLengths = lengths
        self.burstiness = Self.burstiness(of: lengths)
        self.repeatedBigramRate = Self.repeatedBigramRate(of: words)
        self.tokenStats = dictionary.stats(forTokens: words)
        self.phraseReport = phrases.match(text)
        self.aiTypicalityScore = Self.score(
            burstiness: burstiness,
            repeatedBigramRate: repeatedBigramRate,
            tokenStats: tokenStats,
            phraseReport: phraseReport
        )

        let meanLength = Double(words.count) / Double(max(sentences.count, 1))
        self.sentenceAnalyses = sentences.map { sentenceText in
            let sentenceWords = FrequencyDictionary.tokenize(sentenceText)
            let sReport = phrases.match(sentenceText)
            let sStats = dictionary.stats(forTokens: sentenceWords)

            let dev = abs(Double(sentenceWords.count) - meanLength) / max(meanLength, 1.0)
            let sUniformity = 1.0 - min(dev / 1.5, 1.0)

            let rawScore = 0.35 * sUniformity
                + 0.35 * sStats.perplexityTerm
                + 0.30 * sReport.phraseTerm
            let finalScore = min(max(rawScore, 0.0), 1.0)

            return SentenceAnalysis(
                sentenceText: sentenceText,
                wordCount: sentenceWords.count,
                aiTypicalityScore: finalScore,
                matchedPhrases: sReport.matchedPhrases
            )
        }
    }

    var evidenceItems: [EvidenceItem] {
        var items = [
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
            EvidenceItem(
                source: "LocalAnalyzer",
                kind: "perplexity",
                summary: "Vocabulary surprisal: \(String(format: "%.2f", tokenStats.averageSurprisal)) of \(Int(TokenStats.maxSurprisal)), with \(tokenStats.outOfVocabularyCount) unknown words.",
                detail: "Average per-word surprisal measured against a bundled English frequency dictionary. AI prose tends to stay in common vocabulary (low surprisal); human writing reaches for rarer words."
            ),
        ]
        if phraseReport.matchedCount > 0 {
            items.append(EvidenceItem(
                source: "LocalAnalyzer",
                kind: "ai_phrasing",
                summary: "\(phraseReport.matchedCount) AI-typical phrases matched (weight \(String(format: "%.1f", phraseReport.totalWeight))).",
                detail: phraseReport.matchedPhrases.prefix(8).joined(separator: ", ")
            ))
        }
        return items
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

    /// The five-signal fusion. Sentence-shape signals (uniformity and
    /// repetition) carry the most weight because they separate cleanly;
    /// vocabulary surprisal, rare-word rate, and phrase density act as the
    /// secondary signals that push a borderline text over the line - this is
    /// what lets a bursty but phrase-heavy and low-surprisal AI passage still
    /// read as AI-typical, for any model family.
    static func score(
        burstiness: Double,
        repeatedBigramRate: Double,
        tokenStats: TokenStats,
        phraseReport: AIPhraseDatabase.MatchReport
    ) -> Double {
        // Uniform sentence lengths (burstiness 0.3 or less) are strongly
        // AI-typical; at a coefficient of variation of 1.0 the text looks
        // human-bursty and the uniformity term reaches zero.
        let uniformity = 1 - min(max(burstiness - 0.3, 0) / 0.7, 1)
        let repetition = min(repeatedBigramRate * 5, 1)
        return 0.40 * uniformity
            + 0.20 * repetition
            + 0.15 * tokenStats.perplexityTerm
            + 0.10 * tokenStats.commonVocabularyTerm
            + 0.15 * phraseReport.phraseTerm
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
