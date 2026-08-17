import Foundation
import Testing
@testable import OriginCheckEngine

/// Builds a synthetic signed PNG: a manifest store JSON plus a claim CBOR
/// box and a COSE_Sign1 box inside a JUMBF superbox, exactly the shape the
/// built-in reader walks. The COSE carries a real DER certificate so the
/// reader can extract the signer identity; the signature bytes themselves
/// are dummy, because the built-in reader does not claim to verify them.
private enum SignedSynthetic {
    static let storeJSON = """
    {"active_manifest":"id1","manifests":{"id1":{"claim_generator":"test","claim_generator_info":[{"name":"Claude","version":"2.0"}]}}}
    """

    struct Artifacts {
        var certDER: [UInt8]
        var cose: [UInt8]
        var superbox: [UInt8]
    }

    static func build(algorithm: Int64 = -8, subjectCN: String = "Claude Test Signer") throws -> Artifacts {
        let publicKey = [UInt8](repeating: 0x42, count: 32)
        let certDER = TestDER.certificate(publicKey: publicKey, subjectCN: subjectCN, issuerCN: "Test CA")

        // COSE protected header: {1: alg, 33: x5chain}
        var protected: [UInt8] = CBOR.encodeMapHeader(2)
        protected += CBOR.encodeInteger(1) + CBOR.encodeInteger(algorithm)
        protected += CBOR.encodeInteger(33) + CBOR.encodeArrayHeader(1) + CBOR.encodeBytes(certDER)

        // COSE_Sign1: [protected, {}, null (detached payload), signature]
        var cose: [UInt8] = CBOR.encodeArrayHeader(4)
        cose += CBOR.encodeBytes(protected)
        cose += CBOR.encodeMapHeader(0)
        cose += CBOR.nullValue
        cose += CBOR.encodeBytes([UInt8](repeating: 0xAB, count: 64))

        let label = Array("c2pa".utf8)
        let jumd = box(type: "jumd", payload: [0] + label)
        let jsonBox = box(type: "json", payload: Array(storeJSON.utf8))
        let signatureBox = box(type: "cbor", payload: cose)
        let superbox = box(type: "jumb", payload: jumd + jsonBox + signatureBox)

        return Artifacts(certDER: certDER, cose: cose, superbox: superbox)
    }

    static func pngData(withITXtText text: String) -> [UInt8] {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        var data: [UInt8] = signature
        data += chunk(type: "IHDR", data: ihdr)
        data += iTXtChunk(keyword: "c2pa", text: text)
        data += chunk(type: "IEND", data: [])
        return data
    }

    static func iTXtChunk(keyword: String, text: String) -> [UInt8] {
        var payload: [UInt8] = Array(keyword.utf8)
        payload.append(0) // keyword terminator
        payload.append(0) // compression flag: uncompressed
        payload.append(0) // compression method
        payload.append(0) // language tag terminator
        payload.append(0) // translated keyword terminator
        payload += Array(text.utf8)
        return chunk(type: "iTXt", data: payload)
    }

    static func box(type: String, payload: [UInt8]) -> [UInt8] {
        let size = 8 + payload.count
        return u32(size) + Array(type.utf8) + payload
    }

    private static func chunk(type: String, data: [UInt8]) -> [UInt8] {
        u32(data.count) + Array(type.utf8) + data + [0, 0, 0, 0] // CRC ignored by the reader
    }

    private static let ihdr: [UInt8] = u32(1) + u32(1) + [8, 6, 0, 0, 0]

    private static func u32(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}

/// A minimal DER builder for the synthetic X.509 certificate.
private enum TestDER {
    static func certificate(publicKey: [UInt8], subjectCN: String, issuerCN: String) -> [UInt8] {
        let version = tlv(0xA0, integer(2)) // [0] EXPLICIT INTEGER
        let serial = integer(1)
        let sha256WithRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
        let signatureAlgorithm = sequence(oid(sha256WithRSA) + null())
        let issuer = name(issuerCN)
        let validity = sequence(utcTime("240101000000Z") + utcTime("340101000000Z"))
        let subject = name(subjectCN)
        let ed25519OID: [UInt8] = [0x2B, 0x65, 0x70]
        let spki = sequence(sequence(oid(ed25519OID) + null()) + bitString(0, publicKey))
        let tbs = sequence(version + serial + signatureAlgorithm + issuer + validity + subject + spki)
        let outerSignature = bitString(0, [UInt8](repeating: 0, count: 8))
        return sequence(tbs + signatureAlgorithm + outerSignature)
    }

    private static func name(_ commonName: String) -> [UInt8] {
        let rdn = sequence(oid([0x55, 0x04, 0x03]) + utf8(commonName)) // 2.5.4.3 CN
        return sequence(tlv(0x31, rdn)) // SET OF
    }

    static func sequence(_ children: [UInt8]) -> [UInt8] { tlv(0x30, children) }
    static func oid(_ bytes: [UInt8]) -> [UInt8] { tlv(0x06, bytes) }
    static func utf8(_ text: String) -> [UInt8] { tlv(0x0C, Array(text.utf8)) }
    static func integer(_ value: UInt8) -> [UInt8] { tlv(0x02, [value]) }
    static func null() -> [UInt8] { tlv(0x05, []) }
    static func bitString(_ unusedBits: UInt8, _ bytes: [UInt8]) -> [UInt8] {
        tlv(0x03, [unusedBits] + bytes)
    }
    static func utcTime(_ text: String) -> [UInt8] { tlv(0x17, Array(text.utf8)) }

    private static func tlv(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        [tag] + length(value.count) + value
    }

    private static func length(_ count: Int) -> [UInt8] {
        if count < 128 { return [UInt8(count)] }
        return [0x81, UInt8(count)]
    }
}

@Suite("C2PA signature metadata")
struct C2PASignatureValidatorTests {
    @Test
    func readsSignerMetadataFromTheCertificate() throws {
        let artifacts = try SignedSynthetic.build()
        let png = SignedSynthetic.pngData(withITXtText: Data(artifacts.superbox).base64EncodedString())
        let url = try write(Data(png))

        let manifest = try #require(try PNGC2PAReader().extractManifest(at: url))
        let info = C2PASignatureReader().read(storeJSON: manifest.storeJSON, jumbfData: manifest.jumbfData)

        #expect(info.present)
        #expect(info.algorithm == "EdDSA (Ed25519)")
        #expect(info.signer == "Claude Test Signer")
        #expect(info.issuer == "Test CA")
        #expect(info.certNotAfter != nil)
    }

    @Test
    func es256SignatureReportsTheAlgorithm() throws {
        let artifacts = try SignedSynthetic.build(algorithm: -7) // ES256
        let png = SignedSynthetic.pngData(withITXtText: Data(artifacts.superbox).base64EncodedString())
        let url = try write(Data(png))

        let manifest = try #require(try PNGC2PAReader().extractManifest(at: url))
        let info = C2PASignatureReader().read(storeJSON: manifest.storeJSON, jumbfData: manifest.jumbfData)
        #expect(info.present)
        #expect(info.algorithm == "ES256")
    }

    @Test
    func noSignatureDataReportsNotPresent() throws {
        // A manifest without any signature box or signatures array.
        let label = Array("c2pa".utf8)
        let jumd = SignedSynthetic.box(type: "jumd", payload: [0] + label)
        let jsonBox = SignedSynthetic.box(type: "json", payload: Array(SignedSynthetic.storeJSON.utf8))
        let superbox = SignedSynthetic.box(type: "jumb", payload: jumd + jsonBox)
        let png = SignedSynthetic.pngData(withITXtText: Data(superbox).base64EncodedString())
        let url = try write(Data(png))

        let manifest = try #require(try PNGC2PAReader().extractManifest(at: url))
        let info = C2PASignatureReader().read(storeJSON: manifest.storeJSON, jumbfData: manifest.jumbfData)
        #expect(!info.present)
        #expect(info.signer == nil)
    }

    @Test
    func signatureMetadataFlowsIntoTheVerdict() async throws {
        let artifacts = try SignedSynthetic.build()
        let png = SignedSynthetic.pngData(withITXtText: Data(artifacts.superbox).base64EncodedString())
        let url = try write(Data(png))

        let verdict = try await C2PAVerifier(toolPath: "/nonexistent/c2patool").verifyFile(at: url)
        #expect(verdict.manifestPresent)
        // The signature math is not checked without the tool, so the verdict
        // stays honest: unverifiable, never claimed as valid.
        #expect(verdict.signatureValid == nil)
        #expect(verdict.kind == .inconclusive)
        #expect(verdict.signer == "Claude Test Signer")
        #expect(verdict.evidence.contains { $0.summary.contains("carries a signature") })
        #expect(verdict.evidence.contains { $0.detail.contains("not verified without c2patool") })
    }

    @Test
    func signatureMetadataDoesNotClaimValidity() async throws {
        // Even with a well-formed signature box, the bundled verdict must not
        // claim the signature is valid: that is the tool's job.
        let artifacts = try SignedSynthetic.build()
        let png = SignedSynthetic.pngData(withITXtText: Data(artifacts.superbox).base64EncodedString())
        let url = try write(Data(png))

        let verdict = try await C2PAVerifier(toolPath: "/nonexistent/c2patool").verifyFile(at: url)
        #expect(verdict.signatureValid == nil)
        #expect(verdict.caveatText == Caveats.general)
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signed-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
