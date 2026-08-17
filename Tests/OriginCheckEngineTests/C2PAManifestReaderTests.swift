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

    // MARK: ISO BMFF (MP4, MOV, HEIC, AVIF)

    /// The C2PA user type for BMFF uuid boxes.
    static let c2paUserType: [UInt8] = [
        0xD8, 0xFE, 0xC3, 0xD6, 0x1B, 0x0E, 0x48, 0x3C,
        0x92, 0x97, 0x58, 0x28, 0x87, 0x7E, 0xC4, 0x81,
    ]

    /// ftyp box plus a top-level uuid box with the C2PA user type, the
    /// version/flags header, a "manifest" purpose, the merkle offset, and
    /// the store, exactly the layout the current reference tool writes.
    static func bmffData() -> [UInt8] {
        let ftyp = box(type: "ftyp", payload: Array("isom".utf8) + [0, 0, 0, 0] + Array("isom".utf8))
        var uuidPayload = c2paUserType
        uuidPayload += [0, 0, 0, 0] // version u8 + flags u24
        uuidPayload += Array("manifest".utf8) + [0]
        uuidPayload += [0, 0, 0, 0, 0, 0, 0, 0] // merkle offset
        uuidPayload += jumbfSuperbox()
        return ftyp + box(type: "uuid", payload: uuidPayload)
    }

    /// The same store inside a meta box as a c2pa box, the Apple HEIF
    /// layout, with the meta FullBox header present.
    static func bmffMetaData() -> [UInt8] {
        let ftyp = box(type: "ftyp", payload: Array("isom".utf8) + [0, 0, 0, 0] + Array("isom".utf8))
        let c2pa = box(type: "c2pa", payload: jumbfSuperbox())
        let meta = box(type: "meta", payload: [0, 0, 0, 0] + c2pa)
        return ftyp + meta
    }

    static func plainBmffData() -> [UInt8] {
        let ftyp = box(type: "ftyp", payload: Array("isom".utf8) + [0, 0, 0, 0] + Array("isom".utf8))
        let moov = box(type: "moov", payload: [0, 0, 0, 0])
        return ftyp + moov
    }

    // MARK: TIFF / DNG

    /// A little-endian TIFF with one IFD carrying the C2PA tag 0xCD41
    /// (type 7, UNDEFINED) pointing at the store bytes.
    static func tiffData() -> [UInt8] {
        let store = jumbfSuperbox()
        var bytes: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]
        let storeOffset = 8 + 2 + 12 + 4
        bytes += [0x01, 0x00] // one entry
        bytes += u16LE(0xCD41) + u16LE(7) + u32LE(UInt32(store.count)) + u32LE(UInt32(storeOffset))
        bytes += [0, 0, 0, 0] // next IFD: none
        bytes += store
        return bytes
    }

    /// A big-endian TIFF carrying the C2PA tag in the Exif IFD, to prove
    /// both endiannesses and both IFD locations work.
    static func tiffExifData() -> [UInt8] {
        let store = jumbfSuperbox()
        let exifIFDOffset = 8 + 2 + 12 + 4 // right after the main IFD
        let storeOffset = exifIFDOffset + 2 + 12 + 4 // right after the Exif IFD
        var bytes: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]
        // Main IFD: one entry, the Exif IFD pointer tag 0x8769.
        bytes += [0x00, 0x01]
        bytes += u16BE(0x8769) + u16BE(4) + u32BE(1) + u32BE(UInt32(exifIFDOffset))
        bytes += [0, 0, 0, 0] // next IFD: none
        // Exif IFD: one entry, the C2PA tag 0xCD41.
        bytes += [0x00, 0x01]
        bytes += u16BE(0xCD41) + u16BE(7) + u32BE(UInt32(store.count)) + u32BE(UInt32(storeOffset))
        bytes += [0, 0, 0, 0]
        bytes += store
        return bytes
    }

    static func plainTiffData() -> [UInt8] {
        var bytes: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]
        bytes += [0x00, 0x00] // zero entries
        bytes += [0, 0, 0, 0] // next IFD: none
        return bytes
    }

    static func u16LE(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    static func u16BE(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    static func u32LE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }

    static func u32BE(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
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

    // MARK: ISO BMFF

    @Test
    func bmffReaderExtractsManifestFromUUIDBox() throws {
        let url = try write(Data(SyntheticMedia.bmffData()), name: "signed.mp4")
        let manifest = try BMFFC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
        #expect(json.contains("Claude"))
        #expect(manifest?.jumbfData != nil)
    }

    @Test
    func bmffReaderExtractsManifestFromMetaBox() throws {
        let url = try write(Data(SyntheticMedia.bmffMetaData()), name: "signed.heic")
        let manifest = try BMFFC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
    }

    @Test
    func bmffWithoutManifestReturnsNil() throws {
        let url = try write(Data(SyntheticMedia.plainBmffData()), name: "plain.mov")
        #expect(try BMFFC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    @Test
    func bmffReaderRejectsNonBMFF() throws {
        let url = try write(Data("not a movie".utf8), name: "not-a-movie.mp4")
        #expect(try BMFFC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    // MARK: TIFF / DNG

    @Test
    func tiffReaderExtractsManifestFromIFD() throws {
        let url = try write(Data(SyntheticMedia.tiffData()), name: "signed.tif")
        let manifest = try TIFFC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
        #expect(json.contains("Claude"))
        #expect(manifest?.jumbfData != nil)
    }

    @Test
    func tiffReaderExtractsManifestFromExifIFDBigEndian() throws {
        let url = try write(Data(SyntheticMedia.tiffExifData()), name: "signed.dng")
        let manifest = try TIFFC2PAReader().extractManifest(at: url)
        let json = try #require(manifest?.storeJSON)
        #expect(json.contains("active_manifest"))
    }

    @Test
    func tiffWithoutManifestReturnsNil() throws {
        let url = try write(Data(SyntheticMedia.plainTiffData()), name: "plain.tiff")
        #expect(try TIFFC2PAReader().extractManifestStoreJSON(at: url) == nil)
    }

    @Test
    func tiffReaderRejectsNonTIFF() throws {
        let url = try write(Data("just some bytes".utf8), name: "not-a-tiff.tif")
        #expect(try TIFFC2PAReader().extractManifestStoreJSON(at: url) == nil)
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
        let expected: Set<String> = [
            "png", "jpg", "jpeg", "svg", "webp",
            "avif", "heic", "heif", "mp4", "mov", "m4a",
            "tif", "tiff", "dng",
        ]
        #expect(StandaloneC2PAReader.supportedExtensions == expected)
        #expect(StandaloneC2PAReader.supportedDisplayNames.contains("PNG"))
        #expect(StandaloneC2PAReader.supportedDisplayNames.contains("MP4"))
        #expect(StandaloneC2PAReader.supportedDisplayNames.contains("TIFF"))
    }

    @Test
    func verifierUsesBundledReadersForAllStandaloneFormats() async throws {
        let samples: [(String, [UInt8], String)] = [
            ("signed.jpg", SyntheticMedia.jpegData(), "jpg"),
            ("signed.svg", SyntheticMedia.svgData(), "svg"),
            ("signed.webp", SyntheticMedia.webpData(), "webp"),
            ("signed.mp4", SyntheticMedia.bmffData(), "mp4"),
            ("signed.heic", SyntheticMedia.bmffMetaData(), "heic"),
            ("signed.tif", SyntheticMedia.tiffData(), "tif"),
            ("signed.dng", SyntheticMedia.tiffExifData(), "dng"),
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
