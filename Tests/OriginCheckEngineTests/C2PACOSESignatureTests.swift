import Foundation
import Testing
@testable import OriginCheckEngine

/// Builds synthetic signed PNGs: an iTXt "c2pa" chunk whose text is the
/// Base64 of a JUMBF superbox containing the manifest store JSON and a real
/// COSE_Sign1 Ed25519 signature over the claim bytes.
///
/// The key material was generated with openssl 3:
///   openssl genpkey -algorithm ED25519
///   openssl req -x509 -new -key priv.pem -subj "/C=US/O=OriginCheck Test/CN=OriginCheck Test Signer"
/// and the signature was produced with openssl pkeyutl -sign -rawin over the
/// COSE Sig_structure bytes. The engine never signs; these fixtures let it
/// prove verification against a known-good signature.
enum SignedPNGFixtures {
    static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// Raw 32-byte Ed25519 public key from the fixture certificate.
    static let publicKey: [UInt8] = hexBytes(
        "befc255681453da76b16d0a1ec6f1e0745c89af6a0057e5dac36ee50957467f8"
    )

    /// The leaf certificate (DER) that carries the public key and the
    /// subject "OriginCheck Test Signer".
    static let certificateDER: [UInt8] = hexBytes(
        "308201a93082015ba00302010202141d38399a844a2576f4a7221b19ae039fa375fd0d300506032b6570" +
        "304a310b300906035504061302555331193017060355040a0c104f726967696e436865636b205465737431" +
        "20301e06035504030c174f726967696e436865636b2054657374205369676e6572301e170d323630383137" +
        "3133343731395a170d3237303831373133343731395a304a310b3009060355040613025553311930170603" +
        "55040a0c104f726967696e436865636b20546573743120301e06035504030c174f726967696e436865636b" +
        "2054657374205369676e6572302a300506032b6570032100befc255681453da76b16d0a1ec6f1e0745c89a" +
        "f6a0057e5dac36ee50957467f8a3533051301d0603551d0e041604143d21732cae5292eb2f323ada52e78e" +
        "6a1670de09301f0603551d230418301680143d21732cae5292eb2f323ada52e78e6a1670de09300f060355" +
        "1d130101ff040530030101ff300506032b6570034100f00872eacec613e93ebfeee47378de5c02e4b55b40" +
        "a74584d16186db22cf5cbad2a0c350778cb84070572a5652fd60941d865fc05a3e56a8d4be0ddd60d1e507"
    )

    /// The claim bytes the signature covers (a compact C2PA-style claim).
    static let claim: [UInt8] = hexBytes(
        "a668636c61696d5f67656e657261746f726c633270612d746573742f302e3164666f726d61746a696d6167652f706e67"
    )

    /// Ed25519 signature over the COSE Sig_structure of the claim, produced
    /// with the matching private key (which is not part of this repository).
    /// The structure uses canonical CBOR (0x43 for the 3-byte protected
    /// header), the encoding real C2PA signers emit.
    static let signatureBytes: [UInt8] = hexBytes(
        "f64049171edf24aaf476f3cca3edd4f4fc8a2a8d18b5e5b216af322e55f25fdd" +
        "8ac7aa95f90ad7465c08ee24b5833b3ae54ed1392cd04615197b30f4950ed50b"
    )

    /// The protected header `{1: -8}` (COSE algorithm EdDSA).
    static func protectedHeader() -> [UInt8] {
        CBOR.encodeMapHeader(1) + CBOR.encodeInteger(1) + CBOR.encodeInteger(-8)
    }

    /// A full COSE_Sign1 message: [protected, {33: [cert]}, nil, signature].
    static func coseSign1(protected: [UInt8], cert: [UInt8]?, signature: [UInt8]) -> [UInt8] {
        let unprotected: [UInt8]
        if let cert {
            unprotected = CBOR.encodeMapHeader(1)
                + CBOR.encodeInteger(33)
                + CBOR.encodeArrayHeader(1)
                + CBOR.encodeBytes(cert)
        } else {
            unprotected = CBOR.encodeMapHeader(0)
        }
        return CBOR.encodeArrayHeader(4)
            + CBOR.encodeBytes(protected)
            + unprotected
            + CBOR.nullValue
            + CBOR.encodeBytes(signature)
    }

    /// The manifest store JSON for a given claim, with the claim embedded as
    /// base64 the way real stores carry it.
    static func storeJSON(claim: [UInt8]) -> String {
        let claimBase64 = Data(claim).base64EncodedString()
        return """
        {"active_manifest":"urn:uuid:11111111-1111-1111-1111-111111111111","manifests":{"urn:uuid:11111111-1111-1111-1111-111111111111":{"claim_generator":"c2pa-test/0.1","claim_generator_info":[{"name":"Claude","version":"2.0"}],"claim":"\(claimBase64)","assertions":[{"label":"c2pa.actions","data":{"actions":[{"action":"c2pa.created","when":"2026-08-16T12:00:00Z","softwareAgent":"Claude"}]}}]}}}
        """
    }

    /// A full PNG with the given manifest store JSON and COSE message wrapped
    /// in the standard JUMBF superbox layout.
    static func signedPNGData(storeJSON: String, cose: [UInt8]) -> Data {
        let jumd = box(type: "jumd", payload: [0] + Array("c2pa".utf8))
        let jsonBox = box(type: "json", payload: Array(storeJSON.utf8))
        let cborBox = box(type: "cbor", payload: cose)
        let superbox = box(type: "jumb", payload: jumd + jsonBox + cborBox)
        let itxtText = Data(superbox).base64EncodedString()

        var bytes = signature
        bytes += chunk(type: "IHDR", data: ihdr)
        bytes += iTXtChunk(keyword: "c2pa", text: itxtText)
        bytes += chunk(type: "IEND", data: [])
        return Data(bytes)
    }

    static func iTXtChunk(keyword: String, text: String) -> [UInt8] {
        var data: [UInt8] = Array(keyword.utf8)
        data.append(0) // keyword terminator
        data.append(0) // compression flag: uncompressed
        data.append(0) // compression method
        data.append(0) // language tag terminator (empty)
        data.append(0) // translated keyword terminator (empty)
        data += Array(text.utf8)
        return chunk(type: "iTXt", data: data)
    }

    private static func box(type: String, payload: [UInt8]) -> [UInt8] {
        u32(8 + payload.count) + Array(type.utf8) + payload
    }

    private static func chunk(type: String, data: [UInt8]) -> [UInt8] {
        u32(data.count) + Array(type.utf8) + data + [0, 0, 0, 0] // CRC ignored by the reader
    }

    private static let ihdr: [UInt8] = {
        var data: [UInt8] = []
        data += u32(1)
        data += u32(1)
        data += [8, 6]
        data += [0, 0, 0]
        return data
    }()

    private static func u32(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func hexBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var text = hex
        if text.count % 2 != 0 { text = "0" + text }
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index..<next], radix: 16) ?? 0)
            index = next
        }
        return bytes
    }
}

@Suite("C2PA COSE Ed25519 verification")
struct C2PACOSESignatureTests {
    /// A fully valid signed PNG: valid claim, EdDSA algorithm, cert chain
    /// with the signing public key. The whole pipeline (reader, COSE parse,
    /// X.509 key extraction, Ed25519 math) must agree the signature is real.
    @Test
    func validEd25519SignatureVerifiesEndToEnd() async throws {
        let url = try writePNG(SignedPNGFixtures.signedPNGData(
            storeJSON: SignedPNGFixtures.storeJSON(claim: SignedPNGFixtures.claim),
            cose: SignedPNGFixtures.coseSign1(
                protected: SignedPNGFixtures.protectedHeader(),
                cert: SignedPNGFixtures.certificateDER,
                signature: SignedPNGFixtures.signatureBytes
            )
        ))
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool", bundledReaderEnabled: true)
        let verdict = try await verifier.verifyFile(at: url)

        #expect(verdict.manifestPresent)
        #expect(verdict.signatureValid == true)
        #expect(verdict.kind == .watermarked)
        #expect(verdict.signer == "OriginCheck Test Signer")
        #expect(verdict.softwareAgent == "Claude")
        #expect(verdict.modifiedSinceSigning == nil,
                "The bundled verifier cannot recompute the content hash, so it must not claim intact")
        #expect(verdict.caveatText.contains("content hash"),
                "The caveat must say the content hash is not checked")
        #expect(verdict.evidence.contains { $0.detail.contains("verifies with the built-in verifier") })
    }

    /// Changing one byte of the claim (and updating the base64 in the store,
    /// as a tampering tool would) must fail verification: the signature no
    /// longer covers the claim.
    @Test
    func tamperedClaimFailsVerification() async throws {
        var tampered = SignedPNGFixtures.claim
        tampered[tampered.count - 1] ^= 0x01
        let url = try writePNG(SignedPNGFixtures.signedPNGData(
            storeJSON: SignedPNGFixtures.storeJSON(claim: tampered),
            cose: SignedPNGFixtures.coseSign1(
                protected: SignedPNGFixtures.protectedHeader(),
                cert: SignedPNGFixtures.certificateDER,
                signature: SignedPNGFixtures.signatureBytes
            )
        ))
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool", bundledReaderEnabled: true)
        let verdict = try await verifier.verifyFile(at: url)

        #expect(verdict.manifestPresent)
        #expect(verdict.signatureValid == false)
        #expect(verdict.kind == .inconclusive)
        #expect(verdict.evidence.contains { $0.detail.contains("did not verify") })
    }

    /// A signature with an unsupported algorithm (ES256) is not a failed
    /// signature: the built-in verifier cannot check it, so the state must
    /// be unverifiable, not invalid.
    @Test
    func unsupportedAlgorithmStaysUnverifiable() async throws {
        let es256Protected = CBOR.encodeMapHeader(1) + CBOR.encodeInteger(1) + CBOR.encodeInteger(-7)
        let url = try writePNG(SignedPNGFixtures.signedPNGData(
            storeJSON: SignedPNGFixtures.storeJSON(claim: SignedPNGFixtures.claim),
            cose: SignedPNGFixtures.coseSign1(
                protected: es256Protected,
                cert: SignedPNGFixtures.certificateDER,
                signature: [UInt8](repeating: 0xAB, count: 64)
            )
        ))
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool", bundledReaderEnabled: true)
        let verdict = try await verifier.verifyFile(at: url)

        #expect(verdict.manifestPresent)
        #expect(verdict.signatureValid == nil,
                "An unsupported algorithm means cannot verify, not invalid")
        #expect(verdict.kind == .inconclusive)
        #expect(verdict.evidence.contains { $0.detail.contains("ES256") })
        #expect(verdict.evidence.contains { $0.detail.contains("could not be verified") })
    }

    /// A signature without a certificate carries no public key, so the
    /// built-in verifier cannot check it: unverifiable, not invalid.
    @Test
    func missingCertificateStaysUnverifiable() async throws {
        let url = try writePNG(SignedPNGFixtures.signedPNGData(
            storeJSON: SignedPNGFixtures.storeJSON(claim: SignedPNGFixtures.claim),
            cose: SignedPNGFixtures.coseSign1(
                protected: SignedPNGFixtures.protectedHeader(),
                cert: nil,
                signature: SignedPNGFixtures.signatureBytes
            )
        ))
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool", bundledReaderEnabled: true)
        let verdict = try await verifier.verifyFile(at: url)

        #expect(verdict.manifestPresent)
        #expect(verdict.signatureValid == nil)
        #expect(verdict.kind == .inconclusive)
    }

    /// A missing claim in the store (no base64 claim field) leaves nothing
    /// to check the signature against: unverifiable, not invalid.
    @Test
    func missingClaimStaysUnverifiable() async throws {
        let storeWithoutClaim = SignedPNGFixtures.storeJSON(claim: SignedPNGFixtures.claim)
            .replacingOccurrences(of: "\"claim\":\"[^\"]*\",", with: "", options: .regularExpression)
        let url = try writePNG(SignedPNGFixtures.signedPNGData(
            storeJSON: storeWithoutClaim,
            cose: SignedPNGFixtures.coseSign1(
                protected: SignedPNGFixtures.protectedHeader(),
                cert: SignedPNGFixtures.certificateDER,
                signature: SignedPNGFixtures.signatureBytes
            )
        ))
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool", bundledReaderEnabled: true)
        let verdict = try await verifier.verifyFile(at: url)

        #expect(verdict.manifestPresent)
        #expect(verdict.signatureValid == nil)
    }

    /// The Sig_structure bytes must match the COSE convention exactly:
    /// ["Signature1", bstr(protected), bstr(""), bstr(claim)]. This pins the
    /// wire format the openssl-produced fixture signature was made over.
    @Test
    func sigStructureMatchesCOSEConvention() {
        let protected = SignedPNGFixtures.protectedHeader()
        let structure = C2PASignatureReader.sigStructure(
            protected: protected,
            payload: SignedPNGFixtures.claim
        )
        let expected = SignedPNGFixtures.hexBytes(
            "846a5369676e61747572653143a10127405830" +
            "a668636c61696d5f67656e657261746f726c633270612d746573742f302e3164666f726d61746a696d6167652f706e67"
        )
        #expect(structure == expected)
        // And the fixture signature must verify against exactly those bytes.
        #expect(Ed25519.verify(
            signature: SignedPNGFixtures.signatureBytes,
            message: structure,
            publicKey: SignedPNGFixtures.publicKey
        ))
    }

    /// The certificate's SubjectPublicKeyInfo must yield the same 32 bytes
    /// the fixture signature was made with.
    @Test
    func subjectPublicKeyExtractedFromCertificate() {
        let key = X509Reader.subjectPublicKey(in: SignedPNGFixtures.certificateDER)
        #expect(key == SignedPNGFixtures.publicKey)
        #expect(X509Reader.commonName(in: SignedPNGFixtures.certificateDER) == "OriginCheck Test Signer")
    }

    /// The reader-level API reports the verified state directly, so the
    /// verdict wiring is not the only thing being tested.
    @Test
    func readerReportsVerifiedSignature() throws {
        let storeJSON = SignedPNGFixtures.storeJSON(claim: SignedPNGFixtures.claim)
        let cose = SignedPNGFixtures.coseSign1(
            protected: SignedPNGFixtures.protectedHeader(),
            cert: SignedPNGFixtures.certificateDER,
            signature: SignedPNGFixtures.signatureBytes
        )
        let jumdBox = [0] + Array("c2pa".utf8)
        // Build the same superbox layout the PNG builder uses.
        func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            (8 + payload.count).toBigEndianBytes + Array(type.utf8) + payload
        }
        let jumb = box("jumb", box("jumd", jumdBox) + box("json", Array(storeJSON.utf8)) + box("cbor", cose))

        let info = C2PASignatureReader().read(
            storeJSON: storeJSON,
            jumbfData: Data(jumb)
        )
        #expect(info.present)
        #expect(info.signatureValid == true)
        #expect(info.signer == "OriginCheck Test Signer")
        #expect(info.algorithm == "EdDSA (Ed25519)")
    }

    private func writePNG(_ data: Data) throws -> URL {
        // Unique per test: Swift Testing runs tests in parallel, and two
        // tests sharing one temp path would clobber each other's files.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signed-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}

private extension Int {
    var toBigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
    }
}
