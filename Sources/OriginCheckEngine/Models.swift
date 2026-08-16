import Foundation

/// The overall shape of a verdict. A positive signal exists, a negative
/// signal does not: no verdict kind here ever claims human authorship.
public enum VerdictKind: String, Codable, Sendable {
    /// A positive signal was found: a watermark or a valid signature.
    case watermarked
    /// No signal was found. This is not evidence of human authorship.
    case notWatermarked
    /// There is not enough input for a reliable signal.
    case insufficientInput
    /// No detector is available for the requested check.
    case notAvailable
    /// Signals conflict or the evidence is weak (unknown signer, bad signature).
    case inconclusive
    /// A folder scan summary. A batch has no single verdict on one piece of
    /// content; the counts live in the record's batchSummary field.
    case batchScan
}

public enum ConfidenceLabel: String, Codable, Sendable {
    case low
    case moderate
    case high
}

public struct Confidence: Codable, Sendable, Equatable {
    public var value: Double
    public var label: ConfidenceLabel

    public init(value: Double, label: ConfidenceLabel) {
        self.value = value
        self.label = label
    }
}

/// A single piece of machine-readable evidence behind a verdict. Every
/// verdict in this product carries at least one evidence item.
public struct EvidenceItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var source: String
    public var kind: String
    public var summary: String
    public var detail: String

    public init(source: String, kind: String, summary: String, detail: String = "") {
        self.id = UUID()
        self.source = source
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

public struct TextVerdict: Codable, Sendable, Equatable {
    public var kind: VerdictKind
    public var confidence: Confidence
    public var characterCount: Int
    public var effectiveTokenEstimate: Int
    public var providersRun: [String]
    public var evidence: [EvidenceItem]
    public var caveatText: String

    public init(
        kind: VerdictKind,
        confidence: Confidence,
        characterCount: Int,
        effectiveTokenEstimate: Int,
        providersRun: [String],
        evidence: [EvidenceItem],
        caveatText: String
    ) {
        self.kind = kind
        self.confidence = confidence
        self.characterCount = characterCount
        self.effectiveTokenEstimate = effectiveTokenEstimate
        self.providersRun = providersRun
        self.evidence = evidence
        self.caveatText = caveatText
    }
}

public struct C2PAClaim: Codable, Sendable, Equatable {
    public var title: String
    public var action: String
    public var softwareAgent: String?
    public var signer: String?
    public var timestamp: Date?

    public init(
        title: String,
        action: String,
        softwareAgent: String? = nil,
        signer: String? = nil,
        timestamp: Date? = nil
    ) {
        self.title = title
        self.action = action
        self.softwareAgent = softwareAgent
        self.signer = signer
        self.timestamp = timestamp
    }
}

public struct FileVerdict: Codable, Sendable, Equatable {
    public var kind: VerdictKind
    public var confidence: Confidence
    public var fileName: String
    public var format: String
    public var manifestPresent: Bool
    public var signatureValid: Bool?
    public var modifiedSinceSigning: Bool?
    public var signer: String?
    public var softwareAgent: String?
    public var claims: [C2PAClaim]
    public var evidence: [EvidenceItem]
    public var caveatText: String

    public init(
        kind: VerdictKind,
        confidence: Confidence,
        fileName: String,
        format: String,
        manifestPresent: Bool,
        signatureValid: Bool?,
        modifiedSinceSigning: Bool?,
        signer: String?,
        softwareAgent: String?,
        claims: [C2PAClaim],
        evidence: [EvidenceItem],
        caveatText: String
    ) {
        self.kind = kind
        self.confidence = confidence
        self.fileName = fileName
        self.format = format
        self.manifestPresent = manifestPresent
        self.signatureValid = signatureValid
        self.modifiedSinceSigning = modifiedSinceSigning
        self.signer = signer
        self.softwareAgent = softwareAgent
        self.claims = claims
        self.evidence = evidence
        self.caveatText = caveatText
    }
}

public struct HistoryRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var inputType: String
    /// The file name for file records (nil for text and folder records).
    /// Optional so older history files without the field still decode.
    public var fileName: String?
    public var inputHash: String
    public var verdictKind: VerdictKind
    public var confidenceValue: Double
    public var evidence: [EvidenceItem]
    public var rawText: String?
    public var fileThumbnailPath: String?
    /// Present only on folder scan records. The summary counts are the
    /// record; the per-file list is deliberately not stored, because a
    /// rescan reproduces it and history would otherwise balloon.
    public var batchSummary: BatchSummary?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        inputType: String,
        inputHash: String,
        verdictKind: VerdictKind,
        confidenceValue: Double,
        evidence: [EvidenceItem],
        fileName: String? = nil,
        rawText: String? = nil,
        fileThumbnailPath: String? = nil,
        batchSummary: BatchSummary? = nil
    ) {
        self.id = id
        self.date = date
        self.inputType = inputType
        self.fileName = fileName
        self.inputHash = inputHash
        self.verdictKind = verdictKind
        self.confidenceValue = confidenceValue
        self.evidence = evidence
        self.rawText = rawText
        self.fileThumbnailPath = fileThumbnailPath
        self.batchSummary = batchSummary
    }
}

public enum ThresholdPreset: String, Codable, Sendable {
    case relaxed
    case balanced
    case strict

    /// Minimum passage length for a reliable text signal.
    public var minimumTextLength: Int {
        switch self {
        case .relaxed: 120
        case .balanced: 200
        case .strict: 300
        }
    }
}

public struct AnalysisOptions: Codable, Sendable, Equatable {
    public var thresholdPreset: ThresholdPreset
    public var localAnalyzerEnabled: Bool
    public var anthropicProviderEnabled: Bool
    public var anthropicAPIKey: String?

    public init(
        thresholdPreset: ThresholdPreset = .balanced,
        localAnalyzerEnabled: Bool = true,
        anthropicProviderEnabled: Bool = false,
        anthropicAPIKey: String? = nil
    ) {
        self.thresholdPreset = thresholdPreset
        self.localAnalyzerEnabled = localAnalyzerEnabled
        self.anthropicProviderEnabled = anthropicProviderEnabled
        self.anthropicAPIKey = anthropicAPIKey
    }
}
