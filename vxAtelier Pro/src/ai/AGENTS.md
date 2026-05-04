# AGENTS.md (ai)

## Boundary
- Treat `ai/core/*` as the reusable provider-neutral LLM domain and transport layer.
- Keep `ai/core/*` free of SwiftUI, SwiftData, view models, views, application settings screens, and app-specific persistence models.
- Treat `ai/app/*` as application AI runtime. It may depend on SwiftData and app services where needed, but it must convert app models into provider-neutral `LLM*` descriptors before calling `ai/core/*`.
- Do not introduce UI presentation concerns into `ai/core/*`. Keep display copy, icons, editor behavior, and persistence materialization in app/model/view code.

## Allowed Dependencies
- `ai/core/*` may use `Foundation`, platform-neutral Swift standard library APIs, shared JSON primitives such as `JSONValue`, and intentionally shared low-level infrastructure such as `NetworkClient`.
- `ai/core/*` may use the shared `vxAtelierPro.log` facility until a neutral logging abstraction exists.
- `ai/app/*` may use SwiftData, app services, concrete tools, and runtime UI state stores when it is orchestrating application behavior.

## Parameter Model
- `ai/core/*` owns semantic LLM parameter concepts: semantic parameter IDs, primitive value types, provider/model endpoint families, mapping descriptors, default mappings, validation, and request encoding.
- A semantic parameter name is the stable internal meaning, for example `maxOutputTokens`.
- A wire key is the provider/model endpoint field name, for example `max_tokens`, `max_completion_tokens`, or `max_output_tokens`.
- Provider/model-specific name differences belong in mapping descriptors, not in UI code or conversation persistence code.
- Runtime-editable mapping overrides should be represented in `ai/core/*` as pure descriptors only. SwiftData materialization and persistence of those descriptors belongs to the app layer.

## UI And Persistence
- UI control hints such as text fields, sliders, steppers, toggles, labels, and icons are app-layer presentation concerns.
- SwiftData models such as `ModelItem`, `ModelParameterMappingItem`, `ConversationOptions`, `APIConfigurationItem`, and `AiRequestArgument` may adapt to and from `ai/core/*` value types, but `ai/core/*` should not depend on those models.
- Conversation-local argument copies belong to the app layer. The core AI layer should consume resolved generation options or primitive parameter values, not mutate conversation storage.
- If a new feature needs both AI-domain data and UI metadata, keep the AI-domain type in `ai/core/*` and add an app-side presentation adapter.

## Direction Of Flow
- App layer resolves persisted configuration and user overrides.
- `ai/app/*` converts SwiftData models into provider-neutral `ai/core/*` descriptors and request options.
- `ai/core/*` validates capabilities, resolves mappings, encodes provider requests, executes adapters, and emits provider-neutral events.
- `ai/app/*` persists stable results and updates runtime draft/tool state.

## Refactoring Rule
- When moving code toward a reusable AI library, move primitive domain concepts down into `ai/core/*` only if they are independent of SwiftUI and SwiftData.
- Move UI hints, editor behavior, persistence materialization, concrete app tools, and app-specific display copy upward or keep them in `ai/app/*`, models, or views.
- If a dependency direction is unclear, prefer a pure descriptor in `ai/core/*` plus an app-side adapter over importing an app model into `ai/core/*`.
