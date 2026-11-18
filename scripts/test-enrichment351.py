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
assert 'enum EnrichmentFeedClient' in feed
assert 'RankingFeedClient.rawBase' in feed            # same raw feed base
assert '"enrich-m-\\(shard).json"' in feed            # per-shard movie files
assert '"enrich-actors.json"' in feed
assert 'func movieEnrichment(javdbID: String)' in feed
assert 'func actorEnrichment(id: String?, names: [String])' in feed
assert 'new < old' in feed                            # monotonic cache guard
assert 'func isEnrichmentCover(_ value: String) -> Bool' in feed
assert 'MovieEnrichment.isEnrichmentCover(value)' in feed   # delegates to Models

# --- Movie / Actor fill-empty merges ---------------------------------------
movie = (r/'AVDB/Models/Movie.swift').read_text()
# The DTOs live in the Models file so Movie.swift stays self-contained
# (several regression harnesses compile it on its own with swiftc).
assert 'struct MovieEnrichment: Decodable' in movie
assert 'struct ActorEnrichment: Decodable' in movie
assert 'static func isEnrichmentCover(_ value: String) -> Bool' in movie
assert 'url.port == 8901' in movie                    # SR static host only
# Every key a DTO init reads must be declared in its CodingKeys, and the
# non-optional actor name must not use the `try? ... ??` precedence trap
# (both were real app compile errors in the first 351 CI run).
import re
for dto in ('MovieEnrichment', 'ActorEnrichment'):
    body = func_body(movie, f'struct {dto}: Decodable', ['\n}\n'])
    keys_block = body.split('enum CodingKeys')[1].split('}')[0]
    declared = set()
    for line in keys_block.split('\n'):
        declared |= {w.strip() for w in line.split('=')[0].replace('case', ' ').split(',') if w.strip().isidentifier()}
    used = set(re.findall(r'forKey: \.([A-Za-z]+)', body)) | set(re.findall(r'JSONFlex\.\w+\(c, \.([A-Za-z]+)\)', body))
    assert used <= declared, (dto, used - declared)
assert 'try? c.decode(String.self, forKey: .name) ?? ""' not in movie
merge = func_body(movie, 'func mergingEnrichment(_ enrichment: MovieEnrichment) -> Movie',
                  ['\n    func withCatalogueMetadata'])
assert 'guard enrichment.javdbID == id else { return self }' in merge
assert 'desc?.trimmingCharacters' in merge and 'copy.summary = plot' in merge   # fill-empty only
assert 'copy.directorName = director' in merge
assert 'copy.score = value' in merge
assert 'copy.previewVideoURL = trailer' in merge
assert 'copy.enrichmentCoverURL = hires' in merge
assert 'MovieEnrichment.isEnrichmentCover(hires)' in merge
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
assert 'scripts/package-lut352.py' in wf and 'AVDB-352-release' in wf and 'AVDB-350-release' not in wf
pkg = (r/'scripts/package-lut352.py').read_text()
assert "=='352'" in pkg and 'AVDB-unsigned-1.0.2-352-endpoints.ipa' in pkg
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
assert plist['CFBundleVersion'] == '352'
assert pbx.count('CURRENT_PROJECT_VERSION = 352;') == 2
doc = (r/'Build351-Enrichment.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '351' in doc and 'unsigned' in doc
print('PASS test-enrichment351: enrichment feed client + fill-empty movie/actor '
      'merges, SR cover below genuine HD, xAI settings + isolated on-device '
      'translation, release 351')
