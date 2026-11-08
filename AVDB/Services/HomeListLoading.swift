// Build 312: list-only stale-while-revalidate. Image loading policy is unchanged.
import Foundation

enum HomeListState: Equatable {
    case loading, loaded, empty, failed
}

/// No tokens, passwords, or request headers belong in this key or payload.
struct HomeListKey: Codable, Equatable {
    let base: String
    let accountID: String
    let query: String

    var filename: String {
        // Stable filename; the envelope also verifies the complete key on read.
        // JSONEncoder key order is unspecified, so hash an ordered representation.
        let ordered = [base, accountID, query].map { "\($0.utf8.count):\($0)" }.joined()
        let hash = ordered.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16) + ".json"
    }
}

private struct HomeListSnapshot<Item: Codable>: Codable {
    let version: Int
    let key: HomeListKey
    let savedAt: Date
    let items: [Item]
}

actor HomeListSnapshotStore {
    static let shared = HomeListSnapshotStore()
    private let directory: URL
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HomeLists312", isDirectory: true)) {
        self.directory = directory
    }

    func read<Item: Codable>(_ type: Item.Type, key: HomeListKey) -> [Item]? {
        let url = directory.appendingPathComponent(key.filename)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2_000_000,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(HomeListSnapshot<Item>.self, from: data),
              snapshot.version == 1, snapshot.key == key,
              Date().timeIntervalSince(snapshot.savedAt) < maxAge else { return nil }
        return snapshot.items
    }

    func write<Item: Codable>(_ items: [Item], key: HomeListKey) {
        guard let data = try? JSONEncoder().encode(HomeListSnapshot(version: 1, key: key, savedAt: Date(), items: items)),
              data.count <= 2_000_000 else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key.filename), options: .atomic)
        // Bound disk use across accounts/pages without retaining account credentials.
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = files.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in sorted.dropFirst(24) { try? FileManager.default.removeItem(at: file) }
    }
}

/// One controller per section. New loads cancel and invalidate the previous load,
/// including transports that ignore cancellation. Parent cancellation is propagated.
@MainActor
final class HomeListLoader<Item: Codable> {
    private(set) var items: [Item] = []
    private(set) var state: HomeListState = .loading
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let store: HomeListSnapshotStore
    init(store: HomeListSnapshotStore = .shared) { self.store = store }

    func cancel(clear: Bool = false) {
        generation = UUID()
        task?.cancel()
        if clear { items = []; state = .loading }
    }

    func load(key: HomeListKey, restore: Bool = true,
              isCurrent: @escaping @MainActor () -> Bool = { true },
              fetch: @escaping @MainActor () async throws -> [Item],
              changed: @escaping @MainActor ([Item], HomeListState) -> Void) async {
        guard !Task.isCancelled else { return }
        cancel()
        let ticket = generation
        state = .loading
        changed(items, state)
        let job = Task { @MainActor in
            defer {
                if ticket == generation, state == .loading, isCurrent() {
                    state = items.isEmpty ? .empty : .loaded
                    changed(items, state)
                }
            }
            if restore, items.isEmpty, let cached = await store.read(Item.self, key: key) {
                guard ticket == generation, !Task.isCancelled, isCurrent() else { return }
                items = cached
                changed(items, state)
            }
            do {
                try Task.checkCancellation()
                let fresh = try await fetch()
                guard ticket == generation, !Task.isCancelled, isCurrent() else { return }
                items = fresh
                state = fresh.isEmpty ? .empty : .loaded
                changed(items, state)
                // Failure/cancellation never replaces a successful snapshot.
                await store.write(fresh, key: key)
            } catch {
                guard ticket == generation, isCurrent() else { return }
                // Cancellation is not a network failure and must not leave a spinner.
                state = (Task.isCancelled || error is CancellationError) ? (items.isEmpty ? .empty : .loaded) : .failed
                changed(items, state)
            }
        }
        task = job
        await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
    }
}
