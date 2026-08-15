import Foundation

/// Counts behind a batch scan. The counts are factual: what was found, what
/// was skipped, what failed. No count here is presented as proof of human
/// authorship, because a missing manifest proves nothing by itself.
public struct BatchSummary: Codable, Sendable, Equatable {
    public var totalFiles: Int
    public var supportedFiles: Int
    public var watermarked: Int
    public var noManifest: Int
    public var inconclusive: Int
    public var failed: Int
    public var unsupportedSkipped: Int

    public init(
        totalFiles: Int = 0,
        supportedFiles: Int = 0,
        watermarked: Int = 0,
        noManifest: Int = 0,
        inconclusive: Int = 0,
        failed: Int = 0,
        unsupportedSkipped: Int = 0
    ) {
        self.totalFiles = totalFiles
        self.supportedFiles = supportedFiles
        self.watermarked = watermarked
        self.noManifest = noManifest
        self.inconclusive = inconclusive
        self.failed = failed
        self.unsupportedSkipped = unsupportedSkipped
    }
}

/// A single file that could not be verified. The scan continues past broken
/// files and reports them here instead of failing the whole folder.
public struct BatchFailure: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var fileName: String
    public var reason: String

    public init(fileName: String, reason: String) {
        self.id = UUID()
        self.fileName = fileName
        self.reason = reason
    }
}

/// The result of a folder scan. It holds one verdict per supported file, the
/// failures, and a summary the UI can render as a report card.
public struct BatchReport: Codable, Sendable, Equatable {
    public var directoryName: String
    public var scannedAt: Date
    public var summary: BatchSummary
    public var verdicts: [FileVerdict]
    public var failures: [BatchFailure]
    /// True when the C2PA tool could not be launched, which means no file was
    /// actually verified and every failure shares that cause.
    public var toolMissing: Bool

    public init(
        directoryName: String,
        scannedAt: Date,
        summary: BatchSummary,
        verdicts: [FileVerdict],
        failures: [BatchFailure],
        toolMissing: Bool
    ) {
        self.directoryName = directoryName
        self.scannedAt = scannedAt
        self.summary = summary
        self.verdicts = verdicts
        self.failures = failures
        self.toolMissing = toolMissing
    }

    public var hasFailures: Bool {
        toolMissing || !failures.isEmpty
    }
}

/// Scans a folder of media files and verifies each supported file with
/// c2patool. One broken file does not stop the scan; failures are collected
/// and reported. Hidden files and unsupported extensions are skipped.
public struct FolderVerifier: Sendable {
    public let c2paVerifier: C2PAVerifier

    public init(c2paToolPath: String = "c2patool", toolTimeout: TimeInterval = 30) {
        self.c2paVerifier = C2PAVerifier(toolPath: c2paToolPath, timeout: toolTimeout)
    }

    public func verifyDirectory(
        at url: URL,
        includeSubdirectories: Bool = true
    ) async throws -> BatchReport {
        let walk = try walk(url, includeSubdirectories: includeSubdirectories)

        var verdicts: [FileVerdict] = []
        var failures: [BatchFailure] = []
        var toolMissing = false

        for file in walk.supported {
            do {
                verdicts.append(try await c2paVerifier.verifyFile(at: file))
            } catch let error as C2PAVerifier.VerificationError {
                switch error {
                case .toolUnavailable(let message):
                    toolMissing = true
                    failures.append(BatchFailure(fileName: file.lastPathComponent, reason: message))
                case .toolTimeout(let message):
                    // A timeout is a per-file failure, not a missing tool:
                    // the scan continues with the remaining files.
                    failures.append(BatchFailure(fileName: file.lastPathComponent, reason: message))
                case .fileUnreadable(let path):
                    failures.append(BatchFailure(
                        fileName: file.lastPathComponent,
                        reason: "File could not be read: \(path)"
                    ))
                }
            } catch {
                failures.append(BatchFailure(
                    fileName: file.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        verdicts.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        failures.sort { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }

        let summary = BatchSummary(
            totalFiles: walk.supported.count + walk.unsupportedCount,
            supportedFiles: walk.supported.count,
            watermarked: verdicts.filter { $0.kind == .watermarked }.count,
            noManifest: verdicts.filter { $0.kind == .notWatermarked }.count,
            inconclusive: verdicts.filter { $0.kind == .inconclusive }.count,
            failed: failures.count,
            unsupportedSkipped: walk.unsupportedCount
        )

        return BatchReport(
            directoryName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            scannedAt: Date(),
            summary: summary,
            verdicts: verdicts,
            failures: failures,
            toolMissing: toolMissing
        )
    }

    // MARK: - Walking

    private struct WalkResult {
        var supported: [URL]
        var unsupportedCount: Int
    }

    private func walk(_ url: URL, includeSubdirectories: Bool) throws -> WalkResult {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !includeSubdirectories {
            options.insert(.skipsSubdirectoryDescendants)
        }

        var supported: [URL] = []
        var unsupportedCount = 0
        let keys: [URLResourceKey] = [.isRegularFileKey]

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        )

        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if MediaFormat.isSupported(pathExtension: file.pathExtension) {
                supported.append(file)
            } else {
                unsupportedCount += 1
            }
        }

        supported.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return WalkResult(supported: supported, unsupportedCount: unsupportedCount)
    }
}
