import Foundation
import Testing
@testable import OriginCheckEngine

@Suite("Frequency dictionary")
struct FrequencyDictionaryTests {
    @Test
    func bundledDictionaryLoadsAndCoversCommonWords() throws {
        let dictionary = try BundledResources.frequencyDictionary()
        #expect(dictionary.logFrequency(of: "the") != nil)
        #expect(dictionary.logFrequency(of: "of") != nil)
        #expect(dictionary.logFrequency(of: "quantum") == nil, "Rare words are out of vocabulary")
        #expect(dictionary.logFrequency(of: "THE") == dictionary.logFrequency(of: "the"), "Lookup is case-insensitive")
    }

    @Test
    func numbersAreMidFrequencyNotRare() throws {
        let dictionary = try BundledResources.frequencyDictionary()
        let stats = dictionary.stats(forTokens: ["2026", "3", "14"])
        #expect(stats.outOfVocabularyCount == 0)
        #expect(stats.outOfVocabularyRate == 0)
    }

    @Test
    func inflectedFormsResolveToBaseWord() throws {
        let dictionary = try BundledResources.frequencyDictionary()
        let base = try #require(dictionary.logFrequency(of: "company"))
        let plural = try #require(dictionary.logFrequency(of: "companies"))
        #expect(plural < base, "Inflected forms nudge frequency down, never up")
        #expect(dictionary.logFrequency(of: "issues") != nil)
        #expect(dictionary.logFrequency(of: "walked") != nil)
        #expect(dictionary.logFrequency(of: "quickly") != nil)
    }

    @Test
    func tokenizationDropsContractionRemnants() {
        let tokens = FrequencyDictionary.tokenize("It's a great day! Don't stop.")
        #expect(tokens.contains("it"))
        #expect(tokens.contains("s") == false, "Contraction remnants are dropped")
        #expect(tokens.contains("a"))
        #expect(tokens.contains("don"))
        #expect(tokens.contains("t") == false)
    }

    @Test
    func statsReportSurprisalAndRareWords() throws {
        let dictionary = try BundledResources.frequencyDictionary()
        // "the" is the most common word (surprisal 0); an invented token is
        // maximally surprising; a known rare word sits in between.
        let stats = dictionary.stats(forTokens: ["the", "zzyzxq", "serendipity"])
        #expect(stats.averageSurprisal > 0)
        #expect(stats.averageSurprisal < TokenStats.maxSurprisal)
        #expect(stats.rareWordCount == 2, "OOV plus the rare-but-known word")
        #expect(stats.perplexityTerm > 0)
        #expect(stats.perplexityTerm < 1)
    }

    @Test
    func tsvParserRejectsMalformedLines() {
        #expect(throws: FrequencyDictionaryError.self) {
            _ = try FrequencyDictionary(parsingTSV: "the\t7.0\nbroken-line\n")
        }
    }
}

@Suite("AI phrase database")
struct AIPhraseDatabaseTests {
    @Test
    func bundledDatabaseLoads() throws {
        let database = try BundledResources.phraseDatabase()
        let report = database.match("In conclusion, this is a comprehensive guide.")
        #expect(report.matchedCount >= 2)
        #expect(report.totalWeight > 0)
    }

    @Test
    func matchingIsCaseInsensitiveAndPunctuationTolerant() throws {
        let database = AIPhraseDatabase(phrases: [
            AIPhraseDatabase.AIPhraseEntry(phrase: "delve into", families: [.generic], weight: 1.0)
        ])
        let report = database.match("Let's DELVE INTO this topic.")
        #expect(report.matchedCount == 1)
        #expect(report.totalWeight == 1.0)
    }

    @Test
    func genericPhrasesNeverProduceFamilyHints() {
        let database = AIPhraseDatabase(phrases: [
            AIPhraseDatabase.AIPhraseEntry(phrase: "delve into", families: [.generic], weight: 1.0)
        ])
        let report = database.match("We delve into the details.")
        #expect(report.familyWeights.isEmpty)
        #expect(database.familyHints(from: report).isEmpty)
    }

    @Test
    func familyHintsRequireEnoughWeightAndCarryExamples() {
        let database = AIPhraseDatabase(phrases: [
            AIPhraseDatabase.AIPhraseEntry(phrase: "let's dive in", families: [.chatgpt], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "in conclusion", families: [.chatgpt], weight: 0.8),
            AIPhraseDatabase.AIPhraseEntry(phrase: "it's worth noting", families: [.claude], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "stray weak phrase", families: [.gemini], weight: 0.4)
        ])
        let report = database.match("Let's dive in and, in conclusion, note that it's worth noting.")
        let hints = database.familyHints(from: report)
        let families = hints.map(\.family)
        #expect(families.contains(.chatgpt))
        #expect(families.contains(.claude))
        #expect(families.contains(.gemini) == false, "Weight below the bar produces no hint")
        let chatgpt = hints.first { $0.family == .chatgpt }
        #expect(chatgpt?.matchedPhrases.count == 2)
        #expect(chatgpt?.matchedPhrases.first == "let's dive in", "Strongest phrase first")
    }

    @Test
    func phraseTermSaturates() {
        let database = AIPhraseDatabase(phrases: [
            AIPhraseDatabase.AIPhraseEntry(phrase: "delve", families: [.generic], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "furthermore", families: [.generic], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "moreover", families: [.generic], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "landscape", families: [.generic], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "robust", families: [.generic], weight: 1.0),
            AIPhraseDatabase.AIPhraseEntry(phrase: "seamless", families: [.generic], weight: 1.0),
        ])
        let report = database.match("Delve furthermore moreover landscape robust seamless")
        #expect(report.phraseTerm == 1.0, "Heavy phrasing saturates at 1.0")
    }
}

@Suite("Sample passages")
struct SamplePassagesTests {
    @Test
    func bundledPassagesLoadAndAreSubstantial() throws {
        let passages = try BundledResources.samplePassages()
        #expect(passages.count == 3)
        for passage in passages {
            #expect(!passage.text.isEmpty)
            #expect(passage.text.count > 200)
        }
    }
}
