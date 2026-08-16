import Testing
@testable import OriginCheckEngine

@Suite
struct CombinerTests {
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

    @Test
    func testNoProvidersEnabledIsNotAvailable() {
        let verdict = VerdictCombiner().combineText(
            results: [],
            characterCount: 500,
            providersRun: [],
            preset: .balanced
        )
        #expect(verdict.kind == .notAvailable)
        #expect(verdict.confidence.value == 0)
        #expect(!verdict.evidence.isEmpty)
    }

    @Test
    func testWatermarkDetectedHighConfidence() {
        let verdict = VerdictCombiner().combineText(
            results: [result("AnthropicAPI", .detected, confidence: 0.88)],
            characterCount: 2400,
            providersRun: ["AnthropicAPI"],
            preset: .balanced
        )
        #expect(verdict.kind == .watermarked)
        #expect(verdict.confidence.label == .high)
        #expect(verdict.caveatText.contains("not proof of AI authorship"))
        #expect(!verdict.evidence.isEmpty)
    }

    @Test
    func testNoWatermarkDetectedIsNotWatermarkedWithCaveat() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .notDetected, confidence: 0.2)],
            characterCount: 1200,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        #expect(verdict.kind == .notWatermarked)
        #expect(verdict.caveatText.contains("does not prove human authorship"))
    }

    @Test
    func testShortTextIsInsufficientAndCapped() {
        let verdict = VerdictCombiner().combineText(
            results: [result("AnthropicAPI", .detected, confidence: 0.9)],
            characterCount: 40,
            providersRun: ["AnthropicAPI"],
            preset: .balanced
        )
        #expect(verdict.kind == .watermarked)
        #expect(verdict.confidence.value <= 0.3)
        #expect(verdict.confidence.label == .low)
    }

    @Test
    func testShortTextWithoutSignalIsInsufficientInput() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 40,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        #expect(verdict.kind == .insufficientInput)
        // The caveat must match the verdict: this is not a "no watermark"
        // result, it is a "not enough text" result.
        #expect(verdict.caveatText == Caveats.textTooShort)
    }

    @Test
    func testInsufficientOnlyResultCarriesTooShortCaveat() {
        let verdict = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 600,
            providersRun: ["LocalAnalyzer"],
            preset: .balanced
        )
        #expect(verdict.kind == .insufficientInput)
        #expect(verdict.caveatText == Caveats.textTooShort)
    }

    @Test
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
        #expect(verdict.kind == .notAvailable)
        #expect(verdict.confidence.value == 0)
        #expect(!verdict.evidence.isEmpty)
        #expect(verdict.caveatText.contains("not yet released"))
    }

    @Test
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
        #expect(verdict.kind == .watermarked)
        #expect(verdict.confidence.label == .high)
        #expect(verdict.providersRun.count == 2)
    }

    @Test
    func testStrictPresetRaisesMinimumLength() {
        let short = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 150,
            providersRun: ["LocalAnalyzer"],
            preset: .strict
        )
        #expect(short.kind == .insufficientInput)

        let relaxed = VerdictCombiner().combineText(
            results: [result("LocalAnalyzer", .insufficient, confidence: 0.1)],
            characterCount: 150,
            providersRun: ["LocalAnalyzer"],
            preset: .relaxed
        )
        #expect(relaxed.kind == .insufficientInput)
    }

    @Test
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
            #expect(!verdict.evidence.isEmpty, "No verdict without evidence for \(signal)")
            #expect(!verdict.caveatText.isEmpty, "No verdict without a caveat for \(signal)")
        }
    }
}
