#!/usr/bin/env python3
"""Apply the multilingual refactor with method-specific post-processing edits."""

from __future__ import annotations

from apply_multilingual_refactor import ROOT, patch_app_state, patch_settings_view, replace_once


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
        '''                return try await self.processWithFallback(
                    transcript: transcript,
                    contextSummary: context.contextSummary,
                    customVocabulary: vocabularyTerms,
                    customSystemPrompt: customSystemPrompt,
                    outputLanguage: outputLanguage
                )
''',
        '''                return try await self.processWithFallback(
                    transcript: transcript,
                    contextSummary: context.contextSummary,
                    customVocabulary: vocabularyTerms,
                    customSystemPrompt: customSystemPrompt,
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
        '''                return try await self.processCommandTransformWithFallback(
                    selectedText: selectedText,
                    voiceCommand: voiceCommand,
                    contextSummary: context.contextSummary,
                    customVocabulary: vocabularyTerms,
                    outputLanguage: outputLanguage
                )
''',
        '''                return try await self.processCommandTransformWithFallback(
                    selectedText: selectedText,
                    voiceCommand: voiceCommand,
                    contextSummary: context.contextSummary,
                    customVocabulary: vocabularyTerms,
                    outputLanguage: resolvedOutputLanguage
                )
''',
        "pass resolved output language to Edit Mode",
    )


def main() -> None:
    patch_app_state()
    patch_settings_view()
    patch_post_processing()
    print("multilingual refactor v2 applied successfully")


if __name__ == "__main__":
    main()
