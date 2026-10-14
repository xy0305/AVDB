// Neutral mock transport. Compiles the production VM, SDK topMovies and full Movie decoder.
@MainActor final class RankGate {
    var calls: [RankingsViewModel.Request] = []
    var pending: [Int: CheckedContinuation<[Movie], Error>] = [:]
    func fetch(_ r: RankingsViewModel.Request) async throws -> [Movie] {
        let id = calls.count
        calls.append(r)
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func wait(_ count: Int) async {
        for _ in 0..<10000 { if calls.count >= count { return }; await Task.yield() }
        preconditionFailure("request never reached mock transport")
    }
    func finish(_ i: Int, _ movies: [Movie]) { pending.removeValue(forKey: i)!.resume(returning: movies) }
    func fail(_ i: Int, _ error: Error) { pending.removeValue(forKey: i)!.resume(throwing: error) }
}
@main struct RankingRegression {
    @MainActor static func main() async throws {
        let api = APIClient.shared
        // Actual anonymous response observed 2026-10-15; contains no account/token/media data.
        api.raw = Data(#"{"success":0,"action":"JWTVerificationError","message":"請登錄帳號","data":null}"#.utf8)
        do { _ = try await JavDBSDK.shared.topMovies(); preconditionFailure("auth failure was silently empty") }
        catch JavDBError.apiError(let action, _) { assert(action == "JWTVerificationError") }
        // Synthetic neutral success exercises the real flexible decoder, not invented live evidence.
        api.raw = Data(#"{"success":1,"data":{"current_page":1,"movies":[{"id":42,"type":1,"number":"HEYZO-3953"},{"id":"neutral2","number":"FC2-PPV-1234567"}]}}"#.utf8)
        let decoded = try await JavDBSDK.shared.topMovies(startRank:51,type:"video_type",typeValue:"1",ignoreWatched:true,page:2)
        assert(decoded.count == 2 && decoded[0].id == "42" && decoded[0].type == "1")
        assert(decoded[1].type == "1")
        assert(api.path == "/api/v1/movies/top")
        assert(api.query == ["start_rank":"51","type":"video_type","type_value":"1","ignore_watched":"true","page":"2","limit":"25"])
        api.raw = Data(#"{"success":1,"data":{}}"#.utf8)
        do { _ = try await JavDBSDK.shared.topMovies(); preconditionFailure("missing movies was silently empty") }
        catch JavDBError.decodeError(_) { }
        api.raw = Data(#"{"success":1,"data":{"movies":[]}}"#.utf8)
        let empty = try await JavDBSDK.shared.topMovies(); assert(empty.isEmpty)
        let g = RankGate()
        let vm = RankingsViewModel(movieLoader: { try await g.fetch($0) })
        let a = Task { await vm.load(tab:.top250,period:.daily,playbackFilter:"high_score") }
        await g.wait(1); assert(vm.isLoading)
        let b = Task { await vm.load(tab:.western,period:.daily,playbackFilter:"high_score") }
        await g.wait(2)
        g.finish(1,[Movie(id:"western")]); await b.value
        g.finish(0,[Movie(id:"stale-top")]); await a.value
        assert(vm.movies.map(\.id) == ["western"] && !vm.isLoading)
        // Filter change while request is pending: old error must not poison new result/loading.
        let c = Task { await vm.load(tab:.top250,period:.daily,playbackFilter:"high_score") }
        await g.wait(3); vm.catalog="1"; vm.startRank=51
        let d = Task { await vm.applyTopFilter() }
        await g.wait(4)
        assert(g.calls[3].catalog == "1" && g.calls[3].startRank == 51 && g.calls[3].page == 1)
        g.fail(2,JavDBError.httpError(401,"expired")); await c.value
        assert(vm.isLoading && vm.errorMessage == nil)
        g.finish(3,[Movie(id:"new-filter")]); await d.value
        assert(vm.movies.map(\.id) == ["new-filter"] && !vm.isLoading)
        let more = Task { await vm.loadMore() }; await g.wait(5)
        g.fail(4,JavDBError.httpError(503,"retry")); await more.value
        assert(vm.movies.count == 1 && vm.errorMessage != nil && !vm.isLoading)
        let retry = Task { await vm.loadMore() }; await g.wait(6)
        assert(g.calls[4].page == 2 && g.calls[5].page == 2)
        g.finish(5,[Movie(id:"new-filter"),Movie(id:"page2")]); await retry.value
        assert(vm.movies.map(\.id) == ["new-filter","page2"] && vm.errorMessage == nil)
        let refresh = Task { await vm.load(tab:.top250,period:.daily,playbackFilter:"high_score",force:true) }
        await g.wait(7); assert(vm.movies.count == 2)
        g.fail(6,JavDBError.httpError(401,"expired")); await refresh.value
        assert(vm.movies.count == 2 && vm.errorMessage != nil)
        let cancel = Task { await vm.load(tab:.fc2,period:.daily,playbackFilter:"high_score") }
        await g.wait(8); cancel.cancel(); g.finish(7,[Movie(id:"cancelled")]); await cancel.value
        assert(vm.movies.isEmpty && !vm.isLoading)
        print("PASS production VM tab/filter stale responses, error retention, loading, cancellation, page retry/dedup; production TOP250 SDK/API wrapper/full Movie decoder")
    }
}
