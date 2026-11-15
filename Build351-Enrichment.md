# Build 351 — Enrichment

Muse / Kai, Build 351 (unsigned). Marketing version stays 1.0.2.

## What changed

The detail pages now read the server enrichment feed published by the
VPS pipeline on the repo's `feed` branch (the App side of the user's
「1 2 3 4 全部做，代码可以抄」 decision for the Amane feature set):

- **EnrichmentFeedClient** (new): mirrors RankingFeedClient — network
  first, last-good Caches fallback, generated_at monotonicity, one fetch
  per file per session. Files: `enrich-m-<shard>.json` (shard = first
  character of the JavDB movie id) and `enrich-actors.json`.
- **Movies**: `Movie.mergingEnrichment` fills only empty fields (plot →
  summary, director, maker, series, score, duration), merges stills into
  previewImages with dedup, and fills the trailer URL. The feed's
  upscaled cover (`cover_hires_url`) rides along as
  `Movie.enrichmentCoverURL`: DetailPosterResolver admits it as a poster
  candidate ranked above the plain cover_url, but it leaves the pool
  whenever another candidate decoded from a genuine ≥1200 px native
  bitmap, and a stored sub-HD winner no longer short-circuits a resolve
  that could use it. List grids are untouched.
- **Actors**: `Actor` gains a `bio` field; the enrichment merge fills
  birthday / height / cup / bust / waist / hips / birthplace / bio only
  where empty. The header now shows measurements and birthplace, and the
  bio appears as a section under the header (absent without data). The
  enrichment portrait joins ActorAvatarArtwork directly below the JavDB
  original avatar and above the JavBus chain. Actor lookup is by
  javdb_id first, then by alias-catalog-normalized name.
- **xAI translation** (new): per the user's correction, the API key
  lives in the App's own settings （我的 → AI 翻译 → AI 翻译（xAI）), stored
  only in the device keychain; the model defaults to
  `grok-4-1-fast-non-reasoning` and is editable. With a key configured
  and a Japanese plot on screen, the 简介 section shows a 「翻译成中文」
  button: the plot is translated on-device via
  `https://api.x.ai/v1/chat/completions` and replaced in place (tap
  again for the original), and the translated title appears as small
  text under the original title. Translations are cached in Caches
  under a content-addressed key (text hash + language + field + prompt
  hash). No key → no button, no request. Translation traffic never
  touches the JavDB APIs, tokens or request signatures.

Both view models merge enrichment best-effort after the native record
loads; a feed miss or failure changes nothing and never errors.

## Not covered

- List grids and ranking boards do not consume enrichment (the ranking
  feed is unchanged); the upscaled cover only competes on the detail
  page of the movie it belongs to.
- Translation is plot + title only, triggered manually from the 简介
  section; actor bios are not translated.
- The pipeline account remains off the VPS (user decision 2026-11-15):
  enrichment data comes from DMM / Wikidata / gfriends only.

## Release

Unsigned IPA: `AVDB-unsigned-1.0.2-351-enrichment.ipa`, artifact
`AVDB-351-release`.
