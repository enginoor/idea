import XCTest
@testable import OriginCheckEngine

final class BatchVerifierTests: XCTestCase {
    private var stubToolURL: URL!
    private var fixturesDir: URL!

    override func setUpWithError() throws {
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
        try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
        stubToolURL = toolDir.appendingPathComponent("c2patool")
        try script.write(to: stubToolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stubToolURL.path
        )
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

    func testBatchScanClassifiesEverySupportedFile() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root)

        XCTAssertEqual(report.summary.totalFiles, 9)
        XCTAssertEqual(report.summary.supportedFiles, 8)
        XCTAssertEqual(report.summary.watermarked, 6)
        XCTAssertEqual(report.summary.noManifest, 1)
        XCTAssertEqual(report.summary.inconclusive, 1)
        XCTAssertEqual(report.summary.failed, 0)
        XCTAssertEqual(report.summary.unsupportedSkipped, 1)
        XCTAssertFalse(report.toolMissing)
        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.verdicts.count, 8)

        let formats = Set(report.verdicts.map(\.format))
        XCTAssertTrue(formats.contains("webp"))
        XCTAssertTrue(formats.contains("png"))
        XCTAssertTrue(formats.contains("jpg"))
        XCTAssertTrue(formats.contains("mp4"))
        XCTAssertTrue(formats.contains("mov"))
        XCTAssertTrue(formats.contains("svg"))
        XCTAssertTrue(formats.contains("pdf"))
    }

    func testBatchScanSkipsHiddenFiles() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root)

        XCTAssertFalse(report.verdicts.contains { $0.fileName == ".hidden-intact.png" })
        XCTAssertFalse(report.failures.contains { $0.fileName == ".hidden-intact.png" })
        XCTAssertEqual(report.summary.totalFiles, 9, "The hidden file must not be counted")
    }

    func testBatchScanWithoutSubdirectories() async throws {
        let root = try makeSampleFolder()
        let report = try await verifier().verifyDirectory(at: root, includeSubdirectories: false)

        XCTAssertEqual(report.summary.supportedFiles, 7)
        XCTAssertEqual(report.summary.watermarked, 5)
        XCTAssertEqual(report.summary.totalFiles, 8)
        XCTAssertFalse(report.verdicts.contains { $0.fileName == "logo-intact.svg" })
    }

    func testBatchScanIsDeterministic() async throws {
        let root = try makeSampleFolder()
        let first = try await verifier().verifyDirectory(at: root)
        let second = try await verifier().verifyDirectory(at: root)

        XCTAssertEqual(first.summary, second.summary)
        XCTAssertEqual(first.verdicts.map(\.fileName), second.verdicts.map(\.fileName))
        XCTAssertEqual(first.verdicts.map(\.format), second.verdicts.map(\.format))
        XCTAssertEqual(first.verdicts.map(\.kind), second.verdicts.map(\.kind))
    }

    func testToolTimeoutIsAPerFileFailureNotToolMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("dummy bytes".utf8).write(to: root.appendingPathComponent("video-sleepy.mp4"))

        let report = try await FolderVerifier(c2paToolPath: stubToolURL.path, toolTimeout: 1)
            .verifyDirectory(at: root)

        XCTAssertFalse(report.toolMissing)
        XCTAssertEqual(report.summary.failed, 1)
        XCTAssertEqual(report.verdicts.count, 0)
        XCTAssertTrue(report.failures.allSatisfy { $0.reason.contains("timed out") })
    }

    func testMissingToolMarksEveryFileFailed() async throws {
        let root = try makeSampleFolder()
        let report = try await FolderVerifier(c2paToolPath: "/nonexistent/c2patool")
            .verifyDirectory(at: root)

        XCTAssertTrue(report.toolMissing)
        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.summary.failed, report.summary.supportedFiles)
        XCTAssertEqual(report.verdicts.count, 0)
        XCTAssertTrue(report.failures.allSatisfy { $0.reason.contains("Could not launch") })
    }
}
