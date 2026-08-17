import Foundation

/// A compact English word-frequency dictionary loaded from the app bundle.
/// It powers the two vocabulary signals behind the local detector:
///
/// - **Perplexity estimate**: the average surprisal of the words in a text,
///   where surprisal is high for rare words and low for common ones. AI
///   prose tends to stay in the middle of the vocabulary (low average
///   surprisal); human prose reaches for rarer words more often.
/// - **Rare-word rate**: the fraction of tokens that are out of vocabulary
///   or in the rarest buckets. Same underlying signal, expressed as a rate.
///
/// The dictionary is deliberately coarse (log10 frequency buckets). Fine
/// frequencies are not needed: the detector only compares the *relative*
/// rarity of the words a writer chose, so buckets are enough and keep the
/// bundled data small enough to load instantly.
public struct FrequencyDictionary: Sendable {
    /// log10(frequency per million tokens) for every dictionary word.
    private let logFrequencies: [String: Double]

    public init(logFrequencies: [String: Double]) {
        self.logFrequencies = logFrequencies
    }

    /// Loads the bundled dictionary. Throws only when the resource is
    /// missing or malformed, which would indicate a broken app bundle; the
    /// analyzer treats that as a hard failure rather than guessing.
    public static func bundled() throws -> FrequencyDictionary {
        try BundledResources.frequencyDictionary()
    }

    public func logFrequency(of word: String) -> Double? {
        let normalized = word.lowercased()
        if let exact = logFrequencies[normalized] {
            return exact
        }
        // A run of digits is common in ordinary writing regardless of
        // authorship; treat every number as mid-frequency instead of rare.
        if normalized.allSatisfy({ $0.isNumber }) {
            return 4.5
        }
        // Light inflection handling: the dictionary stores base forms, so
        // try common suffixes before declaring a word rare. This keeps
        // plurals, past tenses, and -ly adverbs from inflating the
        // rare-word signal of otherwise ordinary text.
        for suffix in ["ies", "es", "ed", "ing", "ly", "s"] {
            guard normalized.count > suffix.count + 2 else { continue }
            let stem = String(normalized.dropLast(suffix.count))
            if suffix == "ies" {
                // companies -> company, studies -> study
                if let inflected = logFrequencies[stem + "y"] {
                    return inflected - 0.1
                }
                continue
            }
            if let inflected = logFrequencies[stem] {
                // Inflected forms read slightly less predictable than the
                // base word, so nudge the frequency down a touch.
                return inflected - 0.1
            }
            // Double-consonant reduction: stopping -> stop, running -> run
            if stem.count >= 3, stem.hasSuffix(String(repeating: stem.last!, count: 2)) {
                let reduced = String(stem.dropLast())
                if let inflected = logFrequencies[reduced] {
                    return inflected - 0.1
                }
            }
        }
        return nil
    }

    /// The per-token statistics the detector feeds on. `tokens` must already
    /// be normalized by `FrequencyDictionary.tokenize`.
    public func stats(forTokens tokens: [String]) -> TokenStats {
        guard !tokens.isEmpty else {
            return TokenStats(tokenCount: 0, outOfVocabularyCount: 0, rareWordCount: 0)
        }

        var outOfVocabulary = 0
        var rare = 0
        var surprisalSum = 0.0
        for token in tokens {
            let logFreq = logFrequency(of: token)
            let surprisal: Double
            switch logFreq {
            case .none:
                outOfVocabulary += 1
                rare += 1
                surprisal = TokenStats.maxSurprisal
            case .some(let value):
                surprisal = min(max(TokenStats.maxSurprisal - value, 0), TokenStats.maxSurprisal)
                // Words at or below this bucket read as unusual choices.
                if value <= 2.0 {
                    rare += 1
                }
            }
            surprisalSum += surprisal
        }

        return TokenStats(
            tokenCount: tokens.count,
            outOfVocabularyCount: outOfVocabulary,
            rareWordCount: rare,
            averageSurprisal: surprisalSum / Double(tokens.count)
        )
    }

    /// Splits text into the same lowercase word tokens the dictionary uses.
    /// Contraction remnants ("it's" -> "it", "s") are dropped, and bare
    /// "a"/"i" survive. Shared with the rest of the analyzer so every
    /// signal counts words the same way.
    public static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                if current.count > 1 || current == "a" || current == "i" {
                    words.append(current)
                }
                current = ""
            }
        }
        if !current.isEmpty && (current.count > 1 || current == "a" || current == "i") {
            words.append(current)
        }
        return words
    }
}

public struct TokenStats: Sendable, Equatable {
    /// Highest surprisal a token can carry (an out-of-vocabulary word).
    public static let maxSurprisal = 6.0

    public var tokenCount: Int
    public var outOfVocabularyCount: Int
    public var rareWordCount: Int

    public init(
        tokenCount: Int,
        outOfVocabularyCount: Int,
        rareWordCount: Int
    ) {
        self.tokenCount = tokenCount
        self.outOfVocabularyCount = outOfVocabularyCount
        self.rareWordCount = rareWordCount
        self.surprisalSum = 0
    }

    public var outOfVocabularyRate: Double {
        tokenCount == 0 ? 0 : Double(outOfVocabularyCount) / Double(tokenCount)
    }

    public var rareWordRate: Double {
        tokenCount == 0 ? 0 : Double(rareWordCount) / Double(tokenCount)
    }

    /// 0...1, higher means the text stays in common vocabulary (AI-typical).
    public var commonVocabularyTerm: Double {
        tokenCount == 0 ? 0 : 1 - min(rareWordRate, 1)
    }

    /// 0...1, higher means low average surprisal (AI-typical).
    public var perplexityTerm: Double {
        tokenCount == 0 ? 0 : 1 - (averageSurprisal / TokenStats.maxSurprisal)
    }

    /// Average surprisal per token (0...maxSurprisal).
    public var averageSurprisal: Double {
        tokenCount == 0 ? 0 : surprisalSum / Double(tokenCount)
    }

    // Stored separately so averageSurprisal stays cheap to compute.
    private var surprisalSum: Double

    init(tokenCount: Int, outOfVocabularyCount: Int, rareWordCount: Int, averageSurprisal: Double) {
        self.tokenCount = tokenCount
        self.outOfVocabularyCount = outOfVocabularyCount
        self.rareWordCount = rareWordCount
        self.surprisalSum = averageSurprisal * Double(tokenCount)
    }
}
