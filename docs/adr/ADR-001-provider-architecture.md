# ADR-001: Provider-based AI architecture

- **Status:** Accepted
- **Date:** 2026-07-16
- **Decision owners:** FreeFlow maintainers

## Context

FreeFlow currently uses OpenAI-compatible cloud endpoints for transcription and post-processing. The product roadmap includes additional cloud vendors, whisper.cpp, local cleanup models, Apple Speech, hybrid execution, and optional context integrations.

Without an explicit provider boundary, model selection, credentials, request construction, fallback behavior, and UI state would continue to accumulate inside `AppState` and SwiftUI views. That would make local-only guarantees difficult to enforce and each new backend would require branching throughout the application.

## Decision drivers

- Cloud, Local, and Hybrid execution must share one product flow.
- Users must be able to understand where audio, transcripts, and context are processed.
- A local-only selection must never silently fall through to cloud processing.
- Provider-specific request formats and errors must not leak into the UI.
- New providers should be testable without microphone capture or paste automation.
- The migration must be incremental; a full rewrite is not justified.

## Considered options

### Option A: Keep provider branching in `AppState`

Add enums and `switch` statements wherever a transcription or cleanup service is created.

**Advantages**

- lowest immediate implementation effort,
- minimal new types.

**Disadvantages**

- rapidly increases `AppState` complexity,
- duplicates selection and fallback policy,
- makes privacy guarantees difficult to audit,
- couples UI state to implementation details,
- becomes harder to test as providers multiply.

### Option B: One generic AI provider interface

Create a single protocol that handles speech, cleanup, translation, context, and future actions.

**Advantages**

- superficially simple registry,
- one provider-selection mechanism.

**Disadvantages**

- capabilities are fundamentally different,
- implementations would contain many unsupported methods,
- encourages vendor-shaped rather than product-shaped boundaries,
- makes hybrid combinations awkward.

### Option C: Capability-specific provider protocols

Use separate small protocols for speech, cleanup, context, and later skills. Compose them through an application-level execution policy.

**Advantages**

- narrow, testable interfaces,
- natural Cloud/Local/Hybrid combinations,
- capability discovery is explicit,
- privacy policy can be enforced per stage,
- provider-specific errors can be mapped consistently.

**Disadvantages**

- introduces more types,
- requires a registry/composition layer,
- migration takes several small steps.

## Decision

Adopt **Option C: capability-specific provider protocols**.

The initial protocols are:

- `SpeechProvider`
- `CleanupProvider`
- `ContextProvider`

Translation remains a capability of cleanup providers until a separate translation provider is required by at least two concrete implementations.

Providers are registered by stable IDs in a composition root. The UI selects configurations and execution policy; it does not instantiate providers or construct HTTP requests.

Cloud, Local, and Hybrid are represented as combinations of independently selected stages rather than separate duplicate pipelines.

## Initial interface direction

```swift
protocol SpeechProvider: Sendable {
    var id: SpeechProviderID { get }
    var capabilities: SpeechProviderCapabilities { get }

    func transcribe(
        audio: RecordedAudio,
        request: SpeechTranscriptionRequest
    ) async throws -> SpeechTranscriptionResult
}

protocol CleanupProvider: Sendable {
    var id: CleanupProviderID { get }
    var capabilities: CleanupProviderCapabilities { get }

    func process(_ request: CleanupRequest) async throws -> CleanupResult
}
```

These signatures may evolve during the first adapter extraction. Changes to their responsibility, not ordinary naming refinements, require a new ADR.

## Fallback policy

Fallback is owned by application policy, not by arbitrary provider implementations.

Rules:

1. A local-only stage cannot fall back to a cloud provider without explicit user configuration.
2. Fallback decisions are visible in run diagnostics.
3. Authentication and invalid-configuration errors do not silently switch providers.
4. Rate-limit and transient-service fallbacks may be configured between providers in the same allowed privacy class.
5. Cancellation never triggers fallback.

## Migration plan

1. Establish shared language semantics and settings migration.
2. Introduce provider IDs, request/result value types, and capability types.
3. Wrap the existing OpenAI-compatible transcription service in a `SpeechProvider` adapter.
4. Move provider selection out of SwiftUI and service internals into a registry/policy layer.
5. Add contract tests using fake providers.
6. Implement whisper.cpp as a second `SpeechProvider`.
7. Introduce `CleanupProvider` after the speech boundary is stable.

`AppState` remains the observable composition root during migration but should delegate provider selection and session work to dedicated services.

## Consequences

### Positive

- local speech can be introduced without duplicating the dictation flow,
- privacy behavior becomes easier to reason about,
- cloud vendors can share OpenAI-compatible transport while remaining distinct configurations,
- provider behavior can be unit-tested,
- profile and future skill systems can select capabilities rather than concrete classes.

### Negative

- more architectural types exist before the second provider ships,
- developers must avoid over-generalizing interfaces from hypothetical needs,
- temporary adapter layers will exist while legacy service construction is migrated.

## Guardrails

- Do not create a universal provider protocol.
- Do not expose vendor response payloads outside an adapter.
- Do not put API keys in serializable profile definitions.
- Do not add implicit cloud fallback to make an error appear recovered.
- Do not introduce a third-party binary plugin ABI as part of this decision.

## Validation

This decision is considered successfully implemented when:

- the existing cloud transcription path runs through `SpeechProvider`,
- a fake speech provider can exercise the orchestration layer in tests,
- the UI can select a provider using a stable ID,
- a local provider can be added without changing Audio or Output Engine behavior,
- diagnostics identify the provider used for each stage.
