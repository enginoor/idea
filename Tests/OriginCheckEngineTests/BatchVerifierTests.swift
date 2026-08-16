import Foundation
import Testing
@testable import OriginCheckEngine

@Suite
struct BatchVerifierTests {
    private let stubToolURL: URL
    private let fixturesDir: URL

    // Swift Testing creates a fresh instance of the suite for each test, so
    // building the stub here gives the same per-test isolation XCTest's
    // setUp provided.
    init() {
        let testFile = URL(fileURLWithPath: #filePath)
        fixturesDir = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("c2pa")

        let intact = fixturesDir.appendingPathComponent("signed-intact.json").path
        let modified = fixturesDir.appendingPathComponent("signed-modified.json").path
        let unknown = fixturesDir.appendingPathComponent("unknown-signer.json").path
        let expired = fixturesDir.appendingPathComponent("expired-cert.json").path
        let expiredHash = fixturesDir.appendingPathComponent("expired-hash-mismatch.json").path

        let script = """
        #!/bin/bash
        case "$(basename "$1")" in
          *intact*) cat "\(intact)" ;;
          *modified*) cat "\(modified)" ;;
          *unknown*) cat "\(unknown)" ;;
          *expired-hash*) cat "\(expiredHash)" ;;
          *expired*) cat "\(expired)" ;;
          *sleepy*) while :; do :; done ;;
          *) echo "No C2PA manifest found." >&2; exit 1 ;;
        esac
        """

        let toolDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckBatchTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
        let url = toolDir.appendingPathComponent("c2patool")
        try! script.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        stubToolURL = url
    }

    /// Builds a representative folder:
    /// 8 supported files across formats, 1 unsupported text file, 1 hidden
    /// supported file, and a subfolder with another supported file.
    private func makeSampleFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let names = [
            "banner-intact.webp",
            "chart-intact.png",
            "document-expired.pdf",
            "motion-intact.mov",
            "notes.txt",
            "photo-modified.jpg",
            "screenshot.png",
            "video-intact.mp4",
            ".hidden-intact.png",
        ]
        for name in names {
            try Data("dummy bytes".utf8).write(to: root.appendingPathComponent(name))
        }

        let assets = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("dummy bytes".utf8).write(to: assets.appendingPathComponent("logo-intact.svg"))

        return root
    }

    private func verifier() -> FolderVerifier {
        FolderVerifier(c2paToolPath: stubToolURL.path)
    }

    @Test
    func testBatchScanClassifiesEverySupportedFile() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root)

        #expect(report.summary.totalFiles == 9)
        #expect(report.summary.supportedFiles == 8)
        #expect(report.summary.watermarked == 6)
        #expect(report.summary.noManifest == 1)
        #expect(report.summary.inconclusive == 1)
        #expect(report.summary.failed == 0)
        #expect(report.summary.unsupportedSkipped == 1)
        #expect(!report.toolMissing)
        #expect(!report.hasFailures)
        #expect(report.verdicts.count == 8)

        let formats = Set(report.verdicts.map(\.format))
        #expect(formats.contains("webp"))
        #expect(formats.contains("png"))
        #expect(formats.contains("jpg"))
        #expect(formats.contains("mp4"))
        #expect(formats.contains("mov"))
        #expect(formats.contains("svg"))
        #expect(formats.contains("pdf"))
    }

    @Test
    func testBatchScanSkipsHiddenFiles() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root)

        #expect(!report.verdicts.contains { $0.fileName == ".hidden-intact.png" })
        #expect(!report.failures.contains { $0.fileName == ".hidden-intact.png" })
        #expect(report.summary.totalFiles == 9, "The hidden file must not be counted")
    }

    @Test
    func testBatchScanWithoutSubdirectories() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root, includeSubdirectories: false)

        #expect(report.summary.supportedFiles == 7)
        #expect(report.summary.watermarked == 5)
        #expect(report.summary.totalFiles == 8)
        #expect(!report.verdicts.contains { $0.fileName == "logo-intact.svg" })
    }

    @Test
    func testBatchScanIsDeterministic() async throws {
        let root = try makeSampleFolder()
        let first = try await verifier().verifyDirectory(at: root)
        let second = try await verifier().verifyDirectory(at: root)

        #expect(first.summary == second.summary)
        #expect(first.verdicts.map(\.fileName) == second.verdicts.map(\.fileName))
        #expect(first.verdicts.map(\.format) == second.verdicts.map(\.format))
        #expect(first.verdicts.map(\.kind) == second.verdicts.map(\.kind))
    }

    @Test
    func testToolTimeoutIsAPerFileFailureNotToolMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("dummy bytes".utf8).write(to: root.appendingPathComponent("video-sleepy.mp4"))

        let report = try await FolderVerifier(c2paToolPath: stubToolURL.path, toolTimeout: 1)
            .verifyDirectory(at: root)

        #expect(!report.toolMissing)
        #expect(report.summary.failed == 1)
        #expect(report.verdicts.count == 0)
        #expect(report.failures.allSatisfy { $0.reason.contains("timed out") })
    }

    @Test
    func testMissingToolMarksEveryFileFailed() async throws {
        let root = try makeSampleFolder()
        let report = try await FolderVerifier(c2paToolPath: "/nonexistent/c2patool")
            .verifyDirectory(at: root)

        #expect(report.toolMissing)
        #expect(report.hasFailures)
        #expect(report.summary.failed == report.summary.supportedFiles)
        #expect(report.verdicts.count == 0)
        #expect(report.failures.allSatisfy { $0.reason.contains("Could not launch") })
    }

    @Test
    func testMissingDirectoryThrowsInsteadOfEmptyReport() async {
        // A nonexistent path used to scan as an empty report card, which
        // read as a successful scan of nothing. It must fail loudly.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckMissing-\(UUID().uuidString)")
        do {
            _ = try await verifier().verifyDirectory(at: missing)
            Issue.record("Expected directoryNotFound for a missing path")
        } catch let error as FolderVerifierError {
            if case .directoryNotFound = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func testFilePathInsteadOfDirectoryThrows() async throws {
        // Pointing the scan at a regular file must not be treated as an
        // empty directory either.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckNotADir-\(UUID().uuidString).png")
        try Data("dummy bytes".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await verifier().verifyDirectory(at: file)
            Issue.record("Expected directoryNotFound for a file path")
        } catch let error as FolderVerifierError {
            if case .directoryNotFound = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
