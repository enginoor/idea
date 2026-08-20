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
        let inconclusive = results.filter { $0.signal == .inconclusive }
        // A provider that has something specific to say about its verdict
        // (for example the local heuristic's disclaimer) wins over the
        // generic caveat.
        let providerCaveat = results.first { !$0.caveatText.isEmpty }?.caveatText
        // Style hints merge across providers: per family, keep the strongest
        // weight and the longest phrase list.
        let familyHints = Self.mergedHints(results.flatMap(\.familyHints))
        let sentenceAnalyses = results.flatMap(\.sentenceAnalyses)

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
                    caveatText: Caveats.textPositive(confidenceLabel: confidence.label.rawValue),
                    familyHints: familyHints,
                    sentenceAnalyses: sentenceAnalyses
                )
            }
            return TextVerdict(
                kind: .insufficientInput,
                confidence: ConfidenceRules.shortTextConfidence,
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: Caveats.textTooShort,
                familyHints: familyHints,
                sentenceAnalyses: sentenceAnalyses
            )
        }

        if let strongest = detected.map(\.confidence.value).max() {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "A positive signal was found by an enabled provider.",
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
                caveatText: providerCaveat ?? Caveats.textPositive(confidenceLabel: confidence.label.rawValue),
                familyHints: familyHints,
                sentenceAnalyses: sentenceAnalyses
            )
        }

        if let strongest = notDetected.map(\.confidence.value).max() {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "No positive signal was found by any enabled provider.",
                detail: "Strongest provider confidence: \(String(format: "%.2f", strongest))."
            ))
            return TextVerdict(
                kind: .notWatermarked,
                confidence: ConfidenceRules.confidence(strongest),
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: providerCaveat ?? Caveats.textNegative,
                familyHints: familyHints,
                sentenceAnalyses: sentenceAnalyses
            )
        }

        if let strongest = inconclusive.map(\.confidence.value).max() {
            evidence.append(EvidenceItem(
                source: "Combiner",
                kind: "decision",
                summary: "The enabled providers could not resolve a clear signal.",
                detail: "Strongest provider confidence: \(String(format: "%.2f", strongest))."
            ))
            return TextVerdict(
                kind: .inconclusive,
                confidence: ConfidenceRules.confidence(strongest),
                characterCount: characterCount,
                effectiveTokenEstimate: characterCount / 4,
                providersRun: providersRun,
                evidence: evidence,
                caveatText: providerCaveat ?? Caveats.textInconclusive,
                familyHints: familyHints,
                sentenceAnalyses: sentenceAnalyses
            )
        }

        if !insufficient.isEmpty {
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
                caveatText: Caveats.textTooShort,
                familyHints: familyHints,
                sentenceAnalyses: sentenceAnalyses
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

    /// Merges style hints from several providers into one list. Per family:
    /// the strongest weight wins, and phrase lists combine (deduplicated,
    /// strongest first, capped). Order follows weight, then family order.
    static func mergedHints(_ hints: [ModelFamilyHint]) -> [ModelFamilyHint] {
        var byFamily: [ModelFamily: ModelFamilyHint] = [:]
        for hint in hints {
            if var existing = byFamily[hint.family] {
                if hint.weight > existing.weight {
                    existing.weight = hint.weight
                }
                var phrases = existing.matchedPhrases
                for phrase in hint.matchedPhrases where !phrases.contains(phrase) {
                    phrases.append(phrase)
                }
                existing.matchedPhrases = Array(phrases.prefix(6))
                byFamily[hint.family] = existing
            } else {
                byFamily[hint.family] = hint
            }
        }
        return byFamily.values.sorted {
            if $0.weight == $1.weight {
                return $0.family.rawValue < $1.family.rawValue
            }
            return $0.weight > $1.weight
        }
    }
}
