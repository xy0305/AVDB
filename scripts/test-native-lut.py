from pathlib import Path
import subprocess, tempfile
source=Path('AVDB/Views/Player/NativeLUT.swift').read_text()
pure=source[source.index('struct LUTParameters:'):source.index('@MainActor')]
test='''
let p = LUTParameters()
let data = NativeLUT.cube(p)
precondition(data.count == 33*33*33*4*4)
let f = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
precondition(f.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
for i in stride(from: 3, to: f.count, by: 4) { precondition(f[i] == 1) }
precondition(f[0] == 0 && f[1] == 0 && f[2] == 0)
precondition(f[4*32] > 0.99 && f[4*32+1] == 0 && f[4*32+2] == 0)
precondition(f[4*33*32+1] > 0.99)
precondition(f[4*33*33*32+2] > 0.99)
let sample = Array(repeating:[0.60,0.40,0.30],count:200)
let result = NativeLUT.search(sample)
precondition(result.values.count == 7 && result.values.allSatisfy { $0.isFinite })
precondition(NativeLUT.cube(result).count == data.count)
print("PASS: complete cube length, RGBA bounds, alpha, RGB axis order, native search")
'''
with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'main.swift';p.write_text('import Foundation\n'+pure+test)
    subprocess.run(['swift',str(p)],check=True)
