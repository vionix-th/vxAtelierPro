# AI Provider Modernization Implementation Plan

## Objective

Refactor the AI provider layer so vxAtelier Pro can support multiple endpoint families and provider-specific behavior behind a stable internal abstraction.

Required provider families:

- OpenAI Platform: Responses API and Chat Completions API.
- OpenAI Codex / ChatGPT subscription route.
- OpenAI-compatible providers: OpenRouter, LM Studio, Ollama, xAI, DeepSeek.
- Native providers: Anthropic Messages.

Required application capabilities:

- Typed content parts instead of string-only messages.
- First-class tool-call lifecycle.
- Provider-neutral streaming events.
- Provider/model-aware parameter mapping.
- Provider/model-aware model metadata.
- Normalized usage accounting.
- Normalized provider errors.
- Cancellation and retry for transport failures.
- SwiftUI streaming state that does not churn SwiftData.

## Scope

In scope:

- Provider profile registry.
- Endpoint family abstraction.
- Auth profile abstraction.
- Message/content-part schema refactor.
- Tool-call schema refactor.
- Request option and parameter schema refactor.
- Model descriptor and model-fetch refactor.
- Stream event pipeline.
- Conversation draft state for streaming UI.
- Normalized provider errors and usage.
- Cancellation and retry policy for request transport.
- Export/import verification for new SwiftData entities.
- Test fixtures and matrix for providers, endpoints, streaming, tools, and model fetch.

Out of scope for this refactor:

- General logging/security overhaul.
- Tool permission and safety policy.
- Long-term backward compatibility with old persisted schemas.
- Automatic support for every provider-specific feature exposed by every provider.
- Parallel tool execution as default behavior.

## Current Implementation Baseline

Provider entry points:

- `AIService`
- `AIChatCompletionServiceStreamable`
- `GenericChatCompletionRequest`
- `CompletionStreamProcessor`
- `ConversationItem.complete`

Current providers:

- `OpenAIService`: Chat Completions only.
- `XAIService`: subclasses `OpenAIService`.
- `DeepSeekService`: subclasses `OpenAIService`.
- `AnthropicService`: separate Messages API implementation.

Current configuration model:

- `APIConfigurationItem` stores API key, base URL, chat endpoint, models endpoint, default model, and default status.

Current limitations to remove:

- Message content is string-only.
- Request model is chat-completion-shaped.
- `stream` is stored as a normal model parameter.
- Parameters are arbitrary key/value rows without provider/model capability rules.
- Tool calls are serialized into message JSON instead of durable queryable state.
- Streaming tool-call parsing is brittle and not event based.
- SwiftData persistence and streaming UI state are not separated cleanly.
- Model fetch expects OpenAI-like model payloads in places where providers return different metadata.
- Provider detection relies on URL string matching and falls back to OpenAI.
- Configuration save is blocked by live model fetch failures.

## Architecture Decisions

### Compatibility

- No long-lived compatibility bridge around old chat-shaped data.
- Short-lived refactor helpers are allowed only when they sequence risky changes and have a clear removal point.
- Existing local development stores may be reset or destructively converted if that is simpler than migration.

### Endpoint Selection

- Endpoint family is explicit.
- Endpoint family may be user-selected when multiple valid choices exist.
- Endpoint family may be constrained by provider or model metadata.
- OpenAI Platform must support both Responses and Chat Completions.
- OpenAI-compatible providers may support Chat Completions, Responses, or both depending on provider/model capability.

### Streaming

- `stream` is execution/transport configuration, not a model parameter.
- Streaming emits provider-neutral events.
- Provider adapters own provider-specific parsing.
- Application UI consumes only the internal event model.
- SwiftData writes occur only at stable persistence boundaries.

### Tool Calls

- Tool calls are first-class persisted records.
- Tool-call deltas are assembled in transient state during streaming.
- Tool calls preserve provider order by `index`.
- First implementation executes tool calls sequentially.
- Parallel tool execution requires explicit future policy.
- Tool failures are durable tool-call status and are also surfaced to the model as structured tool errors.

### Parameters

- Parameters are described by provider/model/endpoint-aware specs.
- Unsupported parameters are omitted, transformed, or rejected by explicit policy.
- Provider-specific escape hatches stay available through advanced extras.
- Tool/JSON schema support is modeled as provider/model capability.

### Model Metadata

- Model fetch returns normalized `LLMModelDescriptor` records.
- Saved model metadata stores fields needed by the app abstraction.
- Raw provider metadata may be retained for diagnostics and future remapping.
- Model metadata can constrain endpoint family, parameters, modalities, and schema features.

### Configuration Validation

- Save configuration even when validation/model fetch fails.
- Show validation warnings instead of blocking.
- Keep explicit "Test connection" separate from save.

### Auth

- Auth mode is provider profile metadata, not implicit URL behavior.
- API key routes and ChatGPT/Codex subscription routes are separate provider profiles.
- Codex/ChatGPT subscription support should use an OpenAI-supported OAuth/auth-key route where available.
- Reusing existing Codex auth files is not the primary design and is only a possible fallback after verification.

### SwiftUI / SwiftData

- Streaming UI uses transient draft state.
- SwiftData stores completed/stable records only.
- Network and stream parsing run off the main actor.
- Draft/UI updates run on the main actor.
- SwiftData writes run on the correct model-context actor.

## Target Internal Types

### Provider Profile

```swift
struct LLMProviderProfile {
    var id: LLMProviderID
    var displayName: String
    var transportKind: LLMTransportKind
    var authKind: LLMAuthKind
    var defaultBaseURL: String
    var endpoints: Set<LLMEndpointKind>
    var defaultHeaders: [String: String]
    var modelListDecoder: LLMModelListDecoderKind
    var parameterPolicy: LLMParameterPolicy
}
```

Initial provider IDs:

- `openAIPlatform`
- `openAICodexSubscription`
- `openRouter`
- `lmStudio`
- `ollama`
- `xAI`
- `deepSeek`
- `anthropic`
- `customOpenAICompatible`

### Endpoint Family

```swift
enum LLMEndpointKind {
    case responses
    case chatCompletions
    case anthropicMessages
    case embeddings
    case models
}
```

### Auth Profile

```swift
enum LLMAuthKind {
    case none
    case bearerToken
    case anthropicAPIKey
    case customHeaders
    case codexChatGPTOAuth
}
```

### Content Parts

```swift
enum LLMContentPart {
    case inputText(String)
    case outputText(String)
    case image(LLMImageContent)
    case file(LLMFileContent)
    case audio(LLMAudioContent)
    case refusal(String)
    case reasoningSummary(String)
}

struct LLMMessage {
    var role: LLMRole
    var parts: [LLMContentPart]
    var toolCallID: String?
    var toolCalls: [LLMToolCall]?
}
```

### Generation Options

```swift
struct LLMGenerationOptions {
    var model: String
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var stop: [String]?
    var responseFormat: LLMResponseFormat?
    var reasoning: LLMReasoningOptions?
    var text: LLMTextOptions?
    var serviceTier: String?
    var stream: LLMStreamMode
    var retryPolicy: LLMRetryPolicy?
    var providerExtras: [String: JSONValue]
}
```

### Parameter Spec

```swift
struct LLMParameterSpec {
    var key: String
    var displayName: String
    var valueType: ParameterValueType
    var endpoints: Set<LLMEndpointKind>
    var providers: Set<LLMProviderID>
    var defaultValue: JSONValue?
    var allowedValues: [JSONValue]?
    var behavior: LLMParameterBehavior
}
```

### Model Descriptor

```swift
struct LLMModelDescriptor {
    var id: String
    var displayName: String
    var provider: LLMProviderID
    var endpointSupport: Set<LLMEndpointKind>
    var inputModalities: Set<LLMModality>
    var outputModalities: Set<LLMModality>
    var contextWindow: Int?
    var maxOutputTokens: Int?
    var supportedParameters: Set<String>
    var supportedSchemaFeatures: Set<LLMSchemaFeature>
    var rawMetadata: JSONValue
}
```

### Stream Event

```swift
enum LLMStreamEvent {
    case started(LLMResponseIdentity)
    case contentPartStarted(partID: String?, kind: LLMContentPartKind)
    case contentDelta(partID: String?, text: String)
    case reasoningDelta(String)
    case toolCallStarted(index: Int, id: String?, name: String?)
    case toolCallArgumentsDelta(index: Int, id: String?, delta: String)
    case toolCallCompleted(LLMToolCall)
    case completed(LLMUsage?)
    case failed(LLMProviderError)
}
```

### Usage

```swift
struct LLMUsage {
    var inputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
    var cachedInputTokens: Int?
    var totalTokens: Int?
    var providerRequestID: String?
    var billedModel: String?
}
```

### Provider Error

```swift
enum LLMProviderErrorKind {
    case authentication
    case rateLimited
    case quotaExceeded
    case unsupportedModel
    case unsupportedParameter
    case unsupportedCapability
    case contextLengthExceeded
    case malformedRequest
    case malformedResponse
    case malformedStream
    case localServerUnavailable
    case providerUnavailable
    case cancelled
}
```

## Target SwiftData Model Direction

### Message Content Parts

Replace string-only message content as source of truth with ordered content parts.

```swift
@Model
final class MessageContentPartItem {
    var kind: String
    var text: String?
    var mimeType: String?
    var fileName: String?
    var dataReference: String?
    var order: Int
    var message: MessageItem?
}
```

Text may be denormalized for search/display if useful, but ordered content parts are the canonical message payload.

### Tool Calls

```swift
@Model
final class ToolCallItem {
    var id: String
    var index: Int
    var name: String
    var argumentsJSON: String
    var status: String
    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
    var assistantMessage: MessageItem?
    var resultMessage: MessageItem?
}
```

Tool-call statuses should cover at least:

- pending
- streamingArguments
- readyToExecute
- executing
- completed
- failed
- cancelled

### Attachments

File/image content parts must use the app's existing sandbox approach:

- security-scoped access when referencing external user files
- app-private copied storage where durable access is required
- cleanup when owning message/conversation is deleted

## Work Plan

### Phase 0: Test Fixtures and Regression Matrix

Dependency: none  
Impact: high

Deliverables:

- Add representative provider fixtures:
  - OpenAI Chat Completions non-streaming text.
  - OpenAI Chat Completions streaming text.
  - OpenAI Chat Completions streaming tool call with argument deltas.
  - OpenAI Responses streaming text.
  - OpenAI Responses streaming tool call.
  - Anthropic Messages streaming text.
  - Anthropic tool-use stream.
  - OpenRouter model list.
  - LM Studio model list.
  - Ollama model list.
- Define test matrix:
  - provider
  - endpoint family
  - streaming mode
  - tool usage
  - model fetch
  - cancellation
  - retryable network failure
  - malformed stream
  - unsupported parameter
  - unsupported schema feature
  - local provider offline

Acceptance criteria:

- Existing provider request conversion behavior is covered before refactor.
- Existing streaming behavior is covered before parser replacement.
- Fixtures can be reused by new adapters.

### Phase 1: Provider, Endpoint, and Auth Profiles

Dependency: Phase 0  
Impact: high

Deliverables:

- Add provider profile registry.
- Add endpoint family model.
- Add auth profile model.
- Add profile-backed presets for:
  - OpenAI Platform
  - OpenAI Codex / ChatGPT subscription
  - OpenRouter
  - LM Studio
  - Ollama
  - xAI
  - DeepSeek
  - Anthropic
  - Custom OpenAI-compatible
- Replace URL-only provider detection with explicit profile selection.
- Keep only short-lived conversion helpers where needed to sequence existing configs.

Acceptance criteria:

- Existing OpenAI, xAI, DeepSeek, and Anthropic configs resolve through provider profiles.
- Unknown/custom OpenAI-compatible provider can be represented without pretending it is OpenAI Platform.
- Config save does not require successful model fetch.

### Phase 2: Content IR and SwiftData Content Parts

Dependency: Phase 1  
Impact: high

Deliverables:

- Add `LLMContentPart`.
- Add `LLMMessage`.
- Add first-class `MessageContentPartItem`.
- Make ordered content parts canonical.
- Add conversion from SwiftData conversation state to `LLMMessage`.
- Remove or demote string-only message content as source of truth.

Acceptance criteria:

- Conversation messages can represent multiple content parts.
- Existing text conversations still render and send as text.
- SwiftData does not require long-lived bridge code around old content semantics.

### Phase 3: Tool-Call Model and Lifecycle

Dependency: Phase 2  
Impact: very high

Deliverables:

- Add first-class `ToolCallItem`.
- Add transient tool-call assembler for streaming deltas.
- Merge streamed tool calls by provider `index`, then attach `id` and `name` when available.
- Persist completed/ready tool calls as durable records.
- Execute first implementation sequentially by provider index.
- Persist tool-call failure/cancellation status.
- Surface tool failures to the model as structured tool results.

Acceptance criteria:

- Streaming tool-call arguments are not duplicated.
- Tool-call deltas without repeated ids assemble correctly.
- Tool calls are queryable SwiftData records.
- Tool execution and tool result persistence have deterministic ordering.

### Phase 4: Request Options, Parameters, and Schema Capabilities

Dependency: Phase 2  
Impact: high

Deliverables:

- Add `LLMGenerationOptions`.
- Move `stream` to execution/transport config.
- Add `LLMParameterSpec` registry.
- Add endpoint/provider/model-aware parameter mapping.
- Add app-level retry policy for retryable transport failures.
- Add schema capability model for tool/JSON schemas.
- Add unsupported parameter/capability handling policy.

Required mappings:

- `maxOutputTokens` to `max_tokens` for Chat Completions.
- `maxOutputTokens` to `max_output_tokens` for Responses.
- OpenAI Responses reasoning/text options only where supported.
- Anthropic-specific parameters only for Anthropic.
- Provider extras only through explicit advanced path.

Acceptance criteria:

- UI can derive valid parameters from provider, endpoint, and model.
- Adapters do not send known unsupported parameters.
- Unsupported schema features produce normalized errors or explicit transformations.
- Streaming toggle no longer appears as a normal model parameter.

### Phase 5: Model Descriptor and Model Fetch

Dependency: Phases 1 and 4  
Impact: high

Deliverables:

- Add `LLMModelDescriptor`.
- Add provider-specific model list decoders:
  - OpenAI Platform
  - OpenRouter
  - LM Studio
  - Ollama
  - Anthropic
- Persist normalized descriptors for saved models.
- Persist endpoint support, modalities, context window, max output tokens, supported parameters, and schema capabilities when available.
- Retain raw metadata only where useful for diagnostics or future remapping.

Acceptance criteria:

- OpenRouter model metadata maps into normalized descriptors.
- Local provider sparse metadata maps into usable descriptors.
- Model metadata can constrain endpoint and parameter choices.
- Failed model fetch produces warning, not blocked save.

### Phase 6: Stream Event Engine

Dependency: Phases 2 and 3  
Impact: very high

Deliverables:

- Add `LLMStreamEvent`.
- Replace chunk-level provider parsing with provider-neutral stream events.
- Move accumulation out of provider-specific service code where possible.
- Emit normalized provider errors from transports and stream parsers.
- Emit normalized usage when providers report it.
- Support cancellation.
- Preserve partial draft state without per-token SwiftData writes.

Acceptance criteria:

- Current Chat Completions streaming text still updates UI.
- Current Chat Completions streaming tool calls assemble correctly.
- Stream cancellation leaves consistent UI state.
- Malformed streams produce normalized provider errors.
- No per-token or per-argument-delta SwiftData writes.

### Phase 7: Conversation Draft and Persistence Boundaries

Dependency: Phase 6  
Impact: very high

Deliverables:

- Add transient `ConversationDraft`.
- Render streaming output from draft state.
- Persist only stable records:
  - user message
  - completed assistant message
  - ready/completed tool call
  - tool result
  - completed or failed response metadata
- Enforce actor boundaries:
  - network and stream parsing off main actor
  - draft updates on main actor
  - SwiftData writes on correct model-context actor
- Define cancelled/interrupted response persistence behavior.
- Ensure retry reuses stable persisted context and does not re-execute completed tool calls.

Acceptance criteria:

- SwiftUI updates smoothly from transient state.
- SwiftData stores stable conversation records only.
- Cancellation and retry do not corrupt turn ordering.
- Tool calls and tool results preserve deterministic order.

### Phase 8: OpenAI Platform Responses Adapter

Dependency: Phases 4, 6, 7  
Impact: high

Deliverables:

- Add OpenAI `/v1/responses` request adapter.
- Add non-streaming Responses parser.
- Add streaming Responses parser.
- Map content parts, tool calls, reasoning summaries, usage, and normalized errors.
- Keep Chat Completions adapter available.
- Use provider/model metadata to determine allowed endpoint family.

Acceptance criteria:

- OpenAI Platform can run Responses text requests.
- OpenAI Platform can run Responses tool-call requests.
- OpenAI Platform Chat Completions remains functional.
- Endpoint selection is explicit or model-constrained.

### Phase 9: OpenAI-Compatible Providers

Dependency: Phases 1, 4, 5, 6  
Impact: medium-high

Deliverables:

- Add OpenRouter provider profile and model decoder.
- Add LM Studio provider profile.
- Add Ollama provider profile.
- Convert xAI and DeepSeek from inheritance to profile-backed OpenAI-compatible adapters where practical.
- Add optional/no-auth support for local providers.
- Add provider-specific header support.

Acceptance criteria:

- OpenRouter can fetch models and run chat completions.
- LM Studio can run against local server with no-auth/default local profile.
- Ollama can run against local server with no-auth/default local profile.
- xAI and DeepSeek continue to work.

### Phase 10: Anthropic Modernization

Dependency: Phases 2, 3, 4, 6, 7  
Impact: medium-high

Deliverables:

- Convert Anthropic Messages implementation to IR.
- Add native Anthropic content block mapping.
- Add native Anthropic tool-use and tool-result mapping.
- Add Anthropic streaming event parser.
- Add Anthropic-specific parameter/schema capabilities.

Acceptance criteria:

- Anthropic text requests still work.
- Anthropic streaming maps to `LLMStreamEvent`.
- Anthropic tool-use maps to first-class tool-call records.

### Phase 11: OpenAI Codex / ChatGPT Subscription Provider

Dependency: Phases 1, 4, 6, 7, 8  
Impact: high  
Risk: high

Deliverables:

- Add `openAICodexSubscription` provider profile.
- Research and implement OpenAI-supported OAuth/auth-key path.
- Store credentials through appropriate app credential storage.
- Implement token refresh for selected auth route.
- Implement Codex Responses transport.
- Support HTTP/SSE first.
- Add WebSocket only if required by verified transport behavior.
- Add visible account/status UI.
- Add subscription-route error mapping.

Acceptance criteria:

- ChatGPT/Codex subscription auth can be established through supported route.
- Requests use Codex subscription transport, not OpenAI Platform API key billing.
- Expired auth maps to normalized provider error.
- Tokens are not stored in normal API key fields.

### Phase 12: UI and Settings Integration

Dependency: Phases 1-11 as applicable  
Impact: medium

Deliverables:

- Provider preset UI from profile registry.
- Endpoint selector where multiple endpoint families are valid.
- Parameter UI from parameter/schema capability metadata.
- Model details view from `LLMModelDescriptor`.
- Connection test separate from config save.
- Retry policy application setting.
- Streaming/tool-call status from `ConversationDraft`.

Acceptance criteria:

- UI exposes only valid provider/endpoint/model controls.
- Advanced users can override provider extras intentionally.
- Local provider setup does not require successful connection before save.

### Phase 13: Export, Import, and Cleanup

Dependency: SwiftData schema changes  
Impact: medium

Deliverables:

- Verify backup/export/import includes:
  - content parts
  - tool calls
  - tool results
  - model descriptors
  - provider profile references
- Remove obsolete provider inheritance where replaced.
- Remove obsolete chat-shaped bridge helpers.
- Remove obsolete request/response types after adapters move to IR.
- Update docs:
  - provider setup
  - local provider setup
  - endpoint selection
  - parameter compatibility
  - Codex subscription setup
  - troubleshooting provider errors

Acceptance criteria:

- Export/import round trip preserves conversation content part ordering.
- Export/import round trip preserves tool-call relationships.
