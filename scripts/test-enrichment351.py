#!/usr/bin/env python3
"""Build 351: the App reads the server enrichment feed (fill-empty merges
on movies and actors, upscaled cover as a detail-poster candidate) and
gains on-device xAI translation with the key stored in the App's own
settings — translation never touches the JavDB APIs or signatures."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]

def func_body(src, signature, end_markers):
    i = src.index(signature)
    ends = [src.index(m, i) for m in end_markers if m in src[i:]]
    return src[i:min(ends) if ends else len(src)]

# --- Enrichment feed client -------------------------------------------------
feed = (r/'AVDB/Services/EnrichmentFeedClient.swift').read_text()
assert 'struct MovieEnrichment: Decodable' in feed
assert 'struct ActorEnrichment: Decodable' in feed
assert 'enum EnrichmentFeedClient' in feed
assert 'RankingFeedClient.rawBase' in feed            # same raw feed base
assert '"enrich-m-\\(shard).json"' in feed            # per-shard movie files
assert '"enrich-actors.json"' in feed
assert 'func movieEnrichment(javdbID: String)' in feed
assert 'func actorEnrichment(id: String?, names: [String])' in feed
assert 'new < old' in feed                            # monotonic cache guard
assert 'func isEnrichmentCover(_ value: String) -> Bool' in feed
assert 'port == 8901' in feed                         # SR static host only

# --- Movie / Actor fill-empty merges ---------------------------------------
movie = (r/'AVDB/Models/Movie.swift').read_text()
merge = func_body(movie, 'func mergingEnrichment(_ enrichment: MovieEnrichment) -> Movie',
                  ['\n    func withCatalogueMetadata'])
assert 'guard enrichment.javdbID == id else { return self }' in merge
assert 'desc?.trimmingCharacters' in merge and 'copy.summary = plot' in merge   # fill-empty only
assert 'copy.directorName = director' in merge
assert 'copy.score = value' in merge
assert 'copy.previewVideoURL = trailer' in merge
assert 'copy.enrichmentCoverURL = hires' in merge
assert 'var enrichmentCoverURL: String? = nil' in movie
actor_merge = func_body(movie, 'func mergingEnrichment(_ enrichment: ActorEnrichment) -> Actor',
                        ['\n}\n\nextension Actor'])
assert 'copy.bio = value' in actor_merge
assert 'copy.enrichmentAvatarURL = avatar' in actor_merge
assert 'public let bio: String?' in movie or 'var bio: String?' in movie

# --- Detail poster: SR cover candidate below genuine HD --------------------
resolver = (r/'AVDB/Services/DetailPosterResolver.swift').read_text()
assert 'EnrichmentFeedClient.isEnrichmentCover' in resolver
assert 'func winnerPredatesEnrichment' in resolver
assert 'max(cg.width, cg.height) >= 1200' in resolver   # genuine-HD pool rule
assert 'movie.enrichmentCoverURL' in resolver

# --- Both view models merge enrichment best-effort --------------------------
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'EnrichmentFeedState.shared.movieEnrichment(javdbID: base.id)' in detail
assert 'posterMovie = merged' in detail
actors = (r/'AVDB/Views/Actors/ActorsView.swift').read_text()
assert 'EnrichmentFeedState.shared.actorEnrichment(' in actors
assert 'actor-detail-bio' in actors

# --- Avatar priority: JavDB original -> enrichment -> JavBus chain ---------
avatar = (r/'AVDB/Services/JavBusActorAvatar.swift').read_text()
assert '[actor.avatarURL, actor.enrichmentAvatarURL, actor.coverURL]' in avatar

# --- xAI settings + on-device translation ----------------------------------
xai = (r/'AVDB/Services/XAITranslationService.swift').read_text()
assert 'final class XAISettings' in xai
assert 'grok-4-1-fast-non-reasoning' in xai
assert 'struct XAISettingsView: View' in xai
assert 'AI 翻译（xAI）' in xai
assert 'https://api.x.ai/v1/chat/completions' in xai
assert 'XAITranslationCache' in xai and 'sha256(text)' in xai
assert '只输出译文本身' in xai                          # Amane prompt port
assert 'needsTranslation' in xai
# Isolation: translation never references the JavDB channel at all.
for forbidden in ('JavDBSDK', 'JavDBSignature', 'APIClient', 'jdsignature'):
    assert forbidden not in xai, forbidden
assert 'func toggleTranslation() async' in detail
assert 'detail-translate-plot' in detail
assert 'XAITranslationService.translate(text: plot, field: "plot")' in detail
user = (r/'AVDB/Views/User/UserView.swift').read_text()
assert 'XAISettingsView()' in user and 'xai-settings-entry' in user

# --- Project registration ---------------------------------------------------
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert 'EnrichmentFeedClient.swift in Sources' in pbx
assert 'XAITranslationService.swift in Sources' in pbx

# --- Build machinery ---------------------------------------------------------
wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert wf.count('python3 scripts/test-enrichment351.py') == 5
assert wf.count('python3 scripts/test-rankings-auth350.py') == 5
assert '  enrichment-351:' in wf
assert 'scripts/package-lut351.py' in wf and 'AVDB-351-release' in wf and 'AVDB-350-release' not in wf
pkg = (r/'scripts/package-lut351.py').read_text()
assert "=='351'" in pkg and 'AVDB-unsigned-1.0.2-351-enrichment.ipa' in pkg
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
assert plist['CFBundleVersion'] == '351'
assert pbx.count('CURRENT_PROJECT_VERSION = 351;') == 2
doc = (r/'Build351-Enrichment.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '351' in doc and 'unsigned' in doc
print('PASS test-enrichment351: enrichment feed client + fill-empty movie/actor '
      'merges, SR cover below genuine HD, xAI settings + isolated on-device '
      'translation, release 351')
