import Foundation

/// Loads the detection data bundled with the app. Every loader is
/// thread-safe (the loaded values are immutable and cached behind a lock),
/// so the analyzer can call into it from any task without coordination.
///
/// The resources live in `Sources/OriginCheckEngine/Resources/` and are
/// copied into the app bundle by SwiftPM (declared in Package.swift). The
/// macOS packaging script embeds the generated resource bundle into
/// OriginCheck.app, which is what makes the app fully standalone: no
/// downloads, no network, no installed tools are needed for text detection.
public enum BundledResources {
    private static let lock = NSLock()

    // Lock-protected caches: every access goes through `load`, which takes
    // the lock, so Swift 6's isolation checker is told to trust that.
    private static nonisolated(unsafe) var cachedDictionary: FrequencyDictionary?
    private static nonisolated(unsafe) var cachedPhrases: AIPhraseDatabase?
    private static nonisolated(unsafe) var cachedPassages: [SamplePassages.Passage]?

    public static func frequencyDictionary() throws -> FrequencyDictionary {
        try load(&cachedDictionary) {
            let url = try resourceURL(name: "english-frequencies", ext: "tsv")
            let text = try String(contentsOf: url, encoding: .utf8)
            return try FrequencyDictionary(parsingTSV: text)
        }
    }

    public static func phraseDatabase() throws -> AIPhraseDatabase {
        try load(&cachedPhrases) {
            let url = try resourceURL(name: "ai-phrases", ext: "json")
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode(PhrasePayload.self, from: data).phrases
            return AIPhraseDatabase(phrases: entries)
        }
    }

    public static func samplePassages() throws -> [SamplePassages.Passage] {
        try load(&cachedPassages) {
            let url = try resourceURL(name: "sample-passages", ext: "json")
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SamplePassages.Payload.self, from: data).passages
        }
    }

    private struct PhrasePayload: Decodable {
        var phrases: [AIPhraseDatabase.AIPhraseEntry]
    }

    private static func resourceURL(name: String, ext: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Resources"
        ) else {
            throw ResourceError.missing("\(name).\(ext)")
        }
        return url
    }

    public enum ResourceError: Error, Sendable, CustomStringConvertible {
        case missing(String)

        public var description: String {
            switch self {
            case .missing(let name):
                "Bundled resource \(name) is missing. The app bundle may be damaged; reinstall the app."
            }
        }
    }

    private static func load<T>(_ cache: inout T?, _ build: () throws -> T) throws -> T {
        if let cached = cache { return cached }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache { return cached }
        let value = try build()
        cache = value
        return value
    }
}

/// Keeps the TSV parsing next to the type it builds.
extension FrequencyDictionary {
    /// Parses the bundled TSV: one `word<TAB>logFrequency` per line, `#`
    /// lines and blank lines ignored. Malformed lines fail loudly: a broken
    /// dictionary must never silently produce a weaker detector.
    init(parsingTSV text: String) throws {
        var entries: [String: Double] = [:]
        entries.reserveCapacity(2_000)
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let frequency = Double(parts[1])
            else {
                throw FrequencyDictionaryError.invalidLine(String(line))
            }
            entries[String(parts[0]).lowercased()] = frequency
        }
        self.init(logFrequencies: entries)
    }
}

public enum FrequencyDictionaryError: Error, Sendable, CustomStringConvertible {
    case invalidLine(String)

    public var description: String {
        switch self {
        case .invalidLine(let line):
            "Malformed frequency dictionary line: \(line)"
        }
    }
}
