import Foundation

/// Deliberately AI-typical passages bundled with the app. The Check pane's
/// Sample button loads these so a first-time user sees a positive verdict
/// without hunting for machine-generated text. They are bundled data, not
/// fetched: the app works fully offline.
public enum SamplePassages {
    public struct Passage: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var text: String

        public init(id: String, title: String, text: String) {
            self.id = id
            self.title = title
            self.text = text
        }
    }

    /// The JSON shape of sample-passages.json.
    public struct Payload: Decodable {
        public var passages: [Passage]
    }

    public static func bundled() throws -> [Passage] {
        try BundledResources.samplePassages()
    }
}
