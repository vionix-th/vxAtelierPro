# LLM API

`llm_api` is the reusable provider, model-profile, request-encoding, transport, and tool API surface for vxAtelier Pro. SwiftData-aware run orchestration and concrete application tools live in `llm_runtime`.

## Runtime Flow

1. A provider model-list endpoint produces `LLMProviderModelMetadata` values containing only facts returned by the provider.
2. `ModelItem` persists that metadata and explicit user overrides. Catalog values are never copied into SwiftData.
3. `LLMModelProfileResolver` creates the effective `LLMModelProfile` used by settings, conversation controls, status UI, and request assembly.
4. `LLMGenerationOptionsResolver` combines conversation inclusion intent with the resolved required/default policy and returns resolved options plus active parameters carrying their final mappings.
5. A provider adapter builds the wire body before dispatch. `LLMHTTPGenerationPipeline` sends it and emits provider-neutral `LLMGenerationEvent` values.
6. `llm_runtime` persists stable `MessageItem`, `ToolCallItem`, and `ResponseRunItem` records. SwiftData is not written per token or tool-argument delta.

## Model Profiles

`LLMModelProfileResolver` is the sole model-profile resolution path. Parameter definitions are inherited and mutated in this order:

1. Adapter API baseline.
2. Provider rules.
3. Model-family and model rules.
4. Explicit provider observations.
5. Explicit user overrides.

Provider capability arrays remain positive, non-exhaustive metadata and may resolve to `unknown`. Parameter support is binary: omission preserves the inherited definition, explicit provider `false` disables it, and explicit `true` re-enables it only when an inherited mapping exists.

`LLMDefaultsCatalog` evaluates `adapter`, `provider`, and `model` rules from `Resources/LLMDefaults.json`. Matching rules are applied by level and declaration order. Parameter patches modify only declared fields; missing fields inherit, while explicit `null` clears nullable defaults or options.

The SwiftData schema is changed in place with no migration plan. Development stores created with the former schema must be removed with the startup recovery **Wipe Store** action. Backup format 4 exports provider observations and unified overrides only.

## Parameters

The subsystem keeps three ownership boundaries:

- Semantic value and inclusion intent belong to the conversation.
- Effective support, required/default policy, options, and mapping belong to `LLMParameterProfile`.
- Wire encoding belongs to the selected adapter.

A parameter becomes active only through required policy, explicit conversation selection, or default-enabled policy. Merely retaining a value does not activate it.

A supported parameter always has one inherited mapping: adapter-owned encoding, a scalar key, or a known structured preset. There is no separate encodability state. An enabled parameter that becomes unsupported remains visible so it can be disabled, but request assembly reports `invalidConfiguration` until the stale selection is removed or an advanced override restores valid support and mapping.

## Validation Responsibility

Remote providers are authoritative for request acceptance. There is no general capability preflight.

Local checks are limited to boundaries owned by the application:

- `LLMProviderRegistry.resolveAdapter` validates provider/adapter composition.
- `ConversationHistoryValidator` rejects duplicate, missing, dangling, or out-of-order tool-call identifiers as `invalidConversationState`.
- Provider adapters reject missing required image/file/schema/tool data, reserved option collisions, malformed values, and unrepresentable wire formats as `requestEncoding`.
- Local backends retain framework availability and platform constraints.

Provider HTTP errors retain normalized metadata, redaction, and retry classification. Remote `4xx` responses are non-retryable. A provider rejection before any assistant event is surfaced transiently and the otherwise empty turn/run is rolled back; failures after persisted assistant or tool events retain the failed run.

## Providers

- OpenAI Platform: Responses and Chat Completions.
- Anthropic: Messages.
- OpenCode Zen: configuration-selected Responses, Messages, or OpenAI-compatible Chat Completions. Model discovery returns only models compatible with selected API mode; unsupported Gemini and unknown protocol families remain hidden. Default is DeepSeek V4 Flash through Chat Completions.
- OpenRouter, LM Studio, Ollama, xAI, DeepSeek, and custom OpenAI-compatible services: Chat Completions-compatible transport.
- Codex ChatGPT Subscription: Responses routed through the ChatGPT Codex backend, with app-owned OAuth/device-code credentials and static model metadata when remote listing is unavailable.
- Apple Intelligence: local Foundation Models backend with local availability enforcement.

## Tests

Offline adapter and runtime fixtures live in `vxAtelier ProTests/AI/Fixtures`. Live provider smoke tests are skipped by default and use `LiveLLMProviders.local.json` when explicitly enabled.
