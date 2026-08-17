import Foundation

/// The bundled database of phrases that appear disproportionately often in
/// AI-generated prose, tagged by which model families favor them.
///
/// Matching is deliberately simple (case-insensitive substring search on
/// normalized text). The signal is a *density* signal: one stray phrase
/// proves nothing, but a text studded with them is statistically unlikely to
/// be unedited human writing. The analyzer therefore uses the total matched
/// weight, not any single hit.
public struct AIPhraseDatabase: Sendable {
    private struct Phrase: Sendable {
        let text: String
        let families: [ModelFamily]
        let weight: Double
    }

    private let phrases: [Phrase]

    public init(phrases: [AIPhraseEntry]) {
        self.phrases = phrases.map { entry in
            Phrase(
                text: Self.normalize(entry.phrase),
                families: entry.families,
                weight: min(max(entry.weight, 0), 1)
            )
        }
    }

    public static func bundled() throws -> AIPhraseDatabase {
        try BundledResources.phraseDatabase()
    }

    /// The raw entry shape used by the bundled JSON.
    public struct AIPhraseEntry: Codable, Sendable, Equatable {
        public var phrase: String
        public var families: [ModelFamily]
        public var weight: Double

        public init(phrase: String, families: [ModelFamily], weight: Double) {
            self.phrase = phrase
            self.families = families
            self.weight = weight
        }
    }

    public struct MatchReport: Sendable, Equatable {
        /// Sum of matched phrase weights (each occurrence counted, capped per
        /// phrase to keep one repetitive passage from dominating).
        public var totalWeight: Double
        /// Distinct phrases that matched at least once.
        public var matchedCount: Int
        /// The matched phrases, strongest first.
        public var matchedPhrases: [String]
        /// Matched weight per family, only for families that had hits.
        public var familyWeights: [ModelFamily: Double]
        /// The matched phrases that carried family tags, strongest first.
        public var familyPhrases: [ModelFamily: [String]]

        public init(
            totalWeight: Double,
            matchedCount: Int,
            matchedPhrases: [String],
            familyWeights: [ModelFamily: Double],
            familyPhrases: [ModelFamily: [String]]
        ) {
            self.totalWeight = totalWeight
            self.matchedCount = matchedCount
            self.matchedPhrases = matchedPhrases
            self.familyWeights = familyWeights
            self.familyPhrases = familyPhrases
        }

        /// 0...1, higher means more AI-typical phrasing. Saturates so a
        /// handful of strong phrases is a full signal.
        public var phraseTerm: Double {
            min(totalWeight / 6.0, 1)
        }
    }

    /// Builds the soft style attributions for a match report. A family is
    /// only reported once its matched weight clears the bar, and every hint
    /// carries the actual matched phrases so the UI can show why it fired.
    public func familyHints(
        from report: MatchReport,
        minimumWeight: Double = 1.0,
        maxPhrases: Int = 4
    ) -> [ModelFamilyHint] {
        // Deduplicate defensively: the resource file should not repeat a
        // phrase, but a bad edit must degrade to a hint, never a crash.
        let weightByPhrase = Dictionary(
            phrases.map { ($0.text, $0.weight) },
            uniquingKeysWith: { first, _ in first }
        )
        var hints: [ModelFamilyHint] = []
        for family in ModelFamily.hintable {
            guard let weight = report.familyWeights[family], weight >= minimumWeight else { continue }
            let matched = (report.familyPhrases[family] ?? [])
                .sorted { (weightByPhrase[$0] ?? 0) > (weightByPhrase[$1] ?? 0) }
            hints.append(ModelFamilyHint(
                family: family,
                weight: weight,
                matchedPhrases: Array(matched.prefix(maxPhrases))
            ))
        }
        return hints.sorted { $0.weight > $1.weight }
    }

    public func match(_ text: String) -> MatchReport {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return emptyReport }

        var totalWeight = 0.0
        var matched: [String] = []
        var familyWeights: [ModelFamily: Double] = [:]
        var familyPhrases: [ModelFamily: [String]] = [:]

        for phrase in phrases {
            let count = Self.occurrences(of: phrase.text, in: normalized)
            guard count > 0 else { continue }
            let capped = min(count, 3)
            let weight = phrase.weight * Double(capped)
            totalWeight += weight
            matched.append(phrase.text)
            for family in phrase.families where family != .generic {
                familyWeights[family, default: 0] += weight
                familyPhrases[family, default: []].append(phrase.text)
            }
        }

        // Sort matched phrases strongest first is not possible without
        // storing weight per phrase; sort alphabetically for determinism.
        // Family phrase lists are sorted by weight through a second pass in
        // the analyzer's hint builder, which has the weights.
        return MatchReport(
            totalWeight: totalWeight,
            matchedCount: matched.count,
            matchedPhrases: matched.sorted(),
            familyWeights: familyWeights,
            familyPhrases: familyPhrases
        )
    }

    private var emptyReport: MatchReport {
        MatchReport(
            totalWeight: 0,
            matchedCount: 0,
            matchedPhrases: [],
            familyWeights: [:],
            familyPhrases: [:]
        )
    }

    /// Normalizes a phrase or passage for matching: lowercase, single
    /// spaces, no surrounding punctuation.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Counts non-overlapping occurrences of a phrase in a text.
    static func occurrences(of phrase: String, in text: String) -> Int {
        guard !phrase.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: phrase, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
