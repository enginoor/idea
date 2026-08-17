import Foundation

/// What the bundled verifier could learn about a C2PA signature without
/// running the reference tool. The distinction is deliberate and honest:
/// the COSE structure and the signing certificate can be read from the file,
/// but the signature MATH is only checked by c2patool, which validates the
/// certificate chain and the content hash too. So `present` means "a
/// signature exists and its identity could be read", never "the signature
/// is valid".
public struct C2PASignatureInfo: Sendable {
    /// True when a readable COSE signature was found in the manifest.
    public let present: Bool
    /// Human-readable signing algorithm (EdDSA, ES256, ...), when known.
    public let algorithm: String?
    /// Common name of the leaf certificate subject, when the cert parses.
    public let signer: String?
    /// Common name or organization of the leaf certificate issuer.
    public let issuer: String?
    /// End of the leaf certificate validity, when the cert parses.
    public let certNotAfter: Date?

    public init(
        present: Bool,
        algorithm: String? = nil,
        signer: String? = nil,
        issuer: String? = nil,
        certNotAfter: Date? = nil
    ) {
        self.present = present
        self.algorithm = algorithm
        self.signer = signer
        self.issuer = issuer
        self.certNotAfter = certNotAfter
    }
}

/// Reads C2PA signature metadata in pure Swift: COSE_Sign1 parsing and
/// minimal X.509 certificate reading for the signer identity. It never
/// touches the network, never runs external code, and never claims more
/// than it proved: signature presence and the identity on the certificate,
/// not signature validity.
///
/// The COSE signature lives in the JUMBF signature box and the certificate
/// chain rides in the x5chain header (label 33). The validator finds the
/// signature by shape rather than by label: a box payload that decodes as a
/// four-element COSE_Sign1 array is the signature.
public struct C2PASignatureReader: Sendable {
    public init() {}

    public func read(storeJSON: String, jumbfData: Data?) -> C2PASignatureInfo {
        var coseBlobs: [Data] = []
        var jsonCertChains: [Data] = []

        if let storeData = storeJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: storeData) as? [String: Any] {
            // Some manifest stores carry a "signatures" array with the
            // base64 COSE and certificate chain inline.
            if let signatures = json["signatures"] as? [[String: Any]] {
                for entry in signatures {
                    if let coseText = entry["cose"] as? String,
                       let cose = Data(base64Encoded: coseText) {
                        coseBlobs.append(cose)
                    }
                    if let chain = entry["cert_chain"] as? [String],
                       let first = chain.compactMap({ Data(base64Encoded: $0) }).first {
                        jsonCertChains.append(first)
                    }
                }
            }
        }

        if let jumbfData {
            for payload in JUMBFScanner.boxPayloads(in: jumbfData) {
                if Self.looksLikeCOSESign1(payload) {
                    coseBlobs.append(payload)
                }
            }
        }

        for blob in coseBlobs {
            if let info = Self.readSingle(blob, jsonCertChains: jsonCertChains) {
                return info
            }
        }
        if !coseBlobs.isEmpty {
            return C2PASignatureInfo(present: true)
        }
        return C2PASignatureInfo(present: false)
    }

    // MARK: - COSE_Sign1 parsing

    /// True when the bytes decode as a COSE_Sign1: a four-element array of
    /// [protected bstr, unprotected map, payload (nil or bstr), signature bstr].
    static func looksLikeCOSESign1(_ data: Data) -> Bool {
        parseCOSESign1([UInt8](data)) != nil
    }

    private struct ParsedSign1 {
        var protected: CBOR.Value
        var unprotected: CBOR.Value
    }

    private static func parseCOSESign1(_ bytes: [UInt8]) -> ParsedSign1? {
        guard let value = try? CBOR.decode(bytes) else { return nil }
        guard case .array(let elements) = value, elements.count == 4 else { return nil }
        guard case .bytes(let protectedRaw) = elements[0],
              case .bytes = elements[3],
              let protected = try? CBOR.decode(protectedRaw)
        else { return nil }
        return ParsedSign1(protected: protected, unprotected: elements[1])
    }

    /// The COSE algorithm label: 1 in the protected header, an integer
    /// (negative for the modern algorithms). EdDSA is -8, ES256 is -7.
    private static func signingAlgorithm(_ sign1: ParsedSign1) -> Int64? {
        guard case .map(let entries) = sign1.protected else { return nil }
        for (key, value) in entries {
            if case .unsigned(1) = key {
                switch value {
                case .negative(let algorithm): return algorithm
                case .unsigned(let algorithm): return Int64(algorithm)
                default: return nil
                }
            }
        }
        return nil
    }

    private static func algorithmName(_ algorithm: Int64?) -> String? {
        switch algorithm {
        case -8: return "EdDSA (Ed25519)"
        case -7: return "ES256"
        case -35: return "ES384"
        case -36: return "ES512"
        case -37: return "PS256"
        case -38: return "PS384"
        case -39: return "PS512"
        default: return nil
        }
    }

    /// The leaf certificate DER bytes: the x5chain header (label 33, in the
    /// protected or unprotected header) or the JSON cert_chain, whichever is
    /// present.
    private static func leafCertificate(_ sign1: ParsedSign1, jsonCertChains: [Data]) -> [UInt8]? {
        var headerValues: [CBOR.Value] = []
        if case .map(let protected) = sign1.protected {
            headerValues.append(contentsOf: protected.map { $0.1 })
        }
        if case .map(let unprotected) = sign1.unprotected {
            headerValues.append(contentsOf: unprotected.map { $0.1 })
        }
        for value in headerValues {
            switch value {
            case .bytes(let der):
                if der.count > 0 { return der }
            case .array(let chain):
                for item in chain {
                    if case .bytes(let der) = item, der.count > 0 { return der }
                }
            default:
                break
            }
        }
        return jsonCertChains.first.map { [UInt8]($0) }
    }

    private static func readSingle(_ coseBlob: Data, jsonCertChains: [Data]) -> C2PASignatureInfo? {
        guard let sign1 = parseCOSESign1([UInt8](coseBlob)) else { return nil }
        let algorithm = signingAlgorithm(sign1)
        let certDER = leafCertificate(sign1, jsonCertChains: jsonCertChains)
        return C2PASignatureInfo(
            present: true,
            algorithm: algorithmName(algorithm),
            signer: certDER.flatMap { X509Reader.commonName(in: $0) },
            issuer: certDER.flatMap { X509Reader.issuerName(in: $0) },
            certNotAfter: certDER.flatMap { X509Reader.validityEnd(in: $0) }
        )
    }
}

// MARK: - Minimal X.509 reading

/// The smallest DER reader that can pull the pieces the verdict needs out of
/// an X.509 certificate: the subject and issuer names and the validity end.
/// It is tolerant: unparseable fields return nil and the verdict proceeds
/// with what it has.
enum X509Reader {
    private struct TLV {
        var tag: UInt8
        var value: [UInt8]
        var children: [TLV]
    }

    private static func parse(_ bytes: [UInt8]) -> [TLV] {
        var tlvs: [TLV] = []
        var offset = 0
        while offset < bytes.count {
            let tag = bytes[offset]
            offset += 1
            guard offset < bytes.count else { break }
            let firstLength = bytes[offset]
            offset += 1
            var length = Int(firstLength)
            if firstLength & 0x80 != 0 {
                let count = Int(firstLength & 0x7F)
                guard count > 0, count <= 4, offset + count <= bytes.count else { break }
                length = 0
                for _ in 0..<count {
                    length = (length << 8) | Int(bytes[offset])
                    offset += 1
                }
            }
            guard offset + length <= bytes.count else { break }
            let value = Array(bytes[offset..<offset + length])
            var children: [TLV] = []
            if tag & 0x20 != 0 { // constructed
                children = parse(value)
            }
            tlvs.append(TLV(tag: tag, value: value, children: children))
            offset += length
        }
        return tlvs
    }

    private static let commonNameOID: [UInt8] = [0x55, 0x04, 0x03] // 2.5.4.3
    private static let organizationOID: [UInt8] = [0x55, 0x04, 0x0A] // 2.5.4.10

    /// The last common name in the certificate, which in an X.509 chain is
    /// the subject (the issuer name appears first).
    static func commonName(in certDER: [UInt8]) -> String? {
        nameStrings(in: certDER, oid: commonNameOID).last
    }

    static func issuerName(in certDER: [UInt8]) -> String? {
        let names = nameStrings(in: certDER, oid: commonNameOID)
        if let first = names.first, names.count > 1 { return first }
        return nameStrings(in: certDER, oid: organizationOID).last
    }

    private static func nameStrings(in certDER: [UInt8], oid: [UInt8]) -> [String] {
        var results: [String] = []
        for tlv in parse(certDER) {
            collectNameStrings(in: tlv, oid: oid, into: &results)
        }
        return results
    }

    private static func collectNameStrings(in tlv: TLV, oid: [UInt8], into results: inout [String]) {
        if tlv.tag == 0x30 {
            // An RDN is SEQUENCE { SET { SEQUENCE { OID, string } } }; the
            // flat parse surfaces that inner SEQUENCE with the OID and the
            // string as siblings.
            for (index, child) in tlv.children.enumerated() {
                if child.tag == 0x06, child.value == oid,
                   index + 1 < tlv.children.count,
                   let name = stringValue(tlv.children[index + 1]) {
                    results.append(name)
                }
            }
        }
        for child in tlv.children {
            collectNameStrings(in: child, oid: oid, into: &results)
        }
    }

    private static func stringValue(_ tlv: TLV) -> String? {
        switch tlv.tag {
        case 0x0C, 0x13, 0x14, 0x16: // UTF8String, PrintableString, TeletexString, IA5String
            return String(bytes: tlv.value, encoding: .utf8)
        default:
            return nil
        }
    }

    /// The notAfter time from the validity SEQUENCE, when it parses.
    static func validityEnd(in certDER: [UInt8]) -> Date? {
        for tlv in parse(certDER) {
            if let date = validityEnd(in: tlv) { return date }
        }
        return nil
    }

    private static func validityEnd(in tlv: TLV) -> Date? {
        if tlv.tag == 0x30, tlv.children.count == 2 {
            let timeTags = tlv.children.filter { $0.tag == 0x17 || $0.tag == 0x18 } // UTCTime, GeneralizedTime
            if timeTags.count == 2, let notAfter = parseTime(timeTags[1]) {
                return notAfter
            }
        }
        for child in tlv.children {
            if let date = validityEnd(in: child) { return date }
        }
        return nil
    }

    private static func parseTime(_ tlv: TLV) -> Date? {
        let text = String(bytes: tlv.value, encoding: .ascii) ?? ""
        if tlv.tag == 0x17 { // UTCTime: YYMMDDHHMMSSZ
            guard text.count >= 13, text.hasSuffix("Z") else { return nil }
            let year = Int(text.prefix(2)).map { $0 >= 50 ? 1900 + $0 : 2000 + $0 } ?? 0
            let rest = String(text.dropFirst(2).dropLast())
            return dateFrom(year: year, rest: rest)
        }
        if tlv.tag == 0x18 { // GeneralizedTime: YYYYMMDDHHMMSSZ
            guard text.count >= 15, text.hasSuffix("Z") else { return nil }
            let year = Int(text.prefix(4)) ?? 0
            let rest = String(text.dropFirst(4).dropLast())
            return dateFrom(year: year, rest: rest)
        }
        return nil
    }

    private static func dateFrom(year: Int, rest: String) -> Date? {
        // rest is MM DD HH MM SS, 10 digits for both UTCTime and GeneralizedTime.
        guard rest.count >= 10 else { return nil }
        let month = Int(rest.dropFirst(0).prefix(2)) ?? 0
        let day = Int(rest.dropFirst(2).prefix(2)) ?? 0
        let hour = Int(rest.dropFirst(4).prefix(2)) ?? 0
        let minute = Int(rest.dropFirst(6).prefix(2)) ?? 0
        let second = Int(rest.dropFirst(8).prefix(2)) ?? 0
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
