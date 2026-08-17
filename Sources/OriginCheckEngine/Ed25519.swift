import Foundation

/// Pure-Ed25519 signature verification (RFC 8032 section 5.1), written from
/// the specification so the engine stays dependency free and testable on
/// Linux. Only verification is implemented: the app never signs anything.
///
/// The implementation uses the classic 5-limb 51-bit field representation
/// with a 128-bit accumulator for products. It is deliberately simple
/// double-and-add scalar multiplication, since verification has no
/// side-channel requirements.
public enum Ed25519 {
    /// Verifies an Ed25519 signature over `message` with the given 32-byte
    /// public key. Returns false for malformed inputs, non-canonical
    /// scalars, or a failed check.
    public static func verify(signature: [UInt8], message: [UInt8], publicKey: [UInt8]) -> Bool {
        guard signature.count == 64, publicKey.count == 32,
              Scalar.isCanonical(Array(signature[32..<64])) else { return false }
        guard let a = Point.decompress(publicKey),
              let r = Point.decompress(Array(signature[0..<32])) else { return false }

        // h = SHA-512(R || A || M) reduced mod L.
        let hram = Scalar.reduce64(SHA512.digest(Array(signature[0..<32]) + publicKey + message))
        // [S]B must equal R + [h]A.
        let sB = Point.scalarMultBase(Array(signature[32..<64]))
        let hA = Point.scalarMult(hram.bytes(), a)
        return sB.add(r.add(hA).negated()).isIdentity
    }

    // MARK: - Field element (mod p = 2^255 - 19)

    struct FieldElement: Equatable {
        /// Five 51-bit limbs, little-endian by weight. Limbs stay below
        /// 2^51 + 2^13 between operations; `canonicalized` produces the
        /// strict form used by byte conversion.
        var l0: UInt64
        var l1: UInt64
        var l2: UInt64
        var l3: UInt64
        var l4: UInt64

        static let mask51: UInt64 = (1 << 51) - 1

        static let zero = FieldElement(0, 0, 0, 0, 0)
        static let one = FieldElement(1, 0, 0, 0, 0)

        /// -121665/121666 mod p, the Edwards curve constant.
        static let d = FieldElement(hex: "52036CEE2B6FFE738CC740797779E89800700A4D4141D8AB75EB4DCA135978A3")
        static let twoD = d.add(d)

        /// 2^((p - 1)/4), the square root of -1.
        static let sqrtM1 = FieldElement(hex: "2B8324804FC1DF0B2B4D00993DFBD7A72F431806AD2FE478C4EE1B274A0EA0B0")

        /// (p - 5) / 8 = 2^252 - 3, used by point decompression.
        static let decompressExponent: [UInt8] = [0xFD] + [UInt8](repeating: 0xFF, count: 30) + [0x0F]

        init(_ l0: UInt64, _ l1: UInt64, _ l2: UInt64, _ l3: UInt64, _ l4: UInt64) {
            self.l0 = l0
            self.l1 = l1
            self.l2 = l2
            self.l3 = l3
            self.l4 = l4
        }

        init(hex: String) {
            var bytes: [UInt8] = []
            var text = hex
            if text.count % 2 != 0 { text = "0" + text }
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                bytes.append(UInt8(text[index..<next], radix: 16) ?? 0)
                index = next
            }
            // Hex is big-endian; the field loader wants little-endian bytes.
            self = FieldElement.fromBytes(bytes.reversed())
        }

        /// Loads 32 little-endian bytes into 5 limbs. Bit 255 (the sign bit
        /// in point encodings) is not part of the field and must be clear.
        static func fromBytes(_ bytes: [UInt8]) -> FieldElement {
            func load64(_ offset: Int) -> UInt64 {
                var value: UInt64 = 0
                for j in 0..<8 {
                    let byte = offset + j < bytes.count ? bytes[offset + j] : 0
                    value |= UInt64(byte) << (8 * j)
                }
                return value
            }
            let c0 = load64(0)
            let c1 = load64(8)
            let c2 = load64(16)
            let c3 = load64(24)
            return FieldElement(
                c0 & mask51,
                ((c0 >> 51) | (c1 << 13)) & mask51,
                ((c1 >> 38) | (c2 << 26)) & mask51,
                ((c2 >> 25) | (c3 << 39)) & mask51,
                (c3 >> 12) & mask51
            )
        }

        /// Serializes to 32 little-endian bytes after full reduction.
        func toBytes() -> [UInt8] {
            let e = canonicalized()
            let w0 = e.l0 | ((e.l1 & 0x1FFF) << 51)
            let w1 = (e.l1 >> 13) | ((e.l2 & 0x3FFFFFF) << 38)
            let w2 = (e.l2 >> 26) | ((e.l3 & 0x7FFFFFFFFF) << 25)
            let w3 = (e.l3 >> 39) | (e.l4 << 12)
            var out = [UInt8](repeating: 0, count: 32)
            for i in 0..<4 {
                let word = [w0, w1, w2, w3][i]
                for j in 0..<8 {
                    out[i * 8 + j] = UInt8((word >> (8 * j)) & 0xFF)
                }
            }
            return out
        }

        static func == (lhs: FieldElement, rhs: FieldElement) -> Bool {
            lhs.toBytes() == rhs.toBytes()
        }

        // MARK: Field operations

        /// One carry pass: limbs land below 2^51 + 2^13, which is the bound
        /// the multiplier needs. The value is preserved mod p.
        static func reduce(_ l0: UInt64, _ l1: UInt64, _ l2: UInt64, _ l3: UInt64, _ l4: UInt64) -> FieldElement {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3, l4 = l4
            var c = l0 >> 51; l0 &= mask51; l1 &+= c
            c = l1 >> 51; l1 &= mask51; l2 &+= c
            c = l2 >> 51; l2 &= mask51; l3 &+= c
            c = l3 >> 51; l3 &= mask51; l4 &+= c
            c = l4 >> 51; l4 &= mask51
            l0 &+= c &* 19
            c = l0 >> 51; l0 &= mask51; l1 &+= c
            return FieldElement(l0, l1, l2, l3, l4)
        }

        func add(_ b: FieldElement) -> FieldElement {
            FieldElement.reduce(l0 &+ b.l0, l1 &+ b.l1, l2 &+ b.l2, l3 &+ b.l3, l4 &+ b.l4)
        }

        func sub(_ b: FieldElement) -> FieldElement {
            // a - b mod p via 256-bit arithmetic: t = a - b + p with wrapping
            // (the wrap cancels exactly because t lands in [1, 2p)), then one
            // conditional subtraction of p. Both operands are canonical, so
            // the result is the canonical residue.
            let a = FieldElement.words(from: canonicalized().toBytes())
            let c = FieldElement.words(from: b.canonicalized().toBytes())
            var t = FieldElement.subtractWords(a, c) // wraps mod 2^256
            t = FieldElement.addWords(t, FieldElement.pWords) // wraps
            if FieldElement.wordsAreGE(t, FieldElement.pWords) {
                t = FieldElement.subtractWords(t, FieldElement.pWords)
            }
            return FieldElement.fromWords(t)
        }

        // MARK: 256-bit helpers for subtraction

        /// p = 2^255 - 19 as four little-endian 64-bit words.
        static let pWords: (UInt64, UInt64, UInt64, UInt64) = (
            0xFFFFFFFFFFFFFFED,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            0x7FFFFFFFFFFFFFFF
        )

        static func words(from bytes: [UInt8]) -> (UInt64, UInt64, UInt64, UInt64) {
            func load(_ offset: Int) -> UInt64 {
                var value: UInt64 = 0
                for j in 0..<8 {
                    let byte = offset + j < bytes.count ? bytes[offset + j] : 0
                    value |= UInt64(byte) << (8 * j)
                }
                return value
            }
            return (load(0), load(8), load(16), load(24))
        }

        static func fromWords(_ words: (UInt64, UInt64, UInt64, UInt64)) -> FieldElement {
            var bytes = [UInt8](repeating: 0, count: 32)
            for (i, word) in [words.0, words.1, words.2, words.3].enumerated() {
                for j in 0..<8 {
                    bytes[i * 8 + j] = UInt8((word >> (8 * j)) & 0xFF)
                }
            }
            return FieldElement.fromBytes(bytes)
        }

        static func addWords(
            _ a: (UInt64, UInt64, UInt64, UInt64),
            _ b: (UInt64, UInt64, UInt64, UInt64)
        ) -> (UInt64, UInt64, UInt64, UInt64) {
            var carry: UInt64 = 0
            var out = [UInt64](repeating: 0, count: 4)
            let av = [a.0, a.1, a.2, a.3]
            let bv = [b.0, b.1, b.2, b.3]
            for i in 0..<4 {
                let sum = av[i].addingReportingOverflow(bv[i])
                let withCarry = sum.partialValue.addingReportingOverflow(carry)
                out[i] = withCarry.partialValue
                carry = (sum.overflow ? 1 : 0) | (withCarry.overflow ? 1 : 0)
            }
            return (out[0], out[1], out[2], out[3])
        }

        static func subtractWords(
            _ a: (UInt64, UInt64, UInt64, UInt64),
            _ b: (UInt64, UInt64, UInt64, UInt64)
        ) -> (UInt64, UInt64, UInt64, UInt64) {
            var borrow: UInt64 = 0
            var out = [UInt64](repeating: 0, count: 4)
            let av = [a.0, a.1, a.2, a.3]
            let bv = [b.0, b.1, b.2, b.3]
            for i in 0..<4 {
                let withBorrow = av[i].subtractingReportingOverflow(borrow)
                let diff = withBorrow.partialValue.subtractingReportingOverflow(bv[i])
                out[i] = diff.partialValue
                borrow = (withBorrow.overflow ? 1 : 0) | (diff.overflow ? 1 : 0)
            }
            return (out[0], out[1], out[2], out[3])
        }

        static func wordsAreGE(
            _ a: (UInt64, UInt64, UInt64, UInt64),
            _ b: (UInt64, UInt64, UInt64, UInt64)
        ) -> Bool {
            let aw = [a.0, a.1, a.2, a.3]
            let bw = [b.0, b.1, b.2, b.3]
            for i in stride(from: 3, through: 0, by: -1) {
                if aw[i] != bw[i] { return aw[i] > bw[i] }
            }
            return true
        }

        func negate() -> FieldElement {
            FieldElement.zero.sub(self)
        }

        func mul(_ b: FieldElement) -> FieldElement {
            let a = [l0, l1, l2, l3, l4]
            let c = [b.l0, b.l1, b.l2, b.l3, b.l4]
            var r = [Wide](repeating: Wide(), count: 9)
            for i in 0..<5 {
                for j in 0..<5 {
                    r[i + j].addProduct(a[i], c[j])
                }
            }
            // Fold the limbs above 255 bits: 2^255 = 19 mod p.
            for i in 5..<9 {
                r[i - 5].addScaled(r[i], by: 19)
            }
            var limbs = [UInt64](repeating: 0, count: 5)
            var carry = Wide()
            for i in 0..<5 {
                let v = r[i].adding(carry)
                limbs[i] = v.lo & FieldElement.mask51
                carry = v.shiftedRight51()
            }
            limbs[0] &+= carry.lo &* 19
            return FieldElement.reduce(limbs[0], limbs[1], limbs[2], limbs[3], limbs[4])
        }

        func squared() -> FieldElement {
            mul(self)
        }

        /// Raises to a 256-bit little-endian exponent by square and multiply.
        func pow(_ exponent: [UInt8]) -> FieldElement {
            var result = FieldElement.one
            var base = self
            for byte in exponent {
                var b = byte
                for _ in 0..<8 {
                    if b & 1 == 1 { result = result.mul(base) }
                    base = base.mul(base)
                    b >>= 1
                }
            }
            return result
        }

        var isOdd: Bool {
            toBytes()[0] & 1 == 1
        }

        /// Fully reduces to limbs below 2^51 and to a value below p.
        func canonicalized() -> FieldElement {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3, l4 = l4
            for _ in 0..<4 {
                var c = l0 >> 51; l0 &= FieldElement.mask51; l1 &+= c
                c = l1 >> 51; l1 &= FieldElement.mask51; l2 &+= c
                c = l2 >> 51; l2 &= FieldElement.mask51; l3 &+= c
                c = l3 >> 51; l3 &= FieldElement.mask51; l4 &+= c
                c = l4 >> 51; l4 &= FieldElement.mask51
                l0 &+= c &* 19
                if l0 < (1 << 51), l1 < (1 << 51), l2 < (1 << 51), l3 < (1 << 51), l4 < (1 << 51) {
                    break
                }
            }
            if FieldElement.isGreaterThanOrEqualToP(l0, l1, l2, l3, l4) {
                (l0, l1, l2, l3, l4) = FieldElement.subtractP(l0, l1, l2, l3, l4)
            }
            return FieldElement(l0, l1, l2, l3, l4)
        }

        private static func isGreaterThanOrEqualToP(
            _ l0: UInt64, _ l1: UInt64, _ l2: UInt64, _ l3: UInt64, _ l4: UInt64
        ) -> Bool {
            // p = 2^255 - 19 in base 2^51 is the digits
            // [2^51 - 19, 2^51 - 1, 2^51 - 1, 2^51 - 1, 2^51 - 1].
            let p0: UInt64 = (1 << 51) - 19
            let pHigh: UInt64 = (1 << 51) - 1
            if l4 != pHigh { return l4 > pHigh }
            if l3 != pHigh { return l3 > pHigh }
            if l2 != pHigh { return l2 > pHigh }
            if l1 != pHigh { return l1 > pHigh }
            return l0 >= p0
        }

        private static func subtractP(
            _ l0: UInt64, _ l1: UInt64, _ l2: UInt64, _ l3: UInt64, _ l4: UInt64
        ) -> (UInt64, UInt64, UInt64, UInt64, UInt64) {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3, l4 = l4
            let p0: UInt64 = (1 << 51) - 19
            let pHigh: UInt64 = (1 << 51) - 1
            let (s0, b0) = l0.subtractingReportingOverflow(p0)
            l0 = s0
            var borrow = b0 ? 1 : 0
            let (s1, b1) = l1.subtractingReportingOverflow(pHigh &+ UInt64(borrow)); l1 = s1; borrow = b1 ? 1 : 0
            let (s2, b2) = l2.subtractingReportingOverflow(pHigh &+ UInt64(borrow)); l2 = s2; borrow = b2 ? 1 : 0
            let (s3, b3) = l3.subtractingReportingOverflow(pHigh &+ UInt64(borrow)); l3 = s3; borrow = b3 ? 1 : 0
            let (s4, _) = l4.subtractingReportingOverflow(pHigh &+ UInt64(borrow))
            l4 = s4
            return (l0, l1, l2, l3, l4)
        }
    }

    // MARK: - 128-bit accumulator

    /// Minimal 128-bit unsigned value used to accumulate 51x51 products.
    struct Wide {
        var lo: UInt64 = 0
        var hi: UInt64 = 0

        mutating func addProduct(_ a: UInt64, _ b: UInt64) {
            let p = a.multipliedFullWidth(by: b)
            add(high: p.high, low: p.low)
        }

        mutating func add(high: UInt64, low: UInt64) {
            let (s, overflow) = lo.addingReportingOverflow(low)
            lo = s
            let (s2, overflow2) = hi.addingReportingOverflow(high)
            hi = s2
            if overflow2 { lo &+= 1 }
            if overflow {
                let (s3, overflow3) = hi.addingReportingOverflow(1)
                hi = s3
                if overflow3 { lo &+= 1 }
            }
        }

        mutating func addScaled(_ other: Wide, by factor: UInt64) {
            // other.lo * factor can exceed 64 bits; other.hi * factor cannot
            // overflow given the bounds on partial products used here.
            let p = other.lo.multipliedFullWidth(by: factor)
            let highSum = other.hi &* factor &+ p.high
            add(high: highSum, low: p.low)
        }

        func adding(_ other: Wide) -> Wide {
            var copy = self
            copy.add(high: other.hi, low: other.lo)
            return copy
        }

        func shiftedRight51() -> Wide {
            Wide(lo: (lo >> 51) | (hi << 13), hi: hi >> 51)
        }
    }

    // MARK: - Edwards points (extended coordinates)

    struct Point {
        var x: FieldElement
        var y: FieldElement
        var z: FieldElement
        var t: FieldElement

        static let identity = Point(x: .zero, y: .one, z: .one, t: .zero)

        /// The standard Ed25519 base point B.
        static let base: Point = {
            let x = FieldElement(hex: "216936D3CD6E53FEC0A4E231FDD6DC5C692CC7609525A7B2C9562D608F25D51A")
            let y = FieldElement(hex: "6666666666666666666666666666666666666666666666666666666666666658")
            return Point(x: x, y: y, z: .one, t: x.mul(y))
        }()

        /// Decompresses a 32-byte point encoding (RFC 8032 section 5.1.3).
        static func decompress(_ bytes: [UInt8]) -> Point? {
            guard bytes.count == 32 else { return nil }
            var yBytes = bytes
            let sign = yBytes[31] >> 7
            yBytes[31] &= 0x7F
            let y = FieldElement.fromBytes(yBytes)
            let y2 = y.squared()
            let u = y2.sub(.one)
            let v = y2.mul(.d).add(.one)
            // x = u v^3 (u v^7)^((p-5)/8)
            let v2 = v.squared()
            let v3 = v2.mul(v)
            let v7 = v3.mul(v2).mul(v2)
            var x = u.mul(v3).mul(u.mul(v7).pow(FieldElement.decompressExponent))
            let vx2 = v.mul(x.squared())
            if vx2 == u {
                // x is a square root of u/v.
            } else if vx2 == u.negate() {
                x = x.mul(.sqrtM1)
            } else {
                return nil
            }
            if x.isOdd != (sign == 1) {
                x = x.negate()
            }
            return Point(x: x, y: y, z: .one, t: x.mul(y))
        }

        /// Complete extended addition for a = -1 (RFC 8032 section 5.1.4).
        func add(_ q: Point) -> Point {
            let a = y.sub(x).mul(q.y.sub(q.x))
            let b = y.add(x).mul(q.y.add(q.x))
            let c = t.mul(q.t).mul(FieldElement.twoD)
            let d = z.mul(q.z).add(z.mul(q.z))
            let e = b.sub(a)
            let f = d.sub(c)
            let g = d.add(c)
            let h = b.add(a)
            return Point(x: e.mul(f), y: g.mul(h), z: f.mul(g), t: e.mul(h))
        }

        func negated() -> Point {
            Point(x: x.negate(), y: y, z: z, t: t.negate())
        }

        static func == (lhs: Point, rhs: Point) -> Bool {
            lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.t == rhs.t
        }

        /// True when this point is the identity (X = 0 and Y = Z).
        var isIdentity: Bool {
            x == .zero && y == z
        }

        /// Simple double-and-add; verification has no side-channel needs.
        static func scalarMult(_ scalar: [UInt8], _ point: Point) -> Point {
            var result = Point.identity
            var addend = point
            for byte in scalar {
                var b = byte
                for _ in 0..<8 {
                    if b & 1 == 1 { result = result.add(addend) }
                    addend = addend.add(addend)
                    b >>= 1
                }
            }
            return result
        }

        static func scalarMultBase(_ scalar: [UInt8]) -> Point {
            scalarMult(scalar, base)
        }
    }

    // MARK: - Scalar arithmetic mod L

    /// A 256-bit little-endian integer used for scalars.
    struct Scalar {
        var l0: UInt64
        var l1: UInt64
        var l2: UInt64
        var l3: UInt64

        /// L = 2^252 + 27742317777372353535851937790883648493.
        static let modulus = Scalar(0x5812631A5CF5D3ED, 0x14DEF9DEA2F79CD6, 0, 0x1000000000000000)
        static let zero = Scalar(0, 0, 0, 0)

        init(_ l0: UInt64, _ l1: UInt64, _ l2: UInt64, _ l3: UInt64) {
            self.l0 = l0
            self.l1 = l1
            self.l2 = l2
            self.l3 = l3
        }

        init(bytes: [UInt8]) {
            func load64(_ offset: Int) -> UInt64 {
                var value: UInt64 = 0
                for j in 0..<8 {
                    let byte = offset + j < bytes.count ? bytes[offset + j] : 0
                    value |= UInt64(byte) << (8 * j)
                }
                return value
            }
            self.init(load64(0), load64(8), load64(16), load64(24))
        }

        /// An RFC 8032 signature's S must be a canonical scalar: strictly
        /// below L. `verify` passes the 32-byte S directly, so this takes a
        /// 32-byte scalar, not the full 64-byte signature.
        static func isCanonical(_ bytes: [UInt8]) -> Bool {
            guard bytes.count == 32 else { return false }
            return Scalar(bytes: bytes).isLessThan(modulus)
        }

        /// Reduces a 64-byte little-endian value mod L, bit by bit. Simple,
        /// correct, and fast enough for one signature check per file.
        static func reduce64(_ bytes: [UInt8]) -> Scalar {
            var limbs = [UInt64](repeating: 0, count: 8)
            for i in 0..<8 {
                var value: UInt64 = 0
                for j in 0..<8 {
                    let byte = i * 8 + j < bytes.count ? bytes[i * 8 + j] : 0
                    value |= UInt64(byte) << (8 * j)
                }
                limbs[i] = value
            }
            var result = Scalar.zero
            for bit in stride(from: 511, through: 0, by: -1) {
                result = result.doubled()
                if (limbs[bit / 64] >> UInt64(bit % 64)) & 1 == 1 {
                    result = result.add1()
                }
            }
            return result
        }

        func bytes() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 32)
            for (i, limb) in [l0, l1, l2, l3].enumerated() {
                for j in 0..<8 {
                    out[i * 8 + j] = UInt8((limb >> (8 * j)) & 0xFF)
                }
            }
            return out
        }

        func isLessThan(_ other: Scalar) -> Bool {
            for (a, b) in [(l3, other.l3), (l2, other.l2), (l1, other.l1), (l0, other.l0)] {
                if a != b { return a < b }
            }
            return false
        }

        /// Returns 2 * self mod L. The doubled value can reach almost
        /// 2^254, which is up to four times L, so reduction loops.
        func doubled() -> Scalar {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3
            let c0 = l0 >> 63; l0 <<= 1
            let c1 = l1 >> 63; l1 = (l1 << 1) | c0
            let c2 = l2 >> 63; l2 = (l2 << 1) | c1
            l3 = (l3 << 1) | c2
            var result = Scalar(l0, l1, l2, l3)
            while !result.isLessThan(Scalar.modulus) {
                result = result.subtract(Scalar.modulus)
            }
            return result
        }

        /// Returns self + 1 mod L.
        func add1() -> Scalar {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3
            l0 &+= 1
            if l0 == 0 {
                l1 &+= 1
                if l1 == 0 {
                    l2 &+= 1
                    if l2 == 0 {
                        l3 &+= 1
                    }
                }
            }
            let result = Scalar(l0, l1, l2, l3)
            if result.isLessThan(Scalar.modulus) {
                return result
            }
            return result.subtract(Scalar.modulus)
        }

        static func == (lhs: Scalar, rhs: Scalar) -> Bool {
            lhs.l0 == rhs.l0 && lhs.l1 == rhs.l1 && lhs.l2 == rhs.l2 && lhs.l3 == rhs.l3
        }

        func subtract(_ other: Scalar) -> Scalar {
            var l0 = l0, l1 = l1, l2 = l2, l3 = l3
            let (s0, b0) = l0.subtractingReportingOverflow(other.l0); l0 = s0
            var borrow = b0 ? 1 : 0
            let (s1, b1) = l1.subtractingReportingOverflow(other.l1 &+ UInt64(borrow)); l1 = s1; borrow = b1 ? 1 : 0
            let (s2, b2) = l2.subtractingReportingOverflow(other.l2 &+ UInt64(borrow)); l2 = s2; borrow = b2 ? 1 : 0
            let (s3, _) = l3.subtractingReportingOverflow(other.l3 &+ UInt64(borrow)); l3 = s3
            return Scalar(l0, l1, l2, l3)
        }
    }
}
