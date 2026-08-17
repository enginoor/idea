import Foundation

/// A manifest store extracted from a file by one of the built-in readers:
/// the store JSON plus the raw JUMBF bytes it came from. The JUMBF bytes are
/// what the signature validator needs: the claim box and the signature box
/// live in the JUMBF tree alongside the store JSON box, and the claim bytes
/// are exactly what the COSE signature covers.
public struct C2PAManifest: Sendable {
    public let storeJSON: String
    public let jumbfData: Data?

    public init(storeJSON: String, jumbfData: Data?) {
        self.storeJSON = storeJSON
        self.jumbfData = jumbfData
    }
}

/// Shared JUMBF box scanning for the built-in readers.
///
/// JUMBF (ISO/IEC 19566-5) boxes are `[size, type, payload]` where size is a
/// big-endian u32 (0 means to end of buffer, 1 means a 64-bit extended size
/// follows) and type is a 4-ASCII-byte box type. The scanner is deliberately
/// tolerant: anything it cannot parse is skipped, and the verdict falls back
/// to "no manifest" rather than guessing.
enum JUMBFScanner {
    /// Returns the first payload in the box tree that decodes as a C2PA
    /// manifest store (JSON containing "manifests" or "active_manifest").
    static func findManifestStoreJSON(in data: Data) -> Data? {
        if looksLikeManifestStore(data) { return data }

        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count {
            let size32 = readUInt32(bytes, offset)
            var payloadStart = offset + 8
            var payloadEnd: Int
            var boxSize: Int

            if size32 == 1 {
                // 64-bit extended size: 4-byte size marker + 8-byte size.
                guard offset + 16 <= bytes.count else { break }
                let size64 = readUInt64(bytes, offset + 8)
                guard size64 <= UInt64(bytes.count) else { break }
                payloadStart = offset + 16
                boxSize = Int(size64)
            } else if size32 == 0 {
                boxSize = bytes.count - offset
            } else {
                boxSize = Int(size32)
            }
            guard boxSize >= 8 else { break }
            payloadEnd = offset + boxSize
            guard payloadEnd >= payloadStart, payloadEnd <= bytes.count else { break }

            if let found = findManifestStoreJSON(in: Data(bytes[payloadStart..<payloadEnd])) {
                return found
            }
            if size32 == 0 { break }
            offset = payloadEnd
        }
        return nil
    }

    /// Returns every box payload in the tree, deepest first. The signature
    /// validator uses this to find the claim and COSE boxes without knowing
    /// their exact labels: the payload that decodes as a COSE_Sign1 is the
    /// signature, and the CBOR map payloads are the claim candidates.
    static func boxPayloads(in data: Data) -> [Data] {
        var payloads: [Data] = []
        collectBoxPayloads(data, into: &payloads)
        return payloads
    }

    private static func collectBoxPayloads(_ data: Data, into payloads: inout [Data]) {
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count {
            let size32 = readUInt32(bytes, offset)
            var payloadStart = offset + 8
            var payloadEnd: Int
            var boxSize: Int

            if size32 == 1 {
                guard offset + 16 <= bytes.count else { break }
                let size64 = readUInt64(bytes, offset + 8)
                guard size64 <= UInt64(bytes.count) else { break }
                payloadStart = offset + 16
                boxSize = Int(size64)
            } else if size32 == 0 {
                boxSize = bytes.count - offset
            } else {
                boxSize = Int(size32)
            }
            guard boxSize >= 8 else { break }
            payloadEnd = offset + boxSize
            guard payloadEnd >= payloadStart, payloadEnd <= bytes.count else { break }

            let payload = Data(bytes[payloadStart..<payloadEnd])
            payloads.append(payload)
            // Superboxes nest further boxes; content boxes (json, cbor, ...)
            // carry opaque data that the recursive walk would only misread,
            // so only recurse when the payload starts with a plausible box
            // type (a 4-byte ASCII type at offset 4).
            if payload.count >= 8 {
                let candidate = [UInt8](payload)
                let type = String(bytes: candidate[4..<8], encoding: .ascii) ?? ""
                if type.allSatisfy({ $0.isASCII && !$0.isWhitespace }), type != "json", type != "cbor" {
                    collectBoxPayloads(payload, into: &payloads)
                }
            }
            if size32 == 0 { break }
            offset = payloadEnd
        }
    }

    static func looksLikeManifestStore(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let manifests = object["manifests"] as? [String: Any], !manifests.isEmpty {
            return true
        }
        return object["active_manifest"] != nil
    }

    /// Scans a byte buffer for a "jumb" superbox and returns the manifest
    /// store JSON inside the first one that parses. Used by the JPEG reader,
    /// where the APP11 payload carries the box with a small custom header.
    static func findManifestStoreJSONScanningForSuperbox(in bytes: [UInt8]) -> Data? {
        guard bytes.count >= 12 else { return nil }
        let type: [UInt8] = Array("jumb".utf8)
        var index = 0
        while index + 8 <= bytes.count {
            if Array(bytes[index..<index + 4]) == type {
                let boxStart = max(0, index - 4)
                if let found = findManifestStoreJSON(in: Data(bytes[boxStart...])) {
                    return found
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Byte helpers (big-endian)

    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 where offset + index < bytes.count {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return value
    }
}

// MARK: - JPEG

/// Reads the C2PA manifest store out of a JPEG file without any installed
/// tools. Per the C2PA specification, the store lives in APP11 marker
/// segments: the segment payload starts with the "c2pa" identifier and a
/// counter, followed by the JUMBF box. This reader scans APP11 segments for a
/// "jumb" superbox and extracts the store JSON from it.
public struct JPEGC2PAReader: Sendable {
    public init() {}

    public enum ReadError: Error, Sendable {
        case unreadable(String)
    }

    public func extractManifest(at url: URL) throws -> C2PAManifest? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ReadError.unreadable(url.path)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }

        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { break }
            var markerIndex = offset + 1
            while markerIndex < bytes.count, bytes[markerIndex] == 0xFF {
                markerIndex += 1
            }
            guard markerIndex < bytes.count else { break }
            let marker = bytes[markerIndex]

            // Standalone markers (RST0..RST7, SOI, TEM, EOI) carry no length.
            if marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01 {
                offset = markerIndex + 1
                continue
            }
            // Start of scan: entropy-coded data follows, no more markers.
            if marker == 0xDA || marker == 0xD9 { break }

            guard markerIndex + 3 < bytes.count else { break }
            let length = Int(bytes[markerIndex + 1]) << 8 | Int(bytes[markerIndex + 2])
            guard length >= 2, markerIndex + 2 + length <= bytes.count else { break }
            let payloadStart = markerIndex + 3
            let payloadEnd = payloadStart + (length - 2)

            if marker == 0xEB { // APP11: C2PA manifest store
                let payload = Array(bytes[payloadStart..<payloadEnd])
                if let json = JUMBFScanner.findManifestStoreJSONScanningForSuperbox(in: payload),
                   let string = String(data: json, encoding: .utf8) {
                    return C2PAManifest(storeJSON: string, jumbfData: Data(payload))
                }
            }

            offset = payloadEnd
        }
        return nil
    }

    public func extractManifestStoreJSON(at url: URL) throws -> String? {
        try extractManifest(at: url)?.storeJSON
    }
}

// MARK: - SVG

/// Reads the C2PA manifest store out of an SVG file. Per the C2PA
/// specification, the store is the Base64 text of a `c2pa:manifest` element
/// inside the metadata element. The parser is a tolerant string scan, so
/// namespace prefixes and whitespace differences do not matter.
public struct SVGC2PAReader: Sendable {
    public init() {}

    public enum ReadError: Error, Sendable {
        case unreadable(String)
    }

    public func extractManifest(at url: URL) throws -> C2PAManifest? {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ReadError.unreadable(url.path)
        }
        guard let payload = Self.manifestPayload(from: text) else { return nil }
        let compact = payload.filter { !$0.isWhitespace }
        guard let decoded = Data(base64Encoded: compact),
              let json = JUMBFScanner.findManifestStoreJSON(in: decoded),
              let string = String(data: json, encoding: .utf8)
        else { return nil }
        return C2PAManifest(storeJSON: string, jumbfData: decoded)
    }

    /// Returns the text between the first `c2pa:manifest` open and close tags.
    /// Accepts attributes on the open tag (such as the namespace declaration).
    static func manifestPayload(from text: String) -> String? {
        guard let openRange = text.range(of: "<c2pa:manifest", options: [.caseInsensitive]) else {
            return nil
        }
        let afterOpenTag = text[openRange.upperBound...]
        guard let tagEnd = afterOpenTag.firstIndex(of: ">") else { return nil }
        let content = afterOpenTag[afterOpenTag.index(after: tagEnd)...]
        guard let closeRange = content.range(of: "</c2pa:manifest", options: [.caseInsensitive]) else {
            return nil
        }
        return String(content[..<closeRange.lowerBound])
    }

    public func extractManifestStoreJSON(at url: URL) throws -> String? {
        try extractManifest(at: url)?.storeJSON
    }
}

// MARK: - WebP (RIFF)

/// Reads the C2PA manifest store out of a WebP (RIFF) file. Per the C2PA
/// specification, the store is the data of a `C2PA` chunk, the last
/// sub-chunk of the first RIFF header chunk. RIFF sizes are little-endian.
public struct WebPC2PAReader: Sendable {
    public init() {}

    public enum ReadError: Error, Sendable {
        case unreadable(String)
    }

    public func extractManifest(at url: URL) throws -> C2PAManifest? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ReadError.unreadable(url.path)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP"
        else { return nil }

        let chunkID = Array("C2PA".utf8)
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = Array(bytes[offset..<offset + 4])
            let size = Int(bytes[offset + 4])
                | Int(bytes[offset + 5]) << 8
                | Int(bytes[offset + 6]) << 16
                | Int(bytes[offset + 7]) << 24
            guard offset + 8 + size <= bytes.count else { break }
            let chunkData = Array(bytes[offset + 8..<offset + 8 + size])
            if id == chunkID {
                if let json = JUMBFScanner.findManifestStoreJSON(in: Data(chunkData)),
                   let string = String(data: json, encoding: .utf8) {
                    return C2PAManifest(storeJSON: string, jumbfData: Data(chunkData))
                }
            }
            offset += 8 + size + (size % 2) // chunks pad to even lengths
        }
        return nil
    }

    public func extractManifestStoreJSON(at url: URL) throws -> String? {
        try extractManifest(at: url)?.storeJSON
    }
}

// MARK: - Dispatch

/// Chooses the right built-in reader by magic bytes, so the verifier does not
/// need to trust the file extension.
public struct StandaloneC2PAReader: Sendable {
    public init() {}

    /// The formats the built-in readers cover. These work with no installed
    /// tools; every other supported format needs c2patool for full
    /// verification.
    public static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "svg", "webp"]

    /// Human readable names of the built-in covered formats, for UI copy
    /// that says what works without c2patool. Display order is stable so the
    /// sentence reads naturally ("PNG, JPEG, SVG, and WebP").
    public static let supportedDisplayNames: String = {
        let ordered = ["PNG", "JPEG", "SVG", "WebP"]
        switch ordered.count {
        case 0: return ""
        case 1: return ordered[0]
        case 2: return "\(ordered[0]) and \(ordered[1])"
        default:
            let allButLast = ordered.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(ordered.last!)"
        }
    }()

    public func extractManifest(at url: URL) throws -> C2PAManifest? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PNGC2PAReader.ReadError.unreadable(url.path)
        }
        let bytes = [UInt8](data)

        if bytes.count >= 8,
           Array(bytes[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10] {
            return try PNGC2PAReader().extractManifest(at: url)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return try JPEGC2PAReader().extractManifest(at: url)
        }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            return try WebPC2PAReader().extractManifest(at: url)
        }
        if bytes.count >= 4 {
            let prefix = String(bytes: bytes[0..<min(4, bytes.count)], encoding: .ascii) ?? ""
            if prefix.contains("<") || prefix.lowercased().contains("svg") {
                return try SVGC2PAReader().extractManifest(at: url)
            }
        }
        return nil
    }

    public func extractManifestStoreJSON(at url: URL) throws -> String? {
        try extractManifest(at: url)?.storeJSON
    }
}
