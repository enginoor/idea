import XCTest
@testable import OriginCheckEngine

final class CombinerTests: XCTestCase {
    private func result(
        _ source: String,
        _ signal: ProviderSignal,
        confidence: Double
    ) -> ProviderResult {
        ProviderResult(
            source: source,
            signal: signal,
            confidence: ConfidenceRules.confidence(confidence),
            evidence: [
                EvidenceItem(source: source, kind: "test", summary: "Fixture result from \(source).")
            ]
        )
    }

    func testNoProvidersEnabledIsNotAvailable() {
        let verdict = VerdictCombiner().combineText(
            results: [],
            characterCount: 500,
            providersRun: [],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .notAvailable)
        XCTAssertEqual(verdict.confidence.value, 0)
        XCTAssertFalse(verdict.evidence.isEmpty)
    }

    func testWatermarkDetectedHighConfidence() {
        let verdict = VerdictCombiner().combineText(
            results: [result("AnthropicAPI", .detected, confidence: 0.88)],
            characterCount: 2400,
            providersRun: ["AnthropicAPI"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .watermarked)
        XCTAssertEqual(verdict.confidence.label, .high)
        XCTAssertTrue(verdict.caveatText.contains("not proof of AI authorship"))
        XCTAssertFalse(verdict.evidence.isEmpty)
    }

    func testNoWatermarkDetectedIsNotWatermarkedWithCaveat() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .notDetected, confidence: 0.2)],
            characterCount: 1200,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .notWatermarked)
        XCTAssertTrue(verdict.caveatText.contains("does not prove human authorship"))
    }

    func testShortTextIsInsufficientAndCapped() {
        let verdict = VerdictCombiner().combineText(
            results: [result("AnthropicAPI", .detected, confidence: 0.9)],
            characterCount: 40,
            providersRun: ["AnthropicAPI"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .watermarked)
        XCTAssertLessThanOrEqual(verdict.confidence.value, 0.3)
        XCTAssertEqual(verdict.confidence.label, .low)
    }

    func testShortTextWithoutSignalIsInsufficientInput() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 40,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .insufficientInput)
        // The caveat must match the verdict: this is not a "no watermark"
        // result, it is a "not enough text" result.
        XCTAssertEqual(verdict.caveatText, Caveats.textTooShort)
    }

    func testInsufficientOnlyResultCarriesTooShortCaveat() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 600,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .insufficientInput)
        XCTAssertEqual(verdict.caveatText, Caveats.textTooShort)
    }

    func testAllProvidersUnavailableIsNotAvailable() {
        let verdict = VerdictCombiner().combineText(
            results: [
                result("LocalAnalyzer", .unavailable, confidence: 0),
                result("AnthropicAPI", .unavailable, confidence: 0),
            ],
            characterCount: 800,
            providersRun: ["LocalAnalyzer", "AnthropicAPI"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .notAvailable)
        XCTAssertEqual(verdict.confidence.value, 0)
        XCTAssertFalse(verdict.evidence.isEmpty)
        XCTAssertTrue(verdict.caveatText.contains("not yet released"))
    }

    func testConflictingSignalsResolveToStrongerAndShowConflict() {
        let verdict = VerdictCombiner().combineText(
            results: [
                result("AnthropicAPI", .detected, confidence: 0.8),
                result("LocalAnalyzer", .notDetected, confidence: 0.3),
            ],
            characterCount: 1500,
            providersRun: ["AnthropicAPI", "LocalAnalyzer"],
            preset: .balanced
        )
        XCTAssertEqual(verdict.kind, .watermarked)
        XCTAssertEqual(verdict.confidence.label, .high)
        XCTAssertEqual(verdict.providersRun.count, 2)
    }

    func testStrictPresetRaisesMinimumLength() {
        let short = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 150,
            providersRun: ["LocalAnalyzer"],
            preset: .strict
        )
        XCTAssertEqual(short.kind, .insufficientInput)

        let relaxed = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 150,
            providersRun: ["LocalAnalyzer"],
            preset: .relaxed
        )
        XCTAssertEqual(relaxed.kind, .insufficientInput)
    }

    func testEveryVerdictCarriesEvidenceAndCaveat() {
        let combiner = VerdictCombiner()
        let cases: [ProviderSignal] = [.detected, .notDetected, .insufficient, .unavailable]
        for signal in cases {
            let verdict = combiner.combineText(
                results: [result("LocalAnalyzer", signal, confidence: 0.5)],
                characterCount: 600,
                providersRun: ["LocalAnalyzer"],
                preset: .balanced
            )
            XCTAssertFalse(verdict.evidence.isEmpty, "No verdict without evidence for \(signal)")
            XCTAssertFalse(verdict.caveatText.isEmpty, "No verdict without a caveat for \(signal)")
        }
    }
}
