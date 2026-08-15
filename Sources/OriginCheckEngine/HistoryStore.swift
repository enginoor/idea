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
        return try decoder.decode([HistoryRecord].self, from: data)
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
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            hash = SHA256.hashData(data)
        } else {
            hash = SHA256.hashString(verdict.fileName)
        }
        return HistoryRecord(
            inputType: "file",
            inputHash: hash,
            verdictKind: verdict.kind,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            rawText: nil,
            fileThumbnailPath: storeRawContent ? fileURL?.path : nil
        )
    }
}
