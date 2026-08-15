import XCTest
@testable import OriginCheckEngine

final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> JSONHistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return JSONHistoryStore(fileURL: dir.appendingPathComponent("history.json"))
    }

    func testSHA256KnownVectors() {
        XCTAssertEqual(
            SHA256.hashString("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hashString(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hashString("The quick brown fox jumps over the lazy dog"),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        )
    }

    func testRoundTripAndDelete() async throws {
        let store = try makeStore()
        let first = HistoryRecord(
            inputType: "text",
            inputHash: "abc123",
            verdictKind: .watermarked,
            confidenceValue: 0.9,
            evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")]
        )
        let second = HistoryRecord(
            inputType: "file",
            inputHash: "def456",
            verdictKind: .notWatermarked,
            confidenceValue: 0.05,
            evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "Another record.")]
        )
        try await store.add(first)
        try await store.add(second)

        let loaded = try await store.allRecords()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first?.verdictKind, .watermarked)

        try await store.delete(id: first.id)
        let afterDelete = try await store.allRecords()
        XCTAssertEqual(afterDelete.count, 1)
        XCTAssertEqual(afterDelete.first?.inputType, "file")

        try await store.deleteAll()
        let afterClear = try await store.allRecords()
        XCTAssertTrue(afterClear.isEmpty)
    }

    func testRawTextNotStoredByDefault() async throws {
        let store = try makeStore()
        let record = HistoryRecorder.record(
            forTextVerdict: TextVerdict(
                kind: .notAvailable,
                confidence: ConfidenceRules.confidence(0),
                characterCount: 10,
                effectiveTokenEstimate: 2,
                providersRun: ["LocalAnalyzer"],
                evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")],
                caveatText: Caveats.detectionNotAvailable
            ),
            rawText: "A private essay that must not be stored.",
            storeRawText: false
        )
        try await store.add(record)

        let loaded = try await store.allRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.rawText)

        // The persisted JSON must not contain the raw text either.
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let fileURL = storeDir.appendingPathComponent("history.json")
        let explicit = JSONHistoryStore(fileURL: fileURL)
        try await explicit.add(record)
        let json = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(json.contains("private essay"))
    }

    func testRawTextStoredOnlyWithConsent() async throws {
        let store = try makeStore()
        let record = HistoryRecorder.record(
            forTextVerdict: TextVerdict(
                kind: .notAvailable,
                confidence: ConfidenceRules.confidence(0),
                characterCount: 10,
                effectiveTokenEstimate: 2,
                providersRun: [],
                evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")],
                caveatText: Caveats.detectionNotAvailable
            ),
            rawText: "Essay the user consented to keep.",
            storeRawText: true
        )
        try await store.add(record)
        let loaded = try await store.allRecords()
        XCTAssertEqual(loaded.first?.rawText, "Essay the user consented to keep.")
    }

    func testEmptyStoreReturnsEmpty() async throws {
        let store = try makeStore()
        let loaded = try await store.allRecords()
        XCTAssertTrue(loaded.isEmpty)
    }
}
