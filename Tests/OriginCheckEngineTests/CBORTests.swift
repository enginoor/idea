import XCTest
@testable import OriginCheckEngine

final class CBORTests: XCTestCase {
    func testSimpleValues() throws {
        XCTAssertEqual(try CBOR.decode([0x01]), .unsigned(1))
        XCTAssertEqual(try CBOR.decode([0x18, 0x64]), .unsigned(100))
        XCTAssertEqual(try CBOR.decode([0x20]), .negative(-1))
        XCTAssertEqual(try CBOR.decode([0x61, 0x61]), .text("a"))
        XCTAssertEqual(try CBOR.decode([0x42, 0x01, 0x02]), .bytes([1, 2]))
        XCTAssertEqual(try CBOR.decode([0xF4]), .bool(false))
        XCTAssertEqual(try CBOR.decode([0xF5]), .bool(true))
        XCTAssertEqual(try CBOR.decode([0xF6]), .null)
    }

    func testArrayAndMap() throws {
        let decoded = try CBOR.decode([0x83, 0x01, 0x02, 0x03])
        XCTAssertEqual(decoded, .array([.unsigned(1), .unsigned(2), .unsigned(3)]))

        let map = try CBOR.decode([0xA2, 0x01, 0x02, 0x61, 0x61, 0x61, 0x62])
        XCTAssertEqual(map, .map([(.unsigned(1), .unsigned(2)), (.text("a"), .text("b"))]))
    }

    func testIndefiniteArray() throws {
        let decoded = try CBOR.decode([0x9F, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertEqual(decoded, .array([.unsigned(1), .unsigned(2), .unsigned(3)]))
    }

    func testEncodeText() {
        XCTAssertEqual(CBOR.encodeText("a"), [0x61, 0x61])
    }

    func testEncodeBytes() {
        XCTAssertEqual(CBOR.encodeBytes([1, 2]), [0x42, 0x01, 0x02])
    }

    func testEncodeArrayHeader() {
        XCTAssertEqual(CBOR.encodeArrayHeader(4), [0x84])
        XCTAssertEqual(CBOR.encodeArrayHeader(25), [0x98, 0x19])
    }

    func testEncodeMapHeader() {
        XCTAssertEqual(CBOR.encodeMapHeader(2), [0xA2])
        XCTAssertEqual(CBOR.encodeMapHeader(0), [0xA0])
    }

    func testEncodeInteger() throws {
        XCTAssertEqual(CBOR.encodeInteger(1), [0x01])
        XCTAssertEqual(CBOR.encodeInteger(33), [0x18, 0x21])
        XCTAssertEqual(CBOR.encodeInteger(-8), [0x27])
        XCTAssertEqual(CBOR.encodeInteger(-7), [0x26])
        // Round trips through the decoder.
        XCTAssertEqual(try CBOR.decode(CBOR.encodeInteger(-8)), .negative(-8))
        XCTAssertEqual(try CBOR.decode(CBOR.encodeInteger(33)), .unsigned(33))
    }

    func testNullValueDecodes() throws {
        XCTAssertEqual(try CBOR.decode(CBOR.nullValue), .null)
    }

    func testCOSEShapeDecodes() throws {
        // The exact shape the signature reader looks for:
        // [protected bstr, unprotected map, null, signature bstr]
        let protected = CBOR.encodeBytes(CBOR.encodeMapHeader(2)
            + CBOR.encodeInteger(1) + CBOR.encodeInteger(-8)
            + CBOR.encodeInteger(33) + CBOR.encodeArrayHeader(1) + CBOR.encodeBytes([1, 2, 3]))
        var cose: [UInt8] = CBOR.encodeArrayHeader(4)
        cose += protected
        cose += CBOR.encodeMapHeader(0)
        cose += CBOR.nullValue
        cose += CBOR.encodeBytes([UInt8](repeating: 0xAB, count: 64))
        let decoded = try CBOR.decode(cose)
        guard case .array(let elements) = decoded else {
            return XCTFail("expected a COSE array")
        }
        XCTAssertEqual(elements.count, 4)
    }
}
