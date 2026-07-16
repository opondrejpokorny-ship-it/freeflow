import Foundation

@main
struct AppContextServiceTests {
    static func main() {
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testDeprecatedGroqModelsAreNotPredefined()
        testQwenCleanupDisablesReasoning()
        testLanguageCatalogContainsCanonicalWhisperLanguages()
        testLanguageCodeNormalization()
        testLanguageOptionDefaults()
        testLanguageServiceNormalizesInputCodes()
        testLanguageServiceMigratesLegacyOutputNames()
        testLanguageServicePersistsCanonicalValues()
        print("AppContextServiceTests passed")
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is replying to an email about the product launch. They likely intend to confirm the next steps."
        )
    }

    private static func testQwenReasoningOutputIsStripped() {
        let output = """
        <think>
        Hidden chain of thought should never appear in context.
        It contains misleading details.
        </think>
        The user is editing a project note in FreeFlow. They likely intend to tighten the release wording.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is editing a project note in FreeFlow. They likely intend to tighten the release wording."
        )
        expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        expectEqual(summary, output)
    }

    private static func testDeprecatedGroqModelsAreNotPredefined() {
        let deprecatedModels = [
            "qwen/qwen3-32b",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile"
        ]

        for model in deprecatedModels {
            expect(!ModelConfiguration.llmModels.contains(model), "Deprecated model remains in picker: \(model)")
        }
        expect(ModelConfiguration.llmModels.contains("qwen/qwen3.6-27b"), "New fallback is missing from picker")
    }

    private static func testQwenCleanupDisablesReasoning() {
        let config = ModelConfiguration.config(for: "qwen/qwen3.6-27b")

        expect(config.reasoningEffort == "none", "Qwen cleanup should disable reasoning")
        expect(config.includeReasoning == false, "Qwen cleanup should exclude reasoning output")
    }

    private static func testLanguageCatalogContainsCanonicalWhisperLanguages() {
        let languages = DictationLanguageCatalog.supported
        let uniqueCodes = Set(languages.map(\.code))

        expect(languages.count == 100, "Expected 100 canonical Whisper languages, got \(languages.count)")
        expect(uniqueCodes.count == languages.count, "Language catalog contains duplicate codes")
        expect(uniqueCodes.contains("cs"), "Czech is missing from the language catalog")
        expect(uniqueCodes.contains("sk"), "Slovak is missing from the language catalog")
        expect(uniqueCodes.contains("yue"), "Cantonese is missing from the language catalog")
    }

    private static func testLanguageCodeNormalization() {
        expectEqual(DictationLanguageCatalog.normalizedCode("cs-CZ"), "cs")
        expectEqual(DictationLanguageCatalog.normalizedCode(" pt_BR "), "pt")
        expectEqual(DictationLanguageCatalog.normalizedCode("YUE-Hant-HK"), "yue")
        expectEqual(DictationLanguageCatalog.normalizedCode(""), "")
        expect(DictationLanguageCatalog.normalizedCode("xx-YY") == nil, "Unsupported language should return nil")
    }

    private static func testLanguageOptionDefaults() {
        let locale = Locale(identifier: "en_US")
        let inputOptions = DictationLanguageCatalog.inputOptions(locale: locale)
        let outputOptions = DictationLanguageCatalog.outputOptions(locale: locale)

        expect(inputOptions.first?.code == "", "Input options should start with auto-detect")
        expect(inputOptions.first?.name == "Auto-detect", "Unexpected input default label")
        expect(outputOptions.first?.code == "", "Output options should start with spoken-language preservation")
        expect(outputOptions.first?.name == "Same as spoken language", "Unexpected output default label")
        expect(inputOptions.count == 101, "Input options should include auto-detect and 100 languages")
        expect(outputOptions.count == 101, "Output options should include default and 100 languages")
    }

    private static func testLanguageServiceNormalizesInputCodes() {
        expectEqual(LanguageService.normalizedInputCode(" CS-cz "), "cs")
        expectEqual(LanguageService.normalizedInputCode("pt_BR"), "pt")
        expectEqual(LanguageService.normalizedInputCode("not-a-language"), "")
    }

    private static func testLanguageServiceMigratesLegacyOutputNames() {
        expectEqual(LanguageService.normalizedOutputCode("English"), "en")
        expectEqual(LanguageService.normalizedOutputCode("german"), "de")
        expectEqual(LanguageService.normalizedOutputCode("Chinese (Traditional)"), "zh")
        expectEqual(LanguageService.normalizedOutputCode("cs-CZ"), "cs")
        expectEqual(LanguageService.outputPromptValue(for: "cs"), "Czech")
    }

    private static func testLanguageServicePersistsCanonicalValues() {
        let suiteName = "LanguageServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("Portuguese", forKey: LanguageService.outputLanguageStorageKey)
        defaults.set("CS-cz", forKey: LanguageService.inputLanguageStorageKey)

        expectEqual(LanguageService.loadOutputLanguage(defaults: defaults), "pt")
        expectEqual(LanguageService.loadInputLanguage(defaults: defaults), "cs")
        expectEqual(defaults.string(forKey: LanguageService.outputLanguageStorageKey), "pt")
        expectEqual(defaults.string(forKey: LanguageService.inputLanguageStorageKey), "cs")

        LanguageService.saveOutputLanguage("Slovak", defaults: defaults)
        LanguageService.saveInputLanguage("YUE-Hant-HK", defaults: defaults)
        expectEqual(defaults.string(forKey: LanguageService.outputLanguageStorageKey), "sk")
        expectEqual(defaults.string(forKey: LanguageService.inputLanguageStorageKey), "yue")
    }

    private static func expectEqual(_ actual: String?, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected, "Expected \(expected.debugDescription), got \((actual ?? "nil").debugDescription)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
