import Testing
@testable import OriginCheckEngine

@Suite
struct MediaFormatTests {
    @Test
    func testKnownExtensionsParse() {
        #expect(MediaFormat.from(pathExtension: "png") == .png)
        #expect(MediaFormat.from(pathExtension: "jpg") == .jpg)
        #expect(MediaFormat.from(pathExtension: "jpeg") == .jpeg)
        #expect(MediaFormat.from(pathExtension: "svg") == .svg)
        #expect(MediaFormat.from(pathExtension: "webp") == .webp)
        #expect(MediaFormat.from(pathExtension: "avif") == .avif)
        #expect(MediaFormat.from(pathExtension: "heic") == .heic)
        #expect(MediaFormat.from(pathExtension: "heif") == .heif)
        #expect(MediaFormat.from(pathExtension: "tif") == .tif)
        #expect(MediaFormat.from(pathExtension: "tiff") == .tiff)
        #expect(MediaFormat.from(pathExtension: "dng") == .dng)
        #expect(MediaFormat.from(pathExtension: "mp4") == .mp4)
        #expect(MediaFormat.from(pathExtension: "mov") == .mov)
        #expect(MediaFormat.from(pathExtension: "m4a") == .m4a)
        #expect(MediaFormat.from(pathExtension: "mp3") == .mp3)
        #expect(MediaFormat.from(pathExtension: "wav") == .wav)
        #expect(MediaFormat.from(pathExtension: "pdf") == .pdf)
    }

    @Test
    func testExtensionParsingIsCaseInsensitive() {
        #expect(MediaFormat.from(pathExtension: "PNG") == .png)
        #expect(MediaFormat.from(pathExtension: "Jpg") == .jpg)
        #expect(MediaFormat.from(pathExtension: "WebP") == .webp)
        #expect(MediaFormat.from(pathExtension: "MP4") == .mp4)
    }

    @Test
    func testUnsupportedExtensionsReturnNil() {
        #expect(MediaFormat.from(pathExtension: "txt") == nil)
        #expect(MediaFormat.from(pathExtension: "docx") == nil)
        #expect(MediaFormat.from(pathExtension: "zip") == nil)
        #expect(MediaFormat.from(pathExtension: "") == nil)
    }

    @Test
    func testIsSupportedMatchesFrom() {
        #expect(MediaFormat.isSupported(pathExtension: "png"))
        #expect(MediaFormat.isSupported(pathExtension: "mov"))
        #expect(!MediaFormat.isSupported(pathExtension: "exe"))
    }

    @Test
    func testPdfIsReadOnly() {
        #expect(MediaFormat.pdf.isReadOnly)
        for format in MediaFormat.allCases where format != .pdf {
            #expect(!format.isReadOnly, "\(format.rawValue) should not be read-only")
        }
    }

    @Test
    func testEveryFormatHasAHumanReadableDisplayName() {
        for format in MediaFormat.allCases {
            #expect(!format.displayName.isEmpty)
            #expect(!format.displayName.contains("\u{2014}"), "Display name for \(format.rawValue) must not contain an em dash")
            #expect(!format.displayName.contains("\u{2013}"), "Display name for \(format.rawValue) must not contain an en dash")
        }
    }
}
