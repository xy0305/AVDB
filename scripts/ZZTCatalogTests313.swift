import Foundation

private enum Probe: Error { case offline }

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: " + message) }
}

private func catalogJSON(updated: String, months: [(String, [String])], version: Int = 1) -> Data {
    let list: [[String: Any]] = months.map { month, codes in
        ["month": month, "title": "t \(month)", "video": "https://www.youtube.com/watch?v=x", "source": "https://example.invalid",
         "source_type": "forum_list", "entries": codes.map { ["code": $0, "actresses": ["A"], "note": NSNull()] }]
    }
    return try! JSONSerialization.data(withJSONObject: ["version": version, "updated_at": updated, "months": list])
}

@main
struct ZZTCatalogTests313 {
    static func main() async throws {
        // Bundled production JSON must decode strictly.
        let bundledPath = CommandLine.arguments[1]
        let bundled = try ZZTCatalog.decode(try Data(contentsOf: URL(fileURLWithPath: bundledPath)))
        check(bundled.months.count >= 12, "bundled months")
        check(bundled.months.map(\.month) == bundled.months.map(\.month).sorted(by: >), "newest first")
        check(bundled.months.allSatisfy { !$0.entries.isEmpty }, "non-empty months")

        // Order: months newest first, entry order preserved.
        let c = try ZZTCatalog.decode(catalogJSON(updated: "2026-11-09", months: [("2025-01", ["ABC-001"]), ("2026-10", ["SNOS-384", "IPZZ-937", "300MIUM-423"])]))
        check(c.months.first?.month == "2026-10" && c.months.first?.entries.map(\.code) == ["SNOS-384", "IPZZ-937", "300MIUM-423"], "order")
        check(c.months.first?.label == "2026 年 10 月", "label")

        // Build 314: year grouping keeps newest-first years and months.
        let y = try ZZTCatalog.decode(catalogJSON(updated: "2026-11-09", months: [("2023-05", ["ABC-001"]), ("2026-01", ["ABC-002"]), ("2026-10", ["ABC-003"]), ("2024-12", ["ABC-004"])]))
        check(y.years.map(\.year) == ["2026", "2024", "2023"], "years newest first")
        check(y.years.first?.months.map(\.month) == ["2026-10", "2026-01"], "months within year")
        check(y.years.first?.label == "2026 年" && y.years.first?.months.first?.monthLabel == "10 月", "year/month labels")
        check(bundled.years.flatMap(\.months) == bundled.months, "bundled years cover all months")

        // Strict rejection.
        for bad in [catalogJSON(updated: "x", months: [("2026-13", ["ABC-001"])]),
                    catalogJSON(updated: "x", months: [("2026-10", ["abc 001"])]),
                    catalogJSON(updated: "x", months: [("2026-10", [])]),
                    catalogJSON(updated: "x", months: [("2026-10", ["ABC-001"]), ("2026-10", ["ABC-002"])]),
                    catalogJSON(updated: "x", months: [("2026-10", ["ABC-001"])], version: 2),
                    Data("{}".utf8)] {
            check((try? ZZTCatalog.decode(bad)) == nil, "reject invalid catalog")
        }

        // Preference: newer remote wins, older/equal-smaller never replaces.
        let old = try ZZTCatalog.decode(catalogJSON(updated: "2026-11-01", months: [("2026-09", ["ABC-001"])]))
        let new = try ZZTCatalog.decode(catalogJSON(updated: "2026-11-09", months: [("2026-10", ["ABC-002"]), ("2026-09", ["ABC-001"])]))
        check(ZZTCatalog.preferred(old, new) == new && ZZTCatalog.preferred(new, old) == new, "prefer newer")
        check(ZZTCatalog.preferred(nil, old) == old && ZZTCatalog.preferred(old, nil) == old, "nil handling")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zzt313-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let oldData = catalogJSON(updated: "2026-11-01", months: [("2026-09", ["ABC-001"])])
        let newData = catalogJSON(updated: "2026-11-09", months: [("2026-10", ["ABC-002"]), ("2026-09", ["ABC-001"])])

        // Offline: bundled copy is used; refresh keeps it and reports failure.
        let offline = ZZTCatalogStore(bundledData: { oldData }, cacheDirectory: dir, fetcher: { _ in throw Probe.offline })
        let local = offline.local()
        check(local == old, "bundled offline")
        let failed = await offline.refresh(current: local)
        check(failed.catalog == old && failed.remoteOK == false, "offline keeps bundled")

        // Invalid remote never replaces nor writes cache.
        let garbage = ZZTCatalogStore(bundledData: { oldData }, cacheDirectory: dir, fetcher: { _ in Data("<html>".utf8) })
        let g = await garbage.refresh(current: old)
        check(g.catalog == old && !g.remoteOK, "garbage rejected")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog.json").path), "no cache on garbage")

        // Valid newer remote replaces and is cached for the next offline launch.
        var requested: URL?
        let online = ZZTCatalogStore(bundledData: { oldData }, cacheDirectory: dir, fetcher: { url in requested = url; return newData })
        let ok = await online.refresh(current: old)
        check(ok.catalog == new && ok.remoteOK, "remote newer used")
        check(requested == ZZTCatalog.remoteURL && requested?.host == "raw.githubusercontent.com", "remote url")
        let relaunch = ZZTCatalogStore(bundledData: { oldData }, cacheDirectory: dir, fetcher: { _ in throw Probe.offline })
        check(relaunch.local() == new, "cached remote survives relaunch")

        // Older remote does not downgrade a newer bundle.
        let downgrade = ZZTCatalogStore(bundledData: { newData }, cacheDirectory: dir.appendingPathComponent("d"), fetcher: { _ in oldData })
        let d = await downgrade.refresh(current: downgrade.local())
        check(d.catalog == new, "no downgrade")
        print("PASS ZZTCatalogTests313: strict decode, newest-first, offline bundle, remote refresh/cache, no downgrade")
    }
}
