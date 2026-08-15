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

    /// How many files are verified at the same time. The tool run is
    /// off-process, so a handful of parallel runs keeps a large folder fast
    /// without hammering the machine.
    private static let maxConcurrentChecks = 8

    public init(c2paToolPath: String = "c2patool", toolTimeout: TimeInterval = 30) {
        self.c2paVerifier = C2PAVerifier(toolPath: c2paToolPath, timeout: toolTimeout)
    }

    public func verifyDirectory(
        at url: URL,
        includeSubdirectories: Bool = true
    ) async throws -> BatchReport {
        // A missing path used to produce a silently empty report card, which
        // read as a successful scan of nothing. Say what is wrong instead.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw FolderVerifierError.directoryNotFound(url.path)
        }

        let walk = try walk(url, includeSubdirectories: includeSubdirectories)

        var verdicts: [FileVerdict] = []
        var failures: [BatchFailure] = []
        var toolMissing = false

        // Verify in bounded parallel chunks. Each file carries its own tool
        // timeout, so a hung file fails by itself; the scan continues with
        // the remaining files. Outcome order is per chunk, and both lists are
        // sorted afterwards, so the report stays deterministic.
        let files = walk.supported
        var index = 0
        while index < files.count {
            let end = min(index + Self.maxConcurrentChecks, files.count)
            let chunk = files[index..<end]
            await withTaskGroup(of: CheckOutcome.self) { group in
                for file in chunk {
                    group.addTask { await self.check(file) }
                }
                for await outcome in group {
                    switch outcome {
                    case .verdict(let verdict):
                        verdicts.append(verdict)
                    case .failure(let fileName, let reason, let missingTool):
                        if missingTool { toolMissing = true }
                        failures.append(BatchFailure(fileName: fileName, reason: reason))
                    }
                }
            }
            index = end
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

    // MARK: - Per-file checking

    /// One file's outcome, shaped so it can cross a task group boundary:
    /// plain Sendable values, no thrown errors.
    private enum CheckOutcome: Sendable {
        case verdict(FileVerdict)
        case failure(fileName: String, reason: String, missingTool: Bool)
    }

    private func check(_ file: URL) async -> CheckOutcome {
        do {
            return .verdict(try await c2paVerifier.verifyFile(at: file))
        } catch let error as C2PAVerifier.VerificationError {
            switch error {
            case .toolUnavailable(let message):
                return .failure(
                    fileName: file.lastPathComponent,
                    reason: message,
                    missingTool: true
                )
            case .toolTimeout(let message):
                // A timeout is a per-file failure, not a missing tool.
                return .failure(
                    fileName: file.lastPathComponent,
                    reason: message,
                    missingTool: false
                )
            case .fileUnreadable(let path):
                return .failure(
                    fileName: file.lastPathComponent,
                    reason: "File could not be read: \(path)",
                    missingTool: false
                )
            }
        } catch {
            return .failure(
                fileName: file.lastPathComponent,
                reason: error.localizedDescription,
                missingTool: false
            )
        }
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

        // A nil enumerator means the directory cannot be listed (permissions,
        // a broken symlink). Report it instead of returning a fake empty scan.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            throw FolderVerifierError.directoryUnreadable(url.path)
        }

        while let file = enumerator.nextObject() as? URL {
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

/// A folder could not be scanned at all. The report card is only produced
/// when the scan actually ran.
public enum FolderVerifierError: Error, Sendable {
    case directoryNotFound(String)
    case directoryUnreadable(String)
}
