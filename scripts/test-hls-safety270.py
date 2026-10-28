from pathlib import Path
import subprocess,tempfile,json,re,hashlib
r=Path(__file__).resolve().parents[1];s=(r/'AVDB/Views/Player/NativeHLSLUTSurface.swift').read_text();c=(r/'AVDB/Views/Player/NativeLUT.swift').read_text();p=(r/'AVDB/Views/Player/PlayerView.swift').read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='53293ddbc4966cb0dbd1b39352d004b91c1897d5173674e0cbce84350be328ea', 'runtime must remain exact verified production file'
assert 'guard !protected else' in s and '不绕过 DRM' in s
assert '0x64766831' in s and '0x64766865' in s
assert 'guard self.generation == revision else { return }' in s
assert 'generation += 1; link?.invalidate()' in s
assert 'self.generation == sourceGeneration' in c and 'self.buildGeneration == revision' in c
assert 'surface?.copyDecodedFrameForAnalysis()' in c
assert p.index('NativeLUTOverlay(model: lut)') < p.index('SubtitlePresentationOverlay(')
assert 'view.isUserInteractionEnabled = false' in c
assert 'SpatialTapGesture' in p and 'Slider(' in p
# Execute the EXACT production decoded-color predicate on synthetic CoreVideo metadata.
a=s.index('    private func isKnownSDR(');b=s.index('    fileprivate func draw(',a)
method=s[a:b].replace('private func','func',1)
code='''import Foundation
import CoreVideo
import CoreMedia
struct Gate {
'''+method+'''}
func frame(_ transfer: CFString?, primaries: CFString? = kCVImageBufferColorPrimaries_ITU_R_709_2, matrix: CFString? = kCVImageBufferYCbCrMatrix_ITU_R_709_2) -> CVPixelBuffer {
 var result: CVPixelBuffer?
 precondition(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess)
 let buffer = result!
 if let transfer { CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate) }
 if let primaries { CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, primaries, .shouldPropagate) }
 if let matrix { CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, matrix, .shouldPropagate) }
 return buffer
}
let gate = Gate()
precondition(gate.isKnownSDR(frame(kCVImageBufferTransferFunction_ITU_R_709_2)))
precondition(gate.isKnownSDR(frame(kCVImageBufferTransferFunction_sRGB, matrix:nil)))
precondition(!gate.isKnownSDR(frame(nil)))
precondition(!gate.isKnownSDR(frame(kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)))
precondition(!gate.isKnownSDR(frame(kCVImageBufferTransferFunction_ITU_R_2100_HLG)))
precondition(!gate.isKnownSDR(frame(kCVImageBufferTransferFunction_ITU_R_709_2, primaries:nil)))
precondition(!gate.isKnownSDR(frame(kCVImageBufferTransferFunction_ITU_R_709_2, primaries:kCVImageBufferColorPrimaries_ITU_R_2020)))
precondition(!gate.isKnownSDR(frame(kCVImageBufferTransferFunction_ITU_R_709_2, matrix:kCVImageBufferYCbCrMatrix_ITU_R_601_4)))
print("PASS exact production metadata predicate: SDR positive, unknown/PQ/HLG/missing primaries/BT2020/BT601 negative")
'''
# Protection-state metadata guard extracted from production, NOT actual encrypted media.
guard=re.search(r'guard !protected else \{ self.hide\("受保护内容使用原画；不绕过 DRM"\); return \}',s).group(0)
code+='\nfunc syntheticProtection(_ protected: Bool) -> Bool { '+guard.replace('self.hide("受保护内容使用原画；不绕过 DRM"); return','return false')+'; return true }\nprecondition(!syntheticProtection(true)); precondition(syntheticProtection(false))\n'
with tempfile.TemporaryDirectory() as tmp:
 f=Path(tmp)/'main.swift';f.write_text(code);subprocess.run(['swift',str(f)],check=True)
d=r/'evidence-release';d.mkdir(exist_ok=True)
(d/'safety.json').write_text(json.dumps({'runtimeExactSHA256':hashlib.sha256(s.encode()).hexdigest(),'exactProductionDecodedMetadataPredicate':'PASS','syntheticProtectionMetadataGuard':'PASS','realEncryptedDRMAssetTested':False,'lateGenerationSourceGuards':'PASS','overlayOrdering':'PASS','preservedSpatialTapAndSlider':'PASS'},indent=2))
print('PASS safety and App wiring source contracts; real DRM/PiP/AirPlay are not claimed')
