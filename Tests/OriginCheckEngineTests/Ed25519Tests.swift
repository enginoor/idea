import Foundation
import Testing
@testable import OriginCheckEngine

private func hexBytes(_ hex: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var text = hex
    if text.count % 2 != 0 { text = "0" + text }
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        bytes.append(UInt8(text[index..<next], radix: 16) ?? 0)
        index = next
    }
    return bytes
}

@Suite("Ed25519 verification")
struct Ed25519Tests {
    @Test
    func rfc8032TestVector1() {
        // Empty message.
        let publicKey = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        )
        #expect(Ed25519.verify(signature: signature, message: [], publicKey: publicKey))
    }

    @Test
    func rfc8032TestVector2() {
        // One-byte message 0x72.
        let publicKey = hexBytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        let signature = hexBytes(
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" +
            "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
        )
        #expect(Ed25519.verify(signature: signature, message: [0x72], publicKey: publicKey))
    }

    @Test
    func rfc8032TestVector3() {
        // Two-byte message 0xaf 0x82.
        let publicKey = hexBytes("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025")
        let signature = hexBytes(
            "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac" +
            "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
        )
        #expect(Ed25519.verify(signature: signature, message: [0xAF, 0x82], publicKey: publicKey))
    }

    @Test
    func tamperedSignatureFails() {
        let publicKey = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        var signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        )
        signature[10] ^= 0x01
        #expect(!Ed25519.verify(signature: signature, message: [], publicKey: publicKey))
    }

    @Test
    func tamperedMessageFails() {
        let publicKey = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        )
        #expect(!Ed25519.verify(signature: signature, message: [0x01], publicKey: publicKey))
    }

    @Test
    func wrongPublicKeyFails() {
        // RFC 8032 TEST 2's key does not verify TEST 1's signature.
        let publicKey = hexBytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        let signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        )
        #expect(!Ed25519.verify(signature: signature, message: [], publicKey: publicKey))
    }

    @Test
    func malformedInputsAreRejected() {
        let publicKey = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        )
        #expect(!Ed25519.verify(signature: [], message: [], publicKey: publicKey))
        #expect(!Ed25519.verify(signature: signature, message: [], publicKey: []))
        #expect(!Ed25519.verify(signature: Array(signature.prefix(63)), message: [], publicKey: publicKey))
    }

    @Test
    func nonCanonicalScalarIsRejected() {
        // S = L is not canonical; the RFC test signature with S replaced by L
        // must be rejected before any point math runs.
        let publicKey = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let signature = hexBytes(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5812631a5cf5d3ed14def9dea2f79cd65812631a5cf5d3ed14def9dea2f79cd6"
        )
        #expect(!Ed25519.verify(signature: signature, message: [], publicKey: publicKey))
    }

    @Test
    func sha512KnownVector() {
        // SHA-512("abc") from the FIPS test suite.
        let digest = SHA512.digest(Array("abc".utf8))
        let expected = hexBytes(
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
            "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
        )
        #expect(digest == expected)
    }

    @Test
    func sha512EmptyVector() {
        let digest = SHA512.digest([])
        let expected = hexBytes(
            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce" +
            "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
        )
        #expect(digest == expected)
    }
}
