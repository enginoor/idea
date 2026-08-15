import Foundation

/// The confidence rules are the product's credibility. Unknowns always reduce
/// confidence and never increase it.
public enum ConfidenceRules {
    public static func label(for value: Double) -> ConfidenceLabel {
        if value < 0.4 { return .low }
        if value < 0.75 { return .moderate }
        return .high
    }

    public static func confidence(_ value: Double) -> Confidence {
        let clamped = min(max(value, 0), 1)
        return Confidence(value: clamped, label: label(for: clamped))
    }

    public static func capConfidence(_ value: Double, at maxValue: Double) -> Confidence {
        confidence(min(value, maxValue))
    }

    public static let shortTextConfidence = Confidence(value: 0.1, label: .low)

    /// A valid C2PA signature with a known signer and an intact asset hash is
    /// the strongest evidence the product can produce.
    public static let validSignatureKnownSigner = 0.9

    /// A valid signature from an unknown entity: strong cryptographically,
    /// weak on identity.
    public static let validSignatureUnknownSigner = 0.55

    /// A valid signature with a modified asset hash. The modification is a
    /// hard cryptographic fact, so confidence stays high while the verdict
    /// reads as a warning, not a clean pass.
    public static let validSignatureModified = 0.9

    public static let invalidSignature = 0.2

    public static let unverifiableSignature = 0.3

    public static let noManifest = 0.05
}
