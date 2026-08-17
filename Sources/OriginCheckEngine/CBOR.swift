import Foundation

/// A minimal CBOR decoder (RFC 8949). The engine only needs to *read* CBOR:
/// C2PA manifests are stored as CBOR-encoded JSON and COSE signatures are
/// CBOR structures, so a decoder plus a tiny encoder for the Sig_structure
/// bytes is all that is required. Indefinite-length arrays and maps are
/// supported; tags are preserved as wrappers.
public enum CBOR {
    public struct CBORError: Error, Sendable, CustomStringConvertible {
        public let message: String
        public init(_ message: String) {
            self.message = message
        }
        public var description: String { message }
    }

    public indirect enum Value: Sendable, Equatable {
        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.unsigned(let a), .unsigned(let b)):
                return a == b
            case (.negative(let a), .negative(let b)):
                return a == b
            case (.bytes(let a), .bytes(let b)):
                return a == b
            case (.text(let a), .text(let b)):
                return a == b
            case (.array(let a), .array(let b)):
                return a == b
            case (.map(let a), .map(let b)):
                guard a.count == b.count else { return false }
                for (index, pair) in a.enumerated() {
                    if pair.0 != b[index].0 || pair.1 != b[index].1 { return false }
                }
                return true
            case (.tagged(let a1, let a2), .tagged(let b1, let b2)):
                return a1 == b1 && a2 == b2
            case (.bool(let a), .bool(let b)):
                return a == b
            case (.null, .null):
                return true
            case (.undefined, .undefined):
                return true
            case (.simple(let a), .simple(let b)):
                return a == b
            case (.float(let a), .float(let b)):
                return a == b
            default:
                return false
            }
        }
        case unsigned(UInt64)
        case negative(Int64)
        case bytes([UInt8])
        case text(String)
        case array([Value])
        case map([(Value, Value)])
        case tagged(UInt64, Value)
        case bool(Bool)
        case null
        case undefined
        case simple(UInt8)
        case float(Double)
    }

    // MARK: - Decoding

    public static func decode(_ data: [UInt8]) throws -> Value {
        var cursor = 0
        let value = try decodeValue(data, &cursor)
        return value
    }

    private static func decodeValue(_ data: [UInt8], _ cursor: inout Int) throws -> Value {
        guard cursor < data.count else { throw CBORError("Unexpected end of CBOR data") }
        let initial = data[cursor]
        cursor += 1
        let major = initial >> 5
        let additional = Int(initial & 0x1F)

        switch major {
        case 0:
            return .unsigned(try readArgument(data, &cursor, additional, initial: initial))
        case 1:
            let value = try readArgument(data, &cursor, additional, initial: initial)
            return .negative(-1 - Int64(value))
        case 2:
            let length = try readArgument(data, &cursor, additional, initial: initial)
            let count = Int(length)
            guard count <= data.count - cursor else { throw CBORError("Byte string length out of bounds") }
            let bytes = Array(data[cursor..<(cursor + count)])
            cursor += count
            return .bytes(bytes)
        case 3:
            let length = try readArgument(data, &cursor, additional, initial: initial)
            let count = Int(length)
            guard count <= data.count - cursor else { throw CBORError("Text string length out of bounds") }
            let raw = Array(data[cursor..<(cursor + count)])
            cursor += count
            guard let text = String(bytes: raw, encoding: .utf8) else {
                throw CBORError("Text string is not valid UTF-8")
            }
            return .text(text)
        case 4:
            if additional == 31 {
                var items: [Value] = []
                while true {
                    guard cursor < data.count else { throw CBORError("Unterminated indefinite array") }
                    if data[cursor] == 0xFF { cursor += 1; break }
                    items.append(try decodeValue(data, &cursor))
                }
                return .array(items)
            }
            let count = Int(try readArgument(data, &cursor, additional, initial: initial))
            var items: [Value] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                items.append(try decodeValue(data, &cursor))
            }
            return .array(items)
        case 5:
            if additional == 31 {
                var pairs: [(Value, Value)] = []
                while true {
                    guard cursor < data.count else { throw CBORError("Unterminated indefinite map") }
                    if data[cursor] == 0xFF { cursor += 1; break }
                    let key = try decodeValue(data, &cursor)
                    let value = try decodeValue(data, &cursor)
                    pairs.append((key, value))
                }
                return .map(pairs)
            }
            let count = Int(try readArgument(data, &cursor, additional, initial: initial))
            var pairs: [(Value, Value)] = []
            pairs.reserveCapacity(count)
            for _ in 0..<count {
                let key = try decodeValue(data, &cursor)
                let value = try decodeValue(data, &cursor)
                pairs.append((key, value))
            }
            return .map(pairs)
        case 6:
            let tag = try readArgument(data, &cursor, additional, initial: initial)
            return .tagged(tag, try decodeValue(data, &cursor))
        case 7:
            switch additional {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22: return .null
            case 23: return .undefined
            case 24:
                guard cursor < data.count else { throw CBORError("Unexpected end of CBOR data") }
                let simple = data[cursor]
                cursor += 1
                return .simple(simple)
            case 25:
                let half = try readUInt16(data, &cursor)
                return .float(Self.halfToDouble(half))
            case 26:
                let bits = try readUInt32(data, &cursor)
                return .float(Double(Float(bitPattern: bits)))
            case 27:
                let bits = try readUInt64(data, &cursor)
                return .float(Double(bitPattern: bits))
            default:
                return .simple(UInt8(additional))
            }
        default:
            throw CBORError("Unsupported major type \(major)")
        }
    }

    private static func readArgument(
        _ data: [UInt8],
        _ cursor: inout Int,
        _ additional: Int,
        initial: UInt8
    ) throws -> UInt64 {
        switch additional {
        case 0...23:
            return UInt64(additional)
        case 24:
            guard cursor < data.count else { throw CBORError("Unexpected end of CBOR data") }
            let value = UInt64(data[cursor])
            cursor += 1
            return value
        case 25:
            return UInt64(try readUInt16(data, &cursor))
        case 26:
            return UInt64(try readUInt32(data, &cursor))
        case 27:
            return try readUInt64(data, &cursor)
        default:
            throw CBORError("Indefinite length is not valid for this item")
        }
    }

    private static func readUInt16(_ data: [UInt8], _ cursor: inout Int) throws -> UInt16 {
        guard cursor + 2 <= data.count else { throw CBORError("Unexpected end of CBOR data") }
        let value = UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1])
        cursor += 2
        return value
    }

    private static func readUInt32(_ data: [UInt8], _ cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw CBORError("Unexpected end of CBOR data") }
        let value = UInt32(data[cursor]) << 24
            | UInt32(data[cursor + 1]) << 16
            | UInt32(data[cursor + 2]) << 8
            | UInt32(data[cursor + 3])
        cursor += 4
        return value
    }

    private static func readUInt64(_ data: [UInt8], _ cursor: inout Int) throws -> UInt64 {
        guard cursor + 8 <= data.count else { throw CBORError("Unexpected end of CBOR data") }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[cursor + index])
        }
        cursor += 8
        return value
    }

    /// Converts an IEEE 754 half-precision bit pattern to Double.
    private static func halfToDouble(_ half: UInt16) -> Double {
        let sign = Double((half >> 15) & 1 == 1 ? -1 : 1)
        let exponent = Int((half >> 10) & 0x1F)
        let mantissa = Double(half & 0x3FF)
        switch exponent {
        case 0:
            return sign * mantissa * pow(2, -24)
        case 31:
            return sign * (mantissa == 0 ? .infinity : .nan)
        default:
            return sign * (1 + mantissa / 1024) * pow(2, Double(exponent - 15))
        }
    }

    // MARK: - Convenience accessors

    public static func stringValue(_ value: Value?) -> String? {
        guard case .text(let text) = value else { return nil }
        return text
    }

    public static func bytesValue(_ value: Value?) -> [UInt8]? {
        guard case .bytes(let bytes) = value else { return nil }
        return bytes
    }

    /// Looks up a key in a CBOR map where keys are text strings.
    public static func lookup(_ key: String, in map: [(Value, Value)]) -> Value? {
        for (mapKey, value) in map {
            if case .text(let text) = mapKey, text == key {
                return value
            }
        }
        return nil
    }

    public static func lookup(_ key: Int, in map: [(Value, Value)]) -> Value? {
        for (mapKey, value) in map {
            if case .unsigned(let number) = mapKey, number == UInt64(key) {
                return value
            }
        }
        return nil
    }

    // MARK: - Encoding (only what the Sig_structure needs)

    /// Encodes a text string as a definite-length CBOR string.
    public static func encodeText(_ text: String) -> [UInt8] {
        encodeHeader(3, count: text.utf8.count) + Array(text.utf8)
    }

    /// Encodes a byte string as a definite-length CBOR string.
    public static func encodeBytes(_ bytes: [UInt8]) -> [UInt8] {
        encodeHeader(2, count: bytes.count) + bytes
    }

    /// Encodes an array header with the given item count.
    public static func encodeArrayHeader(_ count: Int) -> [UInt8] {
        encodeHeader(4, count: count)
    }

    /// Encodes a map header with the given pair count.
    public static func encodeMapHeader(_ count: Int) -> [UInt8] {
        encodeHeader(5, count: count)
    }

    /// Encodes a signed integer (negative values use major type 1).
    public static func encodeInteger(_ value: Int64) -> [UInt8] {
        if value >= 0 {
            return encodeHeader(0, count: Int(value))
        }
        return encodeHeader(1, count: Int(-1 - value))
    }

    /// The CBOR null value, used for the detached payload slot in COSE_Sign1.
    public static let nullValue: [UInt8] = [0xF6]

    private static func encodeHeader(_ major: UInt8, count: Int) -> [UInt8] {
        let initial = major << 5
        if count < 24 {
            return [initial | UInt8(count)]
        } else if count <= 0xFF {
            return [initial | 24, UInt8(count)]
        } else if count <= 0xFFFF {
            return [initial | 25, UInt8(count >> 8), UInt8(count & 0xFF)]
        } else {
            return [initial | 26] + withUnsafeBytes(of: UInt32(count).bigEndian, Array.init)
        }
    }
}
