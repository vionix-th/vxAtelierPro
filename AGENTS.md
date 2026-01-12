# AGENTS.md (vxAtelier Pro)

## Swift / SwiftUI / SwiftData
- Generate code targeting Swift 5.9+ 
- Prefer @Observable over ObservableObject
- Prefer @Environment over @EnvironmentObject
- Apply SwiftUI and SwiftData best practices.
- Fully implement requested functionality: no new TODOs, placeholders, or missing pieces.
- Do **not** add `#Preview` blocks or any other SwiftUI preview-related code.
- Do not make assumptions about existing types/properties/functions; verify in the codebase first.
- Do not implement backward compatibility or data migrations unless explicitly requested.

## Comments
- Only add comments when explanation if code is not self explainatory 
- Do not leave comments for removed code

## Project Structure
- Read `Package.swift` to understand the application structure.
- Update `Package.swift` whenever adding or deleting files.

## Logging
- Logging must use the `os.Logger` defined in `vxAtelierPro.swift` (`vxAtelierPro.log`) and the appropriate channel (`log`, `debug`, `error`).
- In `async` functions use `await vxAtelierPro.log…`; otherwise use `vxAtelierPro.log…`.

## Build / Test
- Maintain **both** build systems: Swift Package Manager (SPM) and Xcode (`xcodebuild`).
- Use SPM (`swift build`, `swift test`, `swift package`) for IDE indexing/linting-style workflows and fast compile/test-build checks.
- Use `xcodebuild` for actually running/debugging, unit tests, UI tests, and release/archival builds.
- Swift compiler “complexity” errors are often caused by unknown identifiers or syntax errors; verify identifiers and syntax first.

## macOS / iOS sandboxing
- Be conscious of macOS/iOS sandboxing, permissions, and privileges.
- Use APIs such as `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` when necessary or recommended.

## Documentation Pointers
- Architecture: `docs/DEVELOPER.md`
- Common mistakes/errors: `docs/TROUBLESHOOTING.md`
- TTS system: `src/tts/README.md`
- AI system: `src/ai/README.md`
