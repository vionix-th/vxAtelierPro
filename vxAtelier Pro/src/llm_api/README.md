# LLM API

`llm_api` contains the provider-neutral generation domain, provider integrations, model catalogs, route validation, generation adapters, HTTP transport, and model-profile resolution. SwiftData-aware orchestration and concrete application tools live in `llm_runtime`.

## Ownership Boundaries

The subsystem separates four responsibilities:

- `LLMProviderIntegration` owns a known service: supported routes, authentication policy, effective transport configuration, model-family validation, and catalog selection.
- `LLMGenerationAdapter` owns exactly one request, response, and streaming wire contract. It performs generation only.
- `APIConfigurationItem` represents one provider connection through one persisted adapter. Exposing another protocol requires another configuration.
- `LLMModelProfile` owns model capabilities, parameter support and policy, defaults, limits, and user overrides. A model derives its adapter from its API configuration.

`LLMProviderRegistry` resolves provider integrations and validates provider routes. `LLMAdapterRegistry` resolves pure generation adapters solely by `LLMAdapterID`. `LLMModelCatalog` performs model discovery independently of adapter construction.

`Custom` is a provider configuration for services unknown to the application. It may select any remote adapter and use no authentication, a bearer token, an `x-api-key`, or entered custom headers. A known provider that diverges from another provider's protocol receives its own adapter; OpenRouter is the current example.

## Route Matrix

| Provider | Default adapter | Other adapters |
|---|---|---|
| OpenAI Platform | OpenAI Responses | OpenAI Chat Completions |
| Codex ChatGPT Subscription | OpenAI Responses | None |
| OpenCode Zen | OpenAI Chat Completions (Legacy) | OpenAI Responses, Anthropic Messages |
| Apple Intelligence | Foundation Models | None |
| Anthropic | Anthropic Messages | None |
| OpenRouter | OpenRouter Chat Completions | None |
| LM Studio | OpenAI Chat Completions (Legacy) | None |
| Ollama | OpenAI Chat Completions (Legacy) | None |
| xAI | OpenAI Chat Completions (Legacy) | None |
| DeepSeek | OpenAI Chat Completions (Legacy) | None |
| Custom | OpenAI Chat Completions (Legacy) | Every remote adapter |

`OpenAI Chat Completions (Legacy)` names the shared `max_tokens` dialect explicitly. Modern OpenAI Chat Completions uses `max_completion_tokens`. OpenRouter composes the shared Chat codec while retaining its dedicated route identity, `top_k`, and nested reasoning representation.

## Runtime Flow

1. Parse persisted provider and adapter raw strings. Unknown identifiers fail with `invalidConfiguration`; there is no routing fallback.
2. Resolve and refresh credentials, including Codex OAuth credentials.
3. Ask the provider integration to validate the selected route and produce `LLMResolvedProviderRoute`.
4. Resolve the selected model profile against the route adapter.
5. Resolve active generation parameters and build `LLMGenerationRequest`.
6. Pass the request and resolved route to `ProviderRunExecutor`.
7. Verify request, route, and transport provider/adapter identity, then resolve the pure generation adapter through `LLMAdapterRegistry`.

Model discovery follows a separate path through provider integrations and `LLMModelCatalog`. Remote listing failures are non-fatal in settings; a configuration can still be saved and models can be entered manually.

## Model Profiles and Parameters

`LLMModelProfileResolver` is the sole model-profile resolution path. Definitions are inherited in this order:

1. Adapter API baseline.
2. Provider rules.
3. Model-family and model rules.
4. Explicit provider observations.
5. Explicit user overrides.

Adapter rules own every built-in wire mapping. Provider and model rules may change capabilities, support, required/default-enabled policy, values, options, and limits, but `LLMDefaultsCatalog` rejects wire mappings below adapter level.

Advanced per-model wire mappings remain available as unsafe user overrides. They bypass guaranteed adapter compatibility and are persisted per adapter.

A parameter becomes active only through required policy, explicit conversation selection, or default-enabled policy. Retaining a value alone does not activate it. A supported parameter must resolve a mapping; stale enabled unsupported parameters fail request assembly with `invalidConfiguration`.

## Model Catalogs

Catalog implementations cover OpenAI-shaped `/models`, Anthropic `/models`, OpenRouter metadata, OpenCode Zen model-family filtering, the Codex static inventory, and the Apple local inventory. Custom configurations select a catalog from their adapter:

- Responses, modern Chat, and legacy Chat use OpenAI-shaped discovery.
- OpenRouter Chat uses OpenRouter metadata.
- Anthropic Messages uses Anthropic discovery.

Concrete local infrastructure may implement both generation and catalog operations, but the operations are exposed through separate interfaces.

## Persistence and Export

SwiftData stores provider, adapter, and authentication identifiers as raw strings. `parsedProviderID`, `parsedAdapterID`, and `parsedAuthKind` expose optional values; runtime and save boundaries use the throwing `require...` accessors.

The schema is changed in place with no migration. Development stores made with the old schema must be removed with the startup recovery **Wipe Store** action.

Full backups use format version 5. Version 4 is rejected. API configurations and response runs encode typed provider/adapter identifiers, and exported models include the API configuration adapter identity used for reconnection.

## Validation

Local validation is limited to application-owned boundaries:

- Provider integrations validate provider/adapter/authentication composition and provider-specific model families.
- The executor rejects request/route/transport identity mismatches.
- `ConversationHistoryValidator` rejects duplicate, missing, dangling, or out-of-order tool-call identifiers.
- Generation adapters reject missing required content, reserved-key collisions, malformed values, and unsupported wire representations.
- Local backends enforce framework availability and platform constraints.

Remote providers remain authoritative for request acceptance. Provider HTTP errors retain normalized metadata, redaction, and retry classification.

## Tests

Offline adapter and runtime fixtures live in `vxAtelier ProTests/AI/Fixtures`. Live provider smoke tests are skipped by default and use `LiveLLMProviders.local.json` when explicitly enabled.
