#!/usr/bin/env python3
"""Shipping history start policy execution, wiring/privacy checks. UIKit tests run in iOS CI."""
from pathlib import Path
import shutil, subprocess, tempfile, sys, plistlib
r=Path(__file__).resolve().parents[1]
stores=(r/'AVDB/Services/FeatureStores.swift').read_text()
player=(r/'AVDB/Views/Player/PlayerView.swift').read_text()
pan=(r/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
detail=(r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
sdk=(r/'AVDB/Services/JavDBSDK.swift').read_text()
app=(r/'AVDB/AVDBApp.swift').read_text()
views=(r/'AVDB/Views/User/LibraryFeaturesView.swift').read_text()
schema=stores.split('struct PlaybackHistoryItem:',1)[1].split('@MainActor',1)[0]
for forbidden in ['token:', 'streamURL:', 'headers:', 'magnetURL:', 'playURL:', 'duration:', 'progress:']:
    assert forbidden not in schema, forbidden
assert 'confirmationDialog(' in views and 'store.clear()' in views and 'store.remove(item.id)' in views
assert '.onChange(of: appState.currentUser?.id, initial: true)' in app
assert 'historyMovie: movie' in pan and 'historyArtwork: historyArtwork' in pan
assert 'APIClient.shared.token == historyToken' in player
assert 'historyGate.sample(time: currentTime, playing: coordinator.playerLayer?.player.isPlaying == true' in player
assert 'seeking: isSeeking || seekPending, failed: failureReported' in player
assert 'historyMovie: vm.historyMovie' in player
setter=detail.split('func setReviewStatus(',1)[1].split('func loadRelatedLists',1)[0]
assert 'old == status ? nil : status' in setter
assert 'reviewLoaded, !reviewPending' in setter
assert 'reviewStatus = old' in setter and 'errorMessage =' in setter
assert 'reviewRevision == revision' in setter
assert 'sdk.setMovieReview' not in setter and 'review?.status ?? status' not in setter
assert '/reviews/\\(reviewID)' in sdk and 'client.delete(' in sdk
assert '.reloadIgnoringLocalCacheData' in sdk
assert 'if actual == status { return actual }' in sdk
assert 'detail-want-watch' in detail and 'detail-watched' in detail
assert 'frame(width: 44, height: 44).contentShape(Rectangle())' in detail
assert plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion']=='248'
assert (r/'AVDB.xcodeproj/project.pbxproj').read_text().count('CURRENT_PROJECT_VERSION = 248;')==2
policy='struct PlaybackHistoryStartGate'+stores.split('struct PlaybackHistoryStartGate',1)[1].split('struct DrawRecord',1)[0]
main='''
var gate = PlaybackHistoryStartGate()
assert(!gate.sample(time:0,playing:false,seeking:false,failed:false))
assert(!gate.sample(time:0,playing:true,seeking:false,failed:false))
assert(!gate.sample(time:0,playing:true,seeking:false,failed:false))
assert(!gate.sample(time:30,playing:true,seeking:true,failed:false))
assert(!gate.sample(time:30,playing:true,seeking:false,failed:true))
assert(!gate.sample(time:0.5,playing:true,seeking:false,failed:false))
assert(gate.sample(time:1,playing:true,seeking:false,failed:false))
assert(!gate.sample(time:1.5,playing:true,seeking:false,failed:false))
var failed = PlaybackHistoryStartGate()
for t in [0.0,1.0,2.0] { assert(!failed.sample(time:t,playing:false,seeking:false,failed:true)) }
var seek = PlaybackHistoryStartGate()
assert(!seek.sample(time:0,playing:true,seeking:false,failed:false))
assert(!seek.sample(time:99,playing:true,seeking:false,failed:false))
assert(seek.sample(time:99.5,playing:true,seeking:false,failed:false))
print("PASS shipping Swift gate: no detail/ready/failure/stall/seek-jump record; first actual advancing playback; once per session")
'''
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as td:
        source=Path(td)/'main.swift'; binary=Path(td)/'history'
        source.write_text('import Foundation\n'+policy+main)
        subprocess.run(['swiftc',str(source),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
elif sys.platform=='darwin':
    raise RuntimeError('swiftc mandatory on macOS CI')
else:
    print('SKIP actual Swift execution on local Linux; mandatory macOS Release and hosted iOS CI')
print('PASS history schema/privacy/account lifecycle, both playback bridges, 44pt controls, toggle-off/pending/rollback/generation/authenticated DELETE/readback, version synchronization')
