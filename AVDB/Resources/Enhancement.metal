#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;
extern "C" { namespace coreimage {
// Independent deterministic single-pass range/edge guarded debanding.
float4 avdbDeband(sampler image, float threshold, float radius, destination dest) {
    float2 p = image.coord();
    float4 c = image.sample(p);
    if (c.a < 0.999) return c;
    float3 sum = c.rgb; float weight = 1.0;
    const float2 dirs[8] = {float2(1,0),float2(-1,0),float2(0,1),float2(0,-1),float2(.707,.707),float2(-.707,.707),float2(.707,-.707),float2(-.707,-.707)};
    for (int i=0;i<8;i++) {
        float4 near = image.sample(image.transform(dest.coord()+dirs[i]));
        float4 far = image.sample(image.transform(dest.coord()+dirs[i]*radius));
        float4 mid = image.sample(image.transform(dest.coord()+dirs[i]*radius*.5));
        float edge = max(max(abs(near.r-c.r),abs(near.g-c.g)),abs(near.b-c.b));
        float delta = max(max(abs(far.r-c.r),abs(far.g-c.g)),abs(far.b-c.b));
        float middle = max(max(abs(mid.r-c.r),abs(mid.g-c.g)),abs(mid.b-c.b));
        if (edge < threshold && delta < threshold && middle < threshold && far.a > .999) {sum += far.rgb;weight += 1.0;}
    }
    return float4(sum/weight,c.a);
}
}}
