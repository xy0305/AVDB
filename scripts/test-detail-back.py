#!/usr/bin/env python3
"""Compile and execute the exact shipping gesture policy, never a Python model."""
from pathlib import Path
import shutil, subprocess, tempfile, sys
r=Path(__file__).resolve().parents[1]
s=(r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
policy='struct DetailBackGesturePolicy'+s.split('struct DetailBackGesturePolicy',1)[1].split('/// A completion-only',1)[0]
bridge=s.split('struct StationaryDetailBackGesture',1)[1].split('extension View',1)[0]
assert '.stationaryDetailBackGesture()' in s
assert 'popViewController(animated: false)' in bridge
assert 'sender.state == .ended, canPop' in bridge
assert 'previousPopEnabled' in bridge and 'func uninstall()' in bridge
assert 'nav.topViewController === detail' in bridge and 'nav.viewControllers.count > 1' in bridge
assert 'nav.presentedViewController == nil' in bridge and 'detail.presentedViewController == nil' in bridge
assert 'transitionCoordinator == nil' in bridge
assert not any(x in bridge for x in ['UIPercentDrivenInteractiveTransition', '.transform =', 'contentOffset =', 'translationX:', 'dismiss('])
main=r'''
for w: CGFloat in [320, 375, 390, 430, 600, 744, 1024, 1376] {
 for rtl in [false,true] {
  let sign: CGFloat = rtl ? -1 : 1
  for d: CGFloat in [0, 10, 26] { assert(DetailBackGesturePolicy.starts(x: rtl ? w-d : d, width:w, rtl:rtl)) }
  for d: CGFloat in [-1, 26.01, 27, 100] { assert(!DetailBackGesturePolicy.starts(x: rtl ? w-d : d, width:w, rtl:rtl)) }
  assert(DetailBackGesturePolicy.horizontal(x: sign*20,y:10,rtl:rtl))
  assert(!DetailBackGesturePolicy.horizontal(x: sign*15,y:10,rtl:rtl))
  assert(!DetailBackGesturePolicy.horizontal(x: -sign*30,y:0,rtl:rtl))
  assert(!DetailBackGesturePolicy.horizontal(x: sign*10,y:50,rtl:rtl))
  let threshold = min(120, max(72,w*0.22))
  func commit(_ dx: CGFloat, _ dy: CGFloat = 0, _ v: CGFloat = 0) -> Bool {
   DetailBackGesturePolicy.commits(x: sign*dx,y:dy,velocity:sign*v,width:w,rtl:rtl)
  }
  assert(commit(threshold)); assert(!commit(threshold-0.01))
  assert(!commit(35.99,0,1000)); assert(commit(36,0,650)); assert(!commit(36,0,649.99))
  assert(!commit(200,0,-100)); assert(!commit(200,300,900))
  assert(!commit(-200,0,900)); assert(!commit(0,0,2000))
  print("PASS production detail back policy width=\(w) rtl=\(rtl)")
 }
}
'''
if not shutil.which('swiftc'):
    if sys.platform=='darwin': raise RuntimeError('swiftc mandatory on macOS')
    print('SKIP Swift execution locally (Linux); required in macOS release CI')
else:
    with tempfile.TemporaryDirectory() as td:
        src=Path(td)/'main.swift'; binary=Path(td)/'back'
        src.write_text('import Foundation\n'+policy+main)
        subprocess.run(['swiftc',str(src),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
print('PASS completion-only wiring; exact prior stock-pop state restored; visible top/history/modal guards')
