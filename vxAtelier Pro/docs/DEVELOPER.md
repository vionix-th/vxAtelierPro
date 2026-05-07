# vxAtelier Pro Codebase Documentation

> Last updated: 2026-01-21

This document provides an in-depth technical reference of the **vxAtelier Pro** source code.  Use it together with `README.md` for a complete understanding of architectural concepts and high-level features.

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Directory Structure](#directory-structure)
3. [Build Targets & Tooling](#build-targets--tooling)
4. [Data Flow & Persistence](#data-flow--persistence)
5. [Key Modules](#key-modules)
   1. [LLM API And Runtime](#llm-api-and-runtime)
   2. [Persistence (`persistence/`)](#persistence)
   3. [System Layer (`system/`)](#system-layer)
   4. [Text-to-Speech (`tts/`)](#text-to-speech)
   5. [Search (`search/`)](#search)
   6. [Utilities (`utilities/`)](#utilities)
   7. [Views (`views/`)](#views)
6. [Logging](#logging)
7. [Testing & CI](#testing--ci)
8. [Coding Standards](#coding-standards)
9. [Extending the App](#extending-the-app)
10. [Troubleshooting](#troubleshooting)

---

### Application Entry Point
Location: `src/`

#### Main App (`vxAtelierPro.swift`)

This file defines the `vxAtelierPro` struct, which conforms to the `App` protocol and serves as the main entry point for the application.

*   **Bootstrapping**: It is responsible for bootstrapping the entire application, including initializing the data layer, injecting dependencies, and setting up the main view hierarchy.
*   **SwiftData Initialization**: It defines the complete data `Schema` for all `PersistentModel` types and creates the shared `ModelContainer`.
*   **Dependency Injection**: It initializes `QueryManager`, `TTSQueue`, and `ConversationViewModelStore`, then injects them (and the `ModelContainer`) into the SwiftUI environment.
*   **Root View and Scene Management**: It sets up `AppShellView` as the root view, hosts `ContentView` within it, and defines the main `WindowGroup` plus macOS `Settings` and menu bar scenes.
*   **macOS Hotkeys**: On macOS, it initializes `GlobalHotkeyController` (built on `HotkeyManager`) to register the utility panel hotkey after launch.

---

## Project Overview
* **Name:** vxAtelier Pro
* **Package Manifest:** [`Package.swift`](../Package.swift)
* **Platforms:** macOS 14+, iOS 17+
* **Language Version:** Swift 5.9+
* **Frameworks:** SwiftUI, SwiftData, Foundation, OSLog, AVFoundation (TTS)
* **Build System:** Xcode Schemes; Swift Package Manager (SPM) manifest for dependency and editor integration

The application is entirely Swift-based and uses **SwiftData** for persistence and **SwiftUI** for UI. **SPM** is used for dependency management and editor integration; **Xcode** schemes/projects are authoritative for building app bundles and running tests.

---

## Directory Structure
```text
src/
├─ llm_api/         # Reusable LLM protocol, providers, adapters, transport, tool framework
├─ llm_runtime/     # SwiftData-aware LLM run orchestration and concrete tools
├─ persistence/     # SwiftData schema and persistence-adjacent support types
├─ search/          # Web search provider integration
├─ system/          # App services, defaults, settings, logging, permissions
│  └─ export/       # Codable models and utilities for data backup
├─ tts/             # Text-to-speech pipeline & voice config
├─ utilities/       # General helpers & extensions
├─ views/           # SwiftUI screens, dialogs, controls
│  ├─ AppShellView.swift # Root shell: global sheets, status bar, export/import
│  ├─ ContentView.swift  # Main NavigationSplitView + toolbar actions
│  ├─ StatusBar.swift    # Log/status strip + dialog info header
│  ├─ components/   # Reusable, generic view components (e.g., Markdown renderer)
│  ├─ content/      # Sidebar data source, routing, selection models
│  ├─ dialog/       # Views related to a single conversation/dialog
│  ├─ project/      # Views related to a project
│  ├─ settings/     # All views for the application settings window
│  │  └─ components/# Reusable components specific to settings views
│  └─ utility/      # Utility views (e.g., log history sheet)
└─ vxAtelierPro.swift# Root entry & shared singletons
```

`Package.swift` explicitly lists only the files required for the main target, but *all* sources under `src/` are compiled by SPM.

---

## Build Targets & Tooling
| Target | Type | Path | Purpose |
|--------|------|------|---------|
| `vxAtelier Pro` | swift-target | `src/` | Main application library compiled into the host app bundle. |

### Building
```bash
xcodebuild -scheme "vxAtelier Pro"             # Full IDE build
swift build                                   # Editor/indexing compile check only
```

### Linting & Formatting
Xcode compile-time diagnostics are authoritative. SPM compile-time diagnostics may be used only for editor/indexing feedback. Add SwiftLint or swift-format as desired.

---

## Data Flow & Persistence
1. **SwiftUI View ➜ ViewModel / Environment**  – user interactions trigger intents.
2. **Intent ➜ Provider / System Layer**        – asynchronous operations (AI, network, TTS, DB).
3. **SwiftData Context**                       – persists `@Model` structs.
4. **Combine/Observation ➜ UI Updates**        – UI layers automatically reflect model changes.

---

## Key Modules
### LLM API And Runtime
Locations: `src/llm_api/`, `src/llm_runtime/`

The LLM subsystem is split by reuse boundary. `llm_api` contains the reusable provider and tool API surface. `llm_runtime` contains vxAtelier-specific run orchestration, SwiftData persistence, draft state, and concrete tools. Runtime code builds an `LLMRequest`, materializes `APIConfigurationItem` into pure `LLMProviderConfiguration`, lets provider transport resolve authentication headers, sends the request through a provider adapter, streams or collects `LLMStreamEvent` values through a draft sink, then persists stable `MessageItem`, `ToolCallItem`, and `ResponseRunItem` records.

*   **LLM Protocol Files (`llm_api/LLM*`)**: Define `LLMRequest`, `LLMMessage`, `LLMContentPart`, `LLMToolDefinition`, `LLMToolCall`, `LLMGenerationOptions`, `LLMStreamEvent`, `LLMUsage`, `LLMProviderError`, validation, request encoding, and parameter mapping.
*   **Provider Files (`llm_api/LLMProvider*`, `llm_api/LLMModelMetadataDecoder.swift`)**: Own `LLMProviderID`, `LLMProviderConfiguration`, profiles for supported providers, adapter selection, and model metadata decoding.
*   **Transport Files (`llm_api/LLMHTTPClient.swift`, `llm_api/LLMSecretRedactor.swift`)**: `NetworkClient` owns shared JSON/SSE transport; `LLMHTTPClient` is the LLM-facing facade for provider-specific header resolution, redacted diagnostics, HTTP status mapping, and normalized provider errors.
*   **Adapter Files (`llm_api/OpenAI*`, `llm_api/Anthropic*`, `llm_api/LLMAdapterRunLoop.swift`)**: Map provider-specific request/stream formats into domain events. `LLMAdapterRunLoop` owns the shared streamed/non-streamed HTTP flow.
*   **Tool Framework Files (`llm_api/LLMTool*`, `llm_api/ConfigurableLLMTool.swift`)**: Reusable tool schemas, configuration protocol, catalog interface, and registry.
*   **Runtime Files (`llm_runtime/Conversation*`, `llm_runtime/ProviderRunExecutor.swift`, `llm_runtime/ToolBatchExecutor.swift`, `llm_runtime/LLMRequestFactory.swift`)**: Split request assembly, draft/event collection, sequential tool execution, SwiftData save boundaries, and turn orchestration.
*   **Concrete Tool Files (`llm_runtime/*Tool.swift`, `llm_runtime/ConversationTools.swift`, `llm_runtime/ShortcutTools.swift`)**: vxAtelier-specific tools for conversations, settings, shortcuts, web search, and website reading.
*   **Provider & Capability Utilities (`llm_api/LLMModelProviderUtils.swift`)**: Provides provider/model-name capability inference for persisted `ModelItem` records and UI filtering.

### Search (`search/`)

The `search/` module provides web search capabilities to the application, primarily for use by AI tools. It follows a protocol-oriented architecture so different search providers can be used interchangeably.

*   **Core Protocol (`WebSearchService.swift`)**: This file defines the foundational components for the search feature.
    *   `WebSearchService`: The core protocol that all search providers must implement. It establishes the contract for performing a search via its `search(query:numResults:)` method.
    *   `WebSearchResult`: A standardized `struct` for holding search result data (title, link, snippet), ensuring a consistent data format across the application.
    *   `WebSearchConfiguration`: A protocol for provider-specific configurations.
    *   `WebSearchError`: A comprehensive `enum` for handling all search-related errors.
*   **Concrete Implementation (`GoogleCustomSearchService.swift`)**: A concrete class that implements the `WebSearchService` protocol for the Google Custom Search API. It serves as a clear example of the architecture:
    *   It defines a provider-specific `GoogleCustomSearchConfiguration` to hold the required API key and search engine ID.
    *   It uses its own internal `Codable` types to decode the unique JSON structure of the Google API response.
    *   It leverages `NetworkClient` to handle the underlying network request.
    *   It correctly maps the provider-specific data into the application's standard `WebSearchResult` format, decoupling the rest of the app from the API's details.
*   **Provider Factory (`WebSearchProvider.swift`)**: `WebSearchProvider` lists supported search providers and contains the factory logic that instantiates the appropriate concrete service from a `WebSearchConfigurationItem`.

### System (`system/`)

The `system/` module contains core application services, data management logic, and critical utilities like import/export functionality.

#### Data Management (`DataManager.swift`)

`DataManager.swift` is the central singleton orchestrating all high-level data operations, including backup, restore, import, and export. It serves as the bridge between UI actions, the data mapping layer, and the SwiftData context.

*   **Backup & Restore**: It manages the entire lifecycle. For backups, it fetches live data, uses the `...ExportData` mappers to create a `FullBackup` object, and serializes it. For restores, it performs a destructive operation: it deletes all existing data, decodes the backup file, and uses the `toDataItem(context:)` methods to repopulate the database via the `QueryManager`.
*   **Data Normalization**: After an import or restore, it runs a critical `normalizeModelContext` function to de-duplicate configuration items (e.g., `APIConfigurationItem`), update all references to a single canonical instance, and ensure data integrity.
*   **Error Handling**: It defines a comprehensive `DataManagerError` enum to provide specific, user-friendly error messages for failures during any data operation.

#### Query Manager (`QueryManager.swift`)

`QueryManager` is now a **command-only** façade over SwiftData. Reads are performed directly in views with `@Query`; `QueryManager` provides:

*   **Targeted lookups**: Lightweight `conversation(with:)` and `project(with:)` helpers for status bar and menu actions.
*   **Commands**: Centralized create/delete/archive/restore/assign/cleanup/bookmark/model-sync routines with consistent save + logging semantics.
*   **Invariants**: Utilities like `ensureSystemConversation()` to guarantee required system records exist.

There is no cached read model; invalidation and refresh are handled by SwiftData/`@Query`.

#### Settings Facade (`AppSettings.swift`, `AppDefaults.swift`)

* **Keys**: `AppSettings.Keys` centralizes all `UserDefaults` keys; use these with `@AppStorage` and direct `UserDefaults` calls.
* **Defaults**: `AppDefaults` retains default values and the `resetUserDefaults()` helper; it now writes using `AppSettings.Keys`.
* **Usage**: Avoid string literals for settings; prefer `@AppStorage(AppSettings.Keys.someKey)` to keep tooling and refactors reliable.

#### Streaming State Management

These components manage draft state for in-flight provider responses.

*   **Conversation Draft Store (`ConversationDraftStore.swift`)**: An `@Observable` store keyed by conversation ID. It holds accumulating text, active/run status, tool calls, and error text for the current draft.
*   **Conversation Completion Use Case (`ConversationCompletionUseCase.swift`)**: Coordinates conversation completion phases while `ConversationRunStore` owns SwiftData mutations and `ProviderRunExecutor` consumes provider events.

### Utilities

This module contains a collection of shared helpers, extensions, and services that provide common functionality across the application.

#### Error Handling (`ErrorHandling.swift`)

This file establishes a robust and centralized error handling framework.

*   **`AppError`**: A comprehensive `LocalizedError` enum that defines all application-specific errors (e.g., `dataSaveFailed`, `networkError`). Each case provides a user-friendly `errorDescription` and `recoverySuggestion`.
*   **`ErrorAlert`**: An `Identifiable` struct that wraps a standard `Error` and prepares it for presentation in a SwiftUI `alert`. It standardizes the content of error dialogs.
*   **`View.errorAlert`**: A convenient SwiftUI `View` extension that simplifies the presentation of an `ErrorAlert` from any view.
*   **JSON Coder Extensions**: Safe wrappers for `JSONEncoder` and `JSONDecoder` that catch, log, and re-throw low-level coding errors as standardized `AppError` types.

#### File Helper (`FileHelper.swift`)

This `@MainActor` singleton class provides a platform-agnostic facade for all user-facing file operations, abstracting the native file picker APIs for both macOS and iOS.

*   **Platform Abstraction**: It uses conditional compilation (`#if os(macOS)` / `#if os(iOS)`) to provide a unified `async/await` interface for saving and loading files.
    *   **macOS**: Uses the standard `NSSavePanel` and `NSOpenPanel` for a native AppKit experience.
    *   **iOS**: Uses `UIDocumentPickerViewController` and correctly bridges its delegate-based callback system with modern Swift Concurrency via `CheckedContinuation`.
*   **Security Scope**: It correctly handles security-scoped resource access, which is essential for reading files (like images for avatars) that the user has explicitly granted permission to.
*   **Specialized Functions**: Beyond generic `save` and `load` methods, it provides specific helpers for application tasks like `saveModels()` and `loadModels()`.

#### Hotkey Manager (`HotkeyManager.swift`)

This is a macOS-specific class that provides a simple interface for registering and managing global and local keyboard shortcuts.

*   **Event Monitoring**: It uses a combination of `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents` to capture `keyDown` events system-wide.
*   **Action Dispatch**: It allows associating a specific key-and-modifier combination with a handler closure. The closure can consume the event or allow it to propagate.
*   **Lifecycle**: It correctly removes its event monitors in `deinit` to prevent resource leaks.

#### Logging Service (`LoggingService.swift`)

This singleton provides a sophisticated, application-wide logging solution built on top of Apple's unified `os.Logger`.

*   **Centralized Wrapper**: It acts as a single point of entry for all logging, providing convenience methods (`.debug`, `.info`, `.error`) that mirror the standard `Logger` API.
*   **In-App History**: As an `ObservableObject`, it maintains a `@Published` history of structured `LogEntry` objects. This powers a real-time, in-app log viewer, allowing developers to inspect recent events directly within the application.
*   **Source-Based Filtering**: It includes an advanced mechanism to enable or disable logging from specific sources (file/function pairs), with the configuration persisted to `UserDefaults`. This allows for fine-grained debugging.

#### Parameter Expansion (`ParameterExpansion.swift`)

This file provides a global `expandVariables` function for performing simple, case-insensitive variable substitution in strings. It is likely used for processing prompt templates.

*   **Static & Dynamic Values**: It supports replacing placeholders with both static strings and dynamic values generated by closures at runtime (e.g., `$isodate`).
*   **Contextual Expansion**: It can accept a `ConversationItem` to provide context-specific data, such as the `$dialogid`.

#### Shortcuts Manager (`ShortcutsManager.swift`)

This macOS-specific singleton provides a bridge to the system's Shortcuts app, allowing the application to discover and execute user-defined automation workflows.

*   **CLI Wrapper**: Its architecture is based on wrapping the `/usr/bin/shortcuts` command-line tool to execute sub-processes.
*   **Discovery**: It provides an `async` method to list all available shortcuts by parsing the output of `shortcuts list`.
*   **Execution**: It provides an `async` method to run a shortcut by name. It robustly handles passing string input to the shortcut by writing it to a temporary file and using the `--input-path` argument.

#### Type Conversion Utilities (`TypeConversionUtils.swift`)

This file provides a collection of static functions for robust, safe type casting, which is essential when dealing with loosely-typed data from sources like JSON APIs.

*   **Intelligent Casting**: The functions can convert `Any` to various primitive types (`String`, `Int`, `Double`, `Bool`) and collections, handling multiple source formats. For example, `toBool` correctly interprets `true`, non-zero numbers, and strings like "true" or "yes".
*   **Crash Safety**: Every function accepts a `defaultValue` that is returned if the conversion is not possible, preventing runtime crashes from invalid casts.

#### URL Extensions (`URLExtensions.swift`)

This file extends the standard `URLComponents` struct with a convenience method for building URL paths safely.

*   **`appendingPath(_:)`**: This method correctly handles the logic of adding or omitting leading slashes to ensure that appending a new path component results in a well-formed URL.

#### Dynamic JSON Handling (`JSONValue.swift`, `JSONUtils.swift`)

These utilities provide a robust foundation for working with dynamic or loosely-structured JSON, which is common when interacting with external APIs or defining AI tool schemas.

*   **`JSONValue.swift`**: Defines a powerful `JSONValue` enum that can represent any valid JSON type (`string`, `number`, `object`, `array`, etc.) in a type-safe manner.
    *   **`Codable`**: It has full `Codable` conformance, allowing it to be seamlessly integrated into other data models.
    *   **`ExpressibleBy...Literal`**: It conforms to all literal protocols (`ExpressibleByStringLiteral`, `ExpressibleByDictionaryLiteral`, etc.), enabling the intuitive, declarative creation of complex JSON objects directly in Swift code.
    *   **Accessors**: It provides safe computed properties (`.stringValue`, `.integerValue`) for casting the underlying data to a desired type.
    *   **`JSONUtils.swift`**: A collection of static, general-purpose helper functions for common JSON tasks like converting between strings and dictionaries, validating JSON, and pretty-printing.

#### Permission Manager (`PermissionManager.swift`)

This `@MainActor ObservableObject` provides a centralized, reactive, and platform-agnostic interface for managing all system-level permissions.

*   **Architecture**: It encapsulates all logic for checking and requesting access to protected resources like the Photo Library, Microphone, and Speech Recognition.
    *   `PermissionType`: An `enum` that defines all possible permissions, each with a user-friendly description and system icon.
    *   `PermissionStatus`: An `enum` representing the authorization status (e.g., `authorized`, `denied`).
*   **Reactive UI**: It `@Published` the status of each permission, allowing SwiftUI views to reactively update their UI based on the current authorization state (e.g., enabling or disabling a feature).
*   **Platform Abstraction**: It uses conditional compilation (`#if os(iOS)` vs. `#if os(macOS)`) to abstract away platform-specific API differences, providing a unified interface to the application.
*   **User Experience**: It includes a helper function to deep-link the user directly to the correct pane in the System Settings app, making it easy for users to grant or review permissions.

#### Application Defaults (`AppDefaults.swift`)

This file defines the `AppDefaults` struct, which serves as a centralized, static repository for all default application settings and constants. It eliminates magic numbers and provides a single source of truth for initial configuration values.

*   **Scope**: It contains a wide range of defaults, including:
    *   **UI Constants**: Font sizes, padding, corner radii, and colors.
    *   **Feature Settings**: Default states for TTS, Markdown rendering, and UI toggles.
    *   **API Provider Defaults**: Pre-configured parameters (e.g., model name, temperature, endpoints) for providers like OpenAI, Anthropic, and DeepSeek.
*   **Settings Reset**: It includes a `resetUserDefaults()` function that restores all settings stored in `UserDefaults` to their original default values, providing a convenient way to reset the application's configuration.

#### JSON Serializer (`JsonSerializer.swift`)

This `class` provides a suite of static methods for serializing and deserializing individual data models to and from JSON. It complements the full backup system by enabling single-item import and export.

*   **Architecture**: It uses the same `...ExportData` mapping layer as the full backup system. For each model, it provides a pair of methods:
    *   `export...(Model)`: Takes a live SwiftData object, wraps it in its `...ExportData` counterpart, and encodes it to JSON `Data`.
    *   `import...(from: data)`: Decodes JSON `Data` into the appropriate `...ExportData` object and then calls its `toDataItem(context:)` method to create a new, fully-formed SwiftData object.

#### Export & Backup (`system/export/`)

This submodule manages the export and backup of all user data. It is designed to be robust, version-aware, and integrated with the native SwiftUI file system interface.

*   **Backup Schema (`FullBackup.swift`)**: This file defines the data structures for a complete application backup.
    *   `FullBackup`: A `Codable` struct that defines the schema for the backup file. It contains versioning information and aggregates arrays of serializable `...ExportData` objects for every model in the application (e.g., projects, conversations, settings).
    *   `BackupDocument`: A `FileDocument` wrapper around the backup data. This struct integrates directly with SwiftUI's `.fileImporter` and `.fileExporter` views, handling the reading and writing of the backup JSON file.
*   **Export Utilities (`ExportUtils.swift`)**: An `enum` that serves as a namespace for static helper functions used throughout the export process. It provides robust, reusable utilities for JSON encoding/decoding with standardized date formatting and platform-agnostic clipboard operations.
*   **Data Mapping (`...ExportData.swift`)**: Each SwiftData model has a corresponding `...ExportData.swift` file that defines a `Codable` struct for serialization. These files implement a critical bidirectional mapping pattern:
    *   **Export**: An `init(Model)` initializer takes a live SwiftData object and recursively maps its data into a serializable format.
    *   **Import/Restore**: A `toDataItem(context:)` method takes the deserialized data and converts it back into a new, fully-formed SwiftData object, ready for insertion into the database.

### Persistence
Location: `src/persistence/`

The application's data layer is composed of SwiftData `@Model` classes for persistence and various supporting `structs` and `enums` for state management, configuration, and data handling.

#### Core Data Models (SwiftData)
These are the primary entities persisted in the SwiftData store.

*   **`ProjectItem`**: The top-level container for organizing conversations. A project can contain multiple `ConversationItem`s.
*   **`ConversationItem`**: Represents a single, continuous conversation thread. It manages the conversation's title, status, and options. Its core is an ordered list of `ConversationTurn` objects.
*   **`ConversationTurn`**: Models a single exchange within a conversation. It contains the initial `userMessage`, a subsequent list of `TurnEvent`s (which capture the AI's multi-step responses), and `ResponseRunItem` records for provider diagnostics (status, usage, request IDs).
*   **`TurnEvent`**: Represents a single event within a `ConversationTurn`, such as an assistant's reply, a tool call, or a tool result. This granular structure allows for modeling complex, multi-step tool interactions.
*   **`MessageItem`**: The fundamental unit of content, representing a single message from a user, assistant, or tool. It stores ordered `MessageContentPartItem` records, role, timestamp, tool result ID, and durable tool-call records.
*   **`MessageContentPartItem`**: An ordered content part for text, media references, reasoning, or tool-result content.
*   **`ToolCallItem`**: A persisted tool call with call ID, provider call ID, provider index, name, argument JSON, status, and assistant/result links.
*   **`ResponseRunItem`**: A persisted provider run with provider/endpoint/model/request IDs, status, usage, error, and turn link.

#### Configuration Models (SwiftData)
These models store user-configurable settings.

*   **`APIConfigurationItem`**: Stores the credentials (API key, base URL) and default parameters for a specific AI service provider.
*   **`WebSearchConfigurationItem`**: Stores the configuration for a web search provider, such as an API key and custom search engine ID.
*   **`VoiceConfigurationItem`**: Stores the configuration for a specific TTS voice, linking a voice identifier to a language and role.
*   **`PromptTemplateItem`**: A user-created, reusable prompt template.
*   **`AiRequestArgument`**: A flexible model representing a single parameter for an AI request (e.g., `temperature`). It stores the parameter's name, type, constraints, and value, allowing for dynamic generation of settings UI.

#### Supporting Enums & Structs
These non-persisted types are critical for application logic.

*   **`ItemStatus`**: An enum (`active`, `archived`, `trashed`) that defines the lifecycle state for `ProjectItem` and `ConversationItem`.
### Persistence Module

This module contains the core SwiftData models and supporting data structures that define the application's persistence layer and state.

#### AI Request Parameter (`AiRequestArgument.swift`)

This is a flexible SwiftData `@Model` that represents a single, configurable parameter for an AI service request (e.g., `temperature`, `top_p`). It is a cornerstone of the dynamic AI configuration system.

*   **Dynamic UI Generation**: It stores rich metadata, including the parameter's name, description, data type (`string`, `integer`), validation rules (min/max values), and a hint for the appropriate UI control (`slider`, `toggle`). This allows the application to dynamically generate a settings screen for any AI provider.
*   **Type-Erased Storage**: The parameter's value is serialized to `Data` using `JSONEncoder`, allowing various types to be stored in a single database field. A computed `value` property with validation logic provides convenient, type-safe access.
*   **Observable**: It conforms to `ObservableObject`, allowing it to be bound directly to SwiftUI views for seamless user interaction.

#### API Configuration (`APIConfigurationItem.swift`)

This SwiftData `@Model` stores all the necessary information to connect to a specific AI provider's API.

*   **Connection Details**: It holds the provider's `name`, provider ID, auth kind, API key, base URL, default endpoint family, default model, headers JSON, and options JSON. Endpoint paths are profile-owned except for provider profiles that intentionally expose custom OpenAI-compatible base URLs.
*   **Default Management**: It includes an `isDefault` flag to identify the primary configuration for the application and an optional `defaultModel` to override profile defaults for this configuration.

#### Bookmark (`BookmarkItem.swift`)

This SwiftData `@Model` allows users to save a reference to a specific point in a conversation for quick access.

*   **Granular Targeting**: It can point to either a user's initial `MessageItem` within a turn or, more specifically, to a single `TurnEvent` (like an assistant's reply or a tool result) within that turn.
*   **Core Relationships**: It maintains relationships to the parent `ConversationItem` and the specific `MessageItem` and optional `TurnEvent` being bookmarked.

#### Message Content Part (`MessageContentPartItem.swift`)

This SwiftData `@Model` is the ordered content-part record for a message.

*   **Architectural Role**: A `MessageItem` can hold multiple content parts in provider order. The UI and export paths use `MessageItem.displayText` for text aggregation and the ordered parts for durable content.
*   **Properties**: It stores provider order, content kind, optional text, MIME type, base64 payload, and source URL.

#### Message (`MessageItem.swift`)

This SwiftData `@Model` is the universal container for any piece of communication in a conversation.

*   **Core Properties**: It stores `role`, `timestamp`, ordered content parts, optional tool result call ID, and durable `ToolCallItem` records.
*   **Domain Mapping**: `asDomainMessage()` converts persisted message data into `LLMMessage` for provider requests.
*   **Display Text**: `displayText` is the canonical text aggregation path for rendering, copy, TTS, token estimates, and export.

#### Conversation (`ConversationItem.swift`)

This SwiftData `@Model` represents a single conversation thread and stores the persisted structure for AI interactions.

*   **Hierarchical Structure**: The dialogue is organized into an array of `ConversationTurn` objects. Each turn groups a user's message with all subsequent assistant responses and tool events, creating a structured, chronological record.
*   **Execution Boundary**: Conversation completion is initiated by `ConversationCompletionUseCase`; the model does not own provider orchestration.
*   **Relationships**: It holds critical relationships to its child `ConversationTurn` and `ConversationOptions` objects (cascade delete) and an optional parent `ProjectItem` (nullify).
*   **Features**: Includes a `fork(...)` method to create a deep copy of the conversation at any point.

#### Conversation Options (`ConversationOptions.swift`)

This SwiftData `@Model` is a comprehensive container for all settings that govern a single `ConversationItem`.

*   **Parameter Generation**: Its `setupAiRequestArguments(...)` method builds typed controls from the selected `LLMProviderProfile` and configuration defaults.
*   **Per-Conversation Tool Management**: It provides a complete system for managing tools on a per-conversation basis, storing which tools are enabled and their specific configurations as serialized JSON.
*   **Relationships**: It holds a relationship to the `APIConfigurationItem` to be used for the conversation and a cascade-delete relationship to its list of `AiRequestArgument` parameters.

#### AI Model (`ModelItem.swift`)

This SwiftData `@Model` represents a specific, selectable AI model from a provider.

*   **Automated Inference**: Its `init` method uses a centralized `LLMModelProviderUtils` helper to automatically infer the model's provider and capabilities from its name string, then materializes default parameter mappings from `LLMParameterMappingCatalog`.
*   **Descriptor Bridge**: `descriptor` is a computed property that bridges between persisted fields (`modelID`, `providerID`, `endpointFamiliesRaw`, `modalitiesRaw`, `supportedParameters`, `schemaFeaturesRaw`, `parameterMappings`, `rawMetadataJSON`) and the domain `LLMModelDescriptor` struct used by adapters, validators, and resolvers.
*   **API Configuration Scoping**: `apiConfiguration` links a model to a specific `APIConfigurationItem`, so two configurations with the same model name can carry different parameter mappings.

#### Project (`ProjectItem.swift`)

This SwiftData `@Model` serves as a container for organizing related conversations, acting as a folder or workspace.

*   **Default Settings**: It holds a `defaultOptions` object (`ConversationOptions`) that acts as a template, providing a baseline configuration (e.g., default system prompt, AI model) for all new conversations created within it.
*   **Relationships**: It maintains a cascade-delete relationship to its child `dialogs` and `defaultOptions`, ensuring all associated data is removed when the project is deleted.
*   **Transient Property**: It includes a `@Transient` computed property, `sortedConversations`, which provides a conveniently filtered and sorted list of its active conversations for direct use in the UI.

#### Prompt Template (`PromptTemplate.swift`)

This SwiftData `@Model` represents a reusable text template that can be applied as a user message or a system prompt.

*   **Categorization**: A nested `Category` enum (`User`, `System`) defines the template's intended context, ensuring it can be applied correctly.
*   **Properties**: It stores the template's `name`, `summary`, and the full `prompt` text.

#### Voice Configuration (`VoiceConfigurationItem.swift`)

This SwiftData `@Model` is central to the application's multi-lingual, multi-speaker text-to-speech system.

*   **Role-Based and Language-Specific**: Its core design maps a specific `voiceIdentifier` to a combination of a `role` (`user`, `assistant`, `system`) and a `language` code. This allows each participant in a conversation to have a distinct voice that can change dynamically based on the language of the text.
*   **Speech Customization**: It stores `speechRate` and `pitchMultiplier` to allow fine-grained control over the synthesized speech for each configured voice.
*   **Data Integrity**: It includes validation logic to ensure the `role` property is always a valid value.

#### Web Search Configuration (`WebSearchConfigurationItem.swift`)

This SwiftData `@Model` stores the configuration details for a web search provider, such as Google Custom Search.

*   **Provider Ownership**: It stores provider-specific details like `apiKey` and `searchEngineId`, exposes the stored provider through `providerEnum`, and materializes the matching `WebSearchService` with `makeWebSearchService()`.
*   **Default Configuration**: An `isDefault` flag allows the user to designate a primary search configuration that the application uses by default.
*   **Extensibility**: The flexible schema with optional fields allows the system to easily accommodate future search providers with different configuration requirements.

#### Conversation Turn (`ConversationTurn.swift`)

This SwiftData `@Model` is the structural unit that represents a single, complete exchange within a `ConversationItem`.

*   **Grouping**: Its key architectural role is to group a single user-initiated `MessageItem` with the corresponding array of `TurnEvent`s (e.g., assistant replies, tool calls) that resulted from it, plus durable `ResponseRunItem` records capturing provider-level diagnostics.
*   **Ordering**: It contains a `sequenceNumber` and `timestamp` to ensure the chronological integrity of the conversation.
*   **Relationships**: It holds cascade-delete relationships to its child `userMessage` and `events`, and a back-reference to its parent `ConversationItem`. `responseRuns` is cascaded.

#### Turn Event (`TurnEvent.swift`)

This SwiftData `@Model` represents a single event generated by the assistant within a `ConversationTurn`.

*   **Event Typing**: It uses an `EventType` enum (`assistant`, `toolCall`, `toolResult`) to classify the event, which is crucial for processing and rendering the conversation history correctly.
*   **Content Association**: It links the event type to a `MessageItem`, which holds the actual content (e.g., the assistant's text response, the tool call's JSON payload, or the tool's output).
*   **Hierarchy**: It maintains a cascade-delete relationship to its content (`MessageItem`) and a back-reference to its parent `ConversationTurn`.

### Supporting Enums and Structs

This section covers smaller, non-`@Model` data structures that support persisted entities and LLM request assembly.

#### Tool Call Assembler (`LLMToolCallAssembler.swift`)

The `LLMToolCallAssembler` struct lives in `llm_api/`. It provides the core logic for reconstructing streamed tool-call deltas into complete tool calls.

*   **Delta Merging**: `merge(...)` reassembles fragmented tool-call arguments by provider index and call ID.
*   **Stable Ordering**: `assembled` returns calls sorted by provider index for deterministic tool execution.

#### Item Status (`ItemStatus.swift`)

This `enum` defines the lifecycle state for data models like `ConversationItem` and `ProjectItem`.

*   **State Management**: It provides three distinct states (`active`, `archived`, `trashed`) to manage the visibility and availability of items in the UI and data queries.

#### Model Relationship Delete Rules

When designing relationships between SwiftData models, we follow these consistent principles:

1. **Parent-Child Delete Rules**:
   - **Parent objects** must use `.cascade` deleteRule for their collections of children.
   - **Child objects** should use `.nullify` for their parent references when reassignment is possible, otherwise they can omit the deleteRule.
   - These complementary deleteRules ensure proper cleanup when objects are deleted.

2. **Relationship Examples**:
   - `ProjectItem` → `ConversationItem`: Parent uses `.cascade` on `dialogs` collection
   - `ConversationItem` → `Project`: Child uses `.nullify` on `project` reference
   - `ConversationItem` → `ConversationTurn`: Parent uses `.cascade` on `turns` collection
   - `ConversationTurn` → `ConversationItem`: Child uses `.nullify` on `conversation` reference

3. **Known SwiftData Limitations**:
   - In-memory test containers may not properly handle nullify delete rules in bidirectional relationships.
   - The specific case of `ConversationItem.project` nullification when deleting a `ProjectItem` fails in tests.
   - For affected tests, use `XCTExpectFailure` with a descriptive message.
   - In production code, enforce relationship integrity through explicit code where SwiftData's automatic handling is insufficient.

### System Layer
Location: `src/system/`

This module contains core services, managers, and utilities that provide foundational functionality for the entire application.

#### Application Defaults (`AppDefaults.swift`)

This `struct` acts as a centralized namespace for all static default values and constants used throughout the application. This is a critical architectural pattern for maintainability and consistency.

*   **Centralized Configuration**: It provides a single source of truth for UI constants (fonts, padding), default names, application behavior toggles, and, most importantly, default parameters for all supported AI service providers (OpenAI, Anthropic, etc.).
*   **Extensible Provider Defaults**: Default settings for each AI provider, including model names, API endpoints, and request parameters, are organized into nested structs. This makes it trivial to add or update provider configurations without altering other parts of the codebase.
*   **User Settings Management**: It defines the initial state for settings that are managed via `UserDefaults` (`@AppStorage`). It also includes a `resetUserDefaults()` function to programmatically revert all user-customized settings back to these defined defaults.

#### Appearance Style (`AppearanceStyle.swift`)

This `enum` defines the available UI themes for the application (`system`, `light`, `dark`) and maps the selected setting to SwiftUI `ColorScheme`. It belongs in `system/` because it is app-setting state, not persisted SwiftData schema.

#### Menu Item Style (`MenuItemStyle.swift`)

A simple `struct` that acts as a namespace for a static factory method to create consistently styled menu item labels.

*   **UI Consistency**: Its `label(...)` method returns a SwiftUI `Label` configured with the `.titleAndIcon` style, ensuring that all menu items created via this helper have a uniform appearance.

#### Permission Manager (`PermissionManager.swift`)

This is a comprehensive, cross-platform `@ObservableObject` that provides a centralized service for checking and requesting all system-level permissions.

*   **Unified API**: It abstracts away the various underlying system frameworks (`AVFoundation`, `Speech`, `Contacts`, etc.) into a single, unified API. It uses a `PermissionType` enum to define all supported permissions, making the system clean and extensible.
*   **State Publishing**: It publishes the current `PermissionStatus` for each permission type, allowing SwiftUI views to subscribe to changes and reactively update their UI when a permission is granted or denied.
*   **Deep Linking to Settings**: It includes a `openAppSettings(...)` method that can open the macOS System Settings app and navigate directly to the relevant privacy pane for a denied permission, providing a seamless user experience.

*   **`QueryManager.swift`**: A singleton-like `@Observable` class that acts as the single source of truth for all SwiftData operations. It centralizes queries, mutations, and caching. It provides filtered views of data based on user settings (via `@AppStorage`) and automatically refreshes its caches in response to data changes.
#### Streaming Response Handling

The application's in-flight provider response system is built around `ConversationDraftStore` and the execution layer.

*   **Conversation Draft Store (`ConversationDraftStore.swift`)**: SwiftUI views observe draft text, tool calls, run status, and errors per conversation ID.
*   **Conversation Completion Use Case (`ConversationCompletionUseCase.swift`)**: Orchestrates provider events, draft state, response-run persistence, and sequential tool execution through application-domain helpers.
*   **`PermissionManager.swift`**: An `@ObservableObject` that centralizes all logic for checking and requesting user permissions for protected system services (e.g., Photos, Microphone, Camera, Contacts). It provides a unified interface for the UI to query permission status and trigger requests.
*   **`JsonSerializer.swift`**: A utility class containing static methods to serialize individual SwiftData models to JSON and deserialize them back into the application. It works with the DTOs in `system/export` and is a key part of the single-item import/export functionality.
*   **`AppDefaults.swift`**: An `Observable` struct that bridges `UserDefaults` with the application's default settings, providing a clean interface for managing user preferences.
*   **`MenuItemStyle.swift`**: A minor SwiftUI view helper for creating consistently styled `Label` views for use in menus.
### TTS Layer
Location: `src/tts/`

This module contains the application's Text-to-Speech (TTS) functionality. It is designed as a self-contained system that manages a playback queue, handles multi-language synthesis, and provides UI controls.

#### TTS System (`TTSSystem.swift`)

This file contains the core logic for the TTS system, centered around the `TTSQueue` class.

*   **Playlist-Driven Architecture**: The `TTSQueue` class is an `@Observable` that manages a playlist of messages. It provides comprehensive controls for playback, including play, pause, skip, repeat, and queue manipulation.
*   **Advanced Multi-Language Synthesis**: The system automatically detects and handles text containing multiple languages.
    *   **Segmentation**: It uses the `NaturalLanguage` framework to break text into `TTSSegment` objects, each tagged with its detected language.
    *   **Dynamic Voice Selection**: For each segment, it dynamically selects the appropriate `AVSpeechSynthesisVoice`, prioritizing user-configured voices (`VoiceConfigurationItem`) before falling back to the best available system voice.
*   **`AVSpeechSynthesizerDelegate` Integration**: It acts as the delegate for the underlying `AVSpeechSynthesizer` to manage the lifecycle of speech utterances, seamlessly playing segments and advancing through the playlist.

#### TTS Control View (`TTSControlView.swift`)

This SwiftUI view provides the user interface for the `TTSQueue`.

*   **Reactive Architecture**: The view is purely declarative. It receives the `TTSQueue` instance from the SwiftUI environment and binds directly to its `@Published` properties, creating a reactive UI that automatically updates whenever the playback state changes.
*   **Component-Based UI**: The interface is structured into three main components: a "Now Playing" section, a scrollable playlist, and a control panel for playback actions.
*   **Action Delegation**: All user interactions (play, pause, skip, etc.) are forwarded directly to the `TTSQueue` instance, cleanly separating the presentation layer from the core TTS engine.

### Views Layer
Location: `src/views/`

This module contains all the SwiftUI views that constitute the application's user interface. It is organized by feature area (e.g., `dialog`, `project`, `settings`) and includes shared `components`.

#### App Shell (`AppShellView.swift`)

This is the root view of the application and the stable parent for global UI presentation.

*   **Global Presentation Host**: Owns sheet presentation for settings, conversation options, TTS queue, and log history, keeping presentation anchors stable across navigation changes.
*   **Import/Export Orchestration**: Runs async import/export tasks (via `DataManager`) and updates navigation selection on completion.
*   **Selection Bridging**: Maintains `activeConversationID` and `selectionRequest` to coordinate status bar context and programmatic navigation.

#### Content View (`ContentView.swift`)

This is the main navigation view, responsible for sidebar structure and detail routing.

*   **Main UI Structure**: Builds the primary layout using `NavigationSplitView` (macOS) and `NavigationSplitView` + `navigationDestination` (iOS).
*   **Sidebar Composition**: Uses `ContentSidebarDataSource` to transform `QueryManager` data into projects/dialogs/bookmarks based on `NavigationMode` and `ShowSystemDialogs`, and renders via `ContentSidebarView`.
*   **State-Driven Routing**: Uses `SidebarSelection` to route to `ProjectView` or `ConversationView`, and uses `ProjectConversationSelection` to focus a specific conversation when navigating into a project.
*   **Action Hub**: Exposes toolbar menu actions (new items, import, view options, utilities, settings) and delegates app-level requests back to `AppShellView`.

#### Status Bar (`StatusBar.swift`)

This view provides a persistent, app-wide status bar at the bottom of the main window. It serves a dual purpose: displaying global application status and providing contextual information about the currently selected item.

*   **Global Log Display**: Displays the most recent `LoggingService` entry, with per-type filters persisted to `UserDefaults`.
*   **Contextual Information Header**: When a `ConversationItem` is active, it shows `DialogInfoHeader` with API configuration, model name, model capabilities, streaming toggle, and token counts.
*   **Log History Access**: Tapping the status bar message opens the log history sheet hosted by `AppShellView`.

#### Sidebar & Routing (`src/views/content/`)

This submodule holds the sidebar data and navigation plumbing used by `ContentView`.

*   **`ContentSidebarDataSource.swift`**: Shapes projects/dialogs/bookmarks for the current `NavigationMode` (bookmarks are label-sorted for determinism) and provides a stable list of visible selections.
*   **`ContentSidebarView.swift`**: Renders sidebar sections using `NavigationItem` rows and `SidebarSortButton`, and wires delete/archive/restore/export actions through closures.
*   **`ContentRouting.swift`**: Defines `SidebarSelection`, `ProjectConversationSelection`, and `selectionMatches(...)` helpers for selection syncing and routing.
*   **`Sorters.swift`**: `ConversationSorter` and `ProjectSorter` provide deterministic ordering (with tie-breakers) for sidebar and project lists; `ProjectSorter` scopes last-message timestamps by `NavigationMode`.

#### Conversation Views (`src/views/dialog/`)

This submodule contains the views responsible for displaying and interacting with a single conversation. All views have been migrated to use ID-based selection patterns to prevent crashes when SwiftData objects are deleted while views are active. Deprecated pass-through wrapper properties using the "dialogs" terminology have been removed throughout the codebase.

##### Chat Interface (`ConversationView.swift` & `ConversationViewModel.swift`)

This pair of files implements the core chat interface using the Model-View-ViewModel (MVVM) pattern.

*   **`ConversationView.swift` (The View)**: A declarative SwiftUI view responsible for rendering the UI. It is composed of a `ConversationMessagesList` for the message history and a `MessageInputView` for user input. It observes the ViewModel for all state and forwards all user actions to it. The view has been migrated to use ID-based selection patterns, initializing with a `conversationID` instead of a direct `ConversationItem` reference to prevent crashes when SwiftData objects are deleted while views are active.
*   **`ConversationViewModel.swift` (The ViewModel)**: An `@MainActor ObservableObject` that holds the state and business logic. It is initialized with a `conversationID` and the `QueryManager`. It publishes all UI state (e.g., `selectedMessages`, `streamingState`) and contains the methods to handle every user action, from message selection to forking a conversation. The ViewModel resolves the actual `ConversationItem` from the `QueryManager` by `conversationID` at render time, ensuring data consistency.

##### ViewModel Store (`ConversationViewModelStore.swift`)

This `@Observable` cache provides one `ConversationViewModel` per conversation ID, preserving UI state (scroll position, selection, streaming) as users switch between conversations.

##### Message Bubble (`MessageView.swift`)

This is a reusable SwiftUI component that renders a single message bubble in the conversation list. Its primary responsibility is presentation, and it delegates all action logic to its parent view.

*   **Role-Based Layout**: It uses the `message.role` (`user`, `assistant`, `tool`) to determine the layout, alignment, and visual styling of the message.
*   **Dynamic Content Rendering**: It intelligently renders different content types, including custom views for tool calls, markdown for rich text, and plain text.
*   **Action Delegation**: It provides a `contextMenu` with a comprehensive set of actions (e.g., bookmark, fork, copy). When an action is triggered, it calls an `onAction` closure, passing the action to the `ConversationViewModel` to handle the logic.
*   **State-Aware UI**: It adapts its appearance based on selection state, visually indicating whether it is selected or part of an active selection session.

##### Message Input (`MessageInputView.swift`)

This view is the dedicated component for composing and sending messages.

*   **Message Sending Logic**: Its view model orchestrates user-facing send behavior. This includes auto-naming new conversations, expanding variables, and calling `ConversationCompletionUseCase` to initiate the AI request.
*   **Streaming Integration**: It passes `ConversationDraftStore` to the completion use case and disables itself while a response is actively streaming in, preventing concurrent requests.
*   **Feature Integration**: It integrates key functionalities like a `PhotosPicker` for image attachments (for vision models) and a button to present a sheet of reusable prompt templates.

##### Conversation Settings (`ConversationOptionsView.swift`)

This view, typically presented as a sheet, allows the user to configure conversation-specific settings. This includes overriding the project's default system prompt and adjusting AI parameters like temperature and token limits for the current conversation only.

*   **Tab-Based Organization**: It uses a `TabView` to organize settings into four distinct categories: Parameters, Tools, System Prompt, and Appearance.
*   **Dynamic UI**: The interface is highly dynamic. The "Parameters" tab renders a specific set of controls based on the selected API configuration, and the "Tools" tab lists all tools currently available in the `LLMToolRegistry`, allowing them to be enabled or disabled on a per-conversation basis.

##### BookmarkSheetView (`BookmarkSheetView.swift`)

This is the modal sheet view for creating a new bookmark. It provides a text field for the bookmark label and uses the `QueryManager` to persist the new bookmark, linking it to a specific `MessageItem` within a `ConversationItem`.

##### MessageAction (`MessageAction.swift`)

This enum defines all possible user actions that can be performed on a single `MessageItem` (e.g., copy, bookmark, delete). It provides a type-safe mechanism for views to communicate user intent to the handling logic without being coupled to the implementation details.

#### Settings Views (`src/views/settings/`)

This submodule contains all the views related to the application's settings screens.

##### Main Settings Container (`ApplicationSettingsView.swift`)

This view acts as the main container for the entire settings interface, orchestrating navigation between the various settings panels.

*   **Container View**: It uses a `NavigationSplitView` to create a standard master-detail layout, with a sidebar listing settings categories.
*   **Enum-Driven Navigation**: A `SettingsTab` enum defines all available settings categories. The view uses a `switch` statement on a `@State` variable of this enum type to determine which settings view to display in the detail pane, making the navigation clear and extensible.
*   **Modular Structure**: Each settings screen is implemented as a separate, self-contained SwiftUI view (e.g., `GeneralSettingsView`, `APISettingsView`) embedded within this container.

##### Confirmation Context (`ConfirmationContext.swift`)

This enum defines the text content for various confirmation dialogs used throughout the settings screens. It provides a centralized, type-safe source of truth for the titles, descriptive messages, and button labels for destructive actions like resetting defaults or clearing storage, ensuring a consistent user experience.

##### General Settings (`GeneralSettingsView.swift`)

This view manages a variety of global application settings related to appearance and general behavior.

*   **Direct Preference Binding**: It uses the `@AppStorage` property wrapper to bind UI controls directly to their corresponding `UserDefaults` keys. This ensures that any user change is immediately persisted and reflected throughout the application.
*   **Component-Based UI**: The view is built using reusable components like `ToggleRow`, `SliderRow`, and `AvatarPickerView`, which are organized into logical sections.

##### API Settings (`APISettingsView.swift`)

This view provides a standard Create, Read, Update, and Delete (CRUD) interface for managing `APIConfigurationItem` objects.

*   **Sheet-Based Editing**: It uses a sheet to present the `APIConfigurationEditView` for both creating new configurations and editing existing ones. This modal approach provides a focused editing experience.
*   **Data Source**: It reads the list of configurations directly from the `QueryManager` and uses it to perform all delete operations.
*   **Default Configuration Management**: It visually indicates the default configuration with a star icon and contains the logic to assign a new default if the current one is deleted.

##### API Configuration Editor (`APIConfigurationEditView.swift`)

This is the modal view responsible for the detailed editing of a single `APIConfigurationItem`.

*   **Buffered Editing**: It uses local `@State` variables to buffer all user edits. Changes are only committed to the persistent model object when the user explicitly saves, preventing invalid data from being written.
*   **API Presets**: It features an `APIPreset` enum that allows users to quickly populate the form with default values for common providers (e.g., OpenAI, Anthropic), simplifying setup.
*   **Input Validation**: It performs validation before saving to ensure that required fields like a name and API key are present.

##### Web Search Settings (`WebSearchSettingsView.swift`)

This view provides a CRUD interface for managing `WebSearchConfigurationItem` objects, mirroring the design of the API settings panel.

*   **Sheet-Based Editing**: It uses a sheet to present the `WebSearchConfigurationEditView` for creating and editing configurations.
*   **Data Source**: It reads the list of configurations from the `QueryManager` and uses it to handle delete operations.
*   **Default Configuration Management**: It visually marks the default configuration and ensures a new default is assigned if the current one is deleted.

##### Web Search Configuration Editor (`WebSearchConfigurationEditView.swift`)

This is the modal view for editing a single `WebSearchConfigurationItem`.

*   **Buffered Editing**: It uses local `@State` variables to buffer edits, which are only committed to the persistent model object on save.
*   **Provider-Specific Fields**: The view is driven by the `WebSearchProvider` enum and displays the appropriate input fields based on the selected provider's requirements.
*   **Input Validation**: It validates that all required fields for the selected provider are filled before saving the configuration.

##### Models Settings (`ModelsSettingsView.swift`)

This view is the central hub for managing the AI models (`ModelItem` entities) available within the application.

*   **Provider-Driven Model Fetching**: Its core feature is the ability to automatically fetch and refresh the list of available models directly from all configured API providers via an asynchronous `QueryManager` operation.
*   **Grouped Display**: It groups models by their provider, presenting them in distinct sections for clarity.
*   **Manual Override**: It allows users to manually add custom models using the `ModelEditorView`, which is presented as a sheet.
*   **Bulk Operations**: It includes actions for bulk updates ("Update Model List") and deletions ("Remove All Models").

##### Model Editor (`ModelEditorView.swift`)

This is the form-based view for creating and editing individual `ModelItem` entities.

*   **Buffered Editing**: It uses local `@State` variables to buffer edits, which are only committed to the persistent model object on save.
*   **Structured Form**: It uses a `Form` with distinct `Section`s to logically group related fields (e.g., name, provider, context size, capabilities).
*   **User-Friendly Controls**: It employs user-friendly controls like a `Picker` for the provider, a `TextField` with a number formatter for the context size, and a multi-selection `List` for capabilities.

##### Prompts Settings (`PromptsSettingsView.swift`)

This view provides a comprehensive interface for managing `PromptTemplate` entities, which serve as reusable text snippets.

*   **CRUD Interface**: It offers a standard interface for creating, reading, updating, and deleting prompt templates.
*   **Import/Export Functionality**: A key feature is the ability to import and export templates as JSON files. The view includes a dedicated selection mode for choosing multiple templates to export.
*   **Sheet-Based Editing**: It uses a sheet to present an editor view for creating new and modifying existing templates.
*   **Dynamic Action Bar**: The action bar's content changes based on the current context (e.g., showing export-related actions only when in selection mode).

##### Prompt Template Editor (`PromptTemplateEditView.swift`)

This is the modal view for creating and editing individual `PromptTemplate` entities.

*   **Direct Data Binding**: Unlike other editors, this view uses `@Bindable` to bind its UI controls directly to the `PromptTemplate` object being edited.
*   **Structured Form**: It uses a `ScrollView` with distinct sections for "Basic Settings" and "Prompt Content" for a clear editing experience.
*   **Input Validation**: It validates that template names are not empty and are unique before saving.
*   **Completion Handler**: It uses a completion handler to communicate the result of the edit back to the parent view.

### Project View (`src/views/project/`)

This submodule contains the primary interface for viewing and managing the contents of a single project.

#### `ProjectView.swift`

This view implements the main dashboard for a `ProjectItem`. It uses ID-based selection to avoid dereferencing deleted SwiftData objects while views are active.

*   **`ProjectView.swift` (The View)**: A declarative SwiftUI view responsible for rendering the UI. It displays the project's default settings and provides a filterable, sortable list of all its associated conversations. It initializes with a `projectID` instead of a direct `ProjectItem` reference to prevent crashes when SwiftData objects are deleted while views are active.
*   **Route-Driven Navigation**: Uses a `NavigationStack` with `ProjectRoute` and an optional `initialConversationID` to focus a specific conversation when navigating into a project (e.g., from a bookmark).
*   **Conversation Management**: It displays a list of the project's `ConversationItem`s with advanced filtering and sorting capabilities.
    *   **Filtering**: Conversation visibility is controlled by the global `NavigationMode` preference, persisted via `@AppStorage`.
    *   **Sorting**: The conversation list can be sorted by creation date, last message date, or alphabetically, in either ascending or descending order. Project-level sort preferences are persisted via `@AppStorage` using project-specific keys (`ProjectDialogsSortType`, `ProjectDialogsSortOrderDescending`), independent of the sidebar.
*   **System Prompt Editor**: It includes a dedicated section for viewing and editing the project's default system prompt. Users can edit the prompt directly in a `TextEditor` or apply a predefined template from a popover list.
*   **Component-Based Structure**: The view is organized into logical, reusable sub-views (`sectionSystemPrompt`, `sectionDialogs`) for clarity and maintainability.

### Reusable Components (`src/views/components/`)

This submodule contains a collection of reusable SwiftUI views that are used throughout the application to maintain a consistent user interface and encapsulate common functionality.

#### `AvatarPickerView.swift`

This is a reusable component that provides a standardized UI for selecting, changing, and removing an avatar image.

*   **Stateful Binding**: It uses a `@Binding` to `Data?`, allowing it to directly read and modify the image data owned by its parent view, making it highly reusable.
*   **Platform-Native Experience**: It employs conditional compilation to provide the appropriate image selection mechanism for each platform (`NSOpenPanel` on macOS and a sheet-presented `ImagePicker` on iOS).
*   **Composition**: It uses the `AvatarView` component to render the actual avatar image, separating the logic of picking an image from displaying it.

#### `AvatarView.swift`

This is a purely presentational component responsible for rendering an avatar image.

*   **Graceful Fallback**: It safely handles optional `Data`. If the provided image data is `nil` or invalid, it falls back to displaying a default system placeholder icon.
*   **Platform Abstraction**: It uses conditional compilation to handle platform-specific image types (`NSImage` on macOS, `UIImage` on iOS), providing a unified interface.
*   **Visual Consistency**: It enforces a consistent visual style by clipping the image to a `Circle` and providing an option to add a circular stroke.

#### `HybridNumericInputView.swift`

This is a reusable component that provides a sophisticated hybrid interface for numeric input.

*   **Hybrid Control**: It combines a direct manipulation control (`Slider` or `Stepper`) with a precise `TextField`. This offers users both quick, coarse adjustments and fine-grained control over the value.
*   **Flexible Numeric Handling**: It uses a `Binding<Double>` but can be configured to handle both floating-point numbers and integers via an `isInteger` flag, with a `NumberFormatter` ensuring correct display.
*   **High Configurability**: Its behavior is customizable through its initializer, allowing developers to specify the range, step increment, and whether to use a `Slider` or a `Stepper`.

#### `ImagePicker.swift` (iOS-Only)

This component bridges the UIKit `UIImagePickerController` into the SwiftUI application for use on iOS.

*   **`UIViewControllerRepresentable` Wrapper**: It uses the `UIViewControllerRepresentable` protocol to wrap the UIKit `UIImagePickerController`, making it available within a SwiftUI view hierarchy.
*   **Coordinator Pattern**: It implements the Coordinator pattern to act as the delegate for the `UIImagePickerController`, handling callbacks for image selection and cancellation.
*   **Callback Mechanism**: It uses a closure to pass the selected `UIImage` back to the parent SwiftUI view, providing a clean way to communicate the result.

#### `NavigationItem.swift`

This is a versatile component that serves as the standardized row item for all entities displayed in the main navigation sidebar.

*   **Generic and Reusable**: It is designed to represent different data models (e.g., `ConversationItem`, `ProjectItem`) by accepting bindings and closures for its title and all primary actions (delete, rename, archive), making it fully decoupled from the specific logic of the items it displays.
*   **Comprehensive Context Menu**: It provides a rich, context-aware menu that dynamically shows relevant actions based on the item's state (e.g., showing "Restore" only for trashed items) by using optional closures.
*   **In-Place Editing**: It supports in-place renaming of the item's title, managing its own editing state and using `@FocusState` to programmatically control focus for a seamless user experience.
*   **Data-Driven Actions**: It leverages the `QueryManager` from the environment to populate submenus (e.g., "Move to Project"), ensuring the list of available actions is always up-to-date.

#### `PermissionRowView.swift`

This is a specialized, presentational component for displaying the status of a system permission in a standardized row.

*   **Informative UI**: It presents a comprehensive view of a permission's state, including its name, a usage description, its current status (e.g., "Granted", "Denied"), and a relevant icon, with the status highlighted for immediate visual feedback.
*   **Context-Aware Action Button**: The action button's label intelligently changes based on the permission's status, showing "Request Access" when not determined and "Open Settings" otherwise, guiding the user to the correct action.
*   **Decoupled and Reusable**: The view is purely presentational, receiving the `PermissionType`, `PermissionStatus`, and an `action` closure from its parent, decoupling it from the `PermissionManager` which handles the underlying logic.

#### `SidebarSortButton.swift`

This component provides a compact and reusable control for managing the sort order of lists in the sidebar.

*   **Stateful Binding**: It uses `@Binding` for both the sort direction and the raw string value of the sort type, allowing it to directly manipulate state owned by the parent view (typically persisted via `@AppStorage`).
*   **Type-Safe Enum**: It defines a `SidebarSortType` enum to encapsulate all possible sort criteria, including their labels and icons, providing a type-safe way to manage sort options.
*   **Platform-Adapted UI**: It uses conditional compilation to provide an optimal user experience on both macOS (a button with a `contextMenu`) and iOS (a `Menu`).
*   **Configurable Options**: The `allowedTypes` property allows the parent view to specify which sorting options are available for a particular list, making the component highly adaptable.

### Markdown Rendering Engine (`src/views/components/markdown/`)

This submodule contains a complete, custom-built engine for parsing and rendering Markdown content within the application. It uses Apple's `Markdown` framework to generate an Abstract Syntax Tree (AST) and then traverses this tree to produce a set of custom SwiftUI views.

#### `MarkdownASTParser.swift`

This is the core of the rendering engine, responsible for transforming raw Markdown text into a structured format suitable for rendering with SwiftUI.

*   **AST Traversal with `MarkupWalker`**: It conforms to the `MarkupWalker` protocol from Apple's `Markdown` framework, using the Visitor pattern to traverse the AST generated from a Markdown document.
*   **Custom Intermediate Representation**: As it visits each node, it converts it into a custom, simplified enum case from `MarkdownComponentType`. This decouples the parsing logic from the final SwiftUI rendering.
*   **`AttributedString` for Inline Content**: A key helper function, `collectInlineComponents`, aggregates and converts inline elements (like bold, italics, and links) into `AttributedString`s, preserving rich styling information.
*   **Recursive Parsing for Nested Structures**: It correctly handles nested structures, such as lists within lists, by recursively parsing list items to build a hierarchical representation.

#### `MarkdownRenderer.swift`

This is the main SwiftUI view responsible for orchestrating the parsing and rendering of a given Markdown string.

*   **State Management and Parsing**: It holds the raw `markdown` string and uses `onAppear` and `onChange` to trigger the `MarkdownASTParser`, storing the resulting `[MarkdownComponentType]` array in its `@State`.
*   **Component-Based Rendering**: It iterates over the parsed components and passes each one to a `MarkdownComponentRenderer` view, which then delegates to the appropriate view for that specific component type.
*   **Dynamic Updates**: By reacting to changes in the input string, it automatically re-parses and re-renders the content, ensuring the display is always up-to-date.
*   **Configurable Text Selection**: It includes a `ViewModifier` that makes text selection configurable via `@AppStorage`, allowing the user to enable or disable it.

#### `MarkdownComponentRenderer.swift`

This file defines a global `@ViewBuilder` function that acts as the central dispatch for the Markdown rendering engine, selecting the correct SwiftUI view for each component.

*   **View Switchboard**: It uses a `switch` statement on the `MarkdownComponentType` enum. For each case, it instantiates and returns the specific SwiftUI view responsible for rendering that type of element (e.g., `MarkdownCodeBlockView`, `MarkdownTableView`).
*   **Decoupling and Specialization**: This approach separates the logic of *what* to render from *how* to render it. The individual component views handle the detailed presentation.
*   **Hierarchical Rendering**: For composite components like lists, it passes the necessary data down to `MarkdownListItemView`, which can recursively render nested lists.

#### `MarkdownInlineComponent.swift` and Helpers

This set of files defines the data structures and rendering logic for inline Markdown elements (e.g., bold, italics, links, images).

*   **`MarkdownInlineComponent.swift`**: Defines a `Hashable` enum that serves as the core data structure for all inline content. It uses `AttributedString` as the associated value for styled text elements, preserving the rich styling information parsed from the original document.
*   **`MarkdownHelpers.swift`**: Contains the core logic for rendering inline components and for extracting text from the AST. The `renderInline` function converts `MarkdownInlineComponent` enums into specific SwiftUI views with the correct styling. The `collectAttributedText()` extension is critical for the parser, as it traverses the `Markup` tree to build an `AttributedString` that preserves all inline styles.
*   **`MarkdownComponentType.swift`**: Defines the central `Hashable` enum that serves as the intermediate representation for the entire parsed document. It includes cases for all standard block-level elements (headings, paragraphs, lists, code blocks, etc.), each with a data payload structured for easy rendering.

#### Specific Component Views

The engine uses a suite of dedicated SwiftUI views to render each block-level element.

*   **`MarkdownCodeBlockView.swift`**: Renders a fenced code block. It includes an optional header to display the language, a copy-to-clipboard button that uses `ExportUtils`, and a distinct visual style with a background and border to separate it from other content.
*   **`MarkdownListItemView.swift` & `MarkdownListItemComponent.swift`**: These two files work together to render list items. The `MarkdownListItemComponent` is a recursive data structure that holds the item's inline content and an array of `subItems` for nested lists. The `MarkdownListItemView` is a recursive view that renders its own content and then calls itself to render any sub-lists, allowing for arbitrarily deep nesting.
*   **`MarkdownBlockQuoteView.swift`**: A presentational view that renders block quotes. It applies a distinct background and padding to visually offset the content, and accepts an `AttributedString` to correctly render any inline styling within the quote.
*   **`MarkdownTableView.swift`**: Renders tables using SwiftUI's native `Grid` view for optimal layout. It robustly handles varying column counts between rows, renders headers with bold text, and supports `AttributedString` for rich text within cells.
*   **`MarkdownImageView.swift`**: A robust view for displaying images from URLs using SwiftUI's `AsyncImage`. It provides graceful fallbacks for loading errors (displaying alt text or a placeholder icon) and a `ProgressView` while loading, ensuring a good user experience and accessibility.

### Logging Layer
Location: `src/log/`

This module provides the application's centralized logging system.

*   **`LoggingService.swift`**: The application's central logging system, implemented as an `ObservableObject` singleton. It logs to both the unified `os.Logger` and a `@Published` in-memory history of `LogEntry` structs, which powers the UI's log viewer. It also supports filtering logs by source (`LogSource.swift`).
*   **`LogSource.swift`**: Defines the `LogSource` struct, a simple `Codable` and `Hashable` type used to uniquely identify a logging source by its file and function name. This struct is used by the `LoggingService` to register sources and by `LogSourcesSettingsView` to manage their enabled state.

### Utilities Layer
Location: `src/utilities/`

This module provides a collection of shared services, helpers, and extensions used throughout the application.
*   **`ErrorHandling.swift`**: Defines a comprehensive error handling system. It includes a custom `AppError` enum for application-specific errors, an `ErrorAlert` struct for creating user-facing alerts, and a `.errorAlert()` view modifier for presenting them in SwiftUI.
*   **`FileHelper.swift`**: A singleton providing a cross-platform (macOS/iOS) API for file interactions. It handles saving and loading data using native open/save panels and manages security-scoped resource access for files selected by the user.
*   **`JSONValue.swift` & `JSONUtils.swift`**: A pair of utilities for robust JSON manipulation. `JSONValue` is a powerful `enum` that represents any valid JSON type, complete with `Codable` support and convenient accessors. `JSONUtils` provides static helpers for common tasks like string-to-dictionary conversion and validation.
*   **`TypeConversionUtils.swift`**: A set of safe and robust static methods for converting values between different data types (e.g., `toInt`, `toBool`, `toString`), providing default values to prevent runtime crashes.
*   **`ShortcutsManager.swift`**: A macOS-specific singleton that interacts with the Apple Shortcuts app. It uses the `/usr/bin/shortcuts` command-line tool to fetch a list of all user shortcuts and to execute them with optional input.
*   **`HotkeyManager.swift`**: A macOS-specific manager for registering and handling global and local keyboard shortcuts using `NSEvent` monitors.
*   **`ParameterExpansion.swift`**: A global function, `expandVariables`, that performs simple, dynamic string substitution for variables like `$isodate` or `$dialogid`.
*   **`URLExtensions.swift`**: Contains a convenience extension on `URLComponents` for cleanly appending path segments.

### Views Layer
Location: `src/views/`
*   **`AppShellView.swift`**: Root UI shell that hosts `ContentView` and `StatusBar`, owns global sheet presentation, and runs import/export tasks.
*   **`ContentView.swift`**: Main `NavigationSplitView` for sidebar/detail routing. It uses `SidebarSelection` and `ContentSidebarDataSource` to drive navigation and delegates app-level requests to `AppShellView`.
*   **`StatusBar.swift`**: A persistent view displayed at the bottom of the main window. It shows filtered log output and a `DialogInfoHeader` for the active conversation.
*   **Appearance handling**: The app-level scene builders apply the user-selected appearance using `.preferredColorScheme` with the `@AppStorage("appearanceStyle")` value, so the main window and Settings scene respect runtime theme changes without extra wrapper views.

The rest of the UI is organized into the following subdirectories:

*   **`components/`**: Contains small, reusable SwiftUI views used across the application. Key components include:
    *   **`AvatarPickerView.swift` & `AvatarView.swift`**: A pair of views for selecting and displaying a circular avatar image. `AvatarPickerView` handles the platform-specific logic for choosing an image, while `AvatarView` is responsible for rendering the image with an optional stroke and a placeholder.
    *   **`HybridNumericInputView.swift`**: A flexible component for numeric input that combines a slider or stepper with a text field, supporting both integer and floating-point values.
    *   **`ImagePicker.swift`**: An iOS-specific wrapper for `UIImagePickerController`, used by `AvatarPickerView` to select images from the photo library.
    *   **`NavigationItem.swift`**: A sophisticated, reusable view for list items, typically used in sidebars. It displays an item's title, subtitle, and icon, and provides a rich, configurable context menu for actions like renaming, deleting, archiving, and project assignment.
    *   **`PermissionRowView.swift`**: A view used in settings to display the status of a system permission (e.g., Photos, Contacts) and provide a button to request access or open system settings.
    *   **`SidebarSortButton.swift`**: A UI component that allows users to control the sort order of a list, providing options for sort criteria and direction (ascending/descending).
    *   **`markdown/`**: This subdirectory contains a complete, custom-built Markdown rendering engine for SwiftUI. It parses Markdown text into a custom Abstract Syntax Tree (AST) and then renders it using a series of specialized SwiftUI views. The core components are:
        *   **`MarkdownASTParser.swift`**: Traverses a `Markdown` document's AST and converts it into an array of custom `MarkdownComponentType` objects.
        *   **`MarkdownRenderer.swift`**: The main entry point that takes a Markdown string, orchestrates the parsing, and renders the resulting components.
        *   **`MarkdownComponentRenderer.swift`**: A view factory that switches on a `MarkdownComponentType` and dispatches to the appropriate view for rendering (e.g., `MarkdownCodeBlockView`, `MarkdownTableView`).
        *   **`MarkdownComponentType.swift`**: An `enum` that defines the proprietary AST nodes used by the rendering engine.
*   **`dialog/`**: Views related to displaying and interacting with a single conversation.
*   **`project/`**: Views for managing and displaying `ProjectItem` contents.
*   **`settings/`**: All views related to the application's settings screens.
*   **`utility/`**: Miscellaneous helper views, such as the log history sheet.
*   **`content/`**: Sidebar routing and data source views for the main shell.

### Settings
Location: `src/views/settings/`

This section documents the views responsible for configuring the application's behavior, managing APIs, and handling data.

#### Settings Components

*   **`ModelSelectionView.swift`**: A reusable sheet view for selecting an AI model. It allows users to filter the list of available `ModelItem`s by the current AI service provider, search by name, and filter by model capabilities (e.g., Vision, Tool Use). It is used in any context where a user needs to choose a model for a task.

#### Settings Tabs

* **`ApplicationSettingsView.swift`** – The main container for the settings UI. It uses a `NavigationSplitView` to present a sidebar of settings categories (defined in a `SettingsTab` enum) and displays the corresponding view for the selected category (e.g., `GeneralSettingsView`, `APISettingsView`).
*   **`GeneralSettingsView.swift`**: Manages general application preferences. It provides controls for setting the app's `AppearanceStyle`, toggling UI elements like the status bar, and configuring default avatar settings. All settings are persisted directly via `@AppStorage`.
*   **`APISettingsView.swift`**: The main view for managing AI service provider configurations. It lists all saved `APIConfigurationItem`s, shows which is the default, allows users to add new ones, and handles deletion. It presents the `APIConfigurationEditView` in a sheet for creating or editing a configuration.
*   **`APIConfigurationEditView.swift`**: A sheet view for creating or editing an `APIConfigurationItem`. It exposes provider preset, name, API key, base URL, default endpoint family, default model, and advanced headers/options JSON. Provider endpoint paths come from profiles; users do not edit fixed chat/responses/models paths in normal configuration.
*   **`WebSearchSettingsView.swift`**: The main view for managing web search service configurations. It lists all saved `WebSearchConfigurationItem`s, allows users to add new ones, and handles deletion. It presents the `WebSearchConfigurationEditView` in a sheet for creating or editing a configuration.
*   **`WebSearchConfigurationEditView.swift`**: A detailed sheet view for creating or editing a `WebSearchConfigurationItem`. It allows the user to select a provider (e.g., Google), enter the required credentials like an API key and a search engine ID, and set the configuration as the default for the application. It dynamically shows the required fields based on the selected provider.
*   **`ModelsSettingsView.swift`**: The main interface for managing the AI models available to the application. It provides a primary action to fetch and update the list of models from all configured API providers. The view displays models grouped by provider and allows for the manual addition, editing, or deletion of any model. It also includes a destructive action to remove all models at once.
*   **`ModelEditorView.swift`**: A sheet view for creating or editing a `ModelItem`. It provides fields to define the model's name, provider, context size (with convenient presets), and capabilities (e.g., vision, tool use) via a series of toggles.
*   **`PromptsSettingsView.swift`**: The main view for managing prompt templates. It features a `SettingsActionBar` to enable adding new templates and toggling a multi-select mode for batch operations. It embeds the `PromptTemplateList` to render the list of templates.
*   **`PromptTemplateList.swift`**: A reusable view that displays `PromptTemplate` items. It is highly configurable, supporting both a standard mode (where tapping a template activates it) and a multi-select mode. It can be filtered by category and handles the presentation of the `PromptTemplateEditView` sheet for creation and editing.
*   **`PromptTemplateEditView.swift`**: A sheet view for creating or editing a `PromptTemplate`. It provides a form for all template properties, including name, category, summary, and the full prompt content. It also performs validation to ensure template names are unique and required fields are filled.
*   **`TTSSettingsView.swift`**: The main view for configuring Text-to-Speech (TTS) settings. It provides global controls for autoplay and repeat mode, and it embeds the `VoiceConfigurationListView` to manage individual voice profiles.
*   **`VoiceConfigurationListView.swift`**: A view that lists all `VoiceConfigurationItem`s and allows users to add, edit, or delete them. It presents the `VoiceConfigurationEditView` in a sheet for detailed editing.
*   **`VoiceConfigurationEditView.swift`**: A detailed sheet view for creating or editing a `VoiceConfigurationItem`. It allows the user to assign a voice to a specific role (e.g., user, assistant) and language. It provides controls to select a system-available voice, adjust speech rate and pitch, and includes a preview function to test the current settings.
*   **`PermissionsSettingsView.swift`**: The main view for managing all system-level permissions required by the application. It uses a `PermissionManager` to query and request access to resources like Photos, Camera, and Microphone. It also includes advanced network security settings, embedding the `SelfSignedCertWhitelistView` to manage exceptions for self-signed SSL certificates.
*   **`PermissionRowView.swift`**: A reusable component located in `src/views/components/` that displays the status of a single permission (e.g., granted, denied). It provides a button that either initiates a permission request or directs the user to the relevant section of the system's Settings app.
*   **`SelfSignedCertWhitelistView.swift`**: A reusable component located in `src/views/settings/components/` for managing a whitelist of regular expression patterns. This allows the application to connect to specified servers that use self-signed SSL certificates, providing a necessary security workaround for development or private enterprise environments.
*   **`MaintenanceSettingsView.swift`**: Provides a centralized interface for critical data management tasks. It includes actions to reset user defaults, clear local storage, and perform database backup and restore operations using the native system file exporter and importer views.
*   **`ConfirmationContext.swift`**: A simple enum that defines the content (title, message, button text) for various confirmation dialogs, ensuring a consistent user experience for destructive actions like resetting settings or restoring the database.
*   **`DeveloperSettingsView.swift`**: A view that exposes advanced, developer-focused settings. It provides toggles for default Markdown rendering, text selectability, system dialog visibility, tool call chips, and streaming diagnostics.

### Utility Components (`src/views/utility/`)

This submodule contains views that provide utility functions, often bridging between different parts of the application or providing global UI elements.

#### Global Utility Panel (`GlobalUtilityPanel.swift`)

A macOS-specific class that manages a floating utility panel (`NSWindow`). This panel can be invoked globally to display a `MessageInputView` for a specific conversation, allowing the user to send a message from anywhere in the system. It has been migrated to use ID-based selection patterns, accepting a `conversationID` and resolving the `ConversationItem` via `QueryManager` at render time. It encapsulates the AppKit logic for creating, showing, and managing the window lifecycle, hosting the SwiftUI view within an `NSHostingController`.

#### Log History Sheet (`LogHistorySheet.swift`)

A view that displays the application's log history in a sheet. It connects to the shared `LoggingService` to display live log entries, owns its own filter state, and includes controls for filtering by log type and clearing the history. It is opened from the status bar or the main toolbar utility menu.

*   **`LogSource.swift`**: Located in `src/log/`, this file defines the `LogSource` struct, a simple `Codable` and `Hashable` type used to uniquely identify a logging source by its file and function name. This struct is used by the `LoggingService` to register sources and by `LogSourcesSettingsView` to manage their enabled state.

### Text-to-Speech
Location: `src/tts/`

* **`TTSSystem.swift`** – Defines the `TTSQueue` class, the core of the speech synthesis engine. This `@Observable` class manages a playlist of messages, uses the `NaturalLanguage` framework to segment text and detect language, queries SwiftData for voice configurations, and wraps `AVSpeechSynthesizer` to control playback.
* **`TTSControlView.swift`** – The user interface for the TTS system. It observes the `TTSQueue` to display the current playlist and playback state, and provides controls for play/pause, navigation, and playlist management.

### Search
Location: `src/search/`

This module uses `WebSearchProvider` as the provider factory for web search capabilities.

* **`WebSearchProvider.swift`** – The provider enum and factory that creates search service instances from stored `WebSearchConfigurationItem`s.
* **`WebSearchService.swift`** – A protocol defining the standard interface for any search provider, including the `search(query:numResults:)` method and the `WebSearchResult` return type.
* **`GoogleCustomSearchService.swift`** – The concrete implementation for the Google Custom Search API.

### Export & Import
Location: `src/system/export/`

The application supports full data backup and restore via JSON export/import.

* **`FullBackup.swift`** – Defines the `FullBackup` struct, the top-level `Codable` container for all application data. It also defines the `BackupDocument` which conforms to `FileDocument` for SwiftUI's `.fileExporter` and `.fileImporter`.
* **Export DTOs** – For each `SwiftData` model, there is a corresponding `Codable` data transfer object (e.g., `ConversationExportData.swift`) used for safe serialization.
* **`ExportUtils.swift`** – Provides static helper methods for JSON encoding/decoding and clipboard operations.

### Utilities
Location: `src/utilities/`

Includes: `FileHelper`, `ErrorAlert`, `RegexUtils`, etc.

### Views
Location: `src/views/`

Organized by feature areas: dialogs, projects, TTS, API settings, appearance, search, etc.

Example:
```
views/
  AppShellView.swift
  ContentView.swift
  StatusBar.swift
  content/
    ContentSidebarView.swift
    ContentRouting.swift
  dialog/
    ConversationView.swift
    MessageView.swift
  settings/
    SettingsSidebar.swift
    PromptsSettingsView.swift
    PromptTemplateList.swift
```

> UI best practices: prefer `QueryManager` for app-wide lists, use `@Environment(\.modelContext)` / `@Query` for local SwiftData bindings, and use `NavigationSplitView` for macOS 14 / iPadOS 17.

---

## Deep Dive: Protocols & Contracts

### LLM API Layer
| Protocol | Purpose | Key Conformers |
|----------|---------|----------------|
| `LLMProviderAdapter` | Top-level provider adapter interface for streaming and model fetches. | `OpenAIResponsesAdapter`, `OpenAIChatAdapter`, `AnthropicMessagesAdapter` |
| `LLMRequest` / `LLMMessage` / `LLMStreamEvent` | Provider-neutral request, message, and streaming event types. | LLM protocol structs under `src/llm_api` |
| `LLMProviderProfile` | Provider capabilities, auth kind, endpoint families, defaults, and feature flags. | Profiles in `LLMProviderRegistry` |
| `NetworkClient` / `LLMHTTPClient` | Shared JSON/SSE transport plus core-owned provider header resolution, metadata redaction, and normalized provider errors. | Used by web search and all LLM adapters |
| `LLMAdapterRunLoop` | Shared streamed/non-streamed adapter flow and metadata forwarding. | Used by provider adapters |
| `LLMCapabilityValidator` | Common preflight validation for endpoint, model, parameter, content, and tool replay support. | Used by `LLMRequestFactory` and adapters |

### Tooling Layer
| Protocol | Purpose |
|----------|---------|
| `LLMTool` / `ExecutableLLMTool` | Defines a tool's identity (`name`, `description`) and its executable logic. |
| `LLMToolParameters` / `LLMToolProperty` | Defines the JSON-like schema for a tool's arguments. |
| `LLMToolCall` / `LLMToolExecutionCall` | Represents the model's request to call a tool and the runtime execution call. |
| `LLMToolRegistry` | A singleton that holds a list of all registered tools and can manage tool-specific configurations. |
| `LLMToolCatalog` | Read-only lookup/listing boundary used by conversation orchestration. |

Implementation notes:
* Concrete tools live under `src/llm_runtime/` (e.g. conversation tools, `WebSearchTool`).
* Each tool defines a `parameters` JSON schema so providers like OpenAI can validate the call.
* `registerDefaultTools()` in `vxAtelierPro.App` registers dialog, settings, search, and shortcut tools during launch.

### TTS Pipeline
* **`TTSQueue`** (`src/tts/TTSSystem.swift`) wraps `AVSpeechSynthesizer` and manages the playback queue, segmenting text and selecting voices per `VoiceConfigurationItem`.
* **Environment Injection**: `TTSQueue` is injected via `.environment(ttsQueue)` and accessed with `@Environment(TTSQueue.self)`.

### Search Layer
* **`WebSearchService` protocol** abstracts external search APIs.
* **`GoogleCustomSearchService`** implements the protocol with Google CSE REST, respecting API key and CX settings from `WebSearchConfigurationItem`.
* The **`WebSearchTool`** bridges AI function calls to the service produced by `WebSearchConfigurationItem.makeWebSearchService()`, returning JSON search snippets accessible to LLMs.

### Utilities
| Protocol | Purpose | Conformers |
|----------|---------|------------|
| `WebSearchService` | Abstraction for external web search APIs. | `GoogleCustomSearchService` |
| `WebSearchConfiguration` | SwiftData model describing API key, cx, locale. | `WebSearchConfigurationItem` |

### System / Data
| Protocol | Purpose | Notes |
|----------|---------|-------|
| `StatusModifiable` | Internal helper to update `ItemStatus` on any `PersistentModel`. | Used by `QueryManager` |
| **`QueryManager`** | `@Observable` manager that centralizes SwiftData fetches, provides filtered collections, and CRUD helpers. | Instantiated in `vxAtelierPro.App` |

## SwiftData Model Relationships
```
ConversationItem 1─* ConversationTurn
          │
          ├─> 1 User MessageItem
          └─> * TurnEvent 1─> 1 MessageItem (assistant response, tool call, etc.)

ProjectItem 1─* ConversationItem
ConversationItem *─1 ConversationOptions

ProjectItem 1─* ConversationItem
ConversationItem *─1 ConversationOptions

PromptTemplate — independent model used in settings & dialogs.
VoiceConfigurationItem, APIConfigurationItem, WebSearchConfigurationItem — global settings models.
```
Delete rules:
* `.cascade` for child entities (`turns`, `events`, `options`).
* `.nullify` when a conversation is removed from a project.

## View & State Flow Conventions
* **Environment Objects:** `QueryManager`, `TTSQueue`, `ConversationViewModelStore`, and SwiftData `ModelContext` are seeded in `vxAtelierPro.App`.
* **@Query / @ModelContext:** Used where live SwiftData bindings are needed; most list data flows through `QueryManager`.
* **Navigation:** `NavigationSplitView` for the main shell; `NavigationStack` inside `ProjectView` for project-local routing.
* **Selection Logic:** `SidebarSelection` drives sidebar/detail routing; `ProjectConversationSelection` and `selectionRequest` enable programmatic selection.
* **Logging UI:** Status bar shows filtered `LoggingService` output; log history sheet reads `messageHistory`.

## Lifecycle & Entry Points
1. `vxAtelierPro.App` registers platform specific `AppDelegate`, initialises `ModelContainer`, `QueryManager`, `TTSQueue`, `ConversationViewModelStore`, and default tools.
2. The `WindowGroup` hosts `AppShellView` with `.preferredColorScheme` driven by `@AppStorage("appearanceStyle")`; the `Settings` scene hosts `ApplicationSettingsView` with the same override and injected environments.
3. On macOS, a `MenuBarExtra` supplies quick actions.

---

## Logging
All logging routes through `vxAtelierPro.log` (`LoggingService.shared`), which wraps Swift’s `os.Logger` and records an in-memory `messageHistory` for UI display. Levels include `debug`, `info`, `notice`, `warning`, `error`, `critical`, and `fault`, with optional source filtering via `LogSource`.

---

## Testing & CI
* Unit and UI tests live in Xcode test targets and run through Xcode / `xcodebuild`.
* Do not add XCTest targets or test resources to `Package.swift`.
* Suggested CI: macOS latest with `xcodebuild` build and test actions.

---

## Coding Standards
1. Follow **Apple Swift API Design Guidelines**.
2. Use **SwiftUI** data-flow patterns (`@Observable`, `@State`, `@Bindable`, `@Environment`) consistently.
3. Keep view files ≤ 300 LOC; extract subviews.
4. Abide by memory rules: selection logic, logging via `vxAtelierPro.log`, no backward compat/migrations unless tasked.

---

## Extending the App
1. **Add a new AI Provider**
   * Add an `LLMProviderProfile` entry in `LLMProviderRegistry` with provider ID, auth kind, endpoint families, supported parameters, schema features, and modalities.
   * If the provider uses a non-OpenAI-compatible API, implement `LLMProviderAdapter` (`stream` + `fetchModels`) and wire it in `LLMProviderRegistry.adapter(for:)`.
   * Add model decoding and fixture tests under `vxAtelier ProTests/AI`.
2. **Add a New Feature Tab**
   * Add SwiftUI view under `views/` and wire to sidebar.
3. **Add a New SwiftData Type**
   * Add `@Model` type in `persistence/`.
   * Supply migrations only if schema changes are breaking.

---
