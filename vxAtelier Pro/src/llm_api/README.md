# LLM API

`llm_api` is the reusable LLM provider and tool API surface for vxAtelier Pro.

- `LLMRequest`, `LLMContentTypes`, `LLMResponseTypes`, and related files define provider-neutral LLM values and stream events.
- `LLMCapabilityValidator`, `LLMParameter*`, and `LLMRequestEncoding` define validation, parameter mapping, and request encoding.
- `LLMProvider*`, `LLMDefaultsCatalog`, and `LLMModelMetadataDecoder` define provider identities, transport profiles, configuration values, adapter lookup, defaults, and model metadata decoding.
- `OpenAI*`, `Anthropic*`, and `LLMAdapterRunLoop` map provider-specific wire protocols into provider-neutral events.
- `LLMHTTPClient` and `LLMSecretRedactor` contain provider HTTP/SSE helpers, response metadata handling, redaction, and normalized provider errors.
- `LLMTool*` and `ConfigurableLLMTool` contain reusable tool schema, configuration, catalog, and registry contracts.

SwiftData run orchestration and concrete vxAtelier tools live in `llm_runtime`.

## Runtime Flow

1. `llm_runtime` resolves persisted configuration and conversation state.
2. `llm_runtime` builds an `LLMRequest` from `llm_api` values.
3. `llm_api` supplies provider profiles and configuration values.
4. `llm_api` executes provider requests through adapters/transport and emits `LLMStreamEvent` values.
5. `llm_runtime` persists stable `MessageItem`, `ToolCallItem`, and `ResponseRunItem` records.
6. `llm_runtime` executes concrete app tools through the reusable tool contracts.

SwiftData is not written per token or per tool-argument delta.

## Providers

Supported profiles:

- OpenAI Platform: Responses first, with OpenAI Chat Completions adapter support.
- Anthropic: Messages API.
- OpenRouter, LM Studio, Ollama, xAI, DeepSeek, custom OpenAI-compatible: Chat Completions-compatible adapter.
- ChatGPT Subscription: profile exists but is disabled until supported OAuth, device-code, or Codex-token auth can be embedded safely.

## Validation

`LLMCapabilityValidator` performs provider/model preflight before runtime persists a run:

- adapter support
- stream mode support
- typed parameter support
- JSON object/schema response format support
- image/file/audio content support
- tool replay ordering and tool-result correlation

## Parameters

Keep these concepts separate:

- Semantic parameter: app-level name and value, such as `temperature`, `max_output_tokens`, or `reasoning_effort`.
- Parameter availability: selected-model support state, including available, unavailable, required, and defaulted.
- Parameter mapping: selected-model semantic-to-wire translation, such as `max_output_tokens` to `max_tokens`, `max_completion_tokens`, or a structured preset.

`LLMParameterDefinitions` owns semantic parameter identities and value metadata. `LLMParameterMapping` owns wire translation descriptors. `LLMParameterAvailabilityResolver` applies selected-model availability plus conversation inclusion preferences before encoding. Provider adapters then encode only the resulting sendable parameters.

Conversation storage may hold semantic values and user enable/disable intent for optional parameters. It must not own model availability, mandatory rules, or wire names.

## Smoke Tests

Offline adapter and LLM runtime tests use fixtures in `vxAtelier ProTests/AI/Fixtures`.

Live provider smoke tests live in `LLMProviderLiveSmokeTests` and are skipped by default. To run them, copy `vxAtelier ProTests/AI/LiveLLMProviders.template.json` to `vxAtelier ProTests/AI/LiveLLMProviders.local.json`, set the top-level `enabled` flag to `true`, and enable only the provider entries that should run locally.
