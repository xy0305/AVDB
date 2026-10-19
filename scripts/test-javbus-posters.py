"""Production JavBus parser/selection fixtures, invoked by test-detail-posters CI."""
from pathlib import Path
import shutil, subprocess, tempfile, json
root=Path(__file__).resolve().parents[1]
services=root/'AVDB/Services'
fixture=(root/'scripts/fixtures/javbus-SSIS-794.html').read_text()
fixture2=(root/'scripts/fixtures/javbus-WAAA-113.html').read_text()
source='\n'.join((services/f).read_text() for f in ['JavRankingCore.swift','TenhowActorLinks.swift','TenhowPoster.swift','JavBusPoster.swift','DetailPosterPolicy.swift'])
# Foundation CGRect works on Darwin; share the exact production crop implementation.
image=(services/'ImageLoader.swift').read_text()
front='public enum FrontPosterPolicy {'+image.split('public enum FrontPosterPolicy {',1)[1].split('\n/// 图片加载器（单例）',1)[0]
source+='\nenum JavDBConstants { static let imageCDNHost="tp.spfcas.com"; static let webCDNHost="c0.jdbstatic.com" }\n'+front
source+='\nlet fixture = '+json.dumps(fixture,ensure_ascii=False)+'\nlet fixture2 = '+json.dumps(fixture2,ensure_ascii=False)+'\n'
source+=r'''
@main struct JavBusRegression {
 static func main() async throws {
    let page=JavBusPoster.page(number:"SSIS-794")!
    func parse(_ html: String, _ n: String = "SSIS-794", _ url: URL? = nil) throws -> [String] {
        try JavBusPoster.images(html:html,number:n,finalURL:url ?? page)
    }
    let main="https://www.javbus.com/pics/cover/9s9e_b.jpg"
    assert(try parse(fixture) == [main])
    assert(try parse(fixture2,"WAAA-113",JavBusPoster.page(number:"WAAA-113")!) == ["https://www.javbus.com/pics/cover/8ihl_b.jpg"])
    let thumb=fixture.replacingOccurrences(of:"<img src=\"/pics/cover/9s9e_b.jpg\"",with:"<img src=\"/pics/thumb/evil.jpg\"")
    assert(try parse(thumb) == [main]) // href, never thumbnail src.
    for wrong in ["SSIS-7940","XSSIS-794","SSIS-0794","SSIS-795","FC2-PPV-794"] {
        assert(try parse(fixture,wrong).isEmpty)
    }
    for wrong in ["FC2-PPV-1234567","FC2-1234567","title SSIS-794","SSIS-794-U","SSIS-0","SSIS-000","SSIS-794/../X"] {
        assert(JavBusPoster.number(wrong) == nil)
    }
    for marker in ["Age Verification","id=\"ageVerify\"","/doc/driver-verify","cf-chl-","CAPTCHA","challenge-platform"] {
        assert(try parse(marker+fixture).isEmpty)
    }
    assert(try parse(fixture,"SSIS-794",URL(string:"https://www.javbus.com/SSIS-795")!).isEmpty)
    assert(try parse(fixture+fixture).isEmpty)
    assert(try parse(fixture.replacingOccurrences(of:"識別碼:",with:"Title:")).isEmpty)
    for bad in ["http://www.javbus.com/pics/cover/9s9e_b.jpg","https://www.javbus.com.evil.test/pics/cover/9s9e_b.jpg","https://127.0.0.1/pics/cover/9s9e_b.jpg","https://[::1]/pics/cover/9s9e_b.jpg","https://user@www.javbus.com/pics/cover/9s9e_b.jpg","https://www.javbus.com:443/pics/cover/9s9e_b.jpg","https://www.javbus.com/pics/cover/9s9e_b.jpg?x=1","https://www.javbus.com/pics/cover/9s9e_b.jpg#x","https://www.javbus.com/pics/thumb/9s9e.jpg","https://www.javbus.com/pics/sample/9s9e_b.jpg","https://photo.javbus.com/pics/cover/9s9e_b.jpg","https://www.javbus.com/pics/cover/%39s9e_b.jpg"] {
        assert(!JavBusPoster.allowedImage(URL(string:bad)!))
    }
    assert(JavBusPoster.allowedImage(URL(string:main)!))
    let crop=FrontPosterPolicy.cropRect(width:800,height:538,source:main,validatedJacket:true)!
    assert(Int(crop.width)==376 && Int(crop.height)==538 && Int(crop.minX)==424)
    assert(FrontPosterPolicy.cropRect(width:1920,height:1080,source:main,validatedJacket:true)==nil)
    assert(FrontPosterPolicy.cropRect(width:538,height:800,source:main,validatedJacket:true)==nil)
    let bus=DetailPosterQuality(source:main,width:376,height:538,originalPortrait:false)
    let amazon=DetailPosterQuality(source:"amazon",width:1050,height:1500,originalPortrait:true)
    assert(DetailPosterQuality.winner([bus,amazon])?.source=="amazon")
    assert(!DetailPosterPolicy.eligible(width:800,height:538))
    let free:[String]=await DetailPosterSelection.collect(sources:["dmm","javdb"],budget:0.5,supplemental:{ _ in [main] }) { s,_ in
        try? await Task.sleep(nanoseconds:20_000_000); return s
    }
    assert(Set(free)==["dmm","javdb",main])
    let all=["dmm1","dmm2","javdb1","javdb2","mgs1","mgs2"]
    let full:[String]=await DetailPosterSelection.collect(sources:all,budget:0.5,supplemental:{ _ in [main] }) { s,_ in
        try? await Task.sleep(nanoseconds:20_000_000); return s
    }
    assert(Set(full)==Set(all)) // no provider displaced or seventh attempt.
    let reserved:[String]=await DetailPosterSelection.collect(sources:["dmm","javdb"],budget:0.5,discover:{ _ in
        try? await Task.sleep(nanoseconds:30_000_000);return ["tenhow","amazon","exactDMM"]
    },supplemental:{ _ in [main] }) { s,_ in
        try? await Task.sleep(nanoseconds:40_000_000);return s
    }
    assert(Set(reserved)==["dmm","javdb","tenhow","amazon","exactDMM",main])
    let start=ProcessInfo.processInfo.systemUptime
    let slow:[String]=await DetailPosterSelection.collect(sources:["dmm"],budget:0.5,supplemental:{ _ in
        do { try await Task.sleep(nanoseconds:1_000_000_000) } catch { return [] }; return [main]
    }) { s,_ in s }
    assert(slow==["dmm"] && ProcessInfo.processInfo.systemUptime-start<0.3)
    print("PASS production JavBus exact identity, main-href, allowlist, age/WAF rejection, effective-front quality, reserved baseline slots, no metadata wait")
 }
}
'''
# Swift assert's autoclosure cannot throw; compute inside a nonthrowing helper.
source=source.replace('func parse(_ html: String, _ n: String = "SSIS-794", _ url: URL? = nil) throws -> [String] {\n        try JavBusPoster.images', 'func parse(_ html: String, _ n: String = "SSIS-794", _ url: URL? = nil) -> [String] {\n        (try? JavBusPoster.images').replace('finalURL:url ?? page)\n    }','finalURL:url ?? page)) ?? []\n    }').replace('assert(try parse(', 'assert(parse(')
source = 'import CoreGraphics\n' + source
assert 'supplemental: supplemental' in (services/'DetailPosterResolver.swift').read_text()
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as td:
        p=Path(td);(p/'main.swift').write_text(source)
        subprocess.run(['swiftc','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True,timeout=20)
else:
    print('PASS JavBus fixture/static wiring; production Swift runtime requires macOS CI')
