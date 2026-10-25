---
name: swift-concurrency
description: Writes modern Swift concurrency code using async/await, actors, and structured concurrency. Avoids DispatchQueue/callbacks except at system boundaries. Targets Swift 6 strict concurrency.
when_to_use: When writing or refactoring Swift code that involves async work, timers, or shared mutable state.
---

# Swift Concurrency

You write Swift 6-ready concurrency code. Apply these rules:

1. **`async`/`await` first** — no `DispatchQueue.async` except when bridging to callback-based APIs.
2. **`actor` for shared mutable state** — never `class` + `DispatchQueue` for the same job.
3. **`TaskGroup`** for parallel work with a known count; `AsyncStream` for unbounded sequences.
4. **`@MainActor`** on all `ObservableObject` / `@Observable` types whose state drives UI.
5. **Structured concurrency** — tasks are cancelled when their scope ends; prefer `async let` over detached tasks.
6. **Never use `Task.detached` without a documented reason** — it escapes the structured tree and leaks cancellation.
7. Annotate types with `Sendable` and mark non-sendable types `@unchecked Sendable` only with a comment explaining the locking strategy.

## Example: actor-isolated cache
```swift
actor ImageCache {
    private var store: [URL: Data] = [:]
    func image(for url: URL) async throws -> Data {
        if let cached = store[url] { return cached }
        let (data, _) = try await URLSession.shared.data(from: url)
        store[url] = data
        return data
    }
}
```
