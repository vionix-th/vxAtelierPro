# AGENTS.md (llm_api)

## Boundary
- Treat `llm_api/*` as the reusable LLM provider and tool API surface.
- `LLMGenerationRequest`, `LLMContentTypes`, `LLMResponseTypes`, and related files own provider-neutral LLM request, response, event, model, generation, parameter, capability, and tool-call value types.
- `LLMProvider*` files own provider identities, profiles, configuration value types, adapter selection, and model metadata decoding.
- `OpenAI*`, `Anthropic*`, and `LLMHTTPGenerationPipeline` own provider wire-protocol mapping into provider-neutral `LLMGenerationEvent` values.
- `LLMHTTPClient` and `LLMSecretRedactor` own reusable provider HTTP/SSE transport helpers, diagnostics redaction, and provider error normalization.
- `LLMTool*` and `ConfigurableLLMTool` own reusable tool schema, configuration, catalog, and registry contracts.
- Keep SwiftUI, SwiftData, view models, views, settings screens, persisted app models, concrete vxAtelier tools, and run orchestration out of `llm_api/*`.

## Allowed Dependencies
- `llm_api/*` may use `Foundation`, platform-neutral Swift standard library APIs, shared JSON primitives such as `JSONValue`, and intentionally shared low-level infrastructure such as `NetworkClient`.
- `llm_api/*` may use the shared `vxAtelierPro.log` facility until a neutral logging abstraction exists.
- `llm_api/*` must not depend on `ConversationItem`, `ConversationTurn`, `ConversationOptions`, `APIConfigurationItem`, `ModelItem`, `MessageItem`, `ToolCallItem`, `ResponseRunItem`, `ConversationDraftStore`, SwiftData, SwiftUI, or concrete app services.

## Direction Of Flow
- Runtime code resolves persisted provider observations and explicit overrides into `llm_api/*` value types.
- `LLMModelContractResolver` is the only model-contract resolution path. Capability and parameter support are advisory for remote providers.
- `llm_api/*` resolves mappings, enforces adapter encodability, executes provider adapters, and emits provider-neutral events.
- `llm_api/*` must not persist results, mutate conversation storage, update UI draft state, or execute concrete vxAtelier tools.

## Parameter Boundary
- A semantic parameter is the app-level identity and value, for example `temperature` or `reasoning_effort`.
- Parameter support is advisory model metadata; required/default policy controls initial inclusion behavior.
- Parameter mapping is selected-model semantic-to-wire translation: wire key or structured preset.
- Conversation storage may contain semantic values and per-conversation enable/disable intent for optional parameters only.
- Conversation storage must not own resolved support, model policy defaults, or wire names.
- Keep contract and inclusion resolution in `LLMModelContractResolver` and `LLMGenerationOptionsResolver`; keep semantic-to-wire translation and hard encodability checks in `LLMParameterMapping` and provider encoders.

## Validation Boundary
- Remote providers decide whether supported, unsupported, or unknown model features are accepted.
- Do not add capability-based request rejection for remote providers.
- Local rejection is limited to invalid provider/adapter composition, corrupt conversation history, and payloads the selected adapter or local backend cannot represent.

## Refactoring Rule
- If a type is reusable across apps and does not require SwiftData, SwiftUI, persisted app models, or concrete app services, it belongs in `llm_api/*`.
- If a type coordinates app persistence, concrete tool execution, draft state, or conversation run lifecycle, it belongs in `llm_runtime/*`.
