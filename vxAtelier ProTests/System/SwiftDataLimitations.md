# SwiftData Limitations in Test Environment

This document outlines observed limitations and behaviors of SwiftData in the test environment, particularly regarding deletion operations, cascade rules, and reference invalidation.

## Deletion and Reference Invalidation

### Nullify Rules

**Issue**: SwiftData `deleteRule: .nullify` does not reliably function in the in-memory test container.

**Example**: When a `ProjectItem` is deleted, its associated `ConversationItem`s should have their `project` property set to `nil` (nullified). However, in the test environment, the reference often remains, causing dangling references.

**Workaround**: Tests that verify nullify behavior should be marked with `XCTExpectFailure` with an appropriate message explaining the SwiftData limitation. For production code, consider implementing manual reference nullification when deleting objects with relationships.

### Cascade Deletion

**Status**: Cascade deletion generally works as expected, with a parent object deletion triggering the deletion of all child objects marked with `deleteRule: .cascade`.

**Validation**: Tests confirm that when a `ProjectItem` is deleted, its child `ConversationItem`s are also deleted. Similarly, when a `ConversationItem` is deleted, its child `ConversationTurn`s are deleted.

### Dangling References

**Issue**: When an object is deleted, other objects that reference it but are not marked with cascade or nullify rules maintain dangling references that can cause runtime errors if accessed.

**Example**: When a `MessageItem` referenced by a `BookmarkItem` is deleted, the bookmark still exists but contains an invalid reference. SwiftData does not automatically clean up or invalidate these references.

**Workaround**: Implement explicit reference cleanup in the application code, particularly before accessing potentially invalid references. Tests should document this behavior and explicitly check for reference integrity.

## Transaction Behavior

### Context Saving

**Observation**: Changes to the ModelContext are not always immediately reflected in queries after saving. 

**Workaround**: Always call `queryManager.fetchAllData()` after model mutations to ensure the in-memory state is refreshed from the persistent store.

### Sequential Operations

**Note**: When performing sequential delete operations, each operation should be followed by a context save and explicit refresh of data from the persistent store to ensure accurate state for subsequent operations.

## In-Memory Container vs. Production Environment

**Important**: Behavior observed in the in-memory test container may differ from production environments:

1. Reference integrity issues that appear in tests may be handled differently in the production SQLite store.
2. Performance characteristics differ significantly between the test and production environments.
3. Cache invalidation timing may differ, affecting when changes become visible through relationships.

## Best Practices for Testing

1. **Explicit Relationship Management**: Always establish both sides of a relationship in tests (`project.conversations.append(dialog)` AND `dialog.project = project`).
2. **Verify After Refresh**: Always call `fetchAllData()` before making assertions about the state after mutations.
3. **Expected Failures**: Use `XCTExpectFailure` to document known SwiftData limitations rather than working around them in test code.
4. **Direct Property Access**: Avoid using cached computed properties after mutations; directly access the updated objects from the context instead.

## Known Test Edge Cases

1. **BookmarkItem with Deleted Message**: A bookmark whose referenced message is deleted will continue to exist but contain an invalid reference.
2. **Concurrent Deletions**: Deleting multiple related objects in parallel may produce inconsistent results; sequential deletion with context saves between operations is more reliable.
