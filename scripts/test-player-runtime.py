from pathlib import Path
import subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'AVDB/Views/Player/NativeLUT.swift').read_text()
if sys.platform != 'darwin':
    print('SKIP actual Swift/CoreImage numerical tests: requires macOS (run in CI)')
    sys.exit(0)
reveal=s[s.index('final class LUTRevealState'):s.index('@MainActor\nfinal class NativeLUTController')]
def method(name,next_name):
    return s[s.index('    func '+name+'('):s.index('    func '+next_name+'(')]
# Execute the shipping toggle/reset/reanalyze implementations, with an in-memory item adapter.
# No decoder or MediaPipe substitute is used for numerical composition below.
controller='''@MainActor final class TransitionHarness {
 var supported = true
 var enabled = false
 var parameters = LUTParameters()
 var composition: Int? = 7
 var item: Item? = Item()
 var original: Int? = nil
 var analysisGeneration = 0
 var busy = false
 var requested = false
 var status = ""
 var cachedCube: Data? = Data()
 var sharpen = false
 var deband = false
 var comparison = false
 var buildGeneration = 0
 var buildTask: Task<Void, Never>?
 func apply() { item?.videoComposition = enabled ? composition : original }
 let reveal = LUTRevealState()
'''+method('toggle','reanalyze')+method('reanalyze','reset')+method('reset','apply')+'}\n'
swift='''import Foundation
import CoreImage
import AVFoundation
struct UIAccessibility { static var isReduceMotionEnabled = false }
struct LUTParameters { }
final class Item { var videoComposition: Int? }
'''+reveal+controller+'''
func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
 var rgba = [UInt8](repeating: 0, count: 4)
 CIContext().render(image, toBitmap: &rgba, rowBytes: 4,
                    bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
 return rgba
}
let extent = CGRect(x: 12, y: 5, width: 100, height: 20)
let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
for fraction in [-1.0, 0, 0.25, 0.5, 1, 2] {
 let result = LUTRevealState.composite(original: red, filtered: blue, originalFraction: fraction)
 precondition(result.extent == extent)
 for x in 12..<112 {
   let p = pixel(result, x: x, y: 10)
   let original = Double(x - 12) < 100 * max(0, min(1, fraction))
   precondition(original ? p[0] > 250 && p[2] < 5 : p[2] > 250 && p[0] < 5)
 }
}
let reveal = LUTRevealState()
reveal.setCovered(true); reveal.begin(reduceMotion: false)
precondition(reveal.originalFraction() == 0.5)
reveal.setCovered(false)
let now = ProcessInfo.processInfo.systemUptime
precondition(abs(reveal.originalFraction(now: now) - 0.5) < 0.01)
precondition(abs(reveal.originalFraction(now: now + 0.85) - 0.25) < 0.01)
precondition(reveal.originalFraction(now: now + 2) == 0)
reveal.cancel(); precondition(reveal.originalFraction() == 0)
reveal.begin(reduceMotion: true); precondition(reveal.originalFraction() == 0)
MainActor.assumeIsolated {
 let c = TransitionHarness()
 for _ in 0..<20 {
   c.toggle(); precondition(c.enabled && c.item?.videoComposition == 7)
   c.busy = true
   let token = c.analysisGeneration
   c.toggle(); precondition(!c.enabled && c.item?.videoComposition == nil && !c.busy)
   precondition(c.analysisGeneration != token)
 }
 c.composition = nil; c.cachedCube = nil; c.toggle(); precondition(c.enabled && c.requested)
 c.busy = true; c.toggle(); c.toggle(); precondition(c.enabled && c.requested && !c.busy)
 c.reset(); precondition(!c.enabled && c.composition == nil && c.requested)
 c.reanalyze(); precondition(c.requested && c.item?.videoComposition == nil)
 c.supported = false; c.toggle(); precondition(!c.enabled)
}
print("PASS actual CoreImage 600 pixels/nonzero extent/wipe bounds; shipping toggle/reset/reanalyze methods 20 cycles, pending cancellation, Reduce Motion and covered reveal")
'''
with tempfile.TemporaryDirectory() as tmp:
    f=Path(tmp)/'test.swift'; f.write_text(swift)
    subprocess.run(['swift',str(f)],check=True)
