import Foundation

/// The model families the phrase pattern database can attribute writing
/// style to. Attribution is a soft hint, never a claim: the same phrasing
/// appears in human writing, so the detector reports "patterns consistent
/// with X-style writing" and shows the matched phrases as evidence.
public enum ModelFamily: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case chatgpt
    case gemini
    /// Phrases shared across AI systems (and some human writing). Generic
    /// matches strengthen the overall signal but never produce a family hint.
    case generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude-style"
        case .chatgpt: "ChatGPT-style"
        case .gemini: "Gemini-style"
        case .generic: "Generic AI-style"
        }
    }

    /// The model families that can appear as hints. Generic is deliberately
    /// excluded: "uses common AI phrasing" is not an attribution.
    public static var hintable: [ModelFamily] {
        [.claude, .chatgpt, .gemini]
    }
}

/// A soft attribution produced by the phrase pattern database. Only present
/// when enough family-tagged phrases matched to be worth reporting.
public struct ModelFamilyHint: Codable, Sendable, Equatable, Identifiable {
    public var family: ModelFamily
    /// Sum of the matched phrase weights for this family. Higher means more
    /// matches, not higher confidence in the attribution.
    public var weight: Double
    /// The matched phrases behind the hint, strongest first, capped at a
    /// handful so the verdict card stays readable.
    public var matchedPhrases: [String]

    public var id: String { family.rawValue }

    public init(family: ModelFamily, weight: Double, matchedPhrases: [String]) {
        self.family = family
        self.weight = weight
        self.matchedPhrases = matchedPhrases
    }
}
