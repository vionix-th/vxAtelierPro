# AI Provider Modernization Plan

## Purpose

Modernize the AI provider layer so vxAtelier Pro can support:

- OpenAI Platform through both Responses API and Chat Completions API.
- OpenAI Codex / ChatGPT subscription access through Codex ChatGPT authentication.
- OpenAI-compatible providers such as OpenRouter, LM Studio, Ollama, xAI, and DeepSeek.
- Native non-OpenAI providers such as Anthropic Messages.
- Modern content parts, tool calls, streaming events, and provider-specific parameter drift without ad hoc request shaping.

This document is an implementation planning artifact. It records current findings, required abstractions, dependencies, and likely work order.

## Current Local State

The existing provider system already has a useful top-level shape:

- `AIService` owns model fetching, default models, default parameters, parameter application, and a `chat` service.
- `AIChatCompletionServiceStreamable` gives every provider one streaming entry point: `completeStream(request:)`.
- `GenericChatCompletionRequest` stores messages, tools, tool choice, and arbitrary parameters.
- `CompletionStreamProcessor` consumes stream chunks and turns them into a `GenericChatCompletionResponse`.
- `ConversationItem` builds provider-specific messages from SwiftData turns, applies parameters, runs completion, persists assistant messages, executes tool calls, and persists tool results.

Existing concrete providers:

- `OpenAIService`: OpenAI Chat Completions only.
- `XAIService`: subclasses `OpenAIService`.
- `DeepSeekService`: subclasses `OpenAIService`.
- `AnthropicService`: separate Anthropic Messages implementation.

Useful existing configuration:

- `APIConfigurationItem` already stores `apiKey`, `baseURL`, `chatCompletionsEndpoint`, `modelsEndpoint`, `defaultModel`, and default status.
- This is enough for simple OpenAI-compatible providers, but not enough for auth profile, endpoint family, request mode, provider-specific headers, or model metadata.

Current weak points:

- Message content is `String` only; no typed content parts.
- Internal request model is chat-completion-shaped.
- `stream` is modeled as a user parameter, but it is really transport/execution mode.
- Parameter support is provider-default arrays plus arbitrary dictionary values; this causes hidden drift and invalid payloads.
- Tool-call streaming parser is fragile. It assumes each streamed tool delta has an id, does not robustly merge by index, and mixes provider accumulation with processor accumulation.
- SwiftData persistence happens around final messages, but streaming state and tool-call lifecycle are not cleanly represented.
- Model fetching assumes provider responses look like OpenAI `/v1/models` in several places.
- Provider detection is URL string sniffing and defaults unknown providers to OpenAI.
- Config validation requires live model fetching before save, which is brittle for local servers and providers with different model-list schemas.
- OpenAI Responses API is not implemented.
- OpenAI Codex / ChatGPT subscription access is not implemented.

## External API Findings

### OpenAI Platform

OpenAI has not moved to an "API v2" naming model for normal platform use. The current shift is from Chat Completions toward the Responses API under `/v1/responses`.

Relevant endpoint families:

- `/v1/responses`: current primary endpoint for modern text generation, tools, multimodal input, reasoning, and state-related features.
- `/v1/chat/completions`: still supported and important for compatibility.
- `/v1/models`: model listing, but not sufficient by itself for all model metadata needed by the app.

Key drift from current app model:

- Responses uses `input` / content items rather than chat `messages` only.
- Output is event/item based, not just `choices[0].message.content`.
- Parameters include modern fields such as `max_output_tokens`, `reasoning`, `text.verbosity`, `service_tier`, `store`, `include`, and tool-specific settings.
- Tool calls and streaming need event-level parsing.

### OpenAI Codex / ChatGPT Subscription

Earlier assumption that ChatGPT Pro cannot be used for app inference was incomplete.

Correct distinction:

- ChatGPT subscription is not a normal OpenAI Platform API billing source.
- Codex officially supports ChatGPT sign-in for subscription access.
- Codex CLI, IDE, and app can authenticate with ChatGPT or an API key.
- ChatGPT auth returns access tokens and stores/refreshes credentials locally.
- Codex usage through ChatGPT auth follows ChatGPT workspace permissions and policies, not API organization billing.

Implications:

- Treat this as a distinct provider/auth route, not as an OpenAI API key.
- Likely transport is Codex Responses over `chatgpt.com/backend-api/codex/responses`.
- It may need SSE and WebSocket handling.
- It should be labeled experimental until vxAtelier Pro verifies auth, refresh, limits, model availability, and transport behavior.
- Token storage must be treated as sensitive credential storage.

### OpenAI-Compatible Providers

Providers like OpenRouter, LM Studio, Ollama, xAI, and DeepSeek expose OpenAI-compatible surfaces, but not identical semantics.

Common pattern:

- Usually `POST /v1/chat/completions`.
- Some also expose `POST /v1/responses`.
- Usually `GET /v1/models`, but schema and metadata vary.
- Auth may be bearer token, no auth, ignored auth, or custom headers.

Provider notes:

- OpenRouter:
  - Chat completions endpoint resembles OpenAI.
  - Model IDs are often provider-qualified, for example `openai/gpt-...`.
  - Model metadata includes context length, pricing, architecture, modalities, and supported parameters.
  - Needs custom model decoder.
- LM Studio:
  - Local OpenAI-compatible server, commonly `http://localhost:1234/v1`.
  - Supports chat completions, models, embeddings, and Responses in current docs.
  - Auth may be absent or ignored.
- Ollama:
  - Local OpenAI-compatible server, commonly `http://localhost:11434/v1`.
  - Supports chat completions, models, embeddings, and Responses compatibility.
  - Responses compatibility has limitations around state.
- xAI and DeepSeek:
  - Existing code treats them as OpenAI-chat-compatible.
  - Keep this where valid, but move behavior into profiles rather than inheritance.

### Anthropic

Anthropic is a native Messages API path, not OpenAI-compatible.

Existing app support is separate and should remain separate, but it needs modernization:

- Typed content parts.
- Native tool-use blocks.
- Native streaming event mapping.
- Parameter schema separate from OpenAI.

## Required Internal Abstractions

## Agreed Planning Decisions

- First milestone should be foundation-only. Do not add visible new providers or switch OpenAI behavior until the internal abstraction is stable.
- `stream` must move out of conversation/model parameters and into execution/transport configuration.
- Backward compatibility is not required. Schema changes are allowed when they produce the correct model.
- Saving API/provider configurations should be warning-based, not blocked by failed validation.
- Users are expected to be experienced. Prefer explicit control and clear warnings over restrictive guardrails.
- Endpoint family should be partly user-selectable and partly model/provider-constrained. Determine allowed combinations from provider and model metadata.
- Model metadata should be stored when needed by the saved model abstraction. Raw metadata can be retained for diagnostics, but normalized fields should drive behavior.
- ChatGPT/Codex subscription support should use an OpenAI-supported auth path rather than blindly reusing Codex auth files as the primary design.
- Do not keep long-lived compatibility bridges around old chat-shaped data. Short-lived refactor helpers are acceptable only when they reduce patch risk and have a clear removal point.
- Tool calls should become durable first-class records, while token/tool-argument streaming remains transient UI state until stable persistence boundaries.
- Default tool execution should preserve provider order and run sequentially first. Parallel execution should be explicit provider/app policy, not accidental behavior.
- Usage/accounting should be normalized in the provider abstraction because providers report usage differently.
- Cancellation should be first-class across request transport, stream parsing, transient UI state, and tool execution.
- Retry should be supported for retryable transport failures and configured through application settings. Tool failures should be surfaced to the model through structured tool errors rather than retried blindly by infrastructure.
- JSON/tool schema compatibility belongs in the abstraction. Concrete providers must translate or reject schemas according to their capabilities.
- Provider-specific errors must be normalized so app code can work against one error vocabulary.
- File/image content parts must respect the app's existing sandbox and security-scoped-resource practices.
- Streaming, SwiftUI updates, and SwiftData writes need explicit actor boundaries.

### Provider Profile

Need explicit provider metadata instead of URL sniffing.

Proposed shape:

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

Provider IDs should include:

- `openAIPlatform`
- `openAICodexSubscription`
- `openRouter`
- `lmStudio`
- `ollama`
- `xAI`
- `deepSeek`
- `anthropic`
- `customOpenAICompatible`

### Endpoint Families

Need distinguish API family from provider.

```swift
enum LLMEndpointKind {
    case responses
    case chatCompletions
    case anthropicMessages
    case embeddings
    case models
}
```

### Auth Profiles

Need auth type independent from provider.

```swift
enum LLMAuthKind {
    case none
    case bearerToken
    case anthropicAPIKey
    case customHeaders
    case codexChatGPTOAuth
}
```

Codex auth should not store tokens in normal API key fields. Prefer keychain or explicit import/reuse of existing Codex auth cache after user consent.

### Content Parts

Need replace `String`-only message payloads with typed content.

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

SwiftData can initially persist only text-compatible parts, then add media/file persistence later. The abstraction should not block media even if first implementation handles text.

Because backward compatibility is not required, the preferred schema direction is first-class persisted content parts rather than string-only messages with an adapter layer. A temporary bridge may still be useful inside code during refactor, but not as a long-term data model.

Any temporary bridge must be treated as scaffolding:

- It exists only to sequence risky refactors.
- It should not define new public/provider-facing APIs.
- It should have a removal task in the same milestone or the next one.
- It should not preserve old persistence semantics if those semantics conflict with the target model.

Proposed persistence direction:

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

`MessageItem.content` can be replaced by ordered content parts. If keeping a derived `text` property helps UI/search, it should be computed or denormalized intentionally, not be the source of truth.

### Request Options and Parameter Schema

Need typed request options plus provider-specific extras.

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

`stream` belongs here as execution/transport mode, not as a model parameter row.

Need parameter specs:

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

Behavior examples:

- forward as-is
- map key, for example `maxOutputTokens` to `max_tokens`
- omit when unsupported
- fail when unsupported
- include only for native OpenAI/Codex

Tool/JSON schema compatibility must be modeled by provider/model capability, not guessed at request time.

Examples:

- strict JSON schema support
- loose tool schema support
- `enum` support
- `additionalProperties` behavior
- nullable value representation
- maximum schema size or nesting limits
- provider-specific schema transforms

Unsupported schema features should either be transformed by the concrete provider adapter or rejected with a normalized unsupported-capability error.

### Model Descriptor

Need model metadata not tied to provider response schema.

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

Model fetch should return descriptors, not provider-specific Codable model objects.

### Stream Events

Need event model instead of content/toolCalls chunks.

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

Adapters emit provider-neutral events. UI and persistence consume one stable event vocabulary.

Usage should be normalized across streaming and non-streaming responses:

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

Provider errors should be normalized:

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

Application code should handle `LLMProviderErrorKind`, not provider-specific HTTP bodies.

### Tool Calls

Tool calls should become first-class state instead of JSON payloads embedded in assistant messages.

Current problems:

- Tool calls are serialized into `MessageItem.toolCallsData`, so they are opaque to SwiftData queries and difficult to validate.
- Streaming tool call assembly is provider-specific and fragile.
- Current stream parsing assumes tool-call ids are present on each delta, but common OpenAI-style streams may send deltas keyed by `index` with id/name only on early chunks.
- Provider service and `CompletionStreamProcessor` both perform accumulation/merging, which risks duplicated arguments and inconsistent final tool calls.
- Tool-call lifecycle is not explicit. The app mixes assistant text, tool-call request, tool execution, tool result, and follow-up model call into one recursive flow.
- Error/cancellation states for tool calls are not modeled as durable state.
- Parallel tool calls have no clear persistence or execution policy.

Preferred model:

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

This makes tool calls inspectable, retryable, and easier to bind in SwiftUI.

Execution policy:

- Assemble streamed tool calls in transient state.
- Persist `ToolCallItem` after call name and arguments are complete enough to execute.
- Execute tool calls sequentially by provider `index` for first implementation.
- Add explicit parallel execution later only after persistence, cancellation, and result ordering are deterministic.
- Persist tool failures as durable tool-call status, not only as log output.

### SwiftUI / SwiftData Conversation Draft

Need transient streaming state separate from persisted SwiftData rows.

Proposed lifecycle:

- Persist user message before request.
- Maintain transient `ConversationDraft` during streaming.
- Update SwiftUI from draft events.
- Persist assistant message only when complete or tool-call boundary reached.
- Persist tool call as assistant event with structured tool calls.
- Persist tool result after tool execution.
- Persist failed response state if needed, but avoid per-token SwiftData writes.
- Cancellation should cancel network work, stop stream parsing, mark transient draft as cancelled, and persist only chosen stable state.
- Retry should reuse stable persisted context and avoid re-executing completed tool calls unless the model explicitly requests a new tool call.

This reduces SwiftData churn, fixes ordering, and makes cancellation/retry clearer.

Actor boundaries:

- Network request and stream parsing should run off the main actor.
- Draft/UI updates should happen on the main actor.
- SwiftData writes should happen on the correct model context actor.
- Stream assemblers must avoid shared mutable parser state races.

Import/export:

- SwiftData export/import must be checked after adding content part and tool-call entities.
- If current export is model-driven, confirm new relationships are included and ordering survives round trip.

## Dependency-Ordered Implementation Plan

### Phase 0: Design Lock and Test Harness

Impact: high. Dependency: none.

Deliverables:

- Add unit tests or fixtures for current provider request conversion and stream parsing before replacing internals.
- Capture representative fixtures:
  - OpenAI Chat Completions non-streaming.
  - OpenAI Chat Completions streaming text.
  - OpenAI Chat Completions streaming tool call with argument deltas.
  - OpenAI Responses streaming text.
  - OpenAI Responses streaming tool call.
  - Anthropic Messages streaming text.
  - Anthropic tool-use stream.
  - OpenRouter models response.
  - LM Studio models response.
  - Ollama models response.
- Define test matrix for provider x endpoint x streaming x tools x model fetch.
- Include cancellation, retryable network failure, malformed stream, unsupported parameter, unsupported schema feature, and local-provider-offline cases.
- Decide first implementation scope for media parts: text-only persistence with typed IR, or immediate image/file support.

Why first:

- Current streaming/tool-call behavior is fragile. Need regression fixtures before refactor.

### Phase 1: Provider and Endpoint Profiles

Impact: high. Dependency: Phase 0.

Deliverables:

- Introduce `LLMProviderProfile`, `LLMEndpointKind`, `LLMAuthKind`.
- Add provider profile registry.
- Stop relying only on URL sniffing.
- Keep old `AIServiceProvider` compatibility temporarily by mapping existing configurations into profiles.
- Add presets:
  - OpenAI Platform
  - OpenAI Codex / ChatGPT subscription
  - OpenRouter
  - LM Studio
  - Ollama
  - xAI
  - DeepSeek
  - Anthropic
  - Custom OpenAI-compatible

Why early:

- Everything else depends on knowing provider, endpoint family, and auth mode explicitly.

### Phase 2: Internal Message and Request IR

Impact: high. Dependency: Phase 1.

Deliverables:

- Add `LLMMessage`, `LLMContentPart`, `LLMGenerationOptions`, `LLMTool`, `LLMToolCall`.
- Design and implement first-class SwiftData content part schema.
- Write conversion helpers from SwiftData message/content-part entities into IR.
- Replace `AIChatCompletionRequest` internals or bridge old protocol to new IR.
- Remove or demote string-only content as source of truth.

Why early:

- Responses API, modern content parts, and robust tool calls need this foundation.

### Phase 3: Parameter Schema and Request Shaping

Impact: high. Dependency: Phase 2.

Deliverables:

- Add `LLMParameterSpec` registry.
- Move `stream` out of normal model parameter UI into execution/transport config.
- Add app-level retry policy setting for retryable transport failures.
- Define mapping policies:
  - `maxOutputTokens` -> `max_tokens` for Chat Completions.
  - `maxOutputTokens` -> `max_output_tokens` for Responses.
  - `reasoning` and `text.verbosity` only for supported Responses routes.
  - `service_tier` only for native OpenAI/Codex routes.
  - `top_k` only for providers that support it.
- UI should show only valid parameters for selected provider + endpoint + model where known.
- Unknown provider extras stay possible through advanced config.
- Add schema compatibility checks to request shaping.

Why now:

- Prevents implementing new endpoints with more hacks.

### Phase 4: Model Descriptor and Model Fetching

Impact: high. Dependency: Phase 1, benefits from Phase 3.

Deliverables:

- Add `LLMModelDescriptor`.
- Implement model fetch decoders:
  - OpenAI Platform.
  - OpenRouter metadata.
  - LM Studio sparse OpenAI-compatible.
  - Ollama sparse OpenAI-compatible.
  - Anthropic.
- Merge static catalog with live metadata.
- Store supported parameters and modality hints when available.
- Persist normalized model descriptors as the app's saved model abstraction.
- Retain raw provider metadata where useful for diagnostics and future remapping.
- Persist normalized schema capability metadata when available.
- Make config save tolerant:
  - Save without successful model fetch.
  - Show validation warning instead of blocking.
  - Provide "Test connection" separately.

Why after parameter schema:

- Model metadata can refine supported parameters and UI.

### Phase 5: Stream Event Engine

Impact: very high. Dependency: Phase 2.

Deliverables:

- Add `LLMStreamEvent`.
- Replace chunk-level provider parsing with event-level adapters.
- Implement robust tool-call assembly:
  - Merge by index first.
  - Attach id/name when received.
  - Accumulate argument deltas safely.
  - Emit completed tool call only once.
- Move accumulation out of provider-specific services where possible.
- Add cancellation and partial-failure behavior.
- Emit normalized provider errors from stream parsers and transports.
- Emit normalized usage data when provider reports it.
- Persist completed tool calls as `ToolCallItem` records rather than opaque JSON.

Why before adding many providers:

- Same event engine serves OpenAI Chat, OpenAI Responses, Codex Responses, Anthropic, OpenRouter, LM Studio, and Ollama.

### Phase 6: Conversation Draft and Persistence Boundary

Impact: very high. Dependency: Phase 5.

Deliverables:

- Add transient `ConversationDraft` or equivalent observable state.
- SwiftUI renders draft during streaming.
- SwiftData persists stable boundaries only:
  - user message
  - assistant final text
  - assistant tool-call event
  - tool result
  - response completed/error metadata
- Define retry/cancel behavior.
- Define ordering rules for multi-tool calls and parallel tool calls.
- Enforce actor boundaries for network, stream parser, UI draft, and SwiftData writes.

Why after stream events:

- Draft state should be driven by provider-neutral events.

### Phase 7: OpenAI Platform Responses Adapter

Impact: high. Dependency: Phases 2, 3, 5.

Deliverables:

- Implement `/v1/responses` request adapter.
- Implement Responses stream parser.
- Implement non-streaming Responses parser.
- Map content parts, tools, reasoning summaries, usage.
- Preserve Chat Completions adapter for compatibility.
- Add endpoint selector per provider/model.

Why here:

- Responses is main target, but should sit on stable IR/event foundation.

### Phase 8: OpenAI-Compatible Providers

Impact: medium-high. Dependency: Phases 1, 3, 4, 5.

Deliverables:

- Add OpenRouter profile and model decoder.
- Add LM Studio profile.
- Add Ollama profile.
- Convert xAI and DeepSeek from inheritance to profile + OpenAI-compatible adapter where possible.
- Add provider-specific header support.
- Add no-auth/optional-auth support for local providers.

Why after core:

- Avoid copying old `OpenAIService` mistakes into more subclasses.

### Phase 9: Anthropic Modernization

Impact: medium-high. Dependency: Phases 2, 3, 5, 6.

Deliverables:

- Convert Anthropic Messages to IR.
- Add native content blocks.
- Add native tool-use and tool-result mapping.
- Add Anthropic streaming event parser.
- Remove claim that Anthropic tools are unsupported if implementation catches up.

Why after stream/tool base:

- Anthropic tool-use shape differs enough that good event abstraction should exist first.

### Phase 10: OpenAI Codex / ChatGPT Subscription Provider

Impact: high for user value, high risk. Dependency: Phases 1, 2, 3, 5, 6, 7.

Deliverables:

- Add `openAICodexSubscription` provider profile.
- Auth choices:
  - Research OpenAI-supported OAuth / auth-key routes for Codex subscription access.
  - Prefer first-party OAuth/device/browser auth over direct reuse of Codex auth files.
  - Allow importing/reusing existing Codex auth only as optional fallback if it is technically and policy safe.
- Store credentials in keychain where possible.
- Implement token refresh through the selected supported auth route.
- Implement Codex Responses transport.
- Support HTTP/SSE first; add WebSocket only if needed.
- Add clear UX:
  - "ChatGPT/Codex subscription"
  - "Experimental"
  - visible account/status
  - no token logging
- Add rate-limit/error mapping specific to subscription route.

Why late:

- It needs the most plumbing and highest care.
- It should not drive the base abstraction; it should fit into it.

### Phase 11: UI Cleanup

Impact: medium. Dependency: most previous phases.

Deliverables:

- Provider preset UI based on profiles.
- Endpoint selector where provider supports both Chat Completions and Responses.
- Parameter UI based on valid parameter schema.
- Model details view using `LLMModelDescriptor`.
- Connection test separate from save.
- Streaming/tool-call status UI driven by `ConversationDraft`.

Why late:

- UI should reflect stable model, not temporary bridge types.

### Phase 12: Cleanup and Migration

Impact: medium. Dependency: implementation maturity.

Deliverables:

- Remove old provider inheritance where obsolete.
- Deprecate old `AIChatCompletionRequest` if replaced.
- Convert or reset existing configurations to provider profiles depending on current development-store needs. No long-term backward compatibility requirement.
- Add docs:
  - provider setup
  - local provider setup
  - Codex subscription auth cautions
  - parameter compatibility matrix
- Add troubleshooting entries for:
  - local server stopped
  - model fetch schema mismatch
  - unsupported parameter
  - tool-call parsing error
  - ChatGPT auth expired
- Verify backup/export/import includes content part and tool-call relationships.

## Impact Ranking

Highest impact:

1. Stream event engine and tool-call lifecycle.
2. Internal message/content IR.
3. Parameter schema and endpoint-specific request shaping.
4. Responses API adapter.
5. Provider profiles and auth profiles.
6. Conversation draft separating SwiftUI streaming from SwiftData persistence.

Medium impact:

1. Model descriptor and model fetch decoders.
2. OpenRouter / LM Studio / Ollama provider profiles.
3. Anthropic modernization.
4. Config validation becoming warning-based.

High value but high risk:

1. OpenAI Codex / ChatGPT subscription provider.
2. WebSocket transport support.
3. OAuth/device-code auth implementation.

## Open Questions

- What exact SwiftData schema should replace string-only message content?
- How should existing local stores be handled if no backward compatibility/migration is required: reset, destructive migration, or developer-only migration script?
- Which endpoint families are permitted per OpenAI model, OpenRouter model, LM Studio model, and Ollama model?
- Should local providers default to configurable auth mode, with no-auth as the default for LM Studio and Ollama?
- Which normalized model metadata fields are required for saved models, and which raw metadata should be retained only for diagnostics?
- Which OpenAI-supported OAuth/auth-key path is available for third-party app use of Codex ChatGPT subscription access?
- Should WebSocket support be delayed until HTTP/SSE Codex Responses is proven insufficient?
- What exact application settings should control retry policy?
- What exact interrupted/cancelled response state should be persisted?

## Suggested First Milestone

Build foundation without changing user-visible provider behavior:

1. Add stream/tool-call fixtures and tests.
2. Add provider profile registry while keeping existing providers functional.
3. Add internal IR types.
4. Add first-class SwiftData content parts and tool-call entities.
5. Add conversion helpers from persisted conversation state into IR.
6. Add parameter schema for existing OpenAI, xAI, DeepSeek, and Anthropic paths.
7. Add schema capability checks and normalized provider error types.
8. Replace stream chunk parsing with provider-neutral stream events for current Chat Completions.
9. Add normalized usage output where current providers already report it.
10. Add cancellation path for current streaming requests.
11. Check backup/export/import round trip for new SwiftData entities.

Success criteria:

- Current OpenAI/xAI/DeepSeek/Anthropic behavior still works.
- Streaming text still updates UI.
- Streaming tool calls merge correctly by index/id.
- Provider-specific errors map into normalized app errors.
- Cancellation leaves consistent UI and persistence state.
- No per-token SwiftData writes.
- Existing configurations still load.
- Message content and tool calls have durable first-class persisted structure.
- Export/import preserves content part and tool-call relationships.

Only after this should vxAtelier Pro add OpenAI Responses and new providers.
