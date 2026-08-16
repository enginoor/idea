import Testing
@testable import OriginCheckEngine

@Suite
struct ConfidenceTests {
    @Test
    func testLabelBoundaries() {
        #expect(ConfidenceRules.label(for: 0.0) == .low)
        #expect(ConfidenceRules.label(for: 0.39) == .low)
        #expect(ConfidenceRules.label(for: 0.4) == .moderate)
        #expect(ConfidenceRules.label(for: 0.74) == .moderate)
        #expect(ConfidenceRules.label(for: 0.75) == .high)
        #expect(ConfidenceRules.label(for: 1.0) == .high)
    }

    @Test
    func testConfidenceClampsOutOfRangeValues() {
        #expect(ConfidenceRules.confidence(-1).value == 0)
        #expect(ConfidenceRules.confidence(2).value == 1)
    }

    @Test
    func testCapConfidenceNeverRaises() {
        let capped = ConfidenceRules.capConfidence(0.9, at: 0.3)
        #expect(capped.value == 0.3)
        #expect(capped.label == .low)
    }

    @Test
    func testKnownConstantsMapToLabels() {
        #expect(ConfidenceRules.confidence(ConfidenceRules.validSignatureKnownSigner).label == .high)
        #expect(ConfidenceRules.confidence(ConfidenceRules.validSignatureUnknownSigner).label == .moderate)
        #expect(ConfidenceRules.confidence(ConfidenceRules.invalidSignature).label == .low)
        #expect(ConfidenceRules.confidence(ConfidenceRules.noManifest).label == .low)
    }

    @Test
    func testShortTextConfidenceIsLow() {
        #expect(ConfidenceRules.shortTextConfidence.label == .low)
        #expect(ConfidenceRules.shortTextConfidence.value <= 0.2)
    }
}
