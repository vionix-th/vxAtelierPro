# AGENTS.md (ai)

## Boundary
- Treat `ai/*` as the provider-neutral LLM domain layer.
- Keep this layer reusable outside vxAtelier Pro where practical.
- Prefer pure Swift value types, protocols, request/response descriptors, encoders, validators, provider adapters, and transport-facing utilities.
- Do not introduce dependencies on SwiftUI, SwiftData, view models, views, application settings screens, or app-specific persistence models.
- Do not make `ai/*` responsible for storing user preferences, conversation-local editable state, or runtime UI state.

## Allowed Dependencies
- `Foundation` and platform-neutral Swift standard library APIs are allowed.
- Low-level application infrastructure can be used only when it is intentionally shared and does not force UI or persistence concerns into this layer.
- Logging may use the shared `vxAtelierPro.log` facility until a neutral logging abstraction exists.
- JSON primitives such as `JSONValue` may be used as provider-neutral transport/domain values.

## Parameter Model
- `ai/*` owns semantic LLM parameter concepts: semantic parameter IDs, primitive value types, provider/model endpoint families, mapping descriptors, default mappings, validation, and request encoding.
- A semantic parameter name is the stable internal meaning, for example `maxOutputTokens`.
- A wire key is the provider/model endpoint field name, for example `max_tokens`, `max_completion_tokens`, or `max_output_tokens`.
- Provider/model-specific name differences belong in mapping descriptors, not in UI code or conversation persistence code.
- Runtime-editable mapping overrides should be represented in `ai/*` as pure descriptors only. SwiftData materialization and persistence of those descriptors belongs to the app layer.

## UI And Persistence
- UI control hints such as text fields, sliders, steppers, toggles, and pickers are app-layer presentation concerns.
- SwiftData models such as `ModelItem`, `ModelParameterMappingItem`, `ConversationOptions`, and `AiRequestArgument` may adapt to and from `ai/*` value types, but `ai/*` should not depend on those models.
- Conversation-local argument copies belong to the app layer. The AI layer should consume resolved generation options or primitive parameter values, not mutate conversation storage.
- If a new feature needs both AI-domain data and UI metadata, keep the AI-domain type in `ai/*` and add a separate app-side presentation adapter.

## Direction Of Flow
- App layer resolves persisted configuration and user overrides.
- App layer converts SwiftData models into provider-neutral `ai/*` descriptors and request options.
- `ai/*` validates capabilities, resolves mappings, encodes provider requests, executes adapters, and emits provider-neutral events.
- App layer persists stable results and renders UI.

## Refactoring Rule
- When moving code toward a reusable AI library, move primitive domain concepts down into `ai/*` only if they are independent of SwiftUI and SwiftData.
- Move UI hints, editor behavior, persistence materialization, and app-specific display copy upward or keep them in the app layer.
- If a dependency direction is unclear, prefer a pure descriptor in `ai/*` plus an app-side adapter over importing an app model into `ai/*`.
