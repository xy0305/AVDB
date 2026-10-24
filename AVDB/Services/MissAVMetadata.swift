import Foundation
import Combine

// The single view-owned queue covers both visible video cards and actor cards.
// No unbounded per-card search tasks. Entries are identity-keyed, so repeated
// editions/pages share one result; rank/order always belongs to the source array.
@MainActor final class MissAVMetadata: ObservableObject {
    struct Result {
        var movie: Movie?
        var actor: Actor?
        var avatarURL: String?
        var candidates: [Actor] = []
        var message = "等待 AVDB 核验…"
        var loading = true
    }
    enum Request {
        case movie(JRVideo)
        case actor(MissAVActress)
        var key: String {
            switch self {
            case .movie(let v): return "movie:" + (JRPolicy.exactCode(v.code) ?? v.path)
            case .actor(let a): return "actor:" + a.path
            }
        }
    }
    @Published private(set) var results: [String: Result] = [:]
    private var pending: [Request] = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var epoch = UUID()
    private var account: String?
    private var originGeneration = -1
    // Injection is only for deterministic shipping-queue runtime tests.
    private let resolver: ((Request) async throws -> Result)?
    private let sourceName: String
    private let generation: () -> Int
    private let enrichMissAV: Bool
    init(sourceName: String = "MissAV", generation: (() -> Int)? = nil, enrichMissAV: Bool = true, resolver: ((Request) async throws -> Result)? = nil) {
        self.sourceName = sourceName; self.generation = generation ?? { MissAVSource.shared.generation }
        self.enrichMissAV = enrichMissAV; self.resolver = resolver
    }
    func value(_ request: Request) -> Result { results[request.key] ?? Result() }
    func reset() {
        epoch = UUID(); tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        pending.removeAll(); results.removeAll()
        account = APIClient.shared.token; originGeneration = generation()
    }
    func suspend() {
        epoch = UUID()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll(); pending.removeAll()
        results = results.filter { !$0.value.loading }
    }
    func enqueue(_ request: Request, retry: Bool = false) {
        if account != APIClient.shared.token || originGeneration != generation() { reset() }
        guard tasks[request.key] == nil, !pending.contains(where: { $0.key == request.key }), retry || results[request.key] == nil else { return }
        // Bounded lifetime cache. Never evict queued/active entries.
        if results.count >= 256 {
            let idle = results.keys.filter { key in tasks[key] == nil && !pending.contains(where: { $0.key == key }) }
            for key in idle.prefix(64) { results[key] = nil }
        }
        results[request.key] = Result(); pending.append(request); pump()
    }
    private func pump() {
        while tasks.count < 2 && !pending.isEmpty {
            let request = pending.removeFirst(), token = epoch
            let owner = account, sourceEpoch = originGeneration
            tasks[request.key] = Task { @MainActor [weak self] in
                guard let self else { return }
                var result: Result
                do {
                    if let resolver = self.resolver { result = try await resolver(request) }
                    else { result = try await self.resolve(request) }
                } catch {
                    result = Result(message: error.localizedDescription, loading: false)
                }
                guard !Task.isCancelled, self.epoch == token,
                      owner == APIClient.shared.token, sourceEpoch == self.generation() else { return }
                result.loading = false
                self.results[request.key] = result
                self.tasks[request.key] = nil
                self.pump()
            }
        }
    }
    private func resolve(_ request: Request) async throws -> Result {
        switch request {
        case .movie(let video):
            var code = video.code
            if code.isEmpty && enrichMissAV { code = try await MissAVSource.shared.detail(video).video.code }
            guard JRPolicy.exactCode(code) != nil else { return Result(message: "未匹配：来源没有可信完整番号", loading: false) }
            let match = try await JavDBSDK.shared.exactMovie(code: code, verifyAllPages: true)
            return Result(movie: match, message: match == nil ? "未匹配：AVDB 前 3 页无唯一完整番号，点击核对 / 重试" : "AVDB 资料 · \(sourceName) 顺序", loading: false)
        case .actor(let actor):
            #if STANDALONE_METADATA_REPLAY
            return try await searchActor(actor.aliases)
            #else
            var aliases = actor.aliases
            let identity = ExternalActorIdentity.resolve(sourceName: actor.name, aliases: aliases, catalog: .bundled())
            if identity.unified { aliases = identity.queries }
            var result = try await searchActor(aliases, identity: identity)
            if enrichMissAV && result.actor == nil && result.candidates.isEmpty {
                let extra = try await MissAVSource.shared.actressAliases(actor)
                aliases = Array(Set(aliases + extra)).sorted()
                if !extra.allSatisfy({ actor.aliases.contains($0) }) { result = try await searchActor(aliases, identity: identity) }
            }
            return result
            #endif
        }
    }
    #if STANDALONE_METADATA_REPLAY
    private func searchActor(_ aliases: [String]) async throws -> Result {
        let owner = APIClient.shared.token
        var exact: [String: Actor] = [:], suggestions: [String: Actor] = [:]
        var complete = Set(aliases).count <= 3
        for name in Array(Set(aliases)).sorted().prefix(3) {
            for page in 1...3 {
                try Task.checkCancellation()
                let found = try await JavDBSDK.shared.searchActors(keyword: name, page: page)
                try Task.checkCancellation()
                guard owner == APIClient.shared.token else { throw CancellationError() }
                for item in found where !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if suggestions.count < 20 { suggestions[item.id] = item }
                    if MissAVIdentity.exact(aliases, [item.name, item.nameZht, item.otherName]) { exact[item.id] = item }
                }
                if found.count < 20 { break }
                if page == 3 { complete = false }
            }
        }
        if exact.count == 1 && complete {
            return Result(actor: exact.values.first, message: "AVDB 演员资料 · \(sourceName) 顺序", loading: false)
        }
        let choices = (exact.isEmpty ? suggestions : exact).values.sorted { $0.id < $1.id }
        return Result(candidates: choices, message: exact.count > 1 ? "多个精确姓名候选，待手动确认" : (complete ? "未匹配唯一精确别名，待手动核对" : "搜索达到分页上限，待手动核对"), loading: false)
    }
    #else
    private func searchActor(_ aliases: [String], identity: ExternalActorIdentity) async throws -> Result {
        let owner = APIClient.shared.token
        var exact: [String: Actor] = [:], suggestions: [String: Actor] = [:]
        var complete = true
        for name in Array(Set(aliases)).sorted().prefix(4) {
            for page in 1...3 {
                try Task.checkCancellation()
                let found = try await JavDBSDK.shared.searchActors(keyword: name, page: page)
                try Task.checkCancellation()
                guard owner == APIClient.shared.token else { throw CancellationError() }
                for item in found where !item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if suggestions.count < 20 { suggestions[item.id] = item }
                    if ExternalActorResolver.match(identity, actor: item) { exact[item.id] = item }
                }
                if found.count < 20 { break }
                if page == 3 { complete = false }
            }
        }
        if exact.count == 1 && complete, let actor = exact.values.first {
            let avatar = await ActorAvatarFallback.resolveMissing(actor: actor, names: identity.queries)
            let note = avatar.status == .missingKey ? "未设置" : (avatar.status == .matched ? "公开头像已唯一匹配" : "\(sourceName) 顺序")
            return Result(actor: actor, avatarURL: avatar.status == .matched ? avatar.url : nil, message: "AVDB 演员资料 · \(note)", loading: false)
        }
        let choices = (exact.isEmpty ? suggestions : exact).values.sorted { $0.id < $1.id }
        return Result(candidates: choices, message: exact.count > 1 ? "多个精确姓名候选，待手动确认" : (complete ? "未匹配唯一精确别名，待手动核对" : "搜索达到分页上限，待手动核对"), loading: false)
    }
    #endif
}
