# Multilingual foundation

## Decision

FreeFlow remains the product base. We will extend the existing application instead of creating another repository.

Why FreeFlow:

- MIT-licensed and suitable for commercial modification.
- Native macOS menu-bar application written in Swift.
- Existing global dictation, context-aware cleanup, custom vocabulary, Edit Mode, and OpenAI-compatible providers.
- Existing separation between transcription language and output language.
- Existing support for automatic language detection and a partial language picker.

VoiceInk remains useful as product inspiration, but its GPLv3 source code must not be copied into a closed-source derivative. open-wispr remains the reference for a simple local whisper.cpp backend and installation flow.

## Product goal

Build a privacy-first multilingual dictation application that can work in three modes:

1. **Cloud** — fast OpenAI-compatible transcription and optional AI cleanup.
2. **Local** — on-device transcription through whisper.cpp, with no audio leaving the Mac.
3. **Hybrid** — local transcription with optional cloud or local LLM cleanup.

The product must not be designed around Czech alone. Czech is an important test language, alongside English, German, Spanish, French, Polish, Slovak, Ukrainian, and mixed-language dictation.

## Language model

The application should use one shared language catalog across all transcription providers. `Sources/LanguageCatalog.swift` contains the canonical language identifiers currently recognized by OpenAI Whisper.

Language settings are intentionally separated:

- **Spoken language** — auto-detect or a fixed hint sent to the transcription provider.
- **Output language** — keep the spoken language or translate the cleaned result.
- **Application language** — future localization of FreeFlow's own interface.

These are different concepts and must not share one setting.

## Implementation phases

### Phase 1 — language foundation

- Replace the partial hard-coded picker with `DictationLanguageCatalog`.
- Preserve existing stored language codes during migration.
- Sort language names according to the user's macOS locale.
- Keep Auto-detect as the recommended default.
- Add search to the language picker because the full catalog is too large for a basic menu.
- Add tests for normalization such as `cs-CZ` → `cs`, `pt_BR` → `pt`, and unsupported codes.
- Verify right-to-left and non-Latin output in the clipboard and active text field.

### Phase 2 — local transcription

- Add a provider abstraction instead of placing local-model conditions directly in `AppState`.
- Implement a whisper.cpp provider with Metal acceleration on Apple Silicon.
- Add model download, progress, checksum verification, removal, and disk-space reporting.
- Offer multilingual model presets rather than English-only models by default.
- Do not retain recordings unless the user explicitly enables local history.

### Phase 3 — multilingual intelligence

- Per-application profiles for transcription language, cleanup mode, output language, and vocabulary.
- Fast language switching from the menu bar.
- Mixed-language dictation without forced translation.
- Language-specific spoken punctuation and self-correction patterns.
- Separate personal dictionaries by language, plus a shared dictionary for names and brands.
- Optional automatic output-language choice based on the active conversation or document.

### Phase 4 — distribution

- Signed and notarized universal macOS build.
- First-run permissions and model setup without Terminal.
- Automatic updates.
- Clear privacy screen showing which steps are local and which provider receives data.

## Initial acceptance criteria

The first usable multilingual release should:

- transcribe into any active text field;
- support auto-detection and the complete Whisper language catalog;
- preserve mixed-language text during cleanup;
- allow a different output language only when explicitly selected;
- support custom vocabulary containing multiple scripts;
- expose Cloud, Local, and Hybrid processing choices;
- work without an account in local mode;
- avoid saving audio and transcripts by default.

## Current branch status

Branch: `feature/multilingual-foundation`

Completed:

- Added a provider-neutral catalog for the full Whisper language set.
- Added normalization helpers for regional identifiers.
- Defined separate input and output option lists.

Next code change:

- Wire `DictationLanguageCatalog` into `AppState` and `SettingsView`, then add language-catalog tests before starting the whisper.cpp provider.
