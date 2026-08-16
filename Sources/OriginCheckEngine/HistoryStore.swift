import Foundation

public protocol HistoryStoring: Sendable {
    func add(_ record: HistoryRecord) async throws
    func allRecords() async throws -> [HistoryRecord]
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

/// A file-backed history store. Records persist as JSON in the app container.
/// Raw content is stored only when the user explicitly consents per record;
/// by default only a SHA-256 hash of the input is kept.
public actor JSONHistoryStore: HistoryStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func add(_ record: HistoryRecord) async throws {
        var records = try load()
        records.append(record)
        try save(records)
    }

    public func allRecords() async throws -> [HistoryRecord] {
        try load()
    }

    public func delete(id: UUID) async throws {
        let records = try load().filter { $0.id != id }
        try save(records)
    }

    public func deleteAll() async throws {
        try save([])
    }

    private func load() throws -> [HistoryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode([HistoryRecord].self, from: data)
        } catch {
            // The file cannot be decoded as history. Quarantine the bytes so
            // the evidence is not silently overwritten, then start fresh:
            // one corrupt record must not brick every later add or delete.
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            return []
        }
    }

    private func save(_ records: [HistoryRecord]) throws {
        let data = try encoder.encode(records)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum HistoryRecorder {
    public static func record(
        forTextVerdict verdict: TextVerdict,
        rawText: String?,
        storeRawText: Bool
    ) -> HistoryRecord {
        HistoryRecord(
            inputType: "text",
            inputHash: SHA256.hashString(rawText ?? ""),
            verdictKind: verdict.kind,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            rawText: storeRawText ? rawText : nil
        )
    }

    public static func record(
        forFileVerdict verdict: FileVerdict,
        fileURL: URL?,
        storeRawContent: Bool
    ) -> HistoryRecord {
        let hash: String
        if let fileURL {
            // Stream the file so a large video is never loaded into memory
            // just to hash it. Falls back to a name hash when unreadable.
            hash = (try? SHA256.hashFile(at: fileURL)) ?? SHA256.hashString(verdict.fileName)
        } else {
            hash = SHA256.hashString(verdict.fileName)
        }
        return HistoryRecord(
            inputType: "file",
            inputHash: hash,
            verdictKind: verdict.kind,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            fileName: verdict.fileName,
            rawText: nil,
            fileThumbnailPath: storeRawContent ? fileURL?.path : nil
        )
    }

    /// A folder scan is a record of counts, not a single verdict: the kind
    /// is .batchScan and the summary is kept in the record. The per-file
    /// verdict list is not stored (a rescan reproduces it), and no file
    /// contents ever are. The hash identifies the scanned location so the
    /// same folder can be found again; it is a path hash, not a content hash.
    public static func record(
        forBatchReport report: BatchReport,
        directoryPath: String
    ) -> HistoryRecord {
        let summary = report.summary
        var evidence: [EvidenceItem] = [
            EvidenceItem(
                source: "Folder scan",
                kind: "scan",
                summary: "Scanned \(report.directoryName): \(summary.totalFiles) files, "
                    + "\(summary.supportedFiles) supported, \(summary.unsupportedSkipped) skipped."
            ),
            EvidenceItem(source: "Folder scan", kind: "count", summary: "Watermarked: \(summary.watermarked)"),
            EvidenceItem(source: "Folder scan", kind: "count", summary: "No manifest: \(summary.noManifest)"),
            EvidenceItem(source: "Folder scan", kind: "count", summary: "Inconclusive: \(summary.inconclusive)"),
            EvidenceItem(source: "Folder scan", kind: "count", summary: "Failed: \(summary.failed)"),
        ]
        if report.toolMissing {
            evidence.append(EvidenceItem(
                source: "Folder scan",
                kind: "tool_missing",
                summary: "c2patool could not be launched; no file was actually verified."
            ))
        }
        return HistoryRecord(
            inputType: "folder",
            inputHash: SHA256.hashString(directoryPath),
            verdictKind: .batchScan,
            confidenceValue: 0,
            evidence: evidence,
            batchSummary: summary
        )
    }
}
