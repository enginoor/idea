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

    func testHashFileMatchesHashData() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("payload.bin")
        // 2 MiB of patterned bytes exercises multi-block streaming.
        let count = 2 * 1024 * 1024
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            bytes[i] = UInt8((i * 7 + 3) % 256)
        }
        let data = Data(bytes)
        try data.write(to: url)
        XCTAssertEqual(try SHA256.hashFile(at: url), SHA256.hashData(data))
    }

    func testHashFileEmptyFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("empty.bin")
        try Data().write(to: url)
        XCTAssertEqual(try SHA256.hashFile(at: url), SHA256.hashData(Data()))
    }

    func testLargeFileHashingIsLinearNotQuadratic() throws {
        // An 8 MiB file must hash in well under a second with a linear
        // digester. The previous implementation appended each chunk to a
        // buffer and shifted it one element at a time, which made the same
        // input take many seconds and made large videos effectively
        // unhashable. The bound is generous: the fixed code finishes this
        // in a few hundred milliseconds here, so slow CI runners cannot
        // flake it, while the quadratic version blew straight past it.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("large.bin")
        let count = 8 * 1024 * 1024
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            bytes[i] = UInt8((i * 7 + 3) % 256)
        }
        try Data(bytes).write(to: url)

        let start = Date()
        let hash = try SHA256.hashFile(at: url)
        XCTAssertEqual(hash, SHA256.hashData(Data(bytes)))
        XCTAssertLessThan(
            Date().timeIntervalSince(start),
            5.0,
            "Hashing 8 MiB must complete quickly, not quadratically"
        )
    }

    func testFileRecordHashesContentNotName() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckRecord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("photo-intact.jpg")
        let content = Data("photo bytes".utf8)
        try content.write(to: url)

        let verdict = FileVerdict(
            kind: .watermarked,
            confidence: ConfidenceRules.confidence(0.9),
            fileName: "photo-intact.jpg",
            format: "jpg",
            manifestPresent: true,
            signatureValid: true,
            modifiedSinceSigning: false,
            signer: "Claude",
            softwareAgent: "Claude",
            claims: [],
            evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")],
            caveatText: Caveats.fileValid(signer: "Claude", tool: "Claude")
        )

        let record = HistoryRecorder.record(forFileVerdict: verdict, fileURL: url, storeRawContent: false)
        XCTAssertEqual(record.inputHash, SHA256.hashData(content))
        XCTAssertNotEqual(record.inputHash, SHA256.hashString(verdict.fileName))
        XCTAssertNil(record.fileThumbnailPath)
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

    func testCorruptHistoryFileIsQuarantinedNotFatal() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("history.json")
        try Data("this is not JSON history".utf8).write(to: fileURL)

        let store = JSONHistoryStore(fileURL: fileURL)
        let loaded = try await store.allRecords()
        XCTAssertTrue(loaded.isEmpty)

        // The unreadable bytes were moved aside, not silently overwritten.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("history-corrupt-") })

        // The store is usable again: new records save and read back.
        let record = HistoryRecord(
            inputType: "text",
            inputHash: "abc123",
            verdictKind: .notAvailable,
            confidenceValue: 0,
            evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")]
        )
        try await store.add(record)
        let after = try await store.allRecords()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.inputHash, "abc123")
    }

    func testEmptyStoreReturnsEmpty() async throws {
        let store = try makeStore()
        let loaded = try await store.allRecords()
        XCTAssertTrue(loaded.isEmpty)
    }
}
