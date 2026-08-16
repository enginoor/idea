import Foundation
import Testing
@testable import OriginCheckEngine

@Suite
struct C2PAVerifierTests {
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
            .appendingPathComponent("OriginCheckTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)
        let url = toolDir.appendingPathComponent("c2patool")
        try! script.write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        stubToolURL = url
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

    @Test
    func testSignedIntactVerdict() async throws {
        let url = try makeDummyFile(named: "chart-intact.png")
        let verdict = try await verifier().verifyFile(at: url)
        #expect(verdict.kind == .watermarked)
        #expect(verdict.manifestPresent == true)
        #expect(verdict.signatureValid == true)
        #expect(verdict.modifiedSinceSigning == false)
        #expect(verdict.softwareAgent == "Claude")
        #expect(verdict.signer?.contains("Claude") == true)
        #expect(verdict.confidence.label == .high)
        #expect(verdict.format == "png")
        #expect(!verdict.claims.isEmpty)
        #expect(verdict.claims.first?.action == "c2pa.created")
        #expect(verdict.caveatText.contains("signed by"))
        #expect(!verdict.evidence.isEmpty)
    }

    @Test
    func testSignedModifiedVerdictIsRedAndFactual() async throws {
        let url = try makeDummyFile(named: "photo-modified.jpg")
        let verdict = try await verifier().verifyFile(at: url)
        #expect(verdict.kind == .watermarked)
        #expect(verdict.signatureValid == true)
        #expect(verdict.modifiedSinceSigning == true)
        #expect(verdict.confidence.label == .high)
        #expect(verdict.caveatText.contains("modified after"))
        #expect(!verdict.caveatText.contains("not modified"))
    }

    @Test
    func testUnknownSignerReducesConfidence() async throws {
        let known = try await verifier().verifyFile(at: makeDummyFile(named: "chart-intact.png"))
        let unknown = try await verifier().verifyFile(at: makeDummyFile(named: "mystery-unknown.png"))
        #expect(unknown.kind == .watermarked)
        #expect(unknown.signatureValid == true)
        #expect(unknown.signer?.contains("Unknown") == true)
        #expect(unknown.confidence.label == .moderate)
        #expect(unknown.confidence.value < known.confidence.value)
    }

    @Test
    func testExpiredCertificateIsInconclusive() async throws {
        let url = try makeDummyFile(named: "document-expired.svg")
        let verdict = try await verifier().verifyFile(at: url)
        #expect(verdict.kind == .inconclusive)
        #expect(verdict.signatureValid == false)
        #expect(verdict.confidence.label == .low)
        #expect(verdict.evidence.contains { $0.kind == "signature_validity" })
    }

    @Test
    func testHashMismatchWithoutValidSignatureIsNotReportedAsModification() async throws {
        // A hash mismatch only proves modification when the signature itself
        // verifies. With an expired certificate the manifest cannot be
        // attributed to its signer, so presenting "modified after signing"
        // as a fact would overstate what is provable.
        let url = try makeDummyFile(named: "photo-expired-hash.jpg")
        let verdict = try await verifier().verifyFile(at: url)
        #expect(verdict.kind == .inconclusive)
        #expect(verdict.signatureValid == false)
        #expect(verdict.modifiedSinceSigning == nil)
        #expect(!verdict.evidence.contains { $0.kind == "asset_hash" })
    }

    @Test
    func testNoManifestIsNotWatermarkedWithCaveat() async throws {
        let url = try makeDummyFile(named: "screenshot.png")
        let verdict = try await verifier().verifyFile(at: url)
        #expect(verdict.kind == .notWatermarked)
        #expect(verdict.manifestPresent == false)
        #expect(verdict.signatureValid == nil)
        #expect(verdict.caveatText.contains("does not prove human authorship"))
        #expect(verdict.evidence.contains { $0.kind == "manifest_absent" })
    }

    @Test
    func testVerificationIsDeterministic() async throws {
        let url = try makeDummyFile(named: "chart-intact.png")
        let first = try await verifier().verifyFile(at: url)
        let second = try await verifier().verifyFile(at: url)
        // Evidence items carry freshly generated UUIDs, so compare everything
        // except those ids: the content must be byte-for-byte identical.
        #expect(normalized(first) == normalized(second))
        #expect(first.kind == second.kind)
        #expect(first.confidence == second.confidence)
        #expect(first.signer == second.signer)
        #expect(first.claims == second.claims)
        #expect(first.caveatText == second.caveatText)
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

    @Test
    func testMissingToolThrowsToolUnavailable() async throws {
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool")
        do {
            _ = try await verifier.verifyFile(at: makeDummyFile(named: "chart-intact.png"))
            Issue.record("Expected toolUnavailable error")
        } catch let error as C2PAVerifier.VerificationError {
            if case .toolUnavailable = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func testHungToolTimesOutInsteadOfHangingForever() async throws {
        let url = try makeDummyFile(named: "video-sleepy.mp4")
        let verifier = C2PAVerifier(toolPath: stubToolURL.path, timeout: 1)
        let start = Date()
        do {
            _ = try await verifier.verifyFile(at: url)
            Issue.record("Expected toolTimeout error")
        } catch let error as C2PAVerifier.VerificationError {
            if case .toolTimeout = error {
                // expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        // The stub sleeps 10 seconds; the verifier must return long before
        // that instead of waiting for the tool to finish.
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test
    func testUnknownsNeverIncreaseConfidence() async throws {
        let intact = try await verifier().verifyFile(at: makeDummyFile(named: "chart-intact.png"))
        let expired = try await verifier().verifyFile(at: makeDummyFile(named: "document-expired.svg"))
        let none = try await verifier().verifyFile(at: makeDummyFile(named: "screenshot.png"))
        #expect(intact.confidence.value > expired.confidence.value)
        #expect(intact.confidence.value > none.confidence.value)
    }
}
