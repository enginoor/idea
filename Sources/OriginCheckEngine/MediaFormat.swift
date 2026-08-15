import Foundation

/// File formats that c2patool, the reference C2PA tool, can verify today.
/// The list tracks the formats supported by c2pa-rs: images, video, audio,
/// and PDF. PDF is read-only: c2patool can read a manifest from it but cannot
/// write one.
public enum MediaFormat: String, Codable, Sendable, CaseIterable {
    case png
    case jpg
    case jpeg
    case svg
    case webp
    case avif
    case heic
    case heif
    case tif
    case tiff
    case dng
    case mp4
    case mov
    case m4a
    case mp3
    case wav
    case pdf

    public var displayName: String {
        switch self {
        case .png: "PNG image"
        case .jpg, .jpeg: "JPEG image"
        case .svg: "SVG image"
        case .webp: "WebP image"
        case .avif: "AVIF image"
        case .heic, .heif: "HEIF image"
        case .tif, .tiff: "TIFF image"
        case .dng: "DNG image"
        case .mp4: "MP4 video"
        case .mov: "QuickTime video"
        case .m4a: "MPEG-4 audio"
        case .mp3: "MP3 audio"
        case .wav: "WAV audio"
        case .pdf: "PDF document"
        }
    }

    /// Formats whose manifests c2patool can read but not write. The verdict
    /// is unaffected; this only matters for tooling that signs files.
    public var isReadOnly: Bool {
        self == .pdf
    }

    public static func from(pathExtension: String) -> MediaFormat? {
        let normalized = pathExtension.lowercased()
        return allCases.first { $0.rawValue == normalized }
    }

    public static func isSupported(pathExtension: String) -> Bool {
        from(pathExtension: pathExtension) != nil
    }
}
