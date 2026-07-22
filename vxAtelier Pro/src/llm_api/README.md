# LLM API

`llm_api` is the reusable provider, model-contract, request-encoding, transport, and tool API surface for vxAtelier Pro. SwiftData-aware run orchestration and concrete application tools live in `llm_runtime`.

## Runtime Flow

1. A provider model-list endpoint produces `LLMProviderModelObservation` values. Observations contain only facts returned by the provider.
2. `ModelItem` persists those observations and explicit user overrides. Catalog values are never copied into SwiftData.
3. `LLMModelContractResolver` creates the effective `LLMResolvedModelContract` used by settings, conversation controls, status UI, and request assembly.
4. `LLMGenerationOptionsResolver` combines conversation inclusion intent with the resolved required/default policy and returns resolved options, active parameter identifiers, and mappings.
5. A provider adapter builds the wire body before dispatch. `LLMHTTPGenerationPipeline` sends it and emits provider-neutral `LLMGenerationEvent` values.
6. `llm_runtime` persists stable `MessageItem`, `ToolCallItem`, and `ResponseRunItem` records. SwiftData is not written per token or tool-argument delta.

## Model Contract

`LLMModelContractResolver` is the sole model-contract resolution path. Precedence is fixed:

1. Explicit user override.
2. Explicit provider observation.
3. Last matching catalog rule.
4. Fallback: model identifier as display name, application default context size, and `unknown` support.

Provider capability arrays are positive, non-exhaustive observations. An omitted field makes no claim. Only an explicit provider `false` becomes an `unsupported` observation. The resolved support source is retained as `userOverride`, `provider`, `catalog`, or `fallback` so the UI can show provenance.

`LLMDefaultsCatalog` evaluates ordered rules from `Resources/LLMDefaults.json`. Rules are evaluated from top to bottom; later matching rules override earlier rules. `providerRegex` and `modelRegex` are regular-expression matches and `adapterID` is exact.

The SwiftData schema is changed in place with no migration plan. Development stores created with the former materialized model schema must be removed with the startup recovery **Wipe Store** action. Backup format 3 exports observations and overrides only and intentionally rejects earlier model-contract backup formats.

## Parameters

The subsystem keeps three concepts separate:

- Semantic value and inclusion intent belong to the conversation.
- Advisory support, required/default policy, options, and effective mapping belong to `LLMResolvedParameterContract`.
- Wire encoding belongs to the selected adapter.

An explicitly enabled mapped parameter remains active when support is `unsupported` or `unknown`; the provider decides whether to accept it. A missing or disabled mapping is different: the application cannot encode that parameter, so an active unmapped parameter produces `LLMProviderError.requestEncoding` before network dispatch. Streaming is read directly from resolved request options and model streaming support is advisory.

## Validation Responsibility

Remote providers are authoritative for request acceptance. There is no general capability preflight.

Local checks are limited to boundaries owned by the application:

- `LLMProviderRegistry.resolveAdapter` validates provider/adapter composition.
- `ConversationHistoryValidator` rejects duplicate, missing, dangling, or out-of-order tool-call identifiers as `invalidConversationState`.
- Provider adapters reject missing/disabled active mappings, required image/file/schema/tool encoding data, reserved option collisions, and unrepresentable wire formats as `requestEncoding`.
- Local backends retain framework availability and platform constraints.

Provider HTTP errors retain normalized metadata, redaction, and retry classification. Remote `4xx` responses are non-retryable. A provider rejection before any assistant event is surfaced transiently and the otherwise empty turn/run is rolled back; failures after persisted assistant or tool events retain the failed run.

## Providers

- OpenAI Platform: Responses and Chat Completions.
- Anthropic: Messages.
- OpenRouter, LM Studio, Ollama, xAI, DeepSeek, and custom OpenAI-compatible services: Chat Completions-compatible transport.
- Codex ChatGPT Subscription: Responses routed through the ChatGPT Codex backend, with app-owned OAuth/device-code credentials and a static observation inventory when remote listing is unavailable.
- Apple Intelligence: local Foundation Models backend with local availability enforcement.

## Tests

Offline adapter and runtime fixtures live in `vxAtelier ProTests/AI/Fixtures`. Live provider smoke tests are skipped by default and use `LiveLLMProviders.local.json` when explicitly enabled.
