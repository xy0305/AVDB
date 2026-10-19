#!/usr/bin/env python3
"""Build217 portrait layout and actual native Swift geometry regressions.
Invoked by mandatory test-detail-posters.py on the macOS release runner.
"""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
hero=s.split('private func portraitHero',1)[1].split('private func portraitMetadata',1)[0]
controls=s.split('private func portraitControls',1)[1].split('private var portraitPlayButton',1)[0]
play=s.split('private var portraitPlayButton',1)[1].split('private func portraitActionGroup',1)[0]
actions=s.split('private func portraitActionGroup',1)[1].split('private func posterAction',1)[0]
glass=(root/'AVDB/Views/Components/GlassUI.swift').read_text()
assert '.background(.clear, in: Capsule())' in play
assert '.overlay(Capsule().stroke(' in play
assert not any(x in play for x in ['.liquidGlass(', '.glassEffect(', '.ultraThinMaterial', '.background(.white'])
assert 'play115 = true' in play and 'GlassHaptic.tap()' in play
assert 'HStack(spacing: 12)' in controls
assert controls.index('portraitPlayButton') < controls.index('portraitActionGroup(movie)')
assert 'ViewThatFits(in: .horizontal)' in controls and 'VStack(spacing: 12)' in controls
assert '.accessibilityIdentifier(' not in controls # Must not override child play identity.
assert 'HStack(spacing: 0)' in actions
assert '.background(.clear, in: Capsule())' in actions
assert '.overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5))' in actions
assert not any(x in actions for x in ['.liquidGlass(', '.glassEffect(', '.glassSurface(', 'Material', '.background(.white', '.fill('])
assert '.padding(.horizontal, 6).padding(.vertical, 2)' in actions
assert '.frame(width: 44, height: 44)' in actions
poster_action=s.split('private func posterAction',1)[1].split('#if DEBUG',1)[0]
assert '.frame(width: 44, height: 44)' in poster_action
assert '.accessibilityLabel(label)' in poster_action
assert '.accessibilityIdentifier("portrait-hero-actions")' in actions
for x in ['showPosterResources = true','MyListsView(movieID: movie.id)','vm.setReviewStatus("want_watch")','vm.setReviewStatus("watched")']:
    assert x in actions,x
assert '.accessibilityElement(children: .contain)' in actions
assert 'if #available(iOS 26.0, *)' in glass and 'content.glassEffect(' in glass
assert 'content.glassSurface(in: Capsule()' in glass and 'shape.fill(.ultraThinMaterial)' in glass
assert '27.0' not in actions
assert '.frame(minHeight: max(0, geometry.controlsTop - titleTop - 18)' in hero
assert 'minHeight: showCoverTitle ?' not in hero # Hiding the title must not lift the row.
assert hero.index('DetailReadableTitle') < hero.index('portraitMetadata(movie)') < hero.index('portraitControls(movie)') < hero.index('portrait-hero-synopsis')
assert '@ScaledMetric(relativeTo: .largeTitle)' in s
# No unrelated wide-title or action semantics change.
wide=s.split('private func heroHeader',1)[1].split('private func heroAction',1)[0]
assert 'landscape-detail-title' in wide and 'collapsedLines: 2' not in wide
policy='struct DetailPortraitGeometry'+s.split('struct DetailPortraitGeometry',1)[1].split('// Two invisible measurements',1)[0]
main='''
let cases: [(CGFloat, CGFloat, Bool)] = [(320,568,false),(375,667,false),(390,844,false),(393,852,false),(430,932,false),(600,375,false),(375,600,true),(744,1133,true),(1032,1376,true),(1376,1032,true)]
for (w,h,pad) in cases {
    let g = DetailPortraitGeometry(availableSize: CGSize(width:w,height:h),isPad:pad)
    assert(g.width <= w && g.width <= (pad ? 900 : 600))
    assert(g.controlsTop >= g.titleTop + 132)
    assert(g.controlsTop.isFinite && g.imageHeight > 0)
    // Ordinary tall phones: row now starts at ~64%, never the old ~51%.
    if !pad && h >= 800 {
        assert(g.controlsTop / h >= 0.63 && g.controlsTop / h <= 0.68)
        assert(g.titleTop / h >= 0.47 && g.titleTop / h <= 0.51)
    }
    print("viewport \\(Int(w))x\\(Int(h)): title \\(g.titleTop), control minimum \\(g.controlsTop)")
}
// SceneLayoutReader reports the safe-area-excluding size, not UIScreen size.
let insetCases: [(CGFloat, CGFloat, CGFloat)] = [(390,751,844),(393,759,852),(402,778,874),(430,838,932)]
for (w, sceneH, displayH) in insetCases {
    let g = DetailPortraitGeometry(availableSize: CGSize(width:w,height:sceneH),isPad:false)
    assert(g.controlsTop / displayH >= 0.63 && g.controlsTop / displayH <= 0.68)
    assert(g.titleTop / displayH >= 0.47 && g.titleTop / displayH <= 0.51)
    print("safe-area scene \\(Int(w))x\\(Int(sceneH)): title \\(g.titleTop / displayH), controls \\(g.controlsTop / displayH) of display")
}
print("PASS production Swift portrait geometry: narrow / tall / safe areas / rotated / iPad / Split View")
'''
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as td:
        src=Path(td)/'main.swift'; exe=Path(td)/'layout'
        src.write_text('import Foundation\n'+policy+main)
        subprocess.run(['swiftc',str(src),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
else:
    print('SKIP native geometry execution: swiftc unavailable locally; mandatory on macOS CI')
print('PASS layout wiring: lower shared row, transparent play and actions, shared glass implementation retained, all four actions, adaptive title and disclosure')
