import XCTest
@testable import OriginCheckEngine

final class MediaFormatTests: XCTestCase {
    func testKnownExtensionsParse() {
        XCTAssertEqual(MediaFormat.from(pathExtension: "png"), .png)
        XCTAssertEqual(MediaFormat.from(pathExtension: "jpg"), .jpg)
        XCTAssertEqual(MediaFormat.from(pathExtension: "jpeg"), .jpeg)
        XCTAssertEqual(MediaFormat.from(pathExtension: "svg"), .svg)
        XCTAssertEqual(MediaFormat.from(pathExtension: "webp"), .webp)
        XCTAssertEqual(MediaFormat.from(pathExtension: "avif"), .avif)
        XCTAssertEqual(MediaFormat.from(pathExtension: "heic"), .heic)
        XCTAssertEqual(MediaFormat.from(pathExtension: "heif"), .heif)
        XCTAssertEqual(MediaFormat.from(pathExtension: "tif"), .tif)
        XCTAssertEqual(MediaFormat.from(pathExtension: "tiff"), .tiff)
        XCTAssertEqual(MediaFormat.from(pathExtension: "dng"), .dng)
        XCTAssertEqual(MediaFormat.from(pathExtension: "mp4"), .mp4)
        XCTAssertEqual(MediaFormat.from(pathExtension: "mov"), .mov)
        XCTAssertEqual(MediaFormat.from(pathExtension: "m4a"), .m4a)
        XCTAssertEqual(MediaFormat.from(pathExtension: "mp3"), .mp3)
        XCTAssertEqual(MediaFormat.from(pathExtension: "wav"), .wav)
        XCTAssertEqual(MediaFormat.from(pathExtension: "pdf"), .pdf)
    }

    func testExtensionParsingIsCaseInsensitive() {
        XCTAssertEqual(MediaFormat.from(pathExtension: "PNG"), .png)
        XCTAssertEqual(MediaFormat.from(pathExtension: "Jpg"), .jpg)
        XCTAssertEqual(MediaFormat.from(pathExtension: "WebP"), .webp)
        XCTAssertEqual(MediaFormat.from(pathExtension: "MP4"), .mp4)
    }

    func testUnsupportedExtensionsReturnNil() {
        XCTAssertNil(MediaFormat.from(pathExtension: "txt"))
        XCTAssertNil(MediaFormat.from(pathExtension: "docx"))
        XCTAssertNil(MediaFormat.from(pathExtension: "zip"))
        XCTAssertNil(MediaFormat.from(pathExtension: ""))
    }

    func testIsSupportedMatchesFrom() {
        XCTAssertTrue(MediaFormat.isSupported(pathExtension: "png"))
        XCTAssertTrue(MediaFormat.isSupported(pathExtension: "mov"))
        XCTAssertFalse(MediaFormat.isSupported(pathExtension: "exe"))
    }

    func testPdfIsReadOnly() {
        XCTAssertTrue(MediaFormat.pdf.isReadOnly)
        for format in MediaFormat.allCases where format != .pdf {
            XCTAssertFalse(format.isReadOnly, "\(format.rawValue) should not be read-only")
        }
    }

    func testEveryFormatHasAHumanReadableDisplayName() {
        for format in MediaFormat.allCases {
            XCTAssertFalse(format.displayName.isEmpty)
            XCTAssertFalse(format.displayName.contains("\u{2014}"), "Display name for \(format.rawValue) must not contain an em dash")
            XCTAssertFalse(format.displayName.contains("\u{2013}"), "Display name for \(format.rawValue) must not contain an en dash")
        }
    }
}
