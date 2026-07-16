import Foundation

/// Central policy and persistence boundary for spoken and output languages.
///
/// The service stores stable language codes rather than localized display
/// names. It also migrates the legacy output-language values that older
/// FreeFlow builds stored as English labels such as `English` or `German`.
enum LanguageService {
    static let inputLanguageStorageKey = "transcription_language"
    static let outputLanguageStorageKey = "output_language"

    static func inputOptions(locale: Locale = .current) -> [(code: String, name: String)] {
        DictationLanguageCatalog.inputOptions(locale: locale)
    }

    static func outputOptions(locale: Locale = .current) -> [(code: String, name: String)] {
        DictationLanguageCatalog.outputOptions(locale: locale)
    }

    /// Returns a canonical Whisper input-language code. Empty means automatic
    /// detection. Unsupported values fall back to automatic detection.
    static func normalizedInputCode(_ rawValue: String) -> String {
        DictationLanguageCatalog.normalizedCode(rawValue) ?? DictationLanguageCatalog.autoDetectCode
    }

    /// Returns a canonical output-language code. Empty means preserve the
    /// spoken language. Legacy English display names are migrated to codes.
    static func normalizedOutputCode(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DictationLanguageCatalog.autoDetectCode }

        if let normalizedCode = DictationLanguageCatalog.normalizedCode(trimmed), !normalizedCode.isEmpty {
            return normalizedCode
        }

        let folded = foldedName(trimmed)
        if let legacyMatch = DictationLanguageCatalog.supported.first(where: {
            foldedName($0.englishName) == folded
        }) {
            return legacyMatch.code
        }

        // Previous releases exposed script-specific Chinese labels. The
        // current provider-neutral catalog has one canonical Whisper code.
        if folded == foldedName("Chinese (Simplified)")
            || folded == foldedName("Chinese (Traditional)") {
            return "zh"
        }

        return DictationLanguageCatalog.autoDetectCode
    }

    static func loadInputLanguage(defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: inputLanguageStorageKey) ?? ""
        let normalized = normalizedInputCode(stored)
        migrateIfNeeded(stored: stored, normalized: normalized, key: inputLanguageStorageKey, defaults: defaults)
        return normalized
    }

    static func loadOutputLanguage(defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: outputLanguageStorageKey) ?? ""
        let normalized = normalizedOutputCode(stored)
        migrateIfNeeded(stored: stored, normalized: normalized, key: outputLanguageStorageKey, defaults: defaults)
        return normalized
    }

    static func saveInputLanguage(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(normalizedInputCode(value), forKey: inputLanguageStorageKey)
    }

    static func saveOutputLanguage(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(normalizedOutputCode(value), forKey: outputLanguageStorageKey)
    }

    /// Human-readable English target used in LLM prompts. Provider requests
    /// still use canonical codes where supported.
    static func outputPromptValue(for storedCode: String) -> String {
        let normalized = normalizedOutputCode(storedCode)
        guard !normalized.isEmpty else { return "" }
        return DictationLanguageCatalog.language(forCode: normalized)?.englishName ?? ""
    }

    static func displayName(
        for code: String,
        locale: Locale = .current,
        defaultLabel: String
    ) -> String {
        let normalized = DictationLanguageCatalog.normalizedCode(code) ?? ""
        guard !normalized.isEmpty,
              let language = DictationLanguageCatalog.language(forCode: normalized) else {
            return defaultLabel
        }
        return language.displayName(locale: locale)
    }

    private static func foldedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func migrateIfNeeded(
        stored: String,
        normalized: String,
        key: String,
        defaults: UserDefaults
    ) {
        guard stored != normalized else { return }
        defaults.set(normalized, forKey: key)
    }
}
