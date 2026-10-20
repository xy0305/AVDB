"""Neutral image/source policy regressions; actual Swift+ImageIO runs on macOS CI."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'AVDB/Services/ImageLoader.swift').read_text()
policy = source.split('public enum FrontPosterPolicy {',1)[1].split('\n/// 图片加载器（单例）',1)[0]
policy = 'public enum FrontPosterPolicy {' + policy
sampler = source.split('    private static func downsample(',1)[1].split('\n    /// 清空缓存',1)[0]
sampler = 'func downsample(' + sampler
sampler = sampler.replace('-> UIImage?', '-> CGImage?').replace('return UIImage(cgImage: cgImage)', 'return cgImage')
swift = '''import Foundation
import CoreGraphics
import ImageIO
enum JavDBConstants { static let imageCDNHost="tp.spfcas.com"; static let webCDNHost="c0.jdbstatic.com" }
''' + policy + '\n' + sampler + r'''
let wrap="https://tp.spfcas.com/key/covers/aa/test.jpg"
let thumb="https://tp.spfcas.com/key/small_covers/aa/test.jpg"
assert(FrontPosterPolicy.sources(thumb:thumb,cover:wrap) == [wrap,thumb])
for type in ["1", "2", "3", "uncensored", "western", "fc2"] {
    assert(FrontPosterPolicy.usesOriginal(type:type,number:"ANY-123"))
    assert(FrontPosterPolicy.sources(thumb:thumb,cover:wrap,original:true) == [thumb,wrap])
}
for code in ["HEYZO-3953", "HEYZO3953", "FC2-PPV-1234567", "FC2-1234567", "Tushy.2026.10.11", "Unknown-42"] {
    assert(FrontPosterPolicy.usesOriginal(type:nil,number:code))
}
assert(!FrontPosterPolicy.usesOriginal(type:"0",number:"IPX-247"))
assert(!FrontPosterPolicy.usesOriginal(type:nil,number:"SSIS-001"))
assert(FrontPosterPolicy.sources(thumb:nil,cover:wrap,original:true) == [wrap])
assert(FrontPosterPolicy.sources(thumb:"https://example.test/portrait.jpg",cover:"https://example.test/wide.jpg").first == "https://example.test/portrait.jpg")
assert(FrontPosterPolicy.sources(thumb:nil,cover:nil).isEmpty)
assert(FrontPosterPolicy.sources(thumb:"",cover:wrap) == [wrap])
assert(FrontPosterPolicy.sources(thumb:wrap,cover:wrap) == [wrap])
assert(!FrontPosterPolicy.isKnownWrap("https://tp.spfcas.com.evil.test/covers/test.jpg"))
for (w,h) in [(147,200),(735,1000),(538,800),(100,100),(1920,1080),(0,538),(800,0)] {
    assert(FrontPosterPolicy.cropRect(width:w,height:h,source:wrap) == nil)
}
assert(FrontPosterPolicy.cropRect(width:800,height:538,source:"https://example.test/photo.jpg") == nil)
assert(FrontPosterPolicy.cropRect(width:800,height:538,source:thumb) == nil)
let box=FrontPosterPolicy.cropRect(width:800,height:538,source:wrap)!
assert(box == CGRect(x:424,y:0,width:376,height:538))
// Neutral jacket: red back at left, green front at right. No media downloads.
// Explicit device-RGB and byte order: avoid implicit sRGB conversion in pixel assertions.
let flags=CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
let ctx=CGContext(data:nil,width:800,height:538,bitsPerComponent:8,bytesPerRow:800*4,
                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags)!
ctx.setShouldAntialias(false)
ctx.setFillColor(CGColor(colorSpace:ctx.colorSpace!,components:[1,0,0,1])!);ctx.fill(CGRect(x:0,y:0,width:800,height:538))
ctx.setFillColor(CGColor(colorSpace:ctx.colorSpace!,components:[0,1,0,1])!);ctx.fill(box)
let original=ctx.makeImage()!
let front=original.cropping(to:box)!
assert(front.width == 376 && front.height == 538)
let check=CGContext(data:nil,width:376,height:538,bitsPerComponent:8,bytesPerRow:376*4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags)!
check.interpolationQuality = .none
check.setShouldAntialias(false)
check.draw(front,in:CGRect(x:0,y:0,width:376,height:538))
let pixels=check.data!.assumingMemoryBound(to:UInt8.self)
for i in stride(from:0,to:376*538*4,by:4) { assert(pixels[i] == 0 && pixels[i+1] == 255 && pixels[i+2] == 0, "neutral pixel at \(i): \(pixels[i]),\(pixels[i+1]),\(pixels[i+2])") }
assert(original.width == 800 && original.height == 538) // originals unmodified
// Exercise production ImageIO downsample with EXIF rotation, not swapped math.
let data=NSMutableData()
let dest=CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil)!
CGImageDestinationAddImage(dest,original,[kCGImagePropertyOrientation:6] as CFDictionary)
assert(CGImageDestinationFinalize(dest))
let rotated=downsample(data as Data,maxPixelSize:1200)!
assert(rotated.width == 538 && rotated.height == 800)
assert(FrontPosterPolicy.cropRect(width:rotated.width,height:rotated.height,source:wrap) == nil)
assert(downsample(Data(),maxPixelSize:1200) == nil)
print("PASS actual Swift source priority, right-front neutral pixels, portrait/landscape guards, EXIF orientation, originals")
'''
if shutil.which('swift'):
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)/'posters.swift';path.write_text(swift)
        subprocess.run(['swift',str(path)],check=True)
else:
    print('Swift unavailable locally: runtime image/policy tests deferred to macOS CI')
assert 'kCGImageSourceCreateThumbnailWithTransform: true' in source
assert 'posterCache.totalCostLimit = 48 * 1024 * 1024' in source
assert 'posterInFlight[key]' in source
assert 'contentMode: .fill, maxPixelSize: maxPixelSize, frontPoster: !original' in source
assert 'FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)' in source
assert 'landscapeFallback = landscapeFallback ?? (img, candidate)' in source
assert 'publish(landscapeFallback.image, identity: identity, source: landscapeFallback.source)' in source
assert '.allowsHitTesting(false)' in source
for name in ['Components/JAVDBUI','Components/GlassBookFlipView','Home/DailyDrawView','Rankings/RankingsView','User/LibraryFeaturesView']:
    assert 'MoviePosterImage(movie: movie' in (root/f'AVDB/Views/{name}.swift').read_text()
assert 'thumbURL: record.thumbURL ?? record.coverURL' in (root/'AVDB/Views/User/LibraryFeaturesView.swift').read_text()
detail=(root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'JavDBImage(url: movie.coverURL ?? movie.thumbURL, fallbackURL: movie.hdCoverURL)' in detail
assert 'FrontPosterPolicy' not in detail
print('PASS list-only rendering contracts, bounded caches, no new detail requests or gesture changes')
