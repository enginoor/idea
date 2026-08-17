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
        try extractManifest(at: url)?.storeJSON
    }

    /// Returns the manifest store JSON and the JUMBF bytes it was found in.
    /// The JUMBF bytes let the signature validator reach the claim and
    /// signature boxes that sit alongside the store JSON box.
    public func extractManifest(at url: URL) throws -> C2PAManifest? {
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
               let json = JUMBFScanner.findManifestStoreJSON(in: decoded),
               let string = String(data: json, encoding: .utf8) {
                return C2PAManifest(storeJSON: string, jumbfData: decoded)
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

    // MARK: - PNG chunk parsing helpers

    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    static func readType(_ bytes: [UInt8], _ offset: Int) -> String {
        guard offset + 4 <= bytes.count else { return "" }
        return String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
    }
}
