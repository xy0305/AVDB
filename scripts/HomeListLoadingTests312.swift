import Foundation

@MainActor
private final class Gate {
    var continuation: CheckedContinuation<[String], Error>?
    func wait() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ items: [String]) { continuation!.resume(returning: items); continuation = nil }
}
private enum ProbeError: Error { case offline }

@main
struct HomeListLoadingTests312 {
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<5_000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Timed out waiting for deterministic test gate")
    }

    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("home312-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HomeListSnapshotStore(directory: directory)
        let rec = HomeListLoader<String>(store: store)
        let latest = HomeListLoader<String>(store: store)
        let key = HomeListKey(base: "https://fixture.invalid", accountID: "42", query: "latest?page=1")
        let recKey = HomeListKey(base: key.base, accountID: key.accountID, query: "recommend?page=1")
        let gate = Gate()
        let slow = Task { await rec.load(key: recKey, fetch: { try await gate.wait() }, changed: { _, _ in }) }
        await until { gate.continuation != nil }
        await latest.load(key: key, fetch: { ["latest"] }, changed: { _, _ in })
        assert(latest.items == ["latest"] && latest.state == .loaded)
        assert(rec.state == .loading && rec.items.isEmpty, "slow recommendation must not block latest")
        gate.finish(["recommended"])
        await slow.value
        print("PASS slow recommend does not block latest")

        await latest.load(key: key, fetch: { throw ProbeError.offline }, changed: { _, _ in })
        assert(latest.state == .failed && latest.items == ["latest"])
        let retained = await store.read(String.self, key: key)
        assert(retained == ["latest"], "failure must not overwrite good snapshot")
        assert(rec.items == ["recommended"] && rec.state == .loaded)
        await latest.load(key: key, fetch: { ["retry"] }, changed: { _, _ in })
        assert(latest.state == .loaded && latest.items == ["retry"] && rec.items == ["recommended"])
        print("PASS failure is terminal, cached content preserved, retry isolated")

        let restored = HomeListLoader<String>(store: store)
        let refresh = Gate()
        let restoring = Task { await restored.load(key: key, fetch: { try await refresh.wait() }, changed: { _, _ in }) }
        await until { refresh.continuation != nil }
        assert(restored.items == ["retry"] && restored.state == .loading)
        refresh.finish(["fresh"])
        await restoring.value
        assert(restored.items == ["fresh"] && restored.state == .loaded)
        let persisted = await store.read(String.self, key: key)
        assert(persisted == ["fresh"])
        print("PASS snapshot displays before refresh; fresh response persists")

        // Deliberately cancellation-ignoring transport finishes after a new refresh.
        let stale = Gate()
        let old = Task { await restored.load(key: key, fetch: { try await stale.wait() }, changed: { _, _ in }) }
        await until { stale.continuation != nil }
        await restored.load(key: key, fetch: { ["newest"] }, changed: { _, _ in })
        stale.finish(["stale"])
        await old.value
        assert(restored.items == ["newest"] && restored.state == .loaded)
        let newest = await store.read(String.self, key: key)
        assert(newest == ["newest"])
        print("PASS cancelled/stale refresh cannot overwrite list or disk")

        let cancelled = HomeListLoader<String>(store: store)
        var started = false
        let parent = Task { await cancelled.load(key: recKey, restore: false, fetch: {
            started = true
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return ["should not publish"]
        }, changed: { _, _ in }) }
        await until { started }
        parent.cancel()
        await parent.value
        assert(cancelled.items.isEmpty && cancelled.state == .empty)
        print("PASS parent cancellation propagates and stops spinner")

        let empty = HomeListLoader<String>(store: store)
        await empty.load(key: key, restore: false, fetch: { [] }, changed: { _, _ in })
        assert(empty.state == .empty && empty.items.isEmpty)
        let failure = HomeListLoader<String>(store: store)
        await failure.load(key: recKey, restore: false, fetch: { throw ProbeError.offline }, changed: { _, _ in })
        assert(failure.state == .failed && failure.items.isEmpty)
        let anotherAccount = HomeListKey(base: key.base, accountID: "99", query: key.query)
        let anotherPage = HomeListKey(base: key.base, accountID: key.accountID, query: "latest?page=2")
        let anotherBase = HomeListKey(base: "https://other.invalid", accountID: key.accountID, query: key.query)
        for isolated in [anotherAccount, anotherPage, anotherBase] {
            let absent = await store.read(String.self, key: isolated)
            assert(absent == nil)
        }
        print("PASS empty is not loading; snapshots isolate account/query/base")
    }
}
