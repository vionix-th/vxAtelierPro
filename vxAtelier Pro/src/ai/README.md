# AI Provider Layer

vxAtelier Pro uses a provider-neutral AI domain. Runtime conversation execution goes through `LLMConversationExecutor`, `LLMProviderRegistry`, and provider adapters.

## Runtime Flow

1. `ConversationItem.complete(_:draftStore:)` delegates to `LLMConversationExecutor`.
2. `LLMConversationRequestBuilder` resolves provider, endpoint family, model, options, messages, and tools into `LLMRequest`.
3. `LLMProviderRegistry` selects an `LLMProviderAdapter`.
4. `LLMAdapterRunLoop` handles shared streamed/non-streamed HTTP flow and adapter-specific parsers emit `LLMStreamEvent` values.
5. `LLMRunCollector` accumulates draft text/tool deltas in `ConversationDraftStore`.
6. Stable boundaries are persisted through `LLMPersistenceCoordinator` as `MessageItem`, `ToolCallItem`, and `ResponseRunItem`.
7. `LLMToolExecutionCoordinator` runs durable tool calls sequentially by provider index.

SwiftData is not written per token or per tool-argument delta.

## Core LLM Types

Core provider-neutral request and event types live in `ai/llm`:

- `LLMRequest`, `LLMMessage`, `LLMContentPart`
- `LLMToolDefinition`, `LLMToolCall`
- `LLMGenerationOptions`
- `LLMProviderProfile`, `LLMModelDescriptor`
- `LLMStreamEvent`, `LLMUsage`, `LLMProviderError`

Provider identity is explicit via `LLMProviderID` and profile-backed configuration presets.

## Providers

Supported profiles:

- OpenAI Platform: Responses first, with Chat Completions endpoint support.
- Anthropic: Messages API.
- OpenRouter, LM Studio, Ollama, xAI, DeepSeek, custom OpenAI-compatible: Chat Completions-compatible adapter.
- ChatGPT Subscription: profile exists but is disabled until supported OAuth, device-code, or Codex-token auth can be embedded safely.

## Persistence

Canonical records:

- `MessageItem` stores ordered `MessageContentPartItem` records and exposes `displayText`.
- `ToolCallItem` stores durable call ID, provider call ID, provider index, name, arguments JSON, status, and result link.
- `ResponseRunItem` stores provider, endpoint family, requested/actual model, request ID, status, usage, error, and turn link.
- `ModelItem` persists `LLMModelDescriptor` fields.
- `APIConfigurationItem` persists provider ID, auth kind, base URL, default endpoint family/model, endpoint overrides, headers, and options.
- `ConversationOptions` persists typed generation fields and provider extras.

## Adding A Provider

1. Add or extend an `LLMProviderProfile` in `LLMProviderRegistry`.
2. Implement `LLMProviderAdapter.stream(_:configuration:)`.
3. Implement `fetchModels(configuration:)` returning `LLMModelDescriptor`.
4. Map provider events into `LLMStreamEvent` without SwiftData writes.
5. Add fixture coverage under `vxAtelier ProTests/AI/Fixtures`.

Tool execution remains sequential by provider index. Retry is disabled by default and, when enabled, is limited to one retry before tool execution starts.

## Streaming And Non-Streaming

Streaming is controlled by `ConversationOptions.streamMode`:

- `enabled`: fail preflight if the provider/model cannot stream.
- `disabled`: request a complete response body.
- `auto`: stream when provider/model metadata advertises streaming, otherwise use non-streaming.

Adapters support both modes where the provider endpoint supports both modes. The executor consumes the same `LLMStreamEvent` stream either way, so SwiftUI draft state and SwiftData persistence do not branch on provider wire format.

## HTTP Guardrails

`NetworkClient` owns shared HTTP transport, including JSON requests, SSE parsing, timeout/body-size enforcement, response metadata, and self-signed certificate handling. `LLMHTTPClient` is the AI-facing facade: it builds LLM requests, applies provider headers, redacts diagnostics metadata, and normalizes network/provider errors.

- request timeout: `APIConfigurationItem.optionsJSON["request_timeout_seconds"]`, default `60`
- SSE idle timeout: `APIConfigurationItem.optionsJSON["sse_idle_timeout_seconds"]`, default `120`
- complete response body cap: `optionsJSON["max_response_body_bytes"]`, default `10485760`
- SSE event cap: `optionsJSON["max_sse_event_bytes"]`, default `1048576`

Provider response metadata stores status code, request id, retry-after, rate-limit headers, and redacted raw headers. Authentication headers and likely secret-bearing response headers are not persisted in diagnostics metadata.

API keys remain in user-managed configuration storage for this release. There is no Keychain migration or secure-storage abstraction in this pass.

## Validation

`LLMCapabilityValidator` performs provider/model preflight before a run is persisted:

- endpoint family support
- stream mode support
- typed parameter support
- JSON object/schema response format support
- image/file/audio content support
- tool replay ordering and tool-result correlation

`json_schema` response format requires `ConversationOptions.providerExtrasJSON` key `json_schema` to decode to an object. The adapter consumes that object into the provider-specific request shape and does not duplicate it at the top level.

## Smoke Tests

Offline adapter and executor tests use fixtures in `vxAtelier ProTests/AI/Fixtures`.

Live provider smoke tests live in `LLMProviderSmokeTests` and are skipped by default. To run them, set `VX_LLM_SMOKE_TESTS=1` plus the provider-specific variables:

- `VX_OPENAI_API_KEY`, optional `VX_OPENAI_MODEL`
- `VX_ANTHROPIC_API_KEY`, optional `VX_ANTHROPIC_MODEL`
- `VX_OPENROUTER_API_KEY`, optional `VX_OPENROUTER_MODEL`
- `VX_LMSTUDIO_BASE_URL`, `VX_LMSTUDIO_MODEL`
- `VX_OLLAMA_BASE_URL`, `VX_OLLAMA_MODEL`

The smoke tests verify streamed and non-streamed response paths for each enabled provider profile they cover.
