#!/usr/bin/env python3
"""MGStage synthetic regression runner; never a live-site/pixel evidence claim."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
services = root / 'AVDB/Services'
helper = (services / 'MGStagePoster.swift').read_text()
resolver = (services / 'DetailPosterResolver.swift').read_text()
policy = (services / 'DetailPosterPolicy.swift').read_text()
assert 'movie.type == "0"' in resolver
assert 'async let mgs = discoverMGStage' in resolver
assert 'async let tenhow = discoverTenhow' in resolver
assert 'derive: !original && !nativeMGS' in resolver
assert 'httpCookieStorage = nil' in helper and 'urlCredentialStorage = nil' in helper
assert 'completionHandler(nil)' in helper
assert 'data.count < 768 * 1024' in helper
assert 'maxAttempts = 6' in policy and 'concurrency = 2' in policy and 'totalBudget: TimeInterval = 12' in policy
assert 'MGStagePoster.swift in Sources' in (root / 'AVDB.xcodeproj/project.pbxproj').read_text()
print('PASS source integration guards (not Swift compilation)')
swift = r'''
@main struct MGStageRegression {
    static func main() {
        let id = "300MIUM-001"
        let image = "https://image.mgstage.com/images/prestigepremium/300mium/001/pf_o1_300mium-001.jpg"
        let page = MGStagePoster.page(id)!
        func html(_ image: String) -> String { "<a href='\(image)' id='EnlargeImage'>cover</a>" }
        func match(_ body: String) -> [String] { MGStagePoster.images(html: body, pageURL: page, id: id) }
        precondition(MGStagePoster.number(" 300mium-001 ") == id)
        precondition(MGStagePoster.evidencedID(number: id, metadata: [image]) == id)
        precondition(MGStagePoster.evidencedID(number: "200MIUM-001", metadata: [image]) == nil)
        precondition(MGStagePoster.evidencedID(number: "MIUM-001", metadata: [image]) == nil)
        precondition(MGStagePoster.evidencedID(number: "300MIUN-001", metadata: [image]) == nil)
        precondition(MGStagePoster.evidencedID(number: "300MIUM-1", metadata: [image]) == nil)
        precondition(match(html(image)) == [image])
        precondition(match(html(image) + html(image)) == [image])
        precondition(match(html(image.replacingOccurrences(of: "/001/", with: "/002/"))).isEmpty)
        precondition(match(html(image.replacingOccurrences(of: "pf_o1_", with: "cap_e_"))).isEmpty)
        precondition(match(html(image.replacingOccurrences(of: "pf_o1_", with: "pb_e_"))).isEmpty)
        precondition(match(html(image.replacingOccurrences(of: "pf_o1_", with: "pf_e_")) + html(image)).isEmpty)
        precondition(match("<img class='enlarge_image' src='\(image)'>").isEmpty)
        precondition(match("<ul id='sample-photo'><a href='\(image)'>still</a></ul>").isEmpty)
        precondition(match("<!--" + html(image) + "-->").isEmpty)
        precondition(match("<script>" + html(image) + "</script>").isEmpty)
        precondition(match(html(image) + "captcha").isEmpty)
        precondition(match("<html>changed layout</html>").isEmpty)
        precondition(match(html(image) + "<link rel='canonical' href='https://www.mgstage.com/product/product_detail/200MIUM-001/'>").isEmpty)
        for bad in [image + "?size=large", image + "#x", image.replacingOccurrences(of: "https:", with: "http:"), image.replacingOccurrences(of: "image.mgstage.com", with: "image.mgstage.com.evil.test"), image.replacingOccurrences(of: "https://", with: "https://user:pass@"), image.replacingOccurrences(of: "300mium/", with: "300m%69um/")] {
            precondition(match(html(bad)).isEmpty)
        }
        precondition(!MGStagePoster.allowedPage(URL(string: page.absoluteString + "?x=1")!, id: id))
        precondition(MGStagePoster.images(html: html(image), pageURL: MGStagePoster.page("200MIUM-001")!, id: id).isEmpty)
        let prestige = "https://image.mgstage.com/images/prestige/abf/001/pf_e_abf-001.jpg"
        precondition(MGStagePoster.evidencedID(number: "ABF-001", metadata: [prestige]) == "ABF-001")
        print("PASS MGStage synthetic Swift identity/cover fixtures")
    }
}
'''
if not shutil.which('swiftc'):
    print('SKIP Swift fixtures: swiftc unavailable; no compiled/runtime claim')
else:
    with tempfile.TemporaryDirectory() as directory:
        p = Path(directory)
        # Test the production pure parser, not a Python reimplementation.
        (p / 'main.swift').write_text(helper.split('private final class MGStageRedirectGuard:')[0] + '\n' + swift)
        subprocess.run(['swiftc', '-parse-as-library', str(p / 'main.swift'), '-o', str(p / 'tests')], check=True)
        subprocess.run([str(p / 'tests')], check=True)
