# Build 312 — independent home lists, no image quality change

Base: Build 311 / 67802d8, `feat/home-hq-posters-from297`.

- Recommendation/latest/magnet list requests publish independently on MainActor.
- Structured initial task group; each section cancels and generation-invalidates overlapping loads, propagates parent cancellation, and checks account/API context before publishing.
- Explicit loading/loaded/empty/failed states. Traditional Chinese retry only reloads its section. Failure keeps existing cards; genuinely empty magnets no longer masquerade as latest cards.
- Bounded atomic Codable snapshots in Caches/HomeLists312 (7 days, 2 MB/file, 24 files), keyed by API base, account ID and full query. Unresolved authenticated accounts use an ephemeral namespace. No token/headers/password stored. Restore before network refresh; only successful responses write. Original thumb/cover URLs, ratings and badges retained.
- Independent per-section HQ prefetch starts on restored/fresh content; global image scheduler and ImageLoader, source policy, pixel sizes and image quality unchanged.
- Version/plist/packaging/artifact identifiers bumped to 312. The production workflow runs on the new branch and keeps commit/tree fingerprints in the IPA.

Validation:
- `python3 scripts/test-home-load312.py`: wiring assertions + real Swift async/cache tests when swiftc exists (required in macOS CI).
- Swift tests cover slow recommendation vs latest, terminal failure and isolated retry, restore-before-refresh, snapshot preservation on failure, stale/cancelled refresh protection, parent cancellation, empty state and base/account/query isolation.
- Existing release regression scripts retained, with only build/artifact assertions updated where needed.
- Linux local static tests pass, including home HQ298, search299, list HD300, category302/304/307, list-HQ303, ONE308, Tangxin311. Executable Swift tests initially unavailable locally: existing `/workspace/swift` lacks libncurses.so.6; macOS CI is authoritative for compilation/runtime tests.
- No physical-device speed/visual acceptance claimed; unsigned IPA requires the user's normal signing/install flow.
