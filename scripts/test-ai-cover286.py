#!/usr/bin/env python3
"""Build 286: AI 增强 controls moved off the cover art (metadata-row chip, cover long-press compare, stacked viewer)
+ Build 285 on-device AI cover enhancer (Core ML super-resolution) and cover-source fixes.
Executes the shipping Swift policy / parser / resolver helpers with swiftc (Linux or macOS)."""
import json, os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; S = ROOT / 'AVDB/Services'
read = lambda p: (ROOT / p).read_text()
detail, user = read('AVDB/Views/Detail/MovieDetailView.swift'), read('AVDB/Views/User/UserView.swift')
views, engine, enh = read('AVDB/Views/Detail/AICoverViews.swift'), read('AVDB/Services/AICoverSREngine.swift'), read('AVDB/Services/AICoverEnhancer.swift')
resolver, loader, meta = read('AVDB/Services/DetailPosterResolver.swift'), read('AVDB/Services/ImageLoader.swift'), read('AVDB/Services/CatalogueMetadata.swift')
pbx = read('AVDB.xcodeproj/project.pbxproj'); plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())
# ---- wiring
chrome = detail.split('private var detailChrome: some View {', 1)[1].split('private func chromeButton', 1)[0]
hero = detail.split('private func portraitHero', 1)[1].split('private func portraitMetadata', 1)[0]
viewer = views.split('struct AICoverViewer: View {', 1)[1].split('private var sizeText', 1)[0]
assert 'AICover' not in chrome and 'aiCover' not in chrome, '286: nothing AI in the top chrome over the cover'
assert 'AICoverHeroControl' not in detail + views, '286: old over-the-art hero control removed'
assert hero.index('portraitMetadata(movie)') < hero.index('AICoverMetaChip(model: aiCover)') < hero.index('portraitControls(movie)'), '286: chip sits under the metadata row'
assert 'AICoverMetaChip.visible(aiCover)' in hero and '.modifier(AICoverPressToCompare(model: aiCover))' in hero and 'aiCover.viewerTapAllowed' in hero, '286: cover long-press compare, tap guard'
assert '.frame(height: imageHeight + 30)\n            .allowsHitTesting(false)' in hero, '286: gradient passes touches to the cover'
assert 'VStack(spacing: 0)' in viewer and 'GeometryReader' in viewer and '.clipped()' in viewer and 'AICoverBadge()' not in viewer, '286: viewer chrome stacked around (not over) the image'
assert '长按封面也可对比原图' in views and '1_600_000_000' in views and '长按封面可查看原图' in views
assert 'aiCover.display(art.image)' in detail and 'AICoverViewer(image: art.image, model: aiCover)' in detail, 'hero + fullscreen viewer'
assert 'art.sourceURL = winner.source; art.nativeWidth = winner.width; art.nativeHeight = winner.height' in resolver, 'native winner size travels with the artwork'
assert 'AICoverSettingsSection()' in user and 'AICoverEnhanceMode.allCases' in views and ('清除增强缓存' in views or '清除缓存' in views), 'settings 自动/仅手动/关 + cache'
assert 'AICoverHoldToCompare' in views and '按住对比原图' in views and 'AICoverBadge' in views and 'AICoverProgressRing' in views
assert 'Task.detached(priority: .userInitiated)' in enh and ('AICoverDiskCache.shared.store' in enh or 'cache.store(img, encoded: data, key: key)' in enh) and 'AICoverEnhanceGuard.check(manual: false) == .ok' in enh, 'off-main, disk cache, guard'
assert 'MLMultiArray(shape: [1, 3' in engine and 'vImageConvert_Planar16FtoPlanarF' in engine and 'AICoverTilePlan.make' in engine, 'fp16 tiled Core ML'
for f in ['AICoverPolicy.swift', 'AICoverSREngine.swift', 'AICoverEnhancer.swift', 'AICoverViews.swift', 'CoverSR.mlpackage']:
    assert f'{f} in ' in pbx, f'{f} in target'
model = ROOT / 'AVDB/Resources/CoverSR.mlpackage'
assert (model / 'Manifest.json').exists(), 'bundled Core ML model'
weights = sum(p.stat().st_size for p in model.rglob('*') if p.is_file())
assert 10e6 < weights < 95e6, f'model size {weights}'
assert 'AvbaseHQExtras.extras(products: products, number: number)' in meta and 'isHQStoreJacket(source)' in loader and 'DMMJacketOnly.shared.observe' in resolver
assert plist['CFBundleVersion'] == '292' and pbx.count('CURRENT_PROJECT_VERSION = 292;') == 2
swiftc = shutil.which('swiftc')
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift'); sys.exit(0)
shim = '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n'
def run(files, main, marker):
    with tempfile.TemporaryDirectory() as td:
        td = Path(td); paths = []
        for name, text in files:
            (td / name).write_text(shim + text); paths.append(td / name)
        (td / 'main.swift').write_text(main); paths.append(td / 'main.swift')
        subprocess.run([swiftc, '-swift-version', '5', '-o', str(td / 't')] + [str(p) for p in paths], check=True)
        r = subprocess.run([str(td / 't')], capture_output=True, text=True, timeout=120)
        print(r.stdout, end='')
        if r.returncode or marker not in r.stdout: print(r.stderr); sys.exit(marker + ' failed')
run([('AICoverPolicy.swift', read('AVDB/Services/AICoverPolicy.swift'))], read('scripts/AICoverPolicyRegression285.swift'), 'PASS ai285')
run([(n, (S / n).read_text()) for n in ('JavRankingCore.swift', 'TenhowActorLinks.swift', 'TenhowPoster.swift', 'DetailPosterPolicy.swift', 'DMMCoverResolver.swift', 'DMMLabelSeed.swift')],
    read('scripts/CoverSourcesRegression285.swift'), 'PASS cover285')
# ---- avbase extras parser (shipping CatalogueMetadata before the network client)
core = read('AVDB/Services/JavRankingCore.swift')
metadata = meta.split('private final class CatalogueRedirectBlocker:')[0]
models = read('AVDB/Services/ExternalLibraryClient.swift').split('final class ExternalLibraryClient')[0] + read('AVDB/Models/JSONFlex.swift') + read('AVDB/Models/Movie.swift')
stub = 'public enum CoverURLBuilder { public static func coverURLs(for number:String?) -> (poster:String?,backdrop:String?) { (nil,nil) } }\n'
main = r'''
import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) { if !c() { failures += 1; print("FAIL", m) } }
func product(_ pid: String, _ url: String, _ image: String, _ thumb: String = "") -> [String: Any] { ["product_id": pid, "url": url, "image_url": image, "thumbnail_url": thumb] }
let dmm = product("118abf087", "https://al.fanza.co.jp/?lurl=https%3A%2F%2Fwww.dmm.co.jp%2Fmono%2Fdvd%2F-%2Fdetail%2F%3D%2Fcid%3D118abf087%2F&af_id=x&ch=api", "https://pics.dmm.co.jp/mono/movie/adult/118abf087/118abf087pl.jpg", "https://pics.dmm.co.jp/mono/movie/adult/118abf087/118abf087ps.jpg")
let duga = product("prestige-6784", "https://click.duga.jp/ppv/prestige-6784/39588-1", "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg", "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket_240.jpg")
let dugaOther = product("eiten-2295", "https://click.duga.jp/ppv/eiten-2295/39588-1", "https://pic.duga.jp/unsecure/eiten/2295/noauth/jacket.jpg")
let mgs = product("ABF-087", "https://www.mgstage.com/product/product_detail/ABF-087/", "https://image.mgstage.com/images/prestige/sp/abf/087/pake-03_sp-abf-087.jpg", "https://image.mgstage.com/images/prestige/sp/abf/087/h1-06_sp-abf-087.jpg")
let e1 = AvbaseHQExtras.extras(products: [dmm, duga, mgs, dugaOther], number: "ABF-087")
check(e1 == ["https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg", "https://image.mgstage.com/images/prestige/sp/abf/087/pake-03_sp-abf-087.jpg"], "ABF-087: label-matched DUGA + Prestige package, re-release eiten skipped \(e1)")
check(AvbaseHQExtras.extras(products: [dmm, duga, dugaOther], number: "ABF-087").isEmpty, "two DUGA products without an MGS maker → none")
check(AvbaseHQExtras.extras(products: [dmm, dugaOther], number: "ABF-087") == ["https://pic.duga.jp/unsecure/eiten/2295/noauth/jacket.jpg"], "single DUGA product accepted")
let siro = product("SIRO-1690", "https://www.mgstage.com/product/product_detail/SIRO-1690/", "https://image.mgstage.com/images/shiroutotv/siro/1690/pake-03_sp-siro-1690.jpg")
check(AvbaseHQExtras.extras(products: [siro], number: "SIRO-1690").isEmpty, "SIRO 1348 px upscale package never admitted")
let amateur = product("259LUXU-1896", "https://www.mgstage.com/product/product_detail/259LUXU-1896/", "https://image.mgstage.com/images/luxutv/259luxu/1896/pb_e_259luxu-1896.jpg")
check(AvbaseHQExtras.extras(products: [amateur], number: "259LUXU-1896") == ["https://image.mgstage.com/images/luxutv/259luxu/1896/pf_e_259luxu-1896.jpg"], "MGS pb_e → pf_e portrait")
let wrong = product("ABF-088", "https://www.mgstage.com/product/product_detail/ABF-088/", "https://image.mgstage.com/images/prestige/sp/abf/088/pake-03_sp-abf-088.jpg")
check(AvbaseHQExtras.extras(products: [wrong], number: "ABF-087").isEmpty, "other number rejected")
check(AvbaseMetadata.allowedDiscoveredImage(URL(string: "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg")!), "DUGA admitted")
check(!AvbaseMetadata.allowedDiscoveredImage(URL(string: "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg?x=1")!), "DUGA query rejected")
check(!AvbaseHQExtras.isDugaJacket(URL(string: "https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket_240.jpg")!), "DUGA thumb not a jacket")
// End-to-end avbase page → record images keep DMM first, extras after.
let work: [String: Any] = ["work_id": "ABF-087", "prefix": "", "title": "fixture", "products": [dmm, duga, mgs, dugaOther], "actors": []]
let data = try! JSONSerialization.data(withJSONObject: ["props": ["pageProps": ["work": work]]])
let html = "<script id='__NEXT_DATA__' type='application/json'>" + String(data: data, encoding: .utf8)! + "</script>"
let rec = AvbaseMetadata.parse(html: html, number: "ABF-087")!
check(rec.images.first == "https://pics.dmm.co.jp/mono/movie/adult/118abf087/118abf087pl.jpg", "DMM pl stays first \(rec.images)")
check(rec.images.contains("https://pic.duga.jp/unsecure/prestige/6784/noauth/jacket.jpg") && rec.images.contains("https://image.mgstage.com/images/prestige/sp/abf/087/pake-03_sp-abf-087.jpg"), "extras in record images")
if failures == 0 { print("PASS avbase285: DUGA (sole / label-matched), MGS Prestige 1125 package, pf_e portrait, identity + admission") } else { exit(1) }
'''
run([('catalogue.swift', core + metadata + stub + models)], main, 'PASS avbase285')
print('PASS test-ai-cover286 wiring: AI chip below metadata (none over the art) / cover long-press compare / stacked viewer / viewer / settings / disk cache / guard / fp16 tiled Core ML, bundled model, cover-source fixes, version 286')
