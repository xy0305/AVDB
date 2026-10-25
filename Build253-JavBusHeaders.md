# Build 253 – production JavBus public headers

The modified production service shares one ephemeral URLSession/header policy for pages, actor images and accepted same-resource redirects. The public header combination was previously verified together; no individual-header causal claim is made. No TLS impersonation, cookies, authentication or solver is used.

A parsed successful page carries its actual final work URL. After exact number and alias selection the service associates only that selected actor image with its validated page. `lookupArtwork` supplies both values to the production SwiftUI `ActorAvatarArtwork`; `imageData(_:sourceURL:)` rejects unproven contexts and sends that page as Referer. Requests rebuilt on allowed redirects retain the policy and never carry Cookie/Authorization. Verification/login targets, foreign hosts, private IP literals, HTTP downgrade and more than three redirects remain denied.

The cache scope includes the public-headers253 policy version. Existing user data is not erased. Existing artwork decoding, six known works, exact multi-actor matching, alias rules, scope/cancellation, page/image bounds and public agency/TMDB fallbacks are retained. This does not touch actor navigation/count policy, subtitle/history/favourites, Windows, VPS or Cloudflare.

Original 57 production avatar assertions and the 207-assertion actor harness remain unchanged. A new push-only validation job compiles the modified production parser/service, runs real URLSession page → exact actor → image → ImageIO checks on macOS and iOS Simulator, and renders the actual production `ActorAvatarArtwork` in a neutral SwiftUI host. It compares visible screenshot pixels with the real downloaded non-explicit actor portrait. Only unrelated image-loader/TMDB presentation dependencies are stubbed in the neutral host; the production JavBus parser, service, stateful view and public agency fallback source are compiled unchanged. No adult cover is downloaded as fixture. This is not a full signed app UI test or physical-device test.

Version 1.0.2 (253), iOS 17.0. GitHub push builds the unsigned Release IPA; no workflow_dispatch is invoked.
