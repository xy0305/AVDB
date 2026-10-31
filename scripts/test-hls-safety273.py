from pathlib import Path
import subprocess,tempfile,json,re,hashlib,sys
r=Path(__file__).resolve().parents[1];s=(r/'AVDB/Views/Player/NativeHLSLUTSurface.swift').read_text();c=(r/'AVDB/Views/Player/NativeLUT.swift').read_text();p=(r/'AVDB/Views/Player/PlayerView.swift').read_text()
# Build 295: re-locked after noteSeek() + visible-stall fallback (seek / reopen black-with-audio fix).
assert hashlib.sha256(s.encode()).hexdigest()=='be2152323ede0c693c0991a8ea743937865219a4b6d109814bb9aa6cbd98d2fa', 'runtime must remain exact verified production file'
assert 'func noteSeek()' in s and '解码停滞，已回原画' in s
assert 'guard !protected else' in s and '不绕过 DRM' in s
# Build 279: decoded SDR buffers are tagged sRGB (no BT.709-OETF→sRGB lift) in presentation AND analysis.
assert 'CIImage(cvPixelBuffer: buffer, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])' in s
assert 'var source = Self.sourceImage(buffer)' in s and 'CIImage(cvPixelBuffer: buffer)\n' not in s
assert 'NativeHLSLUTSurface.sourceImage(buffer)' in c and 'CIImage(cvPixelBuffer: buffer)' not in c
assert '0x64766831' in s and '0x64766865' in s
assert 'guard self.generation == revision else { return }' in s
assert 'generation += 1; link?.invalidate()' in s
assert 'self.generation == sourceGeneration' in c and 'self.buildGeneration == revision' in c
assert 'surface?.copyDecodedFrameForAnalysis(force: true)' in c
assert '最多3帧' in c
assert 'copyAnalysisFrame' in c
assert '120_000_000' in c  # sampleIntervalMs aligned
assert '400_000_000' in c  # enable delay
assert 'filterCrossfadeSeconds' in c
assert 'prepareForcedAnalysisFrame()' in c
assert ('原版 6.7.8' in c or '原版6.7.8' in c)
assert '开启 LUT（自动分析）' in c and '关闭 LUT（恢复原画）' in c
assert '重置并恢复原画' in c
assert p.index('NativeLUTOverlay(model: lut)') < p.index('SubtitlePresentationOverlay(')
assert 'view.isUserInteractionEnabled = false' in c
assert 'SpatialTapGesture' in p and 'Slider(' in p
assert 'bringSubviewToFront(view)' in s
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
d=r/'evidence-release';d.mkdir(exist_ok=True)
payload={'runtimeExactSHA256':hashlib.sha256(s.encode()).hexdigest(),'lateGenerationSourceGuards':'PASS','overlayOrdering':'PASS','preservedSpatialTapAndSlider':'PASS','lut678UX':'PASS','forcedAnalysisAPI':'PASS','realEncryptedDRMAssetTested':False}
if sys.platform!='darwin':
    payload['exactProductionDecodedMetadataPredicate']='NOT RUN (Linux; macOS CI required)'
    payload['syntheticProtectionMetadataGuard']='NOT RUN (Linux; macOS CI required)'
    (d/'safety.json').write_text(json.dumps(payload,indent=2))
    print('PASS safety and App wiring source contracts on Linux; Swift predicate NOT RUN')
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
 f=Path(tmp)/'main.swift';f.write_text(code);subprocess.run(['swift',str(f)],check=True)
payload['exactProductionDecodedMetadataPredicate']='PASS'
payload['syntheticProtectionMetadataGuard']='PASS'
(d/'safety.json').write_text(json.dumps(payload,indent=2))
print('PASS safety and App wiring source contracts; real DRM/PiP/AirPlay are not claimed')
