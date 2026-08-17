import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Verifies C2PA manifests in media files by running the reference
/// `c2patool` command line tool and parsing its JSON output.
///
/// The tool path is injectable so tests can use a stub. The parser is
/// deliberately lenient: anything it cannot parse is reported as no manifest,
/// never as a verdict on authorship.
public struct C2PAVerifier: Sendable {
    public let toolPath: String

    /// How long the tool may run before it is terminated and the check fails.
    /// A hung tool (a malformed file, a slow network volume) must not leave
    /// the app stuck in an analyzing state forever.
    public let timeout: TimeInterval

    /// When true (default), PNG, JPEG, SVG, and WebP files are verified by
    /// the built-in readers when c2patool is not installed, so provenance
    /// works out of the box for the most common formats. The built-in path
    /// reads the signing certificate and algorithm from the embedded
    /// signature; the tool still wins when it is available because it
    /// validates the signature math, certificate chains, and content hashes,
    /// which the built-in verifier does not.
    public let bundledReaderEnabled: Bool

    public init(
        toolPath: String = "c2patool",
        timeout: TimeInterval = 30,
        bundledReaderEnabled: Bool = true
    ) {
        self.toolPath = toolPath
        self.timeout = timeout
        self.bundledReaderEnabled = bundledReaderEnabled
    }

    /// True when the configured tool path names an executable: an absolute
    /// or relative path is checked directly, a bare name is resolved against
    /// PATH. Cheap and synchronous, so the verifier can decide between the
    /// tool and the bundled reader without launching a process.
    public static func toolIsReachable(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded)
        }
        guard let pathValue = getenv("PATH") else { return false }
        let dirs = String(cString: pathValue).split(separator: ":").map(String.init)
        return dirs.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + expanded) }
    }

    public enum VerificationError: Error, Sendable {
        case fileUnreadable(String)
        case toolUnavailable(String)
        case toolTimeout(String)
    }

    public func verifyFile(at url: URL) async throws -> FileVerdict {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VerificationError.fileUnreadable(url.path)
        }
        let fileName = url.lastPathComponent
        let format = url.pathExtension.lowercased()

        // Self-contained path: when c2patool is missing, the formats the
        // built-in readers cover are still checked, so the app works out of
        // the box for the most common AI-image formats (PNG, JPEG, SVG, and
        // WebP). The signer identity is read from the embedded signature;
        // the signature math, certificate chain trust, and content hashes
        // are not checked, and the verdict says so.
        if bundledReaderEnabled, StandaloneC2PAReader.supportedExtensions.contains(format),
           !Self.toolIsReachable(toolPath) {
            return try await bundledVerdict(for: url, fileName: fileName, format: format)
        }

        // The tool run blocks while it waits for the process to exit, so it
        // runs on a detached thread: the caller (often the main actor) never
        // freezes while a large file is being verified.
        let output = try await Task.detached(priority: .userInitiated) {
            try await self.runTool(arguments: [url.path])
        }.value

        guard
            let data = output.stdout.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(ManifestEnvelope.self, from: data),
            let manifest = envelope.activeManifestEntry ?? envelope.manifests?.values.first
        else {
            return noManifestVerdict(
                fileName: fileName,
                format: format,
                toolOutput: output
            )
        }

        return verdict(
            for: url,
            envelope: envelope,
            manifest: manifest,
            fileName: fileName,
            format: format,
            toolOutput: output,
            verifierDescription: toolPath
        )
    }

    /// The no-tool-needed path. Provenance presence, the generating tool,
    /// and claims are read from the manifest store; the signing certificate
    /// and algorithm are read from the embedded signature. Signature math,
    /// certificate chain trust, and the file content hash are not checked,
    /// and the verdict says so.
    private func bundledVerdict(
        for url: URL,
        fileName: String,
        format: String
    ) async throws -> FileVerdict {
        let toolOutput = ToolOutput(
            stdout: "",
            stderr: "",
            exitCode: 0
        )
        guard
            let manifest = try? StandaloneC2PAReader().extractManifest(at: url),
            let data = manifest.storeJSON.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(ManifestEnvelope.self, from: data),
            let entry = envelope.activeManifestEntry ?? envelope.manifests?.values.first
        else {
            return noManifestVerdict(
                fileName: fileName,
                format: format,
                toolOutput: toolOutput,
                verifierDescription: "the built-in reader (no c2patool needed)"
            )
        }
        let signatureInfo = C2PASignatureReader().read(
            storeJSON: manifest.storeJSON,
            jumbfData: manifest.jumbfData
        )
        return verdict(
            for: url,
            envelope: envelope,
            manifest: entry,
            fileName: fileName,
            format: format,
            toolOutput: toolOutput,
            verifierDescription: "the built-in reader (no c2patool needed)",
            bundledSignatureInfo: signatureInfo
        )
    }

    // MARK: - Tool execution

    /// Runs the tool, retrying the launch once. Concurrent process launches
    /// on Linux can transiently fail with an EAGAIN-class error (Foundation
    /// reports it as NSCocoaErrorDomain 256), which would otherwise turn a
    /// working check into a false tool-missing verdict. A genuinely bad tool
    /// path fails both attempts and surfaces the error; a tool that starts
    /// but times out is never retried.
    private func runTool(arguments: [String]) async throws -> ToolOutput {
        do {
            return try await runToolOnce(arguments: arguments)
        } catch let error as VerificationError {
            if case .toolUnavailable = error {
                try await Task.sleep(nanoseconds: 50_000_000)
                return try await runToolOnce(arguments: arguments)
            }
            throw error
        }
    }

    /// Runs the tool exactly once.
    private func runToolOnce(arguments: [String]) async throws -> ToolOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw VerificationError.toolUnavailable(
                "Could not launch \(toolPath): \(error.localizedDescription). "
                    + "Install c2patool (cargo install c2patool) or check the tool path."
            )
        }

        // Drain both pipes on background threads while the tool runs. Reading
        // only after waitUntilExit can deadlock when a manifest is large
        // enough to fill the pipe buffer and the tool blocks writing to it.
        let outBox = FileHandleBox(outPipe.fileHandleForReading)
        let errBox = FileHandleBox(errPipe.fileHandleForReading)
        let outRead = Task.detached { () -> Data in
            (try? outBox.handle.readToEnd()) ?? Data()
        }
        let errRead = Task.detached { () -> Data in
            (try? errBox.handle.readToEnd()) ?? Data()
        }

        // Wait with a deadline. A stuck tool must fail the check, not leave
        // the caller waiting forever. terminate() sends SIGTERM, which some
        // Foundation/Linux contexts can fail to deliver, so when the process
        // is still alive shortly after, escalate to SIGKILL and reap it.
        // The drain tasks are deliberately not awaited on this path: a
        // grandchild holding the pipe could keep readToEnd blocked long
        // after the direct child died. They finish on their own once the
        // pipe closes.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                let reapDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < reapDeadline {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                throw VerificationError.toolTimeout(
                    "Verification timed out after \(Int(timeout)) seconds. "
                        + "The tool may be stuck on this file or the volume may be slow: \(toolPath)"
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        process.waitUntilExit()

        let outData = await outRead.value
        let errData = await errRead.value
        return ToolOutput(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private struct ToolOutput {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    /// Lets a non-Sendable FileHandle cross into a detached drain task. Each
    /// handle is used by exactly one reader task, so this opts out of the
    /// sendability check rather than sharing state unsafely.
    private final class FileHandleBox: @unchecked Sendable {
        let handle: FileHandle
        init(_ handle: FileHandle) {
            self.handle = handle
        }
    }

    // MARK: - Manifest mapping

    private func verdict(
        for url: URL,
        envelope: ManifestEnvelope,
        manifest: ManifestEntry,
        fileName: String,
        format: String,
        toolOutput: ToolOutput,
        verifierDescription: String,
        bundledSignatureInfo: C2PASignatureInfo? = nil
    ) -> FileVerdict {
        var evidence: [EvidenceItem] = [
            EvidenceItem(
                source: "C2PA",
                kind: "tool_run",
                summary: "Verified with \(verifierDescription).",
                detail: "Exit code \(toolOutput.exitCode)."
            ),
            EvidenceItem(
                source: "C2PA",
                kind: "manifest_present",
                summary: "A C2PA manifest was found in the file.",
                detail: "Active manifest: \(envelope.active_manifest ?? "unknown")"
            ),
        ]

        var signer = displayName(from: manifest.signature_info?.issuer)
        if let bundledSigner = bundledSignatureInfo?.signer, !bundledSigner.isEmpty {
            signer = bundledSigner
        }
        let softwareAgent = softwareAgentName(from: manifest)
        // The bundled path verifies the Ed25519 claim signature itself when
        // it can; the tool path reads the validation status c2patool
        // reported. Either way the verdict sees one truth value.
        let signatureValid: Bool?
        if let bundled = bundledSignatureInfo?.signatureValid {
            signatureValid = bundled
        } else {
            signatureValid = signatureState(manifest.validation_status)
        }
        let modified = modificationState(manifest.validation_status, signatureValid: signatureValid)
        let claims = claims(from: manifest, signer: signer)

        if let signer {
            evidence.append(EvidenceItem(source: "C2PA", kind: "signer", summary: "Signing entity: \(signer)."))
        }
        if let softwareAgent {
            evidence.append(EvidenceItem(source: "C2PA", kind: "software_agent", summary: "Processing tool: \(softwareAgent)."))
        }
        if let bundledSignatureInfo {
            appendBundledSignatureEvidence(bundledSignatureInfo, to: &evidence)
        } else if let signatureValid {
            evidence.append(EvidenceItem(
                source: "C2PA",
                kind: "signature_validity",
                summary: signatureValid ? "Signature is valid." : "Signature is invalid or expired.",
                detail: manifest.validation_status?.map { $0.code ?? "" }.joined(separator: ", ") ?? ""
            ))
        } else {
            evidence.append(EvidenceItem(
                source: "C2PA",
                kind: "signature_unverifiable",
                summary: "No validation status was reported for the signature.",
                detail: "The manifest exists but its signature could not be verified with the available output."
            ))
        }
        if let modified {
            evidence.append(EvidenceItem(
                source: "C2PA",
                kind: "asset_hash",
                summary: modified ? "The file was modified after signing." : "The file matches the signed content."
            ))
        }

        let unknownSigner = signer == nil || signer!.localizedCaseInsensitiveContains("unknown")

        let kind: VerdictKind
        let confidence: Confidence
        switch signatureValid {
        case .some(true):
            kind = .watermarked
            if modified == true {
                confidence = ConfidenceRules.confidence(ConfidenceRules.validSignatureModified)
            } else {
                confidence = ConfidenceRules.confidence(
                    unknownSigner
                        ? ConfidenceRules.validSignatureUnknownSigner
                        : ConfidenceRules.validSignatureKnownSigner
                )
            }
        case .some(false):
            kind = .inconclusive
            confidence = ConfidenceRules.confidence(ConfidenceRules.invalidSignature)
        case nil:
            kind = .inconclusive
            confidence = ConfidenceRules.confidence(ConfidenceRules.unverifiableSignature)
        }

        let caveat: String
        if signatureValid == true && modified == true {
            caveat = Caveats.fileModified(tool: softwareAgent)
        } else if signatureValid == true, bundledSignatureInfo != nil, modified == nil {
            // The bundled verifier proved the claim signature but cannot
            // recompute the file content hash, so the wording must not
            // claim the file is unchanged since signing.
            caveat = Caveats.fileValidClaimOnly(signer: signer, tool: softwareAgent)
        } else if signatureValid == true {
            caveat = Caveats.fileValid(signer: signer, tool: softwareAgent)
        } else {
            caveat = Caveats.general
        }

        return FileVerdict(
            kind: kind,
            confidence: confidence,
            fileName: fileName,
            format: format,
            manifestPresent: true,
            signatureValid: signatureValid,
            modifiedSinceSigning: modified,
            signer: signer,
            softwareAgent: softwareAgent,
            claims: claims,
            evidence: evidence,
            caveatText: caveat
        )
    }

    private func appendBundledSignatureEvidence(
        _ info: C2PASignatureInfo,
        to evidence: inout [EvidenceItem]
    ) {
        if info.present {
            var summary = "The manifest carries a signature"
            if let signer = info.signer {
                summary += " issued to \(signer)"
            }
            summary += "."
            var detail = "Algorithm: \(info.algorithm ?? "unknown")."
            if let issuer = info.issuer {
                detail += " Issuer: \(issuer)."
            }
            if let notAfter = info.certNotAfter {
                detail += " Certificate valid until \(Self.shortDate(notAfter))."
            }
            if let valid = info.signatureValid {
                detail += valid
                    ? " The Ed25519 claim signature verifies with the built-in verifier. The file content hash and certificate chain are not checked without c2patool."
                    : " The Ed25519 claim signature did not verify with the built-in verifier."
            } else {
                detail += " This signature could not be verified with the built-in verifier (unsupported algorithm or missing certificate)."
            }
            evidence.append(EvidenceItem(
                source: "C2PA",
                kind: "signature_present",
                summary: summary,
                detail: detail
            ))
        } else {
            evidence.append(EvidenceItem(
                source: "C2PA",
                kind: "signature_unverifiable",
                summary: "No signature data was found in the manifest.",
                detail: "The manifest exists but carries no readable COSE signature."
            ))
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func noManifestVerdict(
        fileName: String,
        format: String,
        toolOutput: ToolOutput,
        verifierDescription: String = "c2patool"
    ) -> FileVerdict {
        let evidence: [EvidenceItem] = [
            EvidenceItem(
                source: "C2PA",
                kind: "tool_run",
                summary: "Verified with \(verifierDescription).",
                detail: "Exit code \(toolOutput.exitCode)."
            ),
            EvidenceItem(
                source: "C2PA",
                kind: "manifest_absent",
                summary: "No C2PA manifest was found in the file.",
                detail: toolOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
        ]
        return FileVerdict(
            kind: .notWatermarked,
            confidence: ConfidenceRules.confidence(ConfidenceRules.noManifest),
            fileName: fileName,
            format: format,
            manifestPresent: false,
            signatureValid: nil,
            modifiedSinceSigning: nil,
            signer: nil,
            softwareAgent: nil,
            claims: [],
            evidence: evidence,
            caveatText: Caveats.fileNoManifest
        )
    }

    // MARK: - Parsing helpers

    private func signatureState(_ statuses: [ValidationStatus]?) -> Bool? {
        guard let statuses, !statuses.isEmpty else { return nil }
        let signatureCodes = statuses.filter { status in
            let code = (status.code ?? "").lowercased()
            return code.contains("signature") || code.contains("certificate")
        }
        guard !signatureCodes.isEmpty else { return nil }
        for status in signatureCodes {
            if isInvalid(status) { return false }
        }
        for status in signatureCodes {
            let code = (status.code ?? "").lowercased()
            let rawStatus = (status.status ?? "").lowercased()
            if rawStatus == "valid" || code.contains(".valid") { return true }
        }
        return nil
    }

    private func modificationState(_ statuses: [ValidationStatus]?, signatureValid: Bool?) -> Bool? {
        // A hash comparison only proves modification when the signature itself
        // verifies. With an invalid or unverifiable signature the manifest
        // cannot be attributed to its signer, so claiming "modified after
        // signing" would overstate what is actually provable.
        guard signatureValid == true else { return nil }
        guard let statuses else { return nil }
        for status in statuses {
            let code = (status.code ?? "").lowercased()
            if code.contains("mismatch") { return true }
            if code.contains("hash") && isInvalid(status) { return true }
        }
        return false
    }

    private func isInvalid(_ status: ValidationStatus) -> Bool {
        let code = (status.code ?? "").lowercased()
        let rawStatus = (status.status ?? "").lowercased()
        return rawStatus == "invalid"
            || code.contains("invalid")
            || code.contains("expired")
            || code.contains("revoked")
    }

    private func softwareAgentName(from manifest: ManifestEntry) -> String? {
        if let name = manifest.claim_generator_info?.first?.name, !name.isEmpty {
            return name
        }
        if let generator = manifest.claim_generator, !generator.isEmpty {
            return generator
        }
        return manifest.assertions?
            .first { $0.label == "c2pa.actions" }?
            .data?.actions?
            .first?.softwareAgent
    }

    private func claims(from manifest: ManifestEntry, signer: String?) -> [C2PAClaim] {
        let actions = manifest.assertions?
            .filter { $0.label == "c2pa.actions" }
            .compactMap { $0.data?.actions }
            .flatMap { $0 } ?? []
        return actions.map { action in
            C2PAClaim(
                title: action.action ?? "unknown action",
                action: action.action ?? "",
                softwareAgent: action.softwareAgent,
                signer: signer,
                timestamp: parseDate(action.when)
            )
        }
    }

    private func displayName(from issuer: String?) -> String? {
        guard let issuer, !issuer.isEmpty else { return nil }
        let parts = issuer.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var fields: [String: String] = [:]
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map { String($0) }
            if pair.count == 2 {
                fields[pair[0].trimmingCharacters(in: .whitespaces)] =
                    pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        if let commonName = fields["CN"] { return commonName }
        if let organization = fields["O"] { return organization }
        return issuer
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Manifest JSON shapes

private struct ManifestEnvelope: Decodable {
    var active_manifest: String?
    var manifests: [String: ManifestEntry]?

    var activeManifestEntry: ManifestEntry? {
        guard let active = active_manifest, let manifests else { return nil }
        return manifests[active]
    }
}

private struct ManifestEntry: Decodable {
    var claim_generator: String?
    var claim_generator_info: [GeneratorInfo]?
    var signature_info: SignatureInfo?
    var assertions: [Assertion]?
    var validation_status: [ValidationStatus]?
}

private struct GeneratorInfo: Decodable {
    var name: String?
    var version: String?
}

private struct SignatureInfo: Decodable {
    var issuer: String?
}

private struct Assertion: Decodable {
    var label: String?
    var data: AssertionData?
}

private struct AssertionData: Decodable {
    var actions: [Action]?
}

private struct Action: Decodable {
    var action: String?
    var when: String?
    var softwareAgent: String?
    var softwareAgentVersion: String?
}

private struct ValidationStatus: Decodable {
    var code: String?
    var status: String?
    var explanation: String?
}
