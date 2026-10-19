import Foundation

/// Unknown is not a negative result. Both cached outcomes can be read before
/// SwiftUI's first body evaluation (an actor hop would already be one frame late).
enum DetailPosterLayout<Value: Sendable>: Sendable {
    case resolving
    case portrait(Value)
    case landscape

    var isLandscape: Bool { if case .landscape = self { return true }; return false }
    var artwork: Value? { if case .portrait(let value) = self { return value }; return nil }
}

/// A completion is valid only for the exact source/account identity and lease
/// generation which started it. Metadata unrelated to artwork does not reset it.
struct DetailPosterPresentation<Value: Sendable>: Sendable {
    let key: String
    let generation: UUID
    private(set) var layout: DetailPosterLayout<Value>

    mutating func complete(_ value: Value?, key: String, generation: UUID) {
        guard self.key == key, self.generation == generation, case .resolving = layout else { return }
        layout = value.map { .portrait($0) } ?? .landscape
    }
}

/// Detail-only bounded memory TTL cache. Synchronous snapshots use a short lock;
/// no image work/network/await occurs while locked. Each caller owns a lease.
final class DetailPosterCache<Value: Sendable>: @unchecked Sendable {
    private struct Entry { let value: Value?; let expires: Date }
    private struct Flight { let id: UUID; let task: Task<Value?, Never>; var users: Set<UUID> }
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    init(positiveTTL: TimeInterval = 120, negativeTTL: TimeInterval = 30) {
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    func snapshot(key: String) -> DetailPosterLayout<Value> {
        locked {
            guard let entry = entries[key] else { return .resolving }
            guard entry.expires > Date() else { entries[key] = nil; return .resolving }
            return entry.value.map { .portrait($0) } ?? .landscape
        }
    }

    func value(key: String, operation: @escaping @Sendable () async -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let user = UUID()
        let acquired: (Value?, Flight?) = locked {
            if let entry = entries[key], entry.expires > Date() { return (entry.value, nil) }
            if var current = flights[key] {
                current.users.insert(user); flights[key] = current; return (nil, current)
            }
            let id = UUID()
            let task = Task { () -> Value? in
                let value = await operation()
                self.finish(key: key, id: id, value: value, cancelled: Task.isCancelled)
                return value
            }
            let flight = Flight(id: id, task: task, users: [user])
            flights[key] = flight
            return (nil, flight)
        }
        guard let flight = acquired.1 else { return acquired.0 }
        return await withTaskCancellationHandler {
            let result = await flight.task.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            self.cancel(key: key, id: flight.id, user: user)
        }
    }

    func invalidate() {
        let abandoned: [Task<Value?, Never>] = locked {
            let tasks = flights.values.map(\.task)
            flights.removeAll(); entries.removeAll()
            return tasks
        }
        abandoned.forEach { $0.cancel() }
    }

    private func cancel(key: String, id: UUID, user: UUID) {
        let abandoned: Task<Value?, Never>? = locked {
            guard var flight = flights[key], flight.id == id else { return nil }
            flight.users.remove(user)
            if flight.users.isEmpty { flights[key] = nil; return flight.task }
            flights[key] = flight
            return nil
        }
        abandoned?.cancel()
    }

    private func finish(key: String, id: UUID, value: Value?, cancelled: Bool) {
        locked {
            guard flights[key]?.id == id else { return }
            flights[key] = nil
            guard !cancelled else { return }
            entries = entries.filter { $0.value.expires > Date() }
            if entries.count >= 24, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
            entries[key] = Entry(value: value, expires: Date().addingTimeInterval(value == nil ? negativeTTL : positiveTTL))
        }
    }
}
