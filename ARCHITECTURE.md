# FreeFlow Architecture

## 1. Purpose

FreeFlow is a macOS voice interface that turns speech into trustworthy text and, later, context-aware actions.

The product must first be excellent at everyday dictation. Context awareness, skills, automation, and ecosystem features are built on top of that reliable core rather than replacing it.

The long-term product direction is:

> A private, multilingual, provider-independent voice interface for macOS.

FreeFlow should support cloud, local, and hybrid execution without forcing the UI or user workflow to depend on a specific AI vendor.

## 2. Product priorities

When priorities conflict, use this order:

1. Correct and predictable user output.
2. Privacy and explicit data handling.
3. Low interaction latency.
4. Reliability and recoverability.
5. Simple defaults for non-technical users.
6. Provider choice and extensibility.
7. Advanced automation and ecosystem features.

A feature that weakens the first four priorities must not ship merely because it appears intelligent.

## 3. Design principles

### 3.1 Dictation first

The baseline microphone-to-text flow must remain usable without context providers, skills, memory, or automation.

### 3.2 Provider independence

Core product state must not encode assumptions that only hold for Groq, OpenAI, whisper.cpp, or any future provider.

Provider-specific model identifiers, credentials, request shapes, and limits belong behind provider adapters.

### 3.3 Local when practical, cloud when valuable

FreeFlow supports three execution modes:

- **Cloud** — hosted speech and cleanup providers.
- **Local** — on-device speech and cleanup where supported.
- **Hybrid** — local and cloud stages combined independently.

Local execution is not treated as a degraded fallback. Cloud execution is not treated as mandatory.

### 3.4 Explicit data boundaries

Every component that can send user data outside the device must expose:

- what data it receives,
- where it sends that data,
- why it needs the data,
- whether data is retained locally,
- whether the component can be disabled.

### 3.5 Small interfaces, replaceable implementations

Modules communicate through narrow value types and protocols. UI code consumes application services rather than vendor SDKs or HTTP response structures.

### 3.6 Context is optional and scoped

Context providers may improve spelling, formatting, and intent resolution. They must not silently become a requirement for normal dictation.

Context must be scoped to the active request and minimized before it reaches a model.

### 3.7 Learning is inspectable

Future learned vocabulary, corrections, and profiles must be visible, editable, exportable, and removable by the user.

### 3.8 Backward-compatible settings

Stored preferences are product data. Migrations must preserve previous values where possible and normalize legacy formats deterministically.

## 4. High-level architecture

```text
┌───────────────────────────────────────────────────────────────┐
│                         macOS UI                              │
│ Settings · Overlay · History · Model Manager · Permissions   │
└──────────────────────────────┬────────────────────────────────┘
                               │ commands / observable state
┌──────────────────────────────▼────────────────────────────────┐
│                    Application Orchestrator                   │
│ Dictation session · cancellation · retries · status · policy  │
└───────┬───────────┬────────────┬────────────┬───────────┬─────┘
        │           │            │            │           │
┌───────▼─────┐ ┌───▼────────┐ ┌─▼─────────┐ ┌▼─────────┐ ┌▼─────────┐
│ Audio Engine│ │Speech Engine│ │Language   │ │Context   │ │Output    │
│ capture/VAD │ │providers    │ │Engine     │ │Engine    │ │Engine    │
└─────────────┘ └────┬───────┘ └────┬──────┘ └────┬─────┘ └────┬────┘
                     │              │             │            │
                ┌────▼──────────────▼─────────────▼─────┐      │
                │            Cleanup Engine             │      │
                │ literal cleanup · translation · edit  │      │
                └──────────────────┬─────────────────────┘      │
                                   │                            │
                             ┌─────▼─────┐                ┌─────▼─────┐
                             │Intent/Skill│                │Clipboard/ │
                             │Engine later│                │keystrokes │
                             └────────────┘                └───────────┘
```

## 5. Module responsibilities

## 5.1 Audio Engine

Responsible for:

- microphone discovery and selection,
- permission handling,
- audio capture,
- sample-rate and channel normalization,
- recording lifecycle,
- optional voice activity detection,
- interruption and cancellation,
- temporary audio ownership and deletion policy.

The Audio Engine does not know which speech provider will consume the audio.

### Primary outputs

```swift
struct RecordedAudio: Sendable {
    let url: URL
    let format: AudioFormatDescriptor
    let duration: TimeInterval
}
```

Streaming providers may consume a separate `AudioChunk` stream.

## 5.2 Speech Engine

Responsible for converting audio into a raw transcript.

```swift
protocol SpeechProvider: Sendable {
    var id: SpeechProviderID { get }
    var capabilities: SpeechProviderCapabilities { get }

    func transcribe(
        audio: RecordedAudio,
        request: SpeechTranscriptionRequest
    ) async throws -> SpeechTranscriptionResult
}
```

A provider implementation may be:

- Groq/OpenAI-compatible HTTP,
- OpenAI Realtime-compatible WebSocket,
- whisper.cpp,
- Apple Speech,
- another local or hosted engine.

Provider-specific errors are translated into shared application errors.

## 5.3 Language Engine

The Language Engine owns language semantics across all providers.

Responsible for:

- canonical language identifiers,
- normalization of locale identifiers such as `cs-CZ` and `pt_BR`,
- localized display names,
- input-language and output-language choices,
- automatic detection semantics,
- compatibility mapping for legacy stored values,
- provider capability checks,
- future mixed-language policy.

The three concepts below must remain separate:

1. **Spoken/input language** — hint for speech recognition.
2. **Output language** — optional translation target.
3. **UI language** — language of the application interface.

Changing one must not implicitly change the others.

## 5.4 Cleanup Engine

Responsible for deterministic post-transcription processing policies:

- literal cleanup,
- punctuation and capitalization,
- vocabulary preservation,
- optional translation,
- Edit Mode transforms,
- fallback and timeout policy,
- instruction-execution protection.

```swift
protocol CleanupProvider: Sendable {
    var id: CleanupProviderID { get }
    var capabilities: CleanupProviderCapabilities { get }

    func process(_ request: CleanupRequest) async throws -> CleanupResult
}
```

The default cleanup contract preserves the user's intended wording and language. Generative expansion is a separate skill and must never be silently enabled in normal dictation.

## 5.5 Context Engine

Responsible for collecting, minimizing, and presenting optional request context.

Potential providers:

- active application and bundle identifier,
- window title,
- selected text,
- clipboard context,
- screenshot context,
- Codebase Brain,
- Cursor, VS Code, Xcode,
- Slack, Outlook, browser context.

```swift
protocol ContextProvider: Sendable {
    var id: ContextProviderID { get }
    var dataDisclosure: ContextDataDisclosure { get }

    func context(for request: ContextRequest) async -> ContextFragment?
}
```

The Context Engine combines fragments under a strict size and privacy budget. Providers are individually switchable.

## 5.6 Profile Engine

Profiles alter policy, not core implementation.

A profile may define:

- preferred input and output language,
- speech and cleanup providers,
- model choices,
- vocabulary sets,
- formatting style,
- enabled context providers,
- application matching rules.

Examples include Programming, Legal, Sales, Slack, Outlook, and Terminal.

Profiles must be serializable and should not require branching inside provider implementations.

## 5.7 Learning Engine

Planned after the core and local-provider milestones.

Responsible for:

- detecting user corrections,
- proposing learned vocabulary,
- tracking application- or profile-specific terminology,
- confidence and conflict handling,
- user review, export, and deletion.

The first implementation should propose changes rather than silently rewriting permanent vocabulary.

## 5.8 Intent and Skills Engine

Planned after trustworthy dictation and context foundations.

A skill is an explicit transformation or action, for example:

- draft an email,
- rewrite selected text,
- prepare a commit message,
- find a symbol through Codebase Brain,
- execute a supported application command.

Skills are not part of literal dictation. The user must enter an explicit mode or invoke a clearly configured command.

## 5.9 Output Engine

Responsible for delivering the final result through:

- clipboard,
- simulated paste,
- optional Return key,
- selected-text replacement,
- future direct application integrations.

The Output Engine receives final text. It does not perform transcription, cleanup, translation, or intent inference.

## 6. Application orchestration

`AppState` currently combines persisted settings, UI state, service creation, session orchestration, output behavior, and diagnostics.

The migration is incremental. `AppState` remains the observable composition root while responsibilities move into dedicated services.

Target direction:

```text
AppState
├── DictationSessionController
├── LanguageService
├── ProviderRegistry
├── ProfileService
├── PermissionService
├── HistoryService
└── DiagnosticsService
```

Rules during migration:

- do not perform a large rewrite solely to reach the target shape,
- extract one coherent responsibility at a time,
- preserve stored settings and public behavior,
- add tests before removing legacy code,
- keep provider construction outside SwiftUI views.

## 7. Request data flow

### 7.1 Normal dictation

```text
shortcut
→ capture application/selection snapshot
→ record audio
→ select speech provider from active execution policy
→ transcribe using canonical input-language hint
→ collect permitted context
→ cleanup and optional translation
→ apply output policy
→ paste/store history
→ delete temporary audio according to retention settings
```

### 7.2 Local mode

```text
Audio Engine
→ Local SpeechProvider (whisper.cpp)
→ optional Local CleanupProvider
→ Output Engine
```

No audio or transcript leaves the device unless an explicitly enabled context, cleanup, telemetry, or sync provider requires it.

### 7.3 Hybrid mode

Examples:

```text
local speech → cloud cleanup
cloud speech → local cleanup
local speech → cloud translation
```

Hybrid mode is represented as independent provider selections, not as a third set of duplicate implementations.

## 8. Provider registry and capabilities

Providers are selected by stable IDs and registered in a composition root.

Capabilities are queried rather than assumed:

```swift
struct SpeechProviderCapabilities: Sendable {
    let supportsBatch: Bool
    let supportsStreaming: Bool
    let supportsAutomaticLanguageDetection: Bool
    let supportedLanguageCodes: Set<String>?
    let executesLocally: Bool
}
```

A `nil` language set means the provider does not publish a fixed list. The Language Engine still validates canonical identifiers before the request is created.

Credentials must be stored through the existing secure settings mechanism and referenced by provider configuration, never embedded in profile exports.

## 9. Plugin boundary

The first provider architecture is compiled into the application. A third-party binary plugin ABI is not a near-term goal.

A future plugin system may expose:

- provider manifests,
- declarative capabilities,
- isolated execution,
- explicit permissions,
- signed distribution.

Until a secure extension model exists, new providers and skills are ordinary reviewed source modules.

## 10. Persistence

Settings are stored by stable keys and migrated through dedicated services.

Persistence rules:

- canonical values are stored whenever possible,
- locale-specific display names are never the primary identifier,
- unknown future values are not destructively replaced unless required for safety,
- migrations are idempotent,
- secrets and ordinary preferences remain separate,
- learned data has its own versioned schema.

## 11. Privacy and security

### 11.1 Data minimization

Only data necessary for the selected request stages is collected.

### 11.2 Temporary audio

Temporary recordings must have an explicit owner and deletion point. Retained run-history audio is a separate user-visible feature.

### 11.3 Context disclosure

Settings must show which context providers are enabled and whether their output can be sent to a cloud model.

### 11.4 Instruction boundaries

Context and dictated text are untrusted inputs. Cleanup must preserve text rather than execute instructions embedded in it.

### 11.5 Local model integrity

Downloaded local models require:

- known source metadata,
- checksum verification,
- atomic installation,
- version and disk-size visibility,
- safe deletion.

## 12. Error handling

Shared application errors should distinguish:

- configuration errors,
- permission errors,
- network and authentication errors,
- provider rate limits,
- unsupported capability errors,
- model download and integrity errors,
- cancellation,
- timeout,
- invalid or empty provider output.

Fallback must be explicit and observable. FreeFlow must not silently send data to a cloud provider when the user selected local-only execution.

## 13. Testing strategy

### Unit tests

- language normalization and migration,
- provider request construction,
- cleanup prompts and instruction guard,
- profile resolution,
- temporary file lifecycle,
- provider capability selection.

### Contract tests

Each provider adapter should pass a common suite for:

- cancellation,
- empty input,
- timeout mapping,
- language hints,
- malformed responses,
- secret redaction in errors.

### Integration tests

- microphone-to-result smoke flow with a fake provider,
- local model installation lifecycle,
- settings migrations,
- output paste behavior where macOS automation permits it.

### CI

Every pull request should run:

- unit tests,
- development app compilation,
- app bundle verification,
- later SwiftFormat/SwiftLint or equivalent checks once adopted.

## 14. Dependency rules

Allowed direction:

```text
UI → application services → domain protocols/value types
                           ↑
             provider implementations
```

Not allowed:

- domain types importing SwiftUI,
- UI views constructing vendor HTTP requests,
- provider implementations mutating `AppState`,
- context providers directly pasting output,
- settings display names serving as persistent identifiers,
- local-only mode falling through to cloud without confirmation.

## 15. Architecture Decision Records

Significant decisions are recorded in `docs/adr/`.

Create or update an ADR when a change introduces or alters:

- a provider interface,
- persistence format,
- local model runtime,
- external data transmission,
- plugin or skill boundary,
- major dependency,
- security or privacy policy.

ADR status values are Proposed, Accepted, Superseded, and Rejected.

## 16. Delivery roadmap

### Milestone A — Multilingual core

- canonical 100-language catalog,
- searchable input and output language selection,
- locale-code migration,
- mixed-language-safe cleanup,
- CI and language tests.

### Milestone B — Provider foundation

- `SpeechProvider` abstraction,
- cloud adapter migrated behind the protocol,
- provider registry and capability model,
- deterministic fallback policy.

### Milestone C — Local speech

- whisper.cpp integration on Apple Silicon,
- Metal acceleration,
- model manager,
- verified downloads,
- Local and Hybrid settings,
- privacy disclosure.

### Milestone D — Intelligent dictation

- app-aware profiles,
- reviewed learning suggestions,
- richer context-provider controls,
- profile-specific vocabulary.

### Milestone E — Skills and ecosystem

- explicit skill invocation,
- Codebase Brain integration,
- application integrations,
- secure extension design evaluation.

## 17. Non-goals for the current roadmap

- replacing macOS accessibility APIs with unsupported injection techniques,
- silently executing arbitrary dictated commands,
- building a public binary plugin marketplace before isolation and signing exist,
- storing raw audio indefinitely by default,
- requiring an account for local-only use,
- coupling the product to one model vendor,
- rewriting the application into a new framework solely for architectural purity.

## 18. Definition of done for architectural changes

A structural change is ready when:

- its responsibility and boundary are clear,
- legacy stored values are migrated or preserved,
- tests cover the new policy,
- privacy behavior is unchanged or explicitly documented,
- the development app compiles,
- the relevant ADR and this document remain accurate,
- the change does not introduce an implicit cloud fallback.
