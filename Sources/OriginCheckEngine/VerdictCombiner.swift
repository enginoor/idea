import Foundation

/// Merges provider results into a single text verdict.
///
/// Rules:
/// 1. A positive signal beats a negative one, and the conflict is shown.
/// 2. Short passages can never reach high confidence.
/// 3. If every provider is unavailable, the verdict says so.
/// 4. Every verdict carries at least one evidence item and a caveat.
public struct VerdictCombiner: Sendable {
    public init() {}

    public func combineText(
        results: [ProviderResult],
        characterCount: Int,
        providersRun: [String],
        preset: ThresholdPreset
    ) -> TextVerdict {
        var evidence: [EvidenceItem] = results.flatMap(\.evidence)

        if results.isEmpty {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "no_providers",
                summary: "No detection providers are enabled.",
                detail: "Enable the local analyzer or the Anthropic API provider in Settings."
            ))
            return TextVerdict(
                kind: .notAvailable,
                confidence: ConfidenceRules.confidence(0),
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.detectionNotAvailable
            )
        }

        let detected = results.filter { $0.signal == .detected }
        let notDetected = results.filter { $0.signal == .notDetected }
        let insufficient = results.filter { $0.signal == .insufficient }
        let unavailable = results.filter { $0.signal == .unavailable }

        if characterCount < preset.minimumTextLength {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "short_text",
                summary: "Passage is shorter than the reliable threshold.",
                detail: "\(characterCount) characters; the \(preset.rawValue) preset requires at least \(preset.minimumTextLength)."
            ))
            if let strongest = detected.map(\.confidence.value).max() {
                let confidence = ConfidenceRules.capConfidence(strongest, at: 0.3)
                return TextVerdict(
                    kind: .watermarked,
                    confidence: confidence,
                    characterCount: characterCount,
                    effectiveTokenEstimate: characterCount / 4,
                    providersRun: providersRun,
                    evidence: evidence,
                    caveatText: Caveats.textPositive(confidenceLabel: confidence.label.rawValue)
                )
            }
            return TextVerdict(
                kind: .insufficientInput,
                confidence: ConfidenceRules.shortTextConfidence,
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.textNegative
            )
        }

        if let strongest = detected.map(\.confidence.value).max() {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "A positive watermark signal was found.",
                detail: "Strongest provider confidence: \(String(format: "%.2f", strongest))."
            ))
            let confidence = ConfidenceRules.confidence(strongest)
            return TextVerdict(
                kind: .watermarked,
                confidence: confidence,
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.textPositive(confidenceLabel: confidence.label.rawValue)
            )
        }

        if let strongest = notDetected.map(\.confidence.value).max() {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "No watermark signal was found by any enabled provider.",
                detail: "Strongest provider confidence: \(String(format: "%.2f", strongest))."
            ))
            return TextVerdict(
                kind: .notWatermarked,
                confidence: ConfidenceRules.confidence(strongest),
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.textNegative
            )
        }

        if !insufficient.isEmpty && unavailable.isEmpty {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "The input is too short for any provider to act on."
            ))
            return TextVerdict(
                kind: .insufficientInput,
                confidence: ConfidenceRules.shortTextConfidence,
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.textNegative
            )
        }

        evidence.append(EvidenceItem(
            source: "Combiner",
            kind: "decision",
            summary: "No detection provider is available yet.",
            detail: "All enabled providers reported that an honest verdict is not possible."
        ))
        return TextVerdict(
            kind: .notAvailable,
            confidence: ConfidenceRules.confidence(0),
            characterCount: characterCount,
            effectiveTokenEstimate: characterCount / 4,
            providersRun: providersRun,
            evidence: evidence,
            caveatText: Caveats.detectionNotAvailable
        )
    }
}
