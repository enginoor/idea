import Foundation
import Testing
@testable import OriginCheckEngine

/// Builds synthetic JPEG, SVG, and WebP files carrying a C2PA manifest
/// store, matching how c2patool writes them: the manifest store JSON inside
/// a JUMBF superbox, placed per format.
private enum SyntheticMedia {
    static let manifestStoreJSON = """
    {"active_manifest":"id1","manifests":{"id1":{"claim_generator":"c2pa-rs","claim_generator_info":[{"name":"Claude","version":"2.0"}]}}}
    """

    static func jumbfSuperbox() -> [UInt8] {
        let label = Array("c2pa".utf8)
        let jumd = box(type: "jumd", payload: [0] + label)
        let c2pa = box(type: "c2pa", payload: Array(manifestStoreJSON.utf8))
        return box(type: "jumb", payload: jumd + c2pa)
    }

    // MARK: JPEG

    static func jpegData() -> [UInt8] {
        var bytes: [UInt8] = [0xFF, 0xD8] // SOI
        let header: [UInt8] = [0x63, 0x32, 0x70, 0x61] + [0x00, 0x01] + [0x00, 0x00, 0x00, 0x01]
        let payload = header + jumbfSuperbox()
        let length = UInt16(payload.count + 2) // includes the 2 length bytes
        bytes += [0xFF, 0xEB] // APP11
        bytes += [UInt8(length >> 8), UInt8(length & 0xFF)]
        bytes += payload
        bytes += [0xFF, 0xD9] // EOI
        return bytes
    }

    static func plainJpegData() -> [UInt8] {
        [0xFF, 0xD8] + [0xFF, 0xDB] + [0x00, 0x03] + [0x00] + [0xFF, 0xD9]
    }

    // MARK: SVG

    static func svgData() -> [UInt8] {
        let encoded = Data(jumbfSuperbox()).base64EncodedString()
        let text = """
        <?xml version="1.0"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:c2pa="http://c2pa.org/manifest">
          <metadata>
            <c2pa:manifest>\(encoded)</c2pa:manifest>
          </metadata>
        </svg>
        """
        return Array(text.utf8)
    }

    static func plainSvgData() -> [UInt8] {
        Array("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"1\" height=\"1\"/></svg>".utf8)
    }

    // MARK: WebP / RIFF

    static func webpData() -> [UInt8] {
        let c2pa = Array("C2PA".utf8) + u32LE(jumbfSuperbox().count) + jumbfSuperbox()
        let payload = Array("WEBP".utf8) + c2pa
        var bytes = Array("RIFF".utf8) + u32LE(payload.count) + payload
        // Pad the odd-sized C2PA chunk per RIFF rules.
        if jumbfSuperbox().count % 2 == 1 { bytes.append(0) }
        return bytes
    }

    static func plainWebpData() -> [UInt8] {
        let payload = Array("WEBP".utf8) + Array("VP8 ".utf8) + [0, 0, 0, 0]
        return Array("RIFF".utf8) + u32LE(payload.count) + payload
    }

    // MARK: Helpers

    static func box(type: String, payload: [UInt8]) -> [UInt8] {
        let size = 8 + payload.count
        return u32BE(size) + Array(type.utf8) + payload
    }

    static func u32BE(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    static func u32LE(_ value: Int) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }
}

@Suite("Standalone C2PA format readers")
struct C2PAManifestReaderTests {
    // MARK: JPEG

    @Test
    func jpegReaderExtractsManifestFromAPP11() throws {
        let url = try write(Data(SyntheticMedia.jpegData()), name: "signed.jpg")
        let manifest = try JPEGC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
        #expect(json.contains("Claude"))
        #expect(manifest?.jumbfData != nil)
    }

    @Test
    func jpegWithoutManifestReturnsNil() throws {
        let url = try write(Data(SyntheticMedia.plainJpegData()), name: "plain.jpg")
        #expect(try JPEGC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    @Test
    func jpegReaderRejectsNonJPEG() throws {
        let url = try write(Data("plain text".utf8), name: "not-a-jpeg.jpg")
        #expect(try JPEGC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    // MARK: SVG

    @Test
    func svgReaderExtractsManifestFromMetadataElement() throws {
        let url = try write(Data(SyntheticMedia.svgData()), name: "signed.svg")
        let manifest = try SVGC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
        #expect(json.contains("Claude"))
    }

    @Test
    func svgWithoutManifestReturnsNil() throws {
        let url = try write(Data(SyntheticMedia.plainSvgData()), name: "plain.svg")
        #expect(try SVGC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    // MARK: WebP

    @Test
    func webpReaderExtractsManifestFromC2PAChunk() throws {
        let url = try write(Data(SyntheticMedia.webpData()), name: "signed.webp")
        let manifest = try WebPC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
        #expect(json.contains("Claude"))
    }

    @Test
    func webpWithoutManifestReturnsNil() throws {
        let url = try write(Data(SyntheticMedia.plainWebpData()), name: "plain.webp")
        #expect(try WebPC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    // MARK: Dispatch by magic bytes

    @Test
    func dispatcherUsesMagicBytesNotTheExtension() throws {
        // The file is named .png but contains a JPEG: the dispatcher must
        // route by content, not by the name.
        let url = try write(Data(SyntheticMedia.jpegData()), name: "misnamed.png")
        let json = try StandaloneC2PAReader().extractManifestStoreJSON(at: url)
        #expect(json?.contains("active_manifest") == true)
    }

    @Test
    func dispatcherCoversTheStandaloneFormats() throws {
        #expect(StandaloneC2PAReader.supportedExtensions == Set(["png", "jpg", "jpeg", "svg", "webp"]))
    }

    @Test
    func verifierUsesBundledReadersForAllStandaloneFormats() async throws {
        let samples: [(String, [UInt8], String)] = [
            ("signed.jpg", SyntheticMedia.jpegData(), "jpg"),
            ("signed.svg", SyntheticMedia.svgData(), "svg"),
            ("signed.webp", SyntheticMedia.webpData(), "webp"),
        ]
        let verifier = C2PAVerifier(toolPath: "/nonexistent/c2patool")
        for (name, data, format) in samples {
            let url = try write(Data(data), name: name)
            let verdict = try await verifier.verifyFile(at: url)
            #expect(verdict.manifestPresent, "\(name) should report a manifest")
            #expect(verdict.format == format)
            #expect(verdict.softwareAgent == "Claude")
        }
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }
}
