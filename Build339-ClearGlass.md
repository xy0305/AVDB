# Build 339 — detail play pill and action group switch to clear liquid glass

Base: Build 338 / `beebe45`, `feat/logout-access-338`. MARKETING 1.0.2, build 339. Branch `feat/detail-glass-clear-339`. Unsigned IPA: `AVDB-unsigned-1.0.2-339-clear-glass.ipa` (CI artifact `AVDB-339-release`).

Context: comparing the detail page against a reference (2026-11-12), the user directed that AVDB keep liquid glass but make it **more transparent — the backdrop colour should be roughly visible through it** （大致能看到底色）. Since Build 335 the detail page's play pill and portrait action group have used untinted iOS 26 `.regular` Liquid Glass, the same material as the home floating chrome. Over the detail page's warm backdrop that material samples as a milky pale beige (measured #D0C6C4 on the user's screenshot), washing out both capsules and flattening the play pill's presence. iOS 26 ships exactly the requested variant: `Glass.clear`, which keeps the liquid-glass refraction and edge behaviour but lets far more of the backdrop through.

## Changes

1. **`AVDB/Views/Components/GlassUI.swift` — `LiquidGlassEffect` gains a `clear` flag (default `false`).** On the iOS 26 path, `clear == true` builds the glass from `.clear` in all four combinations (tint / no tint × interactive / not): `.clear`, `.clear.interactive()`, `.clear.tint(tint)`, `.clear.tint(tint).interactive()`. The `.regular` constructions stay in place as the default path, and the existing gradient `strokeBorder` overlay (edge definition) is applied unchanged on both paths. The `liquidGlass(tint:interactive:)` View helper gains a defaulted `clear: Bool = false` parameter passed through to the modifier, so every existing call site compiles and behaves exactly as before.
2. **`AVDB/Views/Detail/DetailPlayPill.swift`** — the play pill opts in: `.liquidGlass(interactive: true, clear: true)`, with the Build 335 comment extended to record the 339 switch. Foreground stays white with the existing black shadow (legibility now matters more, with the backdrop visible), and the resume progress underline is unchanged.
3. **`AVDB/Views/Detail/MovieDetailView.swift` — `portraitActionGroup`** — the icon group opts in the same way: `.liquidGlass(interactive: false, clear: true)`, comment updated likewise.

## What did NOT change

- **Every other liquid-glass call site stays `.regular`.** Home floating chrome, the tab bar, search, shortcut circles, categories and all remaining `.liquidGlass` users are untouched — `clear: true` occurs at exactly the two detail call sites in the whole app (pinned by the gate).
- **Material only.** No layout, size, icon, text, or behaviour changed anywhere; the two capsules keep their shape, padding, and the gradient edge stroke.
- **Pre-iOS 26 fallback unchanged.** The `glassSurface` fallback's base is already `.ultraThinMaterial` (the thinnest system material), and its only strength knob (`tintStrength`) modulates the optional tint glaze layers, which neither call site uses (both are untinted), so there is no safe scoped knob to weaken for the clear case; the fallback line is byte-identical to Build 338. The user's device runs the iOS 27 beta, so the iOS 26 `.clear` path is the operative one.

## Visible scope for the user

On the movie detail page only: the 「播放」 pill and the four-icon action group next to it become noticeably more transparent — the poster and page colour show through the glass instead of the previous milky pale fill — while the white icons/text and the thin gradient edge keep them readable. Every other screen, including the home page's glass chrome, looks exactly as in Build 338.

Planned and implemented jointly with Muse and Kai.
