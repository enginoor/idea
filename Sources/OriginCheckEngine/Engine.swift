import Foundation

public protocol DetectionEngine: Sendable {
    func analyzeText(_ text: String, options: AnalysisOptions) async throws -> TextVerdict
    func verifyFile(at url: URL, options: AnalysisOptions) async throws -> FileVerdict
}

/// The engine facade. It has no UI dependencies and is safe to unit test
/// without a window server.
public struct OriginCheckEngine: DetectionEngine {
    public let c2paVerifier: C2PAVerifier
    public let localAnalyzer: LocalStatisticalAnalyzer
    public let anthropicProvider: AnthropicDetectionAPIProvider
    public let combiner: VerdictCombiner

    public init(
        c2paToolPath: String = "c2patool",
        keyStore: any KeyStoring = UserDefaultsKeyStore()
    ) {
        self.c2paVerifier = C2PAVerifier(toolPath: c2paToolPath)
        self.localAnalyzer = LocalStatisticalAnalyzer()
        self.anthropicProvider = AnthropicDetectionAPIProvider(keyStore: keyStore)
        self.combiner = VerdictCombiner()
    }

    public func analyzeText(_ text: String, options: AnalysisOptions) async throws -> TextVerdict {
        var providers: [TextWatermarkProvider] = []
        if options.localAnalyzerEnabled {
            providers.append(localAnalyzer)
        }
        if options.anthropicProviderEnabled {
            providers.append(anthropicProvider)
        }

        var results: [ProviderResult] = []
        var providersRun: [String] = []
        for provider in providers {
            providersRun.append(provider.source)
            let result = try await provider.analyze(text, options: options)
            results.append(result)
        }

        return combiner.combineText(
            results: results,
            characterCount: text.count,
            providersRun: providersRun,
            preset: options.thresholdPreset
        )
    }

    public func verifyFile(at url: URL, options: AnalysisOptions) async throws -> FileVerdict {
        try await c2paVerifier.verifyFile(at: url)
    }
}
