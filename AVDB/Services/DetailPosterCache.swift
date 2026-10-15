import Foundation

/// Detail-only, bounded memory TTL cache. Shared callers own separate leases;
/// leaving the final detail cancels the underlying URLSession request.
actor DetailPosterCache<Value: Sendable> {
    private struct Entry { let value: Value?; let expires: Date }
    private struct Flight { let id: UUID; let task: Task<Value?, Never>; var users: Set<UUID> }
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    init(positiveTTL: TimeInterval = 120, negativeTTL: TimeInterval = 30) {
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL
    }

    func value(key: String, operation: @escaping @Sendable () async -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        if let entry = entries[key], entry.expires > Date() { return entry.value }
        let user = UUID()
        let flight: Flight
        if var current = flights[key] {
            current.users.insert(user); flights[key] = current; flight = current
        } else {
            let id = UUID()
            let task = Task { () -> Value? in
                let value = await operation()
                await self.finish(key: key, id: id, value: value, cancelled: Task.isCancelled)
                return value
            }
            flight = Flight(id: id, task: task, users: [user])
            flights[key] = flight
        }
        return await withTaskCancellationHandler {
            let result = await flight.task.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            Task { await self.cancel(key: key, id: flight.id, user: user) }
        }
    }

    private func cancel(key: String, id: UUID, user: UUID) {
        guard var flight = flights[key], flight.id == id else { return }
        flight.users.remove(user)
        if flight.users.isEmpty {
            flights[key] = nil
            flight.task.cancel()
        } else { flights[key] = flight }
    }

    private func finish(key: String, id: UUID, value: Value?, cancelled: Bool) {
        guard flights[key]?.id == id else { return } // late result cannot replace a new flight
        flights[key] = nil
        guard !cancelled else { return }
        entries = entries.filter { $0.value.expires > Date() }
        if entries.count >= 24, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
        entries[key] = Entry(value: value, expires: Date().addingTimeInterval(value == nil ? negativeTTL : positiveTTL))
    }
}
