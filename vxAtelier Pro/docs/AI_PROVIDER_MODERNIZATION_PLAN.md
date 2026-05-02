# AI Provider Modernization Plan

## 1. Goal

Build a green-field internal AI provider architecture for vxAtelier Pro.

The app must support:

- OpenAI Platform through Responses API and Chat Completions API.
- OpenAI-compatible providers: OpenRouter, LM Studio, Ollama, xAI, DeepSeek.
- Native providers: Anthropic Messages.
- OpenAI Codex / ChatGPT subscription access after the supported auth route is verified.

The main deliverable is not a list of provider integrations. The main deliverable is a provider-neutral abstraction that lets conversation logic, SwiftUI views, SwiftData models, tools, settings, and export/import operate without knowing provider request/response shapes.

## 2. Non-Negotiables

- This is green-field for persistence and configuration.
- No database migration path is required.
- No configuration migration path is required.
- Existing local databases and saved configurations may break.
- Prefer correct final schema over transitional compatibility code.
- Provider DTOs must not leak into SwiftUI, SwiftData models, conversation orchestration, tools, or settings.
- Provider-specific logic belongs in provider profiles and concrete adapters.
- SwiftData must not be written per streamed token or per streamed tool-argument delta.
- `stream` is execution/transport configuration, not a model parameter.
- Tool calls are first-class persisted records, not opaque JSON embedded in messages.
- First implementation executes tool calls sequentially by provider order.
- Parallel tool execution is out of scope for this refactor.
- General logging/security overhaul and tool permission policy are out of scope.

## 3. Target Architecture

The implementation has five layers.

### 3.1 Persistence Layer

SwiftData owns stable app records only:

- conversations
- turns
- events
- messages
- ordered message content parts
- tool calls
- response runs
- model descriptors
- API configurations
- conversation options

Persistence does not store provider DTOs. It may store raw provider model metadata as diagnostic JSON, but normalized fields remain the source of truth for app behavior.

### 3.2 Domain Layer

The domain layer defines provider-neutral types:

- `LLMRequest`
- `LLMMessage`
- `LLMContentPart`
- `LLMToolDefinition`
- `LLMToolCall`
- `LLMGenerationOptions`
- `LLMProviderProfile`
- `LLMModelDescriptor`
- `LLMStreamEvent`
- `LLMUsage`
- `LLMProviderError`

Conversation code builds these types from SwiftData records.

### 3.3 Adapter Layer

Adapters translate between domain types and provider APIs.

Initial adapters:

- OpenAI Chat Completions adapter.
- OpenAI Responses adapter.
- OpenAI-compatible Chat Completions adapter.
- OpenAI-compatible Responses adapter where providers support it.
- Anthropic Messages adapter.
- Codex subscription adapter after auth route verification.

Adapter input is `LLMRequest`. Adapter output is `AsyncThrowingStream<LLMStreamEvent, Error>` or a final provider-neutral response.

### 3.4 Execution Layer

The execution layer owns:

- endpoint selection
- request construction
- retry policy
- cancellation
- stream consumption
- tool-call assembly
- tool execution
- stable persistence boundaries

It does not parse provider payloads.

### 3.5 UI Layer

SwiftUI renders:

- persisted conversation state from SwiftData
- in-flight state from a transient `ConversationDraftStore`

Views render domain/draft state. Views do not parse provider chunks.

## 4. Target Data Model

Keep the high-level conversation model:

- `ConversationItem`
- `ConversationTurn`
- `TurnEvent`
- `MessageItem`

Replace the internals that are too chat-shaped.

### 4.1 Message Content

`MessageItem` keeps role and timestamp. Its canonical payload becomes ordered content parts.

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

`ContentItem.text` may survive temporarily during active refactor, but must not remain the canonical source of message content.

### 4.2 Tool Calls

Tool calls become durable records.

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

Use a string-backed `ToolCallStatus` enum:

- `pending`
- `streamingArguments`
- `readyToExecute`
- `executing`
- `completed`
- `failed`
- `cancelled`

Tool results stay as `MessageItem` records with role `tool`, linked through `ToolCallItem.resultMessage`.

### 4.3 Response Runs

Each model request gets a durable run record.

```swift
@Model
final class ResponseRunItem {
    var providerID: String
    var endpointFamily: String
    var requestedModelID: String
    var actualModelID: String?
    var providerRequestID: String?
    var status: String
    var errorKind: String?
    var errorMessage: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
    var cachedInputTokens: Int?
    var totalTokens: Int?
    var createdAt: Date
    var completedAt: Date?
    var turn: ConversationTurn?
}
```

Use a string-backed `ResponseRunStatus` enum:

- `pending`
- `streaming`
- `awaitingToolResults`
- `completed`
- `failed`
- `cancelled`
- `interrupted`

Do not store streamed token deltas in `ResponseRunItem`.

### 4.4 Model Records

Do not add a parallel model table if `ModelItem` can be reshaped cleanly. Prefer replacing `ModelItem` with the persisted representation of `LLMModelDescriptor`.

Required model fields:

- model id
- display name
- provider id
- supported endpoint families
- input modalities
- output modalities
- context window
- max output tokens
- supported parameters
- supported schema features
- raw metadata JSON

### 4.5 Configuration Records

`APIConfigurationItem` stores provider/profile defaults:

- provider id
- auth kind
- base URL
- default endpoint family
- default model id
- provider-specific headers or advanced options where needed

`ConversationOptions` may override endpoint family and model for a conversation.

Endpoint resolution order:

1. Conversation override if set and supported.
2. API configuration default if supported.
3. Provider/model preferred endpoint.
4. Fail with normalized `unsupportedCapability` error.

## 5. Core Domain Types

These are target shapes. Names may be adjusted to fit local style, but responsibilities should not change.

```swift
struct LLMRequest {
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions
    var model: LLMModelDescriptor
    var provider: LLMProviderProfile
    var endpoint: LLMEndpointKind
    var metadata: LLMRequestMetadata
}
```

`LLMRequest` must not contain SwiftData objects or provider DTOs.

```swift
enum LLMEndpointKind {
    case responses
    case chatCompletions
    case anthropicMessages
    case embeddings
    case models
}
```

```swift
enum LLMAuthKind {
    case none
    case bearerToken
    case anthropicAPIKey
    case customHeaders
    case codexChatGPTOAuth
}
```

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

Initial provider ids:

- `openAIPlatform`
- `openAICodexSubscription`
- `openRouter`
- `lmStudio`
- `ollama`
- `xAI`
- `deepSeek`
- `anthropic`
- `customOpenAICompatible`

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

## 6. Request Lifecycle

Final request flow:

1. User sends message.
2. `ConversationItem` persists the user message and turn.
3. Conversation state converts into `[LLMMessage]`.
4. Configuration, conversation options, and selected model resolve to `LLMGenerationOptions`, `LLMProviderProfile`, `LLMModelDescriptor`, and `LLMEndpointKind`.
5. Execution layer creates `ResponseRunItem(status: pending)`.
6. Execution layer builds `LLMRequest`.
7. Selected adapter sends request and emits `LLMStreamEvent`.
8. `ConversationDraftStore` updates SwiftUI from events.
9. Stable boundaries persist assistant messages, tool calls, tool results, and response metadata.
10. `ResponseRunItem` completes, fails, or is cancelled.

Provider-specific request and response details are confined to adapters.

## 7. Streaming and Draft State

Use a transient `ConversationDraftStore`.

Ownership:

- `ConversationViewModel` reads and writes draft state.
- Drafts are keyed by `ConversationItem.id`.
- Draft state is `@MainActor`.
- Provider adapters do not know draft state exists.

Cancellation behavior:

- cancel network task
- stop stream parsing
- mark draft as cancelled
- persist `ResponseRunItem.status = cancelled`
- keep already persisted stable records
- keep the initiating user message
- do not persist partial assistant text unless it reached a stable boundary

Actor rules:

- network and stream parsing run off main actor
- draft updates run on main actor
- SwiftData writes run on the correct model-context actor

## 8. Tool Lifecycle

Tool calls are assembled from stream events in transient state.

Assembly rules:

- merge by provider `index`
- attach `id` when available
- attach `name` when available
- append argument deltas in arrival order
- emit one completed tool call when arguments are complete

Execution rules:

- persist `ToolCallItem(status: readyToExecute)` before execution
- execute sequentially by `index`
- mark `executing`, then `completed`, `failed`, or `cancelled`
- persist tool output as role `tool` `MessageItem`
- link result message from `ToolCallItem.resultMessage`
- return tool failures to the model as structured tool results
- do not retry failed tools in infrastructure

## 9. Retry Policy

Retry policy lives in application settings and is copied into `LLMGenerationOptions`.

Initial behavior:

- manual retry is always possible for failed response runs
- automatic retry is disabled by default
- if enabled, automatic retry applies only to retryable transport/provider failures before tool execution starts
- initial automatic retry count is `1`
- completed tool calls must not execute again during retry unless a new model response requests a new tool call

## 10. Endpoint and Parameter Policy

Endpoint selection is explicit and capability checked.

Parameter mapping examples:

- `maxOutputTokens` maps to `max_tokens` for Chat Completions.
- `maxOutputTokens` maps to `max_output_tokens` for Responses.
- OpenAI Responses reasoning/text options are sent only when supported.
- Anthropic-only options are sent only to Anthropic.
- Provider extras are available only through an explicit advanced path.

Schema compatibility is part of model/provider capability:

- strict JSON schema support
- loose tool schema support
- enum support
- `additionalProperties` behavior
- nullable value representation
- max schema size or nesting limits

Unsupported parameters or schema features are transformed only when a provider adapter explicitly supports the transform. Otherwise they fail with normalized `unsupportedParameter` or `unsupportedCapability`.

## 11. Work Plan

### Phase 0: Fixtures and Matrix

Purpose: lock current behavior before replacing core abstractions.

Primary files:

- `vxAtelier ProTests`
- `vxAtelier Pro/src/ai`
- `vxAtelier Pro/src/models/CompletionStreamProcessor.swift`

Deliverables:

- fixtures for OpenAI Chat Completions text, streaming, and tool calls
- fixtures for OpenAI Responses text and tool calls
- fixtures for Anthropic text and tool use
- fixtures for OpenRouter, LM Studio, and Ollama model lists
- test matrix for provider, endpoint, streaming, tools, model fetch, cancellation, retryable failure, malformed stream, unsupported parameter, unsupported schema, and local-provider-offline

Acceptance:

- current request conversion and streaming behavior are covered before replacement
- fixtures are reusable by new adapters

### Phase 1: Profiles

Purpose: make provider, endpoint, and auth selection explicit.

Primary files:

- `AIServiceManager.swift`
- `AIService.swift`
- `APIConfigurationItem.swift`
- `APIConfigurationEditView.swift`
- `AppDefaults.swift`
- `Package.swift`

Deliverables:

- `LLMProviderProfile`
- `LLMEndpointKind`
- `LLMAuthKind`
- profile registry
- profile-backed presets
- fresh configuration flow based on provider profiles

Acceptance:

- fresh OpenAI, xAI, DeepSeek, Anthropic, and custom OpenAI-compatible configs resolve through profiles
- unknown OpenAI-compatible provider is not treated as OpenAI Platform
- config save does not require model fetch success

### Phase 2: Content and Message Model

Purpose: replace string-only content with provider-neutral content parts.

Primary files:

- `MessageItem.swift`
- `ConversationItem.swift`
- `ConversationTurn.swift`
- `MessageView.swift`
- `MessageExportData.swift`
- `Package.swift`

Deliverables:

- `LLMContentPart`
- `LLMMessage`
- `MessageContentPartItem`
- canonical ordered content parts
- conversion from SwiftData messages to `LLMMessage`

Acceptance:

- text messages in new schema render and send
- multiple content parts are representable
- no long-lived bridge around old content semantics remains

### Phase 3: Tool Model

Purpose: make tool calls durable, ordered, and retry-safe.

Primary files:

- `MessageItem.swift`
- `ConversationItem.swift`
- `CompletionStreamProcessor.swift`
- `vxAtelier Pro/src/ai/tools`
- `MessageView.swift`
- `vxAtelier Pro/src/system/export`
- `Package.swift`

Deliverables:

- `ToolCallItem`
- `ToolCallStatus`
- transient tool-call assembler
- sequential tool execution by index
- structured tool failure results

Acceptance:

- streamed tool calls merge by index and do not duplicate arguments
- tool-call deltas without repeated ids assemble correctly
- tool calls are queryable SwiftData records
- tool result ordering is deterministic

### Phase 4: Options and Parameters

Purpose: replace arbitrary provider parameters with capability-aware request options.

Primary files:

- `ConversationOptions.swift`
- `AiRequestArgument.swift`
- `AIService.swift`
- `OpenAIService.swift`
- `AnthropicService.swift`
- `ConversationOptionsView.swift`
- `StatusBar.swift`

Deliverables:

- `LLMGenerationOptions`
- `LLMParameterSpec`
- retry policy setting
- endpoint preference on `APIConfigurationItem`
- endpoint override on `ConversationOptions`
- schema capability model

Acceptance:

- UI derives valid parameters from provider, endpoint, and model
- unsupported parameters do not get sent
- unsupported schema features produce normalized errors
- `stream` is not a normal model parameter

### Phase 5: Model Descriptors

Purpose: normalize model metadata across providers.

Primary files:

- `ModelItem.swift`
- `ModelProviderUtils.swift`
- `OpenAICodableTypes.swift`
- `OpenAIService.swift`
- `AnthropicService.swift`
- `ModelsSettingsView.swift`
- `ModelSelectionView.swift`

Deliverables:

- `LLMModelDescriptor`
- reshaped `ModelItem`
- model list decoders for OpenAI, OpenRouter, LM Studio, Ollama, Anthropic
- normalized endpoint, modality, context, output, parameter, and schema support

Acceptance:

- OpenRouter rich metadata maps into descriptors
- local sparse metadata maps into usable descriptors
- failed model fetch warns instead of blocking save

### Phase 6: Stream Events

Purpose: replace provider chunks with provider-neutral stream events.

Primary files:

- `CompletionStreamProcessor.swift`
- `StreamingState.swift`
- `OpenAIService.swift`
- `AnthropicService.swift`
- `NetworkManager.swift`
- `ConversationItem.swift`

Deliverables:

- `LLMStreamEvent`
- normalized stream parser output
- normalized usage extraction
- normalized error mapping
- cancellation support

Acceptance:

- current Chat Completions text streaming still updates UI
- current Chat Completions tool streaming assembles correctly
- malformed streams produce normalized errors
- no token or argument-delta SwiftData writes occur

### Phase 7: Draft and Response Runs

Purpose: separate in-flight UI state from persisted conversation state.

Primary files:

- `ConversationItem.swift`
- `StreamingState.swift`
- `StreamingConversationHandler.swift`
- `ConversationViewModel.swift`
- `ConversationView.swift`
- `MessageView.swift`
- `Package.swift`

Deliverables:

- `ConversationDraftStore`
- `ResponseRunItem`
- `ResponseRunStatus`
- persistence boundaries for user message, assistant message, tool call, tool result, and response run metadata
- actor-boundary cleanup

Acceptance:

- SwiftUI streams from draft state
- SwiftData stores stable records only
- cancellation and retry preserve deterministic turn ordering
- response run metadata persists usage/errors/status

### Phase 8: OpenAI Platform Responses

Purpose: add first new endpoint family after the foundation is stable.

Primary files:

- `OpenAIService.swift`
- `OpenAICodableTypes.swift`
- new OpenAI Responses adapter/type files
- `AIServiceManager.swift`
- `APIConfigurationEditView.swift`
- `Package.swift`

Deliverables:

- `/v1/responses` request adapter
- non-streaming parser
- streaming parser
- content/tool/reasoning/usage/error mapping
- endpoint selection with Chat Completions retained

Acceptance:

- OpenAI Responses text works
- OpenAI Responses tool calls work
- OpenAI Chat Completions still works

### Phase 9: OpenAI-Compatible Providers

Purpose: add provider breadth through profiles and adapters.

Primary files:

- `AIServiceManager.swift`
- `OpenAIService.swift`
- `XAIService.swift`
- `DeepSeekService.swift`
- new OpenRouter, LM Studio, Ollama files
- `APIConfigurationEditView.swift`
- `Package.swift`

Deliverables:

- OpenRouter profile and model decoder
- LM Studio profile
- Ollama profile
- profile-backed xAI and DeepSeek where practical
- optional/no-auth local provider support
- provider-specific headers

Acceptance:

- OpenRouter model fetch and chat completions work
- LM Studio local chat works
- Ollama local chat works
- xAI and DeepSeek continue to work

### Phase 10: Anthropic Modernization

Purpose: bring Anthropic onto the same domain, stream, and tool abstractions.

Primary files:

- `AnthropicService.swift`
- `AnthropicCodableTypes.swift`
- `AnthropicDefaults.swift`
- `ConversationItem.swift`
- `CompletionStreamProcessor.swift`

Deliverables:

- Anthropic content block mapping
- Anthropic tool-use mapping
- Anthropic stream event parser
- Anthropic parameter/schema capabilities

Acceptance:

- Anthropic text works
- Anthropic streaming emits `LLMStreamEvent`
- Anthropic tool use persists as `ToolCallItem`

### Phase 11: Codex / ChatGPT Subscription

Purpose: add subscription-backed provider only after auth route is verified.

Primary files:

- new Codex provider/profile/auth files
- `AIServiceManager.swift`
- `NetworkManager.swift`
- `APIConfigurationEditView.swift`
- `APISettingsView.swift`
- `Package.swift`

Deliverables:

- `openAICodexSubscription` profile
- verified OpenAI-supported auth route
- token refresh for selected auth route
- Codex Responses transport
- visible account/status UI
- normalized subscription-route errors

Acceptance:

- subscription auth works through supported route, or provider remains disabled with normalized auth-unavailable error
- requests use Codex subscription transport, not OpenAI Platform API key billing
- expired auth maps to normalized error
- tokens are not stored in normal API key fields

### Phase 12: UI Integration

Purpose: expose the new architecture in settings and conversation UI.

Primary files:

- `APIConfigurationEditView.swift`
- `APISettingsView.swift`
- `ModelsSettingsView.swift`
- `ModelSelectionView.swift`
- `ConversationOptionsView.swift`
- `StatusBar.swift`

Deliverables:

- provider preset UI from profile registry
- endpoint selector
- parameter UI from capability metadata
- model details from `LLMModelDescriptor`
- connection test separate from save
- retry policy setting
- tool/run status from draft and persisted state

Acceptance:

- UI shows valid controls for selected provider/model/endpoint
- advanced provider extras remain explicit
- local provider config can be saved while offline

### Phase 13: Export, Import, Cleanup

Purpose: remove obsolete structures and verify persistence round trip.

Primary files:

- `DataManager.swift`
- `vxAtelier Pro/src/system/export`
- `vxAtelier Pro/src/models`
- `Package.swift`
- `vxAtelier ProTests/System`
- `vxAtelier ProTests/Models`

Deliverables:

- export/import content parts
- export/import tool calls and tool results
- export/import response runs
- export/import model descriptors and provider profile references
- remove obsolete provider inheritance where replaced
- remove obsolete bridge helpers
- remove obsolete request/response types
- update provider setup docs

Acceptance:

- export/import preserves content part ordering
- export/import preserves tool-call relationships
- export/import preserves response-run metadata
- no migration-only code remains for old databases or old configurations

## 12. Verification Commands

Use SPM for fast checks:

```bash
swift build
swift test
```

Use Xcode build/test for runtime-facing phases:

```bash
xcodebuild -quiet
```

Keep `Package.swift` synchronized with every new or deleted Swift file.
