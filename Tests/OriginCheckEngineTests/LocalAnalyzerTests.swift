import Foundation
import Testing
@testable import OriginCheckEngine

@Suite
struct LocalAnalyzerTests {
    private let options = AnalysisOptions()

    /// Uniform, evenly paced sentences with plain vocabulary: the shape of
    /// typical AI-generated prose (low burstiness, low repetition).
    private let aiTypicalText = """
    The report shows the quarterly results for the team.
    The sales team reviewed the numbers in the meeting.
    Growth continued across all of the main regions.
    The product shipped on time and met expectations.
    Customers reported high satisfaction with the update.
    The company plans to expand into new markets soon.
    Engineers fixed several issues found during testing.
    The board approved the budget for next quarter.
    Marketing launched the campaign earlier this week.
    Support tickets decreased after the latest release.
    """

    /// Wildly uneven sentence lengths: short bursts next to long rambling
    /// sentences, the shape of unedited human writing (high burstiness).
    /// Kept on one line: the sentence splitter treats line breaks as
    /// sentence breaks, which would flatten the very variance this fixture
    /// is meant to create.
    private let humanTypicalText = "We went. The entire morning we walked through the old district, stopping at every corner bakery to compare their pastries, and by noon the whole plan had quietly fallen apart. It rained. Then, just when we had given up and were about to head back, a gap opened in the clouds and the light came down sideways across the square, catching the wet cobbles and turning everything a color none of us could name. Home. After that we could not stop talking about it, not for days, and every conversation circled back to the same question of what exactly we had seen and whether it would ever look that way again."

    @Test
    func testShortTextIsInsufficient() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze("Too short.", options: options)
        #expect(result.signal == .insufficient)
        #expect(result.evidence.contains { $0.kind == "insufficient_text" })
    }

    @Test
    func testEmptyTextIsInsufficient() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze("", options: options)
        #expect(result.signal == .insufficient)
    }

    @Test
    func testUniformTextScoresAsDetected() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze(aiTypicalText, options: options)
        #expect(result.signal == .detected)
        #expect(result.confidence.value >= 0.5)
        #expect(result.confidence.label != .high, "A heuristic must never claim high confidence")
        #expect(result.caveatText.contains("heuristic"))
        #expect(result.evidence.contains { $0.kind == "burstiness" })
        #expect(result.evidence.contains { $0.kind == "heuristic_score" })
    }

    @Test
    func testBurstyTextScoresAsNotDetected() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze(humanTypicalText, options: options)
        #expect(result.signal == .notDetected)
        #expect(result.caveatText.contains("does not prove human authorship"))
    }

    @Test
    func testStatisticsAreExposedInEvidence() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze(aiTypicalText, options: options)
        let burstiness = result.evidence.first { $0.kind == "burstiness" }
        #expect(burstiness != nil)
        #expect(burstiness!.summary.contains("0."), "Evidence should carry the numeric statistic")
    }

    @Test
    func testBundledSamplePassagesAllScoreAsDetected() async throws {
        let passages = try BundledResources.samplePassages()
        #expect(passages.count >= 3)
        for passage in passages {
            let result = try await LocalStatisticalAnalyzer().analyze(passage.text, options: options)
            #expect(result.signal == .detected, "Bundled \(passage.id) sample should read as AI-typical, got \(result.signal)")
            #expect(result.confidence.label != .high)
        }
    }

    @Test
    func testSamplePassagesProduceFamilyHints() async throws {
        let passages = try BundledResources.samplePassages()
        let chatgpt = try #require(passages.first { $0.id == "chatgpt" })
        let result = try await LocalStatisticalAnalyzer().analyze(chatgpt.text, options: options)
        let families = result.familyHints.map(\.family)
        #expect(families.contains(.chatgpt))
        #expect(!result.familyHints.isEmpty)
        #expect(result.evidence.contains { $0.kind == "perplexity" })
        #expect(result.evidence.contains { $0.kind == "ai_phrasing" })
    }

    @Test
    func testHumanFixtureProducesNoFamilyHints() async throws {
        let result = try await LocalStatisticalAnalyzer().analyze(humanTypicalText, options: options)
        #expect(result.familyHints.isEmpty)
    }

    @Test
    func testDecimalPointDoesNotSplitSentence() {
        let sentences = TextStatistics.splitSentencesForTesting("The value is 3.14 and it matters. Next one.")
        #expect(sentences.count == 2)
        #expect(sentences[0].contains("3.14"))
    }

    @Test
    func testWordCountingIsCaseInsensitive() {
        let stats = TextStatistics(text: "Hello hello HELLO world")
        #expect(stats.wordCount == 4)
        #expect(stats.uniqueWordCount == 2)
    }
}

/// Small accessor so tests can reach the internal sentence splitter without
/// making the whole type public.
extension TextStatistics {
    static func splitSentencesForTesting(_ text: String) -> [String] {
        splitSentences(text)
    }
}
