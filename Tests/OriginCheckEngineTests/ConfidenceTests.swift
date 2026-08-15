import XCTest
@testable import OriginCheckEngine

final class ConfidenceTests: XCTestCase {
    func testLabelBoundaries() {
        XCTAssertEqual(ConfidenceRules.label(for: 0.0), .low)
        XCTAssertEqual(ConfidenceRules.label(for: 0.39), .low)
        XCTAssertEqual(ConfidenceRules.label(for: 0.4), .moderate)
        XCTAssertEqual(ConfidenceRules.label(for: 0.74), .moderate)
        XCTAssertEqual(ConfidenceRules.label(for: 0.75), .high)
        XCTAssertEqual(ConfidenceRules.label(for: 1.0), .high)
    }

    func testConfidenceClampsOutOfRangeValues() {
        XCTAssertEqual(ConfidenceRules.confidence(-1).value, 0)
        XCTAssertEqual(ConfidenceRules.confidence(2).value, 1)
    }

    func testCapConfidenceNeverRaises() {
        let capped = ConfidenceRules.capConfidence(0.9, at: 0.3)
        XCTAssertEqual(capped.value, 0.3)
        XCTAssertEqual(capped.label, .low)
    }

    func testKnownConstantsMapToLabels() {
        XCTAssertEqual(ConfidenceRules.confidence(ConfidenceRules.validSignatureKnownSigner).label, .high)
        XCTAssertEqual(ConfidenceRules.confidence(ConfidenceRules.validSignatureUnknownSigner).label, .moderate)
        XCTAssertEqual(ConfidenceRules.confidence(ConfidenceRules.invalidSignature).label, .low)
        XCTAssertEqual(ConfidenceRules.confidence(ConfidenceRules.noManifest).label, .low)
    }

    func testShortTextConfidenceIsLow() {
        XCTAssertEqual(ConfidenceRules.shortTextConfidence.label, .low)
        XCTAssertLessThanOrEqual(ConfidenceRules.shortTextConfidence.value, 0.2)
    }
}
