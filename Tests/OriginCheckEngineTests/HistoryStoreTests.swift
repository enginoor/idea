import Foundation
import Testing
@testable import OriginCheckEngine

@Suite
struct HistoryStoreTests {
    private func makeStore() throws -> JSONHistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return JSONHistoryStore(fileURL: dir.appendingPathComponent("history.json"))
    }

    @Test
    func testSHA256KnownVectors() {
        #expect(
            SHA256.hashString("abc") ==
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(
            SHA256.hashString("") ==
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            SHA256.hashString("The quick brown fox jumps over the lazy dog") ==
                "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        )
    }

    @Test
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
        #expect(try SHA256.hashFile(at: url) == SHA256.hashData(data))
    }

    @Test
    func testHashFileEmptyFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("empty.bin")
        try Data().write(to: url)
        #expect(try SHA256.hashFile(at: url) == SHA256.hashData(Data()))
    }

    @Test
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
        #expect(hash == SHA256.hashData(Data(bytes)))
        #expect(
            Date().timeIntervalSince(start) < 5.0,
            "Hashing 8 MiB must complete quickly, not quadratically"
        )
    }

    @Test
    func testFileRecordHashesContentNotName() throws {
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
        #expect(record.inputHash == SHA256.hashData(content))
        #expect(record.inputHash != SHA256.hashString(verdict.fileName))
        #expect(record.fileThumbnailPath == nil)
    }

    @Test
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
        #expect(loaded.count == 2)
        #expect(loaded.first?.verdictKind == .watermarked)

        try await store.delete(id: first.id)
        let afterDelete = try await store.allRecords()
        #expect(afterDelete.count == 1)
        #expect(afterDelete.first?.inputType == "file")

        try await store.deleteAll()
        let afterClear = try await store.allRecords()
        #expect(afterClear.isEmpty)
    }

    @Test
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
        #expect(loaded.count == 1)
        #expect(loaded.first?.rawText == nil)

        // The persisted JSON must not contain the raw text either.
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let fileURL = storeDir.appendingPathComponent("history.json")
        let explicit = JSONHistoryStore(fileURL: fileURL)
        try await explicit.add(record)
        let json = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!json.contains("private essay"))
    }

    @Test
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
        #expect(loaded.first?.rawText == "Essay the user consented to keep.")
    }

    @Test
    func testCorruptHistoryFileIsQuarantinedNotFatal() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("history.json")
        try Data("this is not JSON history".utf8).write(to: fileURL)

        let store = JSONHistoryStore(fileURL: fileURL)
        let loaded = try await store.allRecords()
        #expect(loaded.isEmpty)

        // The unreadable bytes were moved aside, not silently overwritten.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("history-corrupt-") })

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
        #expect(after.count == 1)
        #expect(after.first?.inputHash == "abc123")
    }

    @Test
    func testEmptyStoreReturnsEmpty() async throws {
        let store = try makeStore()
        let loaded = try await store.allRecords()
        #expect(loaded.isEmpty)
    }

    @Test
    func testBatchRecordSummarizesFolderScanAndRoundTrips() async throws {
        let store = try makeStore()
        let summary = BatchSummary(
            totalFiles: 200,
            supportedFiles: 150,
            watermarked: 12,
            noManifest: 130,
            inconclusive: 5,
            failed: 3,
            unsupportedSkipped: 50
        )
        let report = BatchReport(
            directoryName: "Photos",
            scannedAt: Date(),
            summary: summary,
            verdicts: [],
            failures: [],
            toolMissing: false
        )

        let record = HistoryRecorder.record(forBatchReport: report, directoryPath: "/Users/test/Photos")
        #expect(record.verdictKind == .batchScan)
        #expect(record.inputType == "folder")
        #expect(record.batchSummary == summary)
        #expect(record.confidenceValue == 0, "A scan has counts, not a confidence percentage")
        #expect(record.rawText == nil)
        #expect(!record.evidence.isEmpty)
        #expect(record.inputHash == SHA256.hashString("/Users/test/Photos"))

        // The record must survive a real store round trip, which exercises
        // encoding of the new verdict kind and the batchSummary field.
        try await store.add(record)
        let loaded = try await store.allRecords()
        #expect(loaded.count == 1)
        #expect(loaded.first?.verdictKind == .batchScan)
        #expect(loaded.first?.batchSummary == summary)
        #expect(loaded.first?.inputType == "folder")
    }

    @Test
    func testBatchRecordMentionsMissingTool() {
        let report = BatchReport(
            directoryName: "Photos",
            scannedAt: Date(),
            summary: BatchSummary(totalFiles: 3, supportedFiles: 3, failed: 3),
            verdicts: [],
            failures: [],
            toolMissing: true
        )
        let record = HistoryRecorder.record(forBatchReport: report, directoryPath: "/Users/test/Photos")
        #expect(record.verdictKind == .batchScan)
        #expect(record.evidence.contains { $0.kind == "tool_missing" })
    }

    @Test
    func testHistoryRecordWithoutBatchSummaryStillDecodes() async throws {
        // Records written by earlier app versions have no batchSummary key.
        // The optional field must decode as nil; one old record must not
        // break the whole history file.
        let store = try makeStore()
        let record = HistoryRecord(
            inputType: "text",
            inputHash: "abc123",
            verdictKind: .watermarked,
            confidenceValue: 0.9,
            evidence: [EvidenceItem(source: "Test", kind: "fixture", summary: "A record.")]
        )
        try await store.add(record)

        let loaded = try await store.allRecords()
        #expect(loaded.count == 1)
        #expect(loaded.first?.verdictKind == .watermarked)
        #expect(loaded.first?.batchSummary == nil)
    }
}
