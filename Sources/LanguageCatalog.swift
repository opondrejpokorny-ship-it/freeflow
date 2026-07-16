import Foundation

/// A language supported by the Whisper transcription family.
///
/// `code` uses the canonical language identifiers accepted by Whisper and
/// OpenAI-compatible transcription endpoints. Display names are kept in
/// English as a stable fallback and can be localized at runtime through
/// Foundation's `Locale` APIs.
struct DictationLanguage: Identifiable, Hashable, Sendable {
    let code: String
    let englishName: String

    var id: String { code }

    func displayName(locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code) ?? englishName
    }
}

/// Shared multilingual catalog for transcription, cleanup, translation, and
/// future local-model providers.
///
/// Keep this list aligned with the canonical language table in OpenAI Whisper.
/// The catalog deliberately remains provider-neutral so both hosted APIs and
/// a future whisper.cpp backend can consume the same language setting.
enum DictationLanguageCatalog {
    static let autoDetectCode = ""

    static let supported: [DictationLanguage] = [
        .init(code: "en", englishName: "English"),
        .init(code: "zh", englishName: "Chinese"),
        .init(code: "de", englishName: "German"),
        .init(code: "es", englishName: "Spanish"),
        .init(code: "ru", englishName: "Russian"),
        .init(code: "ko", englishName: "Korean"),
        .init(code: "fr", englishName: "French"),
        .init(code: "ja", englishName: "Japanese"),
        .init(code: "pt", englishName: "Portuguese"),
        .init(code: "tr", englishName: "Turkish"),
        .init(code: "pl", englishName: "Polish"),
        .init(code: "ca", englishName: "Catalan"),
        .init(code: "nl", englishName: "Dutch"),
        .init(code: "ar", englishName: "Arabic"),
        .init(code: "sv", englishName: "Swedish"),
        .init(code: "it", englishName: "Italian"),
        .init(code: "id", englishName: "Indonesian"),
        .init(code: "hi", englishName: "Hindi"),
        .init(code: "fi", englishName: "Finnish"),
        .init(code: "vi", englishName: "Vietnamese"),
        .init(code: "he", englishName: "Hebrew"),
        .init(code: "uk", englishName: "Ukrainian"),
        .init(code: "el", englishName: "Greek"),
        .init(code: "ms", englishName: "Malay"),
        .init(code: "cs", englishName: "Czech"),
        .init(code: "ro", englishName: "Romanian"),
        .init(code: "da", englishName: "Danish"),
        .init(code: "hu", englishName: "Hungarian"),
        .init(code: "ta", englishName: "Tamil"),
        .init(code: "no", englishName: "Norwegian"),
        .init(code: "th", englishName: "Thai"),
        .init(code: "ur", englishName: "Urdu"),
        .init(code: "hr", englishName: "Croatian"),
        .init(code: "bg", englishName: "Bulgarian"),
        .init(code: "lt", englishName: "Lithuanian"),
        .init(code: "la", englishName: "Latin"),
        .init(code: "mi", englishName: "Maori"),
        .init(code: "ml", englishName: "Malayalam"),
        .init(code: "cy", englishName: "Welsh"),
        .init(code: "sk", englishName: "Slovak"),
        .init(code: "te", englishName: "Telugu"),
        .init(code: "fa", englishName: "Persian"),
        .init(code: "lv", englishName: "Latvian"),
        .init(code: "bn", englishName: "Bengali"),
        .init(code: "sr", englishName: "Serbian"),
        .init(code: "az", englishName: "Azerbaijani"),
        .init(code: "sl", englishName: "Slovenian"),
        .init(code: "kn", englishName: "Kannada"),
        .init(code: "et", englishName: "Estonian"),
        .init(code: "mk", englishName: "Macedonian"),
        .init(code: "br", englishName: "Breton"),
        .init(code: "eu", englishName: "Basque"),
        .init(code: "is", englishName: "Icelandic"),
        .init(code: "hy", englishName: "Armenian"),
        .init(code: "ne", englishName: "Nepali"),
        .init(code: "mn", englishName: "Mongolian"),
        .init(code: "bs", englishName: "Bosnian"),
        .init(code: "kk", englishName: "Kazakh"),
        .init(code: "sq", englishName: "Albanian"),
        .init(code: "sw", englishName: "Swahili"),
        .init(code: "gl", englishName: "Galician"),
        .init(code: "mr", englishName: "Marathi"),
        .init(code: "pa", englishName: "Punjabi"),
        .init(code: "si", englishName: "Sinhala"),
        .init(code: "km", englishName: "Khmer"),
        .init(code: "sn", englishName: "Shona"),
        .init(code: "yo", englishName: "Yoruba"),
        .init(code: "so", englishName: "Somali"),
        .init(code: "af", englishName: "Afrikaans"),
        .init(code: "oc", englishName: "Occitan"),
        .init(code: "ka", englishName: "Georgian"),
        .init(code: "be", englishName: "Belarusian"),
        .init(code: "tg", englishName: "Tajik"),
        .init(code: "sd", englishName: "Sindhi"),
        .init(code: "gu", englishName: "Gujarati"),
        .init(code: "am", englishName: "Amharic"),
        .init(code: "yi", englishName: "Yiddish"),
        .init(code: "lo", englishName: "Lao"),
        .init(code: "uz", englishName: "Uzbek"),
        .init(code: "fo", englishName: "Faroese"),
        .init(code: "ht", englishName: "Haitian Creole"),
        .init(code: "ps", englishName: "Pashto"),
        .init(code: "tk", englishName: "Turkmen"),
        .init(code: "nn", englishName: "Nynorsk"),
        .init(code: "mt", englishName: "Maltese"),
        .init(code: "sa", englishName: "Sanskrit"),
        .init(code: "lb", englishName: "Luxembourgish"),
        .init(code: "my", englishName: "Myanmar"),
        .init(code: "bo", englishName: "Tibetan"),
        .init(code: "tl", englishName: "Tagalog"),
        .init(code: "mg", englishName: "Malagasy"),
        .init(code: "as", englishName: "Assamese"),
        .init(code: "tt", englishName: "Tatar"),
        .init(code: "haw", englishName: "Hawaiian"),
        .init(code: "ln", englishName: "Lingala"),
        .init(code: "ha", englishName: "Hausa"),
        .init(code: "ba", englishName: "Bashkir"),
        .init(code: "jw", englishName: "Javanese"),
        .init(code: "su", englishName: "Sundanese"),
        .init(code: "yue", englishName: "Cantonese")
    ]

    private static let supportedByCode: [String: DictationLanguage] =
        Dictionary(uniqueKeysWithValues: supported.map { ($0.code, $0) })

    /// Accepts values such as `cs`, `cs-CZ`, and `cs_CZ` and returns the
    /// canonical Whisper language identifier when supported.
    static func normalizedCode(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return autoDetectCode }

        let primaryCode = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? ""

        return supportedByCode[primaryCode]?.code
    }

    static func language(forCode code: String) -> DictationLanguage? {
        guard let normalized = normalizedCode(code), !normalized.isEmpty else {
            return nil
        }
        return supportedByCode[normalized]
    }

    static func inputOptions(locale: Locale = .current) -> [(code: String, name: String)] {
        let localizedLanguages = supported
            .map { language in
                (code: language.code, name: language.displayName(locale: locale))
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return [(code: autoDetectCode, name: "Auto-detect")] + localizedLanguages
    }

    static func outputOptions(locale: Locale = .current) -> [(code: String, name: String)] {
        let localizedLanguages = inputOptions(locale: locale).dropFirst()
        return [(code: autoDetectCode, name: "Same as spoken language")] + localizedLanguages
    }
}
