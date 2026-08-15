import XCTest
@testable import OriginCheckEngine

final class C2PAVerifierTests: XCTestCase {
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
            .appendingPathComponent("OriginCheckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
        stubToolURL = toolDir.appendingPathComponent("c2patool")
        try script.write(to: stubToolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: stubToolURL.path
        )
    }

    private func makeDummyFile(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginCheckFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data("dummy bytes".utf8).write(to: url)
        return url
    }

    private func verifier() -> C2PAVerifier {
        C2PAVerifier(toolPath: stubToolURL.path)
    }

    func testSignedIntactVerdict() async throws {
        let url = try makeDummyFile(named: "chart-intact.png")
        let verdict = try await verifier().verifyFile(at: url)
        XCTAssertEqual(verdict.kind, .watermarked)
        XCTAssertEqual(verdict.manifestPresent, true)
        XCTAssertEqual(verdict.signatureValid, true)
        XCTAssertEqual(verdict.modifiedSinceSigning, false)
        XCTAssertEqual(verdict.softwareAgent, "Claude")
        XCTAssertTrue(verdict.signer?.contains("Claude") == true)
        XCTAssertEqual(verdict.confidence.label, .high)
        XCTAssertEqual(verdict.format, "png")
        XCTAssertFalse(verdict.claims.isEmpty)
        XCTAssertEqual(verdict.claims.first?.action, "c2pa.created")
        XCTAssertTrue(verdict.caveatText.contains("signed by"))
        XCTAssertFalse(verdict.evidence.isEmpty)
    }

    func testSignedModifiedVerdictIsRedAndFactual() async throws {
        let url = try makeDummyFile(named: "photo-modified.jpg")
        let verdict = try await verifier().verifyFile(at: url)
        XCTAssertEqual(verdict.kind, .watermarked)
        XCTAssertEqual(verdict.signatureValid, true)
        XCTAssertEqual(verdict.modifiedSinceSigning, true)
        XCTAssertEqual(verdict.confidence.label, .high)
        XCTAssertTrue(verdict.caveatText.contains("modified after"))
        XCTAssertFalse(verdict.caveatText.contains("not modified"))
    }

    func testUnknownSignerReducesConfidence() async throws {
        let known = try await verifier().verifyFile(at: makeDummyFile(named: "chart-intact.png"))
        let unknown = try await verifier().verifyFile(at: makeDummyFile(named: "mystery-unknown.png"))
        XCTAssertEqual(unknown.kind, .watermarked)
        XCTAssertEqual(unknown.signatureValid, true)
        XCTAssertTrue(unknown.signer?.contains("Unknown") == true)
        XCTAssertEqual(unknown.confidence.label, .moderate)
        XCTAssertLessThan(unknown.confidence.value, known.confidence.value)
    }

    func testExpiredCertificateIsInconclusive() async throws {
        let url = try makeDummyFile(named: "document-expired.svg")
        let verdict = try await verifier().verifyFile(at: url)
        XCTAssertEqual(verdict.kind, .inconclusive)
        XCTAssertEqual(verdict.signatureValid, false)
        XCTAssertEqual(verdict.confidence.label, .low)
        XCTAssertTrue(verdict.evidence.contains { $0.kind == "signature_validity" })
    }

    func testHashMismatchWithoutValidSignatureIsNotReportedAsModification() async throws {
        // A hash mismatch only proves modification when the signature itself
        // verifies. With an expired certificate the manifest cannot be
        // attributed to its signer, so presenting "modified after signing"
        // as a fact would overstate what is provable.
        let url = try makeDummyFile(named: "photo-expired-hash.jpg")
        let verdict = try await verifier().verifyFile(at: url)
        XCTAssertEqual(verdict.kind, .inconclusive)
        XCTAssertEqual(verdict.signatureValid, false)
        XCTAssertNil(verdict.modifiedSinceSigning)
        XCTAssertFalse(verdict.evidence.contains { $0.kind == "asset_hash" })
    }

    func testNoManifestIsNotWatermarkedWithCaveat() async throws {
        let url = try makeDummyFile(named: "screenshot.png")
        let verdict = try await verifier().verifyFile(at: url)
        XCTAssertEqual(verdict.kind, .notWatermarked)
        XCTAssertEqual(verdict.manifestPresent, false)
        XCTAssertNil(verdict.signatureValid)
        XCTAssertTrue(verdict.caveatText.contains("does not prove human authorship"))
        XCTAssertTrue(verdict.evidence.contains { $0.kind == "manifest_absent" })
    }

    func testVerificationIsDeterministic() async throws {
        let url = try makeDummyFile(named: "chart-intact.png")
        let first = try await verifier().verifyFile(at: url)
        let second = try await verifier().verifyFile(at: url)
        // Evidence items carry freshly generated UUIDs, so compare everything
        // except those ids: the content must be byte-for-byte identical.
        XCTAssertEqual(normalized(first), normalized(second))
        XCTAssertEqual(first.kind, second.kind)
        XCTAssertEqual(first.confidence, second.confidence)
        XCTAssertEqual(first.signer, second.signer)
        XCTAssertEqual(first.claims, second.claims)
        XCTAssertEqual(first.caveatText, second.caveatText)
    }

    private struct EvidenceFingerprint: Equatable {
        let source: String
        let kind: String
        let summary: String
        let detail: String
    }

    private func normalized(_ verdict: FileVerdict) -> [EvidenceFingerprint] {
        verdict.evidence.map {
            EvidenceFingerprint(source: $0.source, kind: $0.kind, summary: $0.summary, detail: $0.detail)
        }
    }

    func testMissingToolThrowsToolUnavailable() async {
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool")
        do {
            _ = try await verifier.verifyFile(at: makeDummyFile(named: "chart-intact.png"))
            XCTFail("Expected toolUnavailable error")
        } catch let error as C2PAVerifier.VerificationError {
            if case .toolUnavailable = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHungToolTimesOutInsteadOfHangingForever() async throws {
        let url = try makeDummyFile(named: "video-sleepy.mp4")
        let verifier = C2PAVerifier(toolPath: stubToolURL.path, timeout: 1)
        let start = Date()
        do {
            _ = try await verifier.verifyFile(at: url)
            XCTFail("Expected toolTimeout error")
        } catch let error as C2PAVerifier.VerificationError {
            if case .toolTimeout = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // The stub sleeps 10 seconds; the verifier must return long before
        // that instead of waiting for the tool to finish.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testUnknownsNeverIncreaseConfidence() async throws {
        let intact = try await verifier().verifyFile(at: makeDummyFile(named: "chart-intact.png"))
        let expired = try await verifier().verifyFile(at: makeDummyFile(named: "document-expired.svg"))
        let none = try await verifier().verifyFile(at: makeDummyFile(named: "screenshot.png"))
        XCTAssertGreaterThan(intact.confidence.value, expired.confidence.value)
        XCTAssertGreaterThan(intact.confidence.value, none.confidence.value)
    }
}
