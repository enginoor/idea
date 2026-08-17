import Foundation

/// A compact SHA-512 implementation, needed by Ed25519 verification. Like
/// SHA256, it keeps the engine dependency free so tests run on Linux, and it
/// is incremental so huge inputs never need to load fully into memory.
public enum SHA512 {
    public static func digest(_ data: Data) -> [UInt8] {
        var digester = Digester()
        digester.update(data)
        return digester.finalize()
    }

    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        digest(Data(bytes))
    }

    /// Incremental SHA-512 state. Feed any number of chunks with `update`,
    /// then call `finalize` exactly once.
    public struct Digester {
        private var h: [UInt64]
        private var buffer: [UInt8]
        private var totalBytes: UInt64

        public init() {
            h = [
                0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
            ]
            buffer = []
            totalBytes = 0
        }

        public mutating func update(_ data: Data) {
            totalBytes += UInt64(data.count)
            var offset = 0
            if !buffer.isEmpty {
                let needed = 128 - buffer.count
                let take = min(needed, data.count)
                if take > 0 {
                    buffer.append(contentsOf: data[data.startIndex..<(data.startIndex + take)])
                    offset = take
                    if buffer.count == 128 {
                        Self.compress(&h, block: buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
            }
            let count = data.count
            while offset + 128 <= count {
                Self.compress(
                    &h,
                    block: Array(data[data.startIndex + offset..<(data.startIndex + offset + 128)])
                )
                offset += 128
            }
            if offset < count {
                buffer.append(contentsOf: data[(data.startIndex + offset)...])
            }
        }

        public mutating func finalize() -> [UInt8] {
            let bitLength = totalBytes.multipliedReportingOverflow(by: 8).partialValue
            buffer.append(0x80)
            while buffer.count % 128 != 112 {
                buffer.append(0)
            }
            // 128-bit length field, big-endian; the low 64 bits are all a
            // real file can reach.
            for _ in 0..<8 {
                buffer.append(0)
            }
            for shift in stride(from: 56, through: 0, by: -8) {
                buffer.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
            }

            var state = h
            var offset = 0
            while offset < buffer.count {
                Self.compress(&state, block: Array(buffer[offset..<(offset + 128)]))
                offset += 128
            }

            return state.flatMap { value in
                [
                    UInt8((value >> 56) & 0xff),
                    UInt8((value >> 48) & 0xff),
                    UInt8((value >> 40) & 0xff),
                    UInt8((value >> 32) & 0xff),
                    UInt8((value >> 24) & 0xff),
                    UInt8((value >> 16) & 0xff),
                    UInt8((value >> 8) & 0xff),
                    UInt8(value & 0xff),
                ]
            }
        }

        private static func compress(_ state: inout [UInt64], block: [UInt8]) {
            let k: [UInt64] = [
                0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
                0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
                0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
                0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
                0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
                0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
                0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
                0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
                0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
                0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
                0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
                0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
                0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
                0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
                0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
                0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
                0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
                0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
                0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
                0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
            ]
            var w = [UInt64](repeating: 0, count: 80)
            for i in 0..<16 {
                let idx = i * 8
                var value: UInt64 = 0
                for j in 0..<8 {
                    value = (value << 8) | UInt64(block[idx + j])
                }
                w[i] = value
            }
            for i in 16..<80 {
                let s0 = rotr(w[i - 15], 1) ^ rotr(w[i - 15], 8) ^ (w[i - 15] >> 7)
                let s1 = rotr(w[i - 2], 19) ^ rotr(w[i - 2], 61) ^ (w[i - 2] >> 6)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var hh = state[7]

            for i in 0..<80 {
                let s1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                hh = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            state[0] &+= a
            state[1] &+= b
            state[2] &+= c
            state[3] &+= d
            state[4] &+= e
            state[5] &+= f
            state[6] &+= g
            state[7] &+= hh
        }

        private static func rotr(_ value: UInt64, _ shift: UInt64) -> UInt64 {
            (value >> shift) | (value << (64 - shift))
        }
    }
}
