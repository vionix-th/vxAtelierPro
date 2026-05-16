# Troubleshooting Guide

This document tracks common issues, mistakes, and their solutions to help with development and debugging.

---

## In-Depth Solutions

### SwiftData: Dictionary Modifications in @Model Classes

**Problem:**  
Directly modifying a dictionary property within a SwiftData `@Model` class does not trigger the framework's change tracking. Operations like adding, removing, or updating key-value pairs in place will not be automatically saved or reflected in the UI.

**Solution:**
To ensure SwiftData detects the change, you must create a mutable copy of the dictionary, perform the modification, and then re-assign the updated dictionary back to the model's property. This reassignment signals to SwiftData that the value has changed.
    var myDict: [String: Bool]
    
    func updateValue(_ key: String, to value: Bool) {
        myDict[key] = value  // SwiftData won't track this change!
    }
}
```

**Solution:**  
Always create a new dictionary and reassign the entire property to ensure SwiftData tracks the change:

```swift
@Model
final class MyModel {
    var myDict: [String: Bool]
    
    func updateValue(_ key: String, to value: Bool) {
        var updatedDict = myDict
        updatedDict[key] = value
        myDict = updatedDict  // SwiftData will track this change
    }
}
```

**Files Fixed:**
- `ConversationOptions.swift`: Fixed `setToolEnabled` and `setToolConfiguration` methods

**General Rule:**
When modifying collection types (dictionaries, arrays, sets) in SwiftData models:
1. For read operations: Direct access is fine
2. For write operations: Create a new copy, modify it, then assign it back

### 2. Unnecessary @Query Usage

**Problem:**  
Using `@Query` in views where the data isn't directly displayed or where a filtered subset is immediately computed leads to unnecessary database queries and potential performance issues.

**Example of problematic code:**
```swift
struct MyView: View {
    @Query private var allItems: [Item] // Fetches ALL items
    
    var filteredItems: [Item] {
        allItems.filter { /* some condition */ }
    }
}
```

**Solution:**  
Use `@Query` with predicates to fetch only the needed data, or use relationships when the data is already available through a parent model:

```swift
struct MyView: View {
    @Query(filter: #Predicate<Item> { /* condition */ })
    private var items: [Item]
}
```

**Files Affected:**
- `ConversationView.swift`: Potentially unnecessary `@Query` for projects and apiConfigurations
- `ProjectView.swift`: Could use relationship instead of separate query

### 3. Missing @Transient Properties

**Problem:**  
Properties that shouldn't be persisted or are derived from other data are not marked as `@Transient`, leading to unnecessary storage and potential consistency issues.

**Example of problematic code:**
```swift
@Model
final class MyModel {
    var persistedValue: String
    var derivedValue: String // Should be transient!
}
```

**Solution:**  
Mark computed or temporary properties with `@Transient`:

```swift
@Model
final class MyModel {
    var persistedValue: String
    @Transient var derivedValue: String
}
```

### 4. Making SwiftData Models Sendable

### 5. Settings Keys Drift

**Problem:**  
Hard-coded `@AppStorage("SomeKey")` strings get out of sync when keys are renamed, causing silent preference resets.

**Solution:**  
Use the centralized facade:
```swift
@AppStorage(AppSettings.Keys.appearanceStyle) private var appearanceStyle: AppearanceStyle = .system
```
All keys live in `system/AppSettings.swift`; defaults remain in `system/AppDefaults.swift`.

### 6. macOS Startup Recovery Mode

**Problem:**  
The normal app bootstrap can fail before Settings or maintenance UI becomes available.

**Solution:**  
Hold the Option key during launch on macOS, set `VXATELIER_FORCE_RECOVERY_MODE=1` for tests and local debugging, or enable `Launch in Recovery Mode` in iPhone/iPad `Settings.app` for the app to open the recovery window instead of the normal app shell. Recovery mode can reset `UserDefaults`, wipe the local SwiftData store, and restore or import data before relaunching the app into normal mode.

**Problem:**  
Attempting to make SwiftData `@Model` classes conform to `Sendable` protocol, often as a quick fix for compiler warnings about capturing model instances in async contexts.

**Example of problematic code:**
```swift
@Model
final class MyModel: @unchecked Sendable {  // WRONG!
    var title: String
    var count: Int
}
```

**Solution:**  
Never make SwiftData models `Sendable`. Instead:
1. When using models across actor boundaries, pass only the model ID
2. Fetch the model again on the target actor using the ID
3. Make any modifications on the MainActor where the ModelContext lives

```swift
// Correct approach:
@Model
final class MyModel {
    var title: String
    var count: Int
}

// Usage in async context:
let modelId = model.id
await MainActor.run {
    let descriptor = FetchDescriptor<MyModel>()
    if let model = try? modelContext.fetch(descriptor).first(where: { $0.id == modelId }) {
        model.title = newTitle
    }
}
```

**Files Fixed:**
- `ProjectItem.swift`: Fixed async operations to use ID-based fetching

**Explanation:**
SwiftData models are inherently tied to their `ModelContext`, which must be accessed on the `MainActor`. Making them `Sendable` is incorrect because:
1. Models maintain internal state that's not thread-safe
2. All modifications must happen on the `MainActor`
3. The model's relationship with its context would be violated if sent across actors

**General Rule:**
When working with SwiftData models across actor boundaries:
1. Pass only IDs or value types
2. Re-fetch models on the `MainActor`
3. Keep all model modifications on the `MainActor`

## SwiftUI Issues

### 1. State Management Confusion

**Problem:**  
Inconsistent use of property wrappers (`@State`, `@Binding`, `@StateObject`, etc.) leading to unexpected UI behavior or unnecessary view updates.

**Example of problematic code:**
```swift
struct MyView: View {
    @State var model: MyModel // Should be @StateObject if MyModel is a reference type
    @State var derivedValue: String // Should be computed property
}
```

**Solution:**  
Follow these rules:
- Use `@State` for simple value types owned by the view
- Use `@StateObject` for reference types owned by the view
- Use `@ObservedObject` for reference types passed into the view
- Use `@Binding` for values that need to be modified by child views
- Use computed properties for values derived from other state

**Files Affected:**
- `ConversationView.swift`: Mixed usage of state management
- `StatusBar.swift`: Some `@State` properties could be computed

### 2. View Performance Issues

**Problem:**  
Large views with many subviews and computations in body property can lead to performance issues.

**Example of problematic code:**
```swift
var body: some View {
    VStack {
        // Many direct subviews and computations
    }
}
```

**Solution:**  
Break down large views into smaller components and move expensive computations out of the body:

```swift
struct MyView: View {
    private var computedValue: Int {
        // Expensive computation
    }
    
    var body: some View {
        VStack {
            SubView1(value: computedValue)
            SubView2(value: computedValue)
        }
    }
}
```

**Files Affected:**
- `ConversationView.swift`: Large view body with many subviews
- `StatusBar.swift`: Complex view hierarchy that could be broken down

**General Rules:**
1. Keep view bodies simple and focused
2. Extract repeated or complex UI elements into separate views
3. Use `@ViewBuilder` for conditional content
4. Move expensive computations into computed properties or methods

## Initialization and Lifecycle Issues

### 1. Unsafe Async Operations in View Lifecycle

**Problem:**  
Performing async operations directly in `onAppear` or initialization without proper task management can lead to race conditions and memory leaks.

**Example of problematic code:**
```swift
.onAppear {
    // Direct async call without task management
    await fetchData()  // This is unsafe!
}
```

**Solution:**  
Use `Task` for async operations and handle cancellation properly:

```swift
.task {  // Automatically cancelled when view disappears
    await fetchData()
}
```

**Files Affected:**
- `ContentView.swift`: Direct async calls in `onAppear`
- Settings pages: async fetch/update actions should use `.task`, explicit `Task`, and cancellation-aware view state rather than fire-and-forget work in `onAppear`

### 2. Multiple Source of Truth

**Problem:**  
Having multiple sources managing the same state, especially with a mix of `@State`, `@AppStorage`, and SwiftData.

**Example of problematic code:**
```swift
@State private var localValue: String = ""
@AppStorage("value") var storedValue: String = ""
// Both managing the same value!
```

**Solution:**  
Define a single source of truth and derive other states from it:

```swift
@AppStorage("value") var storedValue: String = ""
var localValue: String {
    get { storedValue }
    set { storedValue = newValue }
}
```

**Files Affected:**
- `ConversationView.swift`: Mixed state management between local state and SwiftData
- `StatusBar.swift`: Redundant state tracking

### 3. Initialization Order Dependencies

**Problem:**  
Relying on specific initialization order or making assumptions about when certain lifecycle events occur.

**Example of problematic code:**
```swift
init() {
    _state = State(initialValue: computeInitialValue())  // Depends on environment values not yet available!
}
```

**Solution:**  
Use lazy initialization or move dependent initialization to appropriate lifecycle events:

```swift
@State private var state: String = ""

var body: some View {
    MyView()
        .onAppear {
            state = computeInitialValue()  // Now has access to environment
        }
}
```

**Files Affected:**
- `ConversationView.swift`: Initialization assumptions in `init`
- `ModelEditorView.swift`: State initialization dependencies

**General Rules:**
1. Use `.task` instead of direct async calls in `onAppear`
2. Maintain a single source of truth for state
3. Don't assume initialization order
4. Handle task cancellation properly
5. Use appropriate lifecycle events for dependent initialization

### More Issues To Be Added... 

## Memory Management Issues

### 1. Closure Capture Lists

**Problem:**  
Strong reference cycles in closures, especially in SwiftUI views and SwiftData models, leading to memory leaks.

**Example of problematic code:**
```swift
Button("Action") {
    self.performAction()  // Strong reference to self
}

.onChange(of: someValue) { _ in
    heavyObject.doSomething()  // Strong reference to heavyObject
}
```

**Solution:**  
Use capture lists to explicitly define capture semantics:

```swift
Button("Action") { [weak self] in
    self?.performAction()
}

.onChange(of: someValue) { [weak heavyObject] _ in
    heavyObject?.doSomething()
}
```

**Files Affected:**
- `ConversationView.swift`: Multiple closures without capture lists
- `StatusBar.swift`: Event handlers with potential retain cycles

### 2. Subscription and Observer Cleanup

**Problem:**  
Not properly cleaning up subscriptions, notifications, or observers in SwiftUI views.

**Example of problematic code:**
```swift
.onAppear {
    NotificationCenter.default.addObserver(...)
    // No cleanup!
}
```

**Solution:**  
Use proper cleanup in `onDisappear` or return a cleanup closure:

```swift
.onReceive(NotificationCenter.default.publisher(...)) { notification in
    // Automatically cleaned up
}

// Or if manual observation is needed:
.onAppear {
    let observer = NotificationCenter.default.addObserver(...)
    return {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

**Files Affected:**
- `ContentView.swift`: Notification observers without cleanup
- `ConversationView.swift`: Manual observers that need cleanup

## Error Handling Patterns

### 1. Silent Failures

**Problem:**  
Catching errors without proper handling or user feedback, especially in SwiftUI views.

**Example of problematic code:**
```swift
do {
    try await performAction()
} catch {
    print(error)  // Silent failure!
}
```

**Solution:**  
Implement proper error handling and user feedback:

```swift
@State private var errorAlert: ErrorAlert?

do {
    try await performAction()
} catch {
    await MainActor.run {
        errorAlert = ErrorAlert(error: error)
    }
    vxAtelierPro.log.error("Action failed: \(error.localizedDescription)")
}
```

**Files Affected:**
- `ConversationView.swift`: Multiple try-catch blocks with minimal error handling
- Settings pages: destructive and persistence actions should log failures through `vxAtelierPro.log` and surface user-facing errors where recovery is needed

### 2. Error Propagation in SwiftData

**Problem:**  
Not properly handling or propagating SwiftData errors, leading to unclear failure states.

**Example of problematic code:**
```swift
func save() {
    try? modelContext.save()  // Silently ignores errors!
}
```

**Solution:**  
Properly handle and propagate SwiftData errors:

```swift
func save() throws {
    do {
        try modelContext.save()
    } catch {
        vxAtelierPro.log.error("Failed to save context: \(error.localizedDescription)")
        throw error
    }
}
```

**Files Affected:**
- Multiple views with `try?` usage for SwiftData operations
- Error handling in model operations could be improved

## Environment Access Patterns

### 1. Environment Value Dependencies

**Problem:**  
Implicit dependencies on environment values without proper handling of missing values.

**Example of problematic code:**
```swift
@Environment(\.modelContext) private var modelContext
// Used directly without checking if it exists
```

**Solution:**  
Handle potential missing environment values gracefully:

```swift
@Environment(\.modelContext) private var modelContext

func performAction() throws {
    guard let context = modelContext else {
        throw ViewError.missingModelContext
    }
    // Use context safely
}
```

**Files Affected:**
- Multiple views assuming environment values are always present
- `ConversationView.swift`: Direct usage of environment values

### 2. Environment Propagation

**Problem:**  
Not properly propagating environment values to child views, leading to unexpected behavior.

**Example of problematic code:**
```swift
struct ParentView: View {
    @State private var settings = ViewSettings()
    
    var body: some View {
        ChildView() // Doesn't receive parent's environment!
    }
}
```

**Solution:**  
Explicitly propagate environment values when needed:

```swift
struct ParentView: View {
    @State private var settings = ViewSettings()
    
    var body: some View {
        ChildView()
            .environment(\.viewSettings, settings)
            .environmentObject(settings)  // If using ObservableObject
    }
}
```

**Files Affected:**
- `ContentView.swift`: Environment value propagation could be more explicit
- Nested views might miss important environment values

**General Rules:**
1. Always use capture lists in closures that reference self or heavy objects
2. Clean up subscriptions and observers
3. Handle errors explicitly and provide user feedback
4. Don't assume environment values are always present
5. Be explicit about environment value propagation
6. Log errors appropriately using the app's logging system 

---

## SwiftData: Predicate Compile Constraints (#Predicate)

**Problem:**  
`#Predicate` often fails to compile when using properties that are not explicitly stored on the model (e.g., protocol/inherited members or SwiftData-synthesized identifiers like `id`, `persistentIdentifier`).

**Guidelines:**
- Only use explicitly stored properties in the predicate body.
- Avoid synthesized identifiers unless exposed as stored, queryable fields on the model.
- Move derived filtering logic to in-memory code after fetch, or expose a stored property that represents the filterable state.

**Correct pattern:**
```swift
@Query(filter: #Predicate<ConversationItem> { item in
    item.status == .active && item.timestamp > cutoff
})
private var items: [ConversationItem]
```

---

## SwiftData: Relationship Ordering Is Not Guaranteed

**Problem:**  
`@Relationship` arrays have no guaranteed order. Assertions or UI logic that assume order will be flaky.

**Rules:**
- Always sort related arrays before display or comparison (e.g., by `timestamp`, `sequence`, or another stable property).
- In tests, mirror the application’s sorting logic. If the app centralizes sorting/filtering in `QueryManager`, prefer using `QueryManager` rather than duplicating sort logic.

**Example:**
```swift
let sorted = project.conversations.sorted { $0.timestamp > $1.timestamp }
```

---

## SwiftData: In-Memory Container Nullify/Delete Limitation (Tests)

**Context:**  
The nullify-delete test for `ConversationItem.project` has been observed to fail on the in-memory container even after:
- Establishing both sides of the relationship
- Fetching by id and saving the context
- Verifying via diagnostic logging

All other relationship tests pass. This points to a SwiftData in-memory container limitation/bug rather than a test logic error.

**Workarounds:**
- In tests, manually nullify both sides of the relationship and re-save:
```swift
conversation.project = nil
project.conversations.removeAll { $0.id == conversation.id }
try context.save()
```
- Refetch the entities after save before asserting.
- If CI requires strict behavior, consider running the test with a file-backed container for this case.

Document this as a known limitation; do not overfit production code to satisfy the in-memory behavior.
