# AGENTS.md (vxAtelier Pro)

## Swift / SwiftUI / SwiftData
- Generate code targeting Swift 5.9+ 
- Prefer @Observable over ObservableObject
- Prefer @Environment over @EnvironmentObject
- Apply SwiftUI and SwiftData best practices.
- Fully implement requested functionality: no new TODOs, placeholders, or missing pieces.
- Do **not** add `#Preview` blocks or any other SwiftUI preview-related code.
- Do not make assumptions about existing types/properties/functions; verify in the codebase first.

## Backward Compatibility / Data Migration
- This app has no stable release yet; persisted local data is disposable during development.
- Do **not** add backward-compatibility layers, schema-history tracking, compatibility shims, or SwiftData migration stages for unreleased schema changes unless explicitly requested for a specific task.
- When a schema change invalidates existing local data, prefer deleting/resetting the incompatible local store over preserving or migrating it.
- Review schema changes for whether destructive reset remains reliable, not for whether old stores can be migrated.
- Do not frame missing migrations as a defect unless the Caesar explicitly asks for preservation of existing data.

## Comments
- Only add comments when explanation if code is not self explainatory 
- Do not leave comments for removed code

## Project Structure
- Read `Package.swift` to understand the application structure.
- Update `Package.swift` whenever adding or deleting files.

## App Composition / Settings UI
- Treat `AppBootstrap` as the app composition root. App-wide dependencies must be injected through `bootstrapped(with:)` / `AppBootstrap.applyingDependencies(to:)`, not ad hoc from feature views.
- `AppShellView` consumes app dependencies, hosts global sheets/tasks, and bridges platform scene requests. It should not re-publish `QueryManager`, `ModelContext`, `AppSceneModel`, `TTSQueue`, or `NavigationRouter`.
- Keep `NavigationRouter` scoped to main content navigation. Do not use it as a generic app router for Settings scene presentation or platform window commands.
- Settings use separate platform shells: `MacOSApplicationSettingsSceneView` for the native macOS `Settings` scene and `IOSApplicationSettingsSheetView` for the iOS sheet. Shared settings pages live below those shells and should not own platform scene policy.
- macOS Settings must keep the native Settings toolbar for section tabs. Root settings page actions belong in inline page action regions on macOS and navigation toolbar actions on iOS.
- When adding a settings page, update `SettingsDestination`, `MacOSSettingsSection`, `AppDefaults` / `AppSettings` if persistence is needed, and `Package.swift` if files are added.

## Logging
- Logging must use the shared logger exposed by `vxAtelierPro.log` and the appropriate level (`debug`, `info`, `warning`, `error`, etc.).
- In `async` functions use `await vxAtelierPro.log…`; otherwise use `vxAtelierPro.log…`.

## Build / Test
- Do not needlessly compile or test; those are token expensive operations and they can pollute context.
- Maintain `Package.swift` only for VS Code/SourceKit IntelliSense and SwiftPM dependency graph support.
- Xcode / `xcodebuild` is the exclusive build and test authority for the application.
- Do not add SwiftPM test targets, SwiftPM test resources, or project guidance that recommends `swift test`.
- Do not run `swift test`; use `xcodebuild` for unit tests, UI tests, running/debugging, and release/archival builds.
- Swift compiler “complexity” errors are often caused by unknown identifiers or syntax errors; verify identifiers and syntax first.

## macOS / iOS sandboxing
- Be conscious of macOS/iOS sandboxing, permissions, and privileges.
- Use APIs such as `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` when necessary or recommended.

## Documentation Pointers
- Architecture: `vxAtelier Pro/docs/DEVELOPER.md`
- Common mistakes/errors: `vxAtelier Pro/docs/TROUBLESHOOTING.md`
- TTS system: `vxAtelier Pro/src/tts/README.md`
- LLM system: `vxAtelier Pro/src/llm_api/README.md`
