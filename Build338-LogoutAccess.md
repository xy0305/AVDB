# Build 338 — manual logout reachable in the needsReauth and restoring states

Base: Build 337 / `bea69bd`, `feat/recommender-throttle-337`. MARKETING 1.0.2, build 338. Branch `feat/logout-access-338`. Unsigned IPA: `AVDB-unsigned-1.0.2-338-logout-access.ipa` (CI artifact `AVDB-338-release`).

Context: the user asked whether AVDB still lets them log out manually (2026-11-12). Checking the code: the app's only 「退出登录」 button lived inside the loaded-profile branch of the 「我的」 page (`UserView`), so it rendered only after the profile had loaded successfully. Two states that still hold a credential could never reach it:

- **needsReauth** — since Build 327, a 401 marks the session `needsReauth` and deliberately retains the stored credential (no automatic clearing, no automatic retry with the dead token). But `currentUser` is nil in that state, so the page falls into the signed-out branch, which showed only the 「服务器已拒绝登录凭证，请重新登录」 footnote and the login/register entry. The retained token could be overwritten by logging in again, but never simply discarded — no manual exit existed.
- **Restoring** — while the profile is being restored (「正在恢复账户」), `isLoggedIn` is true but `currentUser` is still nil, and that branch likewise had no exit; a session stuck restoring could not be ended from the page either.

## Changes (`AVDB/Views/User/UserView.swift` only)

1. **Restoring state:** a new Section after the existing 「正在恢复账户」 Section carries the identical button — `Button("退出登录", role: .destructive) { appState.logout() }`.
2. **needsReauth state:** inside the signed-out branch, a Section with the same button is shown only when `sessionStatus == .needsReauth` (right after the rejection footnote). A truly signed-out user has no token to clear, so the button stays conditional and does not appear for them.

Both buttons call the existing `AppState.logout()` — the same code path as the profile-state button: it drops the cached profile for the token, clears the session state, and calls `JavDBSDK.shared.logout()`. No second logout implementation was added.

## What did NOT change

- **The 327 automatic policy is exactly as it was.** `markNeedsReauth()` still retains the credential on rejection, still never calls `logout()` or `setToken(nil)`, and a rejected token is still never retried automatically. Build 338 adds a *manual* exit to the states that lacked one; nothing about automatic behaviour moved.
- **The profile-state logout is untouched** — same button, same place, same handler.
- Login, re-login, account switching, and every other page are unchanged.

## Visible scope for the user

On the 「我的」 page only: if the server has rejected the login credential (the page shows 「服务器已拒绝登录凭证，请重新登录」), a red 「退出登录」 now appears under that note and clears the stored token for good; the same button is also available while the page shows 「正在恢复账户」. Nothing else on any screen changes, and a fully signed-out page looks exactly as before.

Planned and implemented jointly with Muse and Kai.
