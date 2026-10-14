// Compiled with the shipping CatalogListViewModel (not a reimplemented model).
@MainActor final class Transport {
    var calls: [(CatalogQuery, Int)] = []
    var delayed = false
    var fail = false
    var pending: [CheckedContinuation<[Movie], Error>] = []
    var response = [Movie(id: "a"), Movie(id: "b"), Movie(id: "b")]
    func fetch(_ q: CatalogQuery, _ page: Int) async throws -> [Movie] {
        calls.append((q, page))
        if delayed { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if fail { throw NSError(domain: "mock", code: 1) }
        return response
    }
    func resolve(_ result: Result<[Movie], Error>) { pending.removeFirst().resume(with: result) }
}
@main struct Regression {
    @MainActor static func main() async {
        func q(_ type: String = "all", account: String? = nil, backend: String = "fixed") -> CatalogQuery {
            CatalogQuery(source: "magnets", type: type, filter: "magnets", sort: "update", account: account, backend: backend)
        }
        func check(_ condition: @autoclosure () -> Bool, _ text: String) {
            precondition(condition(), text)
        }
        func drain() async { for _ in 0..<30 { await Task.yield() } }
        let t = Transport()
        let vm = CatalogListViewModel(fetch: t.fetch)
        await vm.enter(q())
        check(t.calls.count == 1 && vm.movies.count == 2 && vm.nextPage == 2, "enter 1 / dedup / next page")
        vm.scrollID = "b"
        await vm.enter(q())
        check(t.calls.count == 1 && vm.scrollID == "b", "back 0 / retain anchor")
        await vm.enter(q("3"))
        check(t.calls.count == 2 && vm.scrollID == nil, "filter change 1 / reset anchor")
        await vm.refresh()
        check(t.calls.count == 3, "manual refresh 1")
        // Preserve content, cursor and scroll through delayed failing refresh.
        t.delayed = true
        vm.scrollID = "b"
        let refresh = Task { await vm.refresh() }
        await drain()
        check(vm.movies.count == 2 && vm.isLoading && vm.nextPage == 2, "refresh must not clear old content")
        t.resolve(.failure(NSError(domain: "mock timeout", code: 60)))
        await refresh.value
        check(!vm.isLoading && vm.errorMessage != nil && vm.movies.count == 2 && vm.scrollID == "b" && vm.nextPage == 2, "failed refresh retains old state")
        t.delayed = false
        t.response = [Movie(id: "a"), Movie(id: "b"), Movie(id: "c"), Movie(id: "c")]
        await vm.retry()
        check(vm.movies.map(\.id) == ["a", "b", "c"] && vm.nextPage == 2, "failed refresh retries page one; dedup")
        // In-flight page loading is single-flight and only advances on success.
        t.delayed = true
        let last = vm.movies.last!
        vm.loadMoreIfNeeded(current: last)
        vm.loadMoreIfNeeded(current: last)
        await drain()
        check(t.calls.last!.1 == 2 && t.pending.count == 1, "duplicate load-more")
        t.resolve(.failure(NSError(domain: "page failure", code: 2)))
        await drain()
        check(vm.nextPage == 2 && vm.movies.count == 3 && !vm.isLoading, "page failure cursor")
        let retry = Task { await vm.retry() }
        await drain()
        t.resolve(.success([Movie(id: "d")]))
        await retry.value
        check(vm.nextPage == 3 && vm.movies.count == 4, "retry same page")
        vm.scrollID = "c"
        let multiPageRefresh = Task { await vm.refresh() }
        await drain()
        check(vm.movies.count == 4 && vm.nextPage == 3 && vm.scrollID == "c", "loaded pages retained during refresh")
        t.resolve(.failure(NSError(domain: "refresh failure", code: 3)))
        await multiPageRefresh.value
        check(vm.movies.count == 4 && vm.nextPage == 3 && vm.scrollID == "c", "loaded pages retained after refresh failure")
        // A cancelled view task must not cancel/reset route work on a push.
        let t2 = Transport(); t2.delayed = true
        let vm2 = CatalogListViewModel(fetch: t2.fetch)
        let enter = Task { await vm2.enter(q()) }
        await drain(); enter.cancel()
        let back = Task { await vm2.enter(q()) }
        await drain()
        check(t2.calls.count == 1, "push cancelled view / return must reuse work")
        t2.resolve(.success([Movie(id: "old")]))
        await back.value
        check(vm2.movies.first?.id == "old", "resume initial load")
        // A transport ignoring cancellation must never apply an older query.
        let old = Task { await vm2.refresh() }
        await drain()
        let changed = Task { await vm2.enter(q("4", account: "new", backend: "other")) }
        await drain()
        check(vm2.movies.isEmpty && vm2.scrollID == nil, "new scope resets")
        t2.resolve(.success([Movie(id: "wrong-generation")]))
        await old.value
        check(vm2.movies.isEmpty && vm2.isLoading, "old generation cannot mutate loading/content")
        t2.resolve(.success([Movie(id: "new")]))
        await changed.value
        check(vm2.movies.first?.id == "new" && !vm2.isLoading, "newest wins")
        await vm2.enter(q("4", account: "new", backend: "other"))
        check(t2.calls.count == 3, "scope unchanged return 0")
        // Successful empty refresh is authoritative, not an infinite spinner.
        t2.delayed = false; t2.response = []
        await vm2.refresh()
        check(vm2.movies.isEmpty && !vm2.hasMore && !vm2.isLoading, "empty state")
        let t3 = Transport()
        let vm3 = CatalogListViewModel(fetch: t3.fetch)
        for type in ["all", "0", "1", "2", "3", "4"] {
            let before = t3.calls.count
            await vm3.enter(q(type))
            await vm3.enter(q(type))
            check(t3.calls.count == before + 1, "each catalog type loads once and returns without requests")
        }
        let latest = CatalogQuery(source: "latest", type: "all", filter: "", sort: "release", account: nil, backend: "fixed")
        await vm3.enter(latest); await vm3.enter(latest)
        check(t3.calls.count == 7, "latest uses identical route helper / sort and source identity")
        t3.fail = true
        let failed = CatalogQuery(source: "latest", type: "all", filter: "subtitle", sort: "update", account: nil, backend: "fixed")
        await vm3.enter(failed); await vm3.enter(failed)
        check(t3.calls.count == 8 && vm3.errorMessage != nil && !vm3.isLoading && vm3.movies.isEmpty, "initial failure bounded; return must not silently retry")
        print("PASS production catalog VM: enter1 back0 filter1 manual1; delayed failure and loaded pages; paging dedup; cancelled view; old generation; account/backend; all types and latest; empty/error")
    }
}
