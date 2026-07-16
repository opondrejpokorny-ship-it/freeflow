#!/usr/bin/env python3
"""Apply the multilingual UI and AppState extraction as guarded text edits.

This script is intentionally strict: every legacy snippet must occur exactly
once. If upstream code moves, the script stops instead of editing a similar but
incorrect block.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count == 0 and new in text:
        print(f"already applied: {description}")
        return
    if count != 1:
        raise RuntimeError(
            f"Expected exactly one legacy block for {description} in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"applied: {description}")


def patch_app_state() -> None:
    path = ROOT / "Sources" / "AppState.swift"

    replace_once(
        path,
        '    private let transcriptionLanguageStorageKey = "transcription_language"\n',
        "",
        "remove AppState input-language storage key",
    )
    replace_once(
        path,
        '    private let outputLanguageStorageKey = "output_language"\n',
        "",
        "remove AppState output-language storage key",
    )

    replace_once(
        path,
        '''    static let transcriptionLanguageOptions: [(code: String, name: String)] = [
        ("", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("cs", "Czech"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("ca", "Catalan")
    ]
''',
        '''    static var transcriptionLanguageOptions: [(code: String, name: String)] {
        LanguageService.inputOptions()
    }
''',
        "replace hard-coded input language list",
    )

    replace_once(
        path,
        '''    @Published var transcriptionLanguage: String {
        didSet {
            let normalized = Self.normalizeTranscriptionLanguage(transcriptionLanguage)
            if normalized != transcriptionLanguage {
                transcriptionLanguage = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: transcriptionLanguageStorageKey)
        }
    }
''',
        '''    @Published var transcriptionLanguage: String {
        didSet {
            let normalized = LanguageService.normalizedInputCode(transcriptionLanguage)
            if normalized != transcriptionLanguage {
                transcriptionLanguage = normalized
                return
            }
            LanguageService.saveInputLanguage(normalized)
        }
    }
''',
        "delegate input-language persistence",
    )

    replace_once(
        path,
        '''    @Published var outputLanguage: String {
        didSet {
            UserDefaults.standard.set(outputLanguage, forKey: outputLanguageStorageKey)
        }
    }
''',
        '''    @Published var outputLanguage: String {
        didSet {
            let normalized = LanguageService.normalizedOutputCode(outputLanguage)
            if normalized != outputLanguage {
                outputLanguage = normalized
                return
            }
            LanguageService.saveOutputLanguage(normalized)
        }
    }
''',
        "delegate output-language persistence",
    )

    replace_once(
        path,
        '''        let transcriptionLanguage = Self.normalizeTranscriptionLanguage(
            UserDefaults.standard.string(forKey: transcriptionLanguageStorageKey) ?? ""
        )
''',
        '''        let transcriptionLanguage = LanguageService.loadInputLanguage()
''',
        "load input language through LanguageService",
    )

    replace_once(
        path,
        '''        let outputLanguage = UserDefaults.standard.string(forKey: outputLanguageStorageKey) ?? ""
''',
        '''        let outputLanguage = LanguageService.loadOutputLanguage()
''',
        "load and migrate output language through LanguageService",
    )

    replace_once(
        path,
        '''    private static func normalizeTranscriptionLanguage(_ language: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard transcriptionLanguageOptions.contains(where: { $0.code == normalized }) else {
            return ""
        }
        return normalized
    }
''',
        '''    private static func normalizeTranscriptionLanguage(_ language: String) -> String {
        LanguageService.normalizedInputCode(language)
    }
''',
        "delegate input-language normalization",
    )


def patch_settings_view() -> None:
    path = ROOT / "Sources" / "SettingsView.swift"

    replace_once(
        path,
        '''                Picker("", selection: $appState.transcriptionLanguage) {
                    ForEach(AppState.transcriptionLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .accessibilityLabel("Transcription Language")
                .labelsHidden()
''',
        '''                LanguagePickerView(
                    mode: .transcription,
                    selection: $appState.transcriptionLanguage
                )
''',
        "install searchable transcription language picker",
    )

    replace_once(
        path,
        '''    private static let outputLanguageOptions = [
        "",
        "English",
        "Chinese (Simplified)",
        "Chinese (Traditional)",
        "Spanish",
        "French",
        "Japanese",
        "Korean",
        "German",
        "Portuguese",
    ]

''',
        "",
        "remove hard-coded output language list",
    )

    replace_once(
        path,
        '''    private var outputLanguageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Language", selection: $appState.outputLanguage) {
                Text("Same as spoken").tag("")
                ForEach(Self.outputLanguageOptions.dropFirst(), id: \.self) { lang in
                    Text(lang).tag(lang)
                }
            }
            .pickerStyle(.menu)

            Text("When set, FreeFlow translates your speech into the selected language.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
''',
        '''    private var outputLanguageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LanguagePickerView(
                mode: .output,
                selection: $appState.outputLanguage
            )

            Text("When set, FreeFlow translates your speech into the selected language.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
''',
        "install searchable output language picker",
    )


def patch_post_processing() -> None:
    path = ROOT / "Sources" / "PostProcessingService.swift"

    replace_once(
        path,
        '''    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)

        let timeoutSeconds = postProcessingTimeoutSeconds
''',
        '''    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)
        let resolvedOutputLanguage = LanguageService.outputPromptValue(for: outputLanguage)

        let timeoutSeconds = postProcessingTimeoutSeconds
''',
        "resolve output language for normal cleanup",
    )

    replace_once(
        path,
        '''                    customSystemPrompt: customSystemPrompt,
                    outputLanguage: outputLanguage
                )
''',
        '''                    customSystemPrompt: customSystemPrompt,
                    outputLanguage: resolvedOutputLanguage
                )
''',
        "pass resolved output language to cleanup",
    )

    replace_once(
        path,
        '''        let trimmedLanguage = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLanguage.isEmpty else {
''',
        '''        let trimmedLanguage = LanguageService.outputPromptValue(for: targetLanguage)
        guard !trimmedLanguage.isEmpty else {
''',
        "resolve output language for verbatim translation",
    )

    replace_once(
        path,
        '''    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)
        let trimmedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
''',
        '''    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)
        let resolvedOutputLanguage = LanguageService.outputPromptValue(for: outputLanguage)
        let trimmedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
''',
        "resolve output language for Edit Mode",
    )

    replace_once(
        path,
        '''                    customVocabulary: vocabularyTerms,
                    outputLanguage: outputLanguage
                )
''',
        '''                    customVocabulary: vocabularyTerms,
                    outputLanguage: resolvedOutputLanguage
                )
''',
        "pass resolved output language to Edit Mode",
    )


def main() -> None:
    patch_app_state()
    patch_settings_view()
    patch_post_processing()
    print("multilingual refactor applied successfully")


if __name__ == "__main__":
    main()
