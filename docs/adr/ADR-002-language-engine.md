# ADR-002: Canonical language engine and persisted codes

- **Status:** Accepted
- **Date:** 2026-07-16
- **Decision owners:** FreeFlow maintainers

## Context

FreeFlow previously kept separate hard-coded language lists for transcription and translation. The transcription list contained only a subset of Whisper languages, while the output-language picker stored English display labels such as `English`, `German`, or `Chinese (Traditional)`.

This creates several problems:

- provider support and UI choices can drift,
- localized display names cannot safely serve as persistent identifiers,
- region identifiers such as `cs-CZ` are rejected even though their primary language is supported,
- local and cloud providers would require separate migrations,
- input, output, and interface language are easy to conflate.

## Decision drivers

- Support the complete canonical Whisper language set.
- Use the same semantics for cloud and local speech providers.
- Preserve previous user settings through migration.
- Keep spoken language, output language, and UI language independent.
- Allow locale-specific display names without changing persisted data.
- Keep language policy outside `AppState` and SwiftUI views.

## Considered options

### Option A: Continue storing display names

**Advantages**

- compatible with the old output-language UI,
- prompt construction can use the stored value directly.

**Disadvantages**

- display names change with localization,
- spelling and naming variants become persistence formats,
- providers require codes and repeated reverse lookup,
- duplicate or ambiguous language names are difficult to handle.

### Option B: Store arbitrary BCP-47 locale identifiers

**Advantages**

- can represent script and region variants,
- aligns with platform locale APIs.

**Disadvantages**

- many speech providers accept only primary Whisper codes,
- provider capability negotiation becomes more complex immediately,
- users may store values unsupported by the selected provider.

### Option C: Store canonical provider-neutral language codes with controlled normalization

**Advantages**

- stable identifiers,
- direct compatibility with Whisper-family providers,
- deterministic migration,
- localized names remain presentation-only,
- one catalog can support cloud and local speech.

**Disadvantages**

- script-specific translation choices require a future extension,
- LLM prompts need code-to-name resolution,
- legacy display labels must be migrated.

## Decision

Adopt **Option C**.

The initial Language Engine stores canonical Whisper primary-language codes for both spoken/input language and output language.

An empty string has different explicit semantics by field:

- input language: automatic detection,
- output language: preserve the spoken language.

These meanings are exposed by the relevant UI and request value types; they are not inferred from one shared label.

## Canonicalization rules

Input examples:

```text
cs       → cs
cs-CZ    → cs
pt_BR    → pt
YUE-Hant → yue
unknown  → automatic detection
```

Output examples:

```text
English               → en
German                → de
cs-CZ                  → cs
Chinese (Simplified)   → zh
Chinese (Traditional)  → zh
unknown                → preserve spoken language
```

The Chinese legacy values are temporarily mapped to `zh` because the canonical speech catalog does not distinguish output script. Script-specific translation targets may later use a separate output-language type and require a new ADR.

## Persistence

`LanguageService` owns:

- storage keys,
- loading,
- normalization,
- legacy migration,
- saving,
- code-to-prompt-name resolution,
- localized option generation.

`AppState` remains observable but delegates language policy and persistence.

Stored values are migrated when loaded. Migrations are idempotent.

## UI

The UI uses a searchable picker because the catalog contains 100 languages.

Requirements:

- search by localized display name or code,
- show the canonical code as secondary information,
- preserve Auto-detect and Same as spoken language as the first options,
- use locale APIs for display names,
- never persist the displayed localized name.

## Provider behavior

Speech providers receive the canonical input code or `nil` for automatic detection.

Cleanup/translation providers receive a human-readable target resolved from the canonical code until their request model supports canonical language identifiers directly.

Provider capability checks may reject or disable a language unavailable for a selected provider. The global catalog is not reduced to the smallest provider's capabilities.

## Consequences

### Positive

- one complete language source exists,
- Czech and all other supported languages follow the same path,
- legacy output-language settings remain usable,
- future whisper.cpp integration can reuse the same code,
- application localization will not corrupt stored preferences.

### Negative

- output script variants are temporarily simplified,
- old builds cannot understand newly stored output codes if a user downgrades,
- providers with different language taxonomies will need explicit adapters.

## Guardrails

- Do not introduce a second hard-coded language list in a view or provider.
- Do not persist localized display names.
- Do not use the UI locale as the spoken language automatically.
- Do not translate unless the output language is explicitly selected.
- Do not silently substitute an unsupported language with a different language; use the documented default behavior and diagnostics.

## Validation

- catalog contains 100 unique canonical codes,
- regional identifiers normalize correctly,
- unsupported input falls back to auto-detect,
- legacy output labels migrate to codes,
- input and output defaults remain distinct,
- the settings UI can select and search the full catalog,
- both cloud and future local speech providers consume the same input code.
