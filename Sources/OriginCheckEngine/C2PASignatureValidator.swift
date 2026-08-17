import Foundation

/// What the bundled verifier could learn about a C2PA signature without
/// running the reference tool. The distinction is deliberate and honest:
/// the COSE structure, the signing certificate, and (for EdDSA) the
/// signature math can be checked in pure Swift, but the certificate chain
/// trust and the file content hash still need c2patool. So `present` means
/// "a signature exists", `signatureValid` means "the Ed25519 claim
/// signature verifies", and neither ever claims the file is unchanged.
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
    /// True when the Ed25519 claim signature verifies, false when it does
    /// not, nil when the built-in verifier cannot check it (unsupported
    /// algorithm, missing certificate, or missing claim bytes).
    public let signatureValid: Bool?

    public init(
        present: Bool,
        algorithm: String? = nil,
        signer: String? = nil,
        issuer: String? = nil,
        certNotAfter: Date? = nil,
        signatureValid: Bool? = nil
    ) {
        self.present = present
        self.algorithm = algorithm
        self.signer = signer
        self.issuer = issuer
        self.certNotAfter = certNotAfter
        self.signatureValid = signatureValid
    }
}

/// Reads and verifies C2PA signatures in pure Swift: COSE_Sign1 parsing,
/// minimal X.509 certificate reading for the signer identity and the
/// Ed25519 public key, and the Ed25519 math itself. It never touches the
/// network and never runs external code.
///
/// What it can prove: that the COSE signature authenticates the claim bytes
/// with the public key in the leaf certificate. What it cannot prove
/// without c2patool: that the leaf certificate is trusted by a chain, and
/// that the file content still matches the hash inside the claim. The
/// verdict says exactly which is which.
///
/// The COSE signature lives in the JUMBF signature box and the certificate
/// chain rides in the x5chain header (label 33). The reader finds the
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
                let verified = Self.verifySign1(
                    blob,
                    storeJSON: storeJSON,
                    jumbfData: jumbfData
                )
                return C2PASignatureInfo(
                    present: true,
                    algorithm: info.algorithm,
                    signer: info.signer,
                    issuer: info.issuer,
                    certNotAfter: info.certNotAfter,
                    signatureValid: verified
                )
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
        parseSign1([UInt8](data)) != nil
    }

    /// Everything the verifier needs out of a COSE_Sign1 message.
    struct ParsedSign1 {
        /// The exact protected-header bytes as they appear in the message;
        /// the Sig_structure signs them verbatim.
        var protectedRaw: [UInt8]
        var algorithm: Int64?
        /// The signature value from the message.
        var signature: [UInt8]
        /// The detached payload from the message, when the payload is
        /// embedded rather than detached.
        var embeddedPayload: [UInt8]?
        /// The raw Ed25519 public key from the x5chain leaf certificate,
        /// when the cert parses as an Ed25519 key.
        var ed25519PublicKey: [UInt8]?
        /// The leaf certificate DER, when an x5chain header is present.
        var leafCertificateDER: [UInt8]?
    }

    static func parseSign1(_ bytes: [UInt8]) -> ParsedSign1? {
        guard let value = try? CBOR.decode(bytes) else { return nil }
        guard case .array(let elements) = value, elements.count == 4 else { return nil }
        guard case .bytes(let protectedRaw) = elements[0],
              case .bytes(let signature) = elements[3],
              let protected = try? CBOR.decode(protectedRaw)
        else { return nil }

        var algorithm: Int64?
        if case .map(let entries) = protected {
            for (key, entryValue) in entries {
                if case .unsigned(1) = key {
                    switch entryValue {
                    case .negative(let value): algorithm = value
                    case .unsigned(let value): algorithm = Int64(value)
                    default: break
                    }
                }
            }
        }

        var embeddedPayload: [UInt8]?
        if case .bytes(let payload) = elements[2] {
            embeddedPayload = payload
        }

        // The x5chain header (label 33) is legal in either header: real
        // C2PA writers place it in the unprotected header, and some fixtures
        // and older writers put it in the protected one. Scan unprotected
        // first, then protected, so both layouts read.
        var leafCertificateDER: [UInt8]?
        if case .map(let unprotected) = elements[1] {
            leafCertificateDER = Self.leafCertificateDER(fromHeaderEntries: unprotected)
        }
        if leafCertificateDER == nil, case .map(let protectedEntries) = protected {
            leafCertificateDER = Self.leafCertificateDER(fromHeaderEntries: protectedEntries)
        }

        return ParsedSign1(
            protectedRaw: protectedRaw,
            algorithm: algorithm,
            signature: signature,
            embeddedPayload: embeddedPayload,
            ed25519PublicKey: leafCertificateDER.flatMap { X509Reader.subjectPublicKey(in: $0) },
            leafCertificateDER: leafCertificateDER
        )
    }

    /// Pulls the leaf certificate DER out of a COSE header map: the
    /// x5chain parameter (label 33) is either an array of DER certificates
    /// or a single DER blob.
    private static func leafCertificateDER(fromHeaderEntries entries: [(CBOR.Value, CBOR.Value)]) -> [UInt8]? {
        for (key, entryValue) in entries {
            if case .unsigned(33) = key { // x5chain
                switch entryValue {
                case .array(let chain):
                    for item in chain {
                        if case .bytes(let der) = item, der.count > 8 {
                            return der
                        }
                    }
                case .bytes(let der):
                    if der.count > 8 { return der }
                default:
                    break
                }
            }
        }
        return nil
    }

    /// The COSE algorithm label: 1 in the protected header, an integer
    /// (negative for the modern algorithms). EdDSA is -8, ES256 is -7.
    private static func signingAlgorithm(_ sign1: ParsedSign1) -> Int64? {
        sign1.algorithm
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
        if let der = sign1.leafCertificateDER { return der }
        return jsonCertChains.first.map { [UInt8]($0) }
    }

    private static func readSingle(_ coseBlob: Data, jsonCertChains: [Data]) -> C2PASignatureInfo? {
        guard let sign1 = parseSign1([UInt8](coseBlob)) else { return nil }
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

    // MARK: - Ed25519 verification

    /// The claim bytes a C2PA COSE signature covers (the detached payload):
    /// the base64 "claim" field of the active manifest in the store JSON, or
    /// the first JUMBF payload that decodes as a CBOR map and is not itself
    /// the COSE signature. Returns nil when neither source is readable.
    private static func claimBytes(storeJSON: String, jumbfData: Data?) -> [UInt8]? {
        if let fromJSON = claimBytesFromStoreJSON(storeJSON) {
            return fromJSON
        }
        guard let jumbfData else { return nil }
        for payload in JUMBFScanner.boxPayloads(in: jumbfData) {
            guard payload.count > 16, !looksLikeCOSESign1(payload) else { continue }
            if case .map = try? CBOR.decode([UInt8](payload)) {
                return [UInt8](payload)
            }
        }
        return nil
    }

    private static func claimBytesFromStoreJSON(_ storeJSON: String) -> [UInt8]? {
        guard let data = storeJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = json["active_manifest"] as? String,
              let manifests = json["manifests"] as? [String: Any],
              let entry = manifests[active] as? [String: Any],
              let claimText = entry["claim"] as? String,
              let claim = Data(base64Encoded: claimText),
              !claim.isEmpty
        else { return nil }
        return [UInt8](claim)
    }

    /// Builds the COSE Sig_structure bytes (RFC 9052 section 4.4):
    /// `[context, body_protected, external_aad, payload]`. For C2PA the
    /// external_aad is empty and the payload slot carries the claim bytes
    /// even when the message stores them detached, because the signature
    /// always covers the full payload.
    static func sigStructure(protected: [UInt8], payload: [UInt8]) -> [UInt8] {
        CBOR.encodeArrayHeader(4)
            + CBOR.encodeText("Signature1")
            + CBOR.encodeBytes(protected)
            + CBOR.encodeBytes([])
            + CBOR.encodeBytes(payload)
    }

    /// Verifies the Ed25519 signature over the Sig_structure with the
    /// public key from the leaf certificate. Returns nil (not false) when
    /// the algorithm is not EdDSA, when no Ed25519 key is readable from the
    /// certificate, or when no claim bytes are available: those cases mean
    /// "cannot verify with the built-in verifier", not "invalid".
    static func verifySign1(_ coseBlob: Data, storeJSON: String, jumbfData: Data?) -> Bool? {
        guard let sign1 = parseSign1([UInt8](coseBlob)) else { return nil }
        guard sign1.algorithm == -8 else { return nil }
        guard let publicKey = sign1.ed25519PublicKey else { return nil }
        guard let claim = sign1.embeddedPayload ?? claimBytes(storeJSON: storeJSON, jumbfData: jumbfData) else {
            return nil
        }
        let structure = sigStructure(protected: sign1.protectedRaw, payload: claim)
        return Ed25519.verify(
            signature: sign1.signature,
            message: structure,
            publicKey: publicKey
        )
    }
}

// MARK: - Minimal X.509 reading

/// The smallest DER reader that can pull the pieces the verdict needs out of
/// an X.509 certificate: the subject and issuer names, the validity end,
/// and the Ed25519 public key. It is tolerant: unparseable fields return
/// nil and the verdict proceeds with what it has.
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

    /// The raw Ed25519 public key from the certificate's
    /// SubjectPublicKeyInfo: the BIT STRING whose content is the unused-bits
    /// marker 0x00 followed by exactly 32 key bytes. Returns nil for other
    /// key types; the certificate's signature BIT STRING is 65 bytes and is
    /// excluded by the length check.
    static func subjectPublicKey(in certDER: [UInt8]) -> [UInt8]? {
        for tlv in parse(certDER) {
            if let key = subjectPublicKey(in: tlv) { return key }
        }
        return nil
    }

    private static func subjectPublicKey(in tlv: TLV) -> [UInt8]? {
        if tlv.tag == 0x03, tlv.value.count == 33, tlv.value[0] == 0x00 {
            return Array(tlv.value.dropFirst())
        }
        for child in tlv.children {
            if let key = subjectPublicKey(in: child) { return key }
        }
        return nil
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
