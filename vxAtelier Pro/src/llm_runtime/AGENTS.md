# AGENTS.md (llm_runtime)

## Boundary
- Treat `llm_runtime/*` as vxAtelier's integration layer for LLM runs and concrete LLM tools.
- `Conversation*`, `ProviderRunExecutor`, `ToolBatchExecutor`, and `LLMRequestFactory` may orchestrate SwiftData models, draft state, provider execution, tool loops, save boundaries, rollback, and run status transitions.
- `LLMToolExecution` and `*Tool` files may implement app-specific executable tools that use app models, settings, search services, shortcuts, and runtime context.
- Keep reusable provider protocol values, provider profiles, adapters, transport, and reusable tool framework code in `llm_api/*`.

## Allowed Dependencies
- `llm_runtime/*` may depend on SwiftData, `ConversationItem`, `ConversationTurn`, `ConversationOptions`, `APIConfigurationItem`, `MessageItem`, `ToolCallItem`, `ResponseRunItem`, `ConversationDraftStore`, app services, and `llm_api/*`.
- `llm_runtime/*` should depend on narrow collaborators such as tool catalogs, provider executors, request factories, and run stores rather than resolving global state directly.

## Direction Of Flow
- Runtime code resolves persisted configuration and user overrides.
- Runtime code converts SwiftData models into provider-neutral `LLM*` descriptors before calling `llm_api/*`.
- Runtime code persists stable provider/tool results and updates transient draft state.
- Runtime code should not add provider-specific wire-shape logic; that belongs in `llm_api/*`.
