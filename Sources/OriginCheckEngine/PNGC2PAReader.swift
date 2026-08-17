import Foundation

/// A self-contained reader for C2PA provenance metadata in PNG files.
///
/// The C2PA spec stores the manifest in an `iTXt` chunk whose keyword is
/// `c2pa`; the chunk text is the Base64 encoding of a JUMBF superbox that
/// contains the manifest store (JSON) and the signature box. This reader
/// walks the PNG chunks, decodes the Base64, and finds the manifest store
/// JSON inside the JUMBF box structure.
///
/// It does not verify the signature: that needs certificate-chain
/// validation, which the `c2patool` reference tool performs. What the
/// built-in reader CAN prove is that a provenance manifest exists, who
/// claims to have created the file, and with which tool. The verdict is
/// therefore honest about what it knows: manifest present, signature
/// unverifiable without the tool.
///
/// This is what makes file verification work out of the box: PNG is the
/// most common format for AI-generated images, and a user should not have
/// to install a Rust tool just to check one.
public struct PNGC2PAReader: Sendable {
    public init() {}

    public enum ReadError: Error, Sendable {
        case unreadable(String)
    }

    /// Returns the manifest store JSON found in the file, or nil when the
    /// file is not a PNG or carries no readable `c2pa` iTXt chunk.
    public func extractManifestStoreJSON(at url: URL) throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ReadError.unreadable(url.path)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<8]) == Self.pngSignature else { return nil }

        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(Self.readUInt32(bytes, offset))
            let type = Self.readType(bytes, offset + 4)
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + length
            guard chunkEnd <= bytes.count else { return nil }

            if type == "iTXt",
               let text = Self.parseITXtText(Array(bytes[chunkStart..<chunkEnd]), keyword: "c2pa"),
               let decoded = Data(base64Encoded: text.filter { !$0.isWhitespace }),
               let json = Self.findManifestStoreJSON(in: decoded),
               let string = String(data: json, encoding: .utf8) {
                return string
            }

            if type == "IEND" { break }
            offset = chunkEnd + 4 // skip the CRC
        }
        return nil
    }

    // MARK: - PNG chunk parsing

    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    /// Parses an iTXt chunk body and returns the text field when the keyword
    /// matches. Compressed text is not supported (c2pa stores plain ASCII),
    /// so a compressed chunk yields nil rather than garbage.
    static func parseITXtText(_ body: [UInt8], keyword: String) -> String? {
        guard let keywordEnd = body.firstIndex(of: 0) else { return nil }
        guard let chunkKeyword = String(bytes: body[..<keywordEnd], encoding: .utf8),
              chunkKeyword == keyword
        else { return nil }

        var index = keywordEnd + 1
        guard index < body.count else { return nil }
        let compressionFlag = body[index]
        index += 1
        guard index < body.count else { return nil }
        // compression method byte (ignored when the flag is 0)
        index += 1

        // language tag, NUL-terminated
        guard let languageEnd = body[index...].firstIndex(of: 0) else { return nil }
        index = languageEnd + 1
        // translated keyword, NUL-terminated
        guard let translatedEnd = body[index...].firstIndex(of: 0) else { return nil }
        index = translatedEnd + 1

        guard compressionFlag == 0 else { return nil }
        let textBytes = body[index...]
        return String(bytes: textBytes, encoding: .utf8)
    }

    // MARK: - JUMBF scanning

    /// Recursively walks JUMBF boxes and returns the first payload that
    /// decodes as a C2PA manifest store (JSON containing "manifests" or
    /// "active_manifest"). Tolerant by design: anything it cannot parse is
    /// skipped, and the verdict falls back to "no manifest" rather than
    /// guessing.
    static func findManifestStoreJSON(in data: Data) -> Data? {
        if Self.looksLikeManifestStore(data) { return data }

        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count {
            let size32 = Self.readUInt32(bytes, offset)
            var payloadStart = offset + 8
            var payloadEnd: Int
            var boxSize: Int

            if size32 == 1 {
                // 64-bit extended size: 4-byte size marker + 8-byte size.
                guard offset + 16 <= bytes.count else { break }
                let size64 = Self.readUInt64(bytes, offset + 8)
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

    static func looksLikeManifestStore(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let manifests = object["manifests"] as? [String: Any], !manifests.isEmpty {
            return true
        }
        return object["active_manifest"] != nil
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

    static func readType(_ bytes: [UInt8], _ offset: Int) -> String {
        guard offset + 4 <= bytes.count else { return "" }
        return String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
    }
}
