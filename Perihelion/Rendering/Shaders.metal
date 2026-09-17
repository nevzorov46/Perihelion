#include <metal_stdlib>
#include "PHShaderTypes.h"

using namespace metal;

// MARK: - Noise

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash12(i), b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float sum = 0, amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        sum += amplitude * valueNoise(p);
        p = p * 2.03 + 17.1;
        amplitude *= 0.5;
    }
    return sum;
}

// MARK: - Fullscreen

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;  // (0,0) top-left
};

vertex FullscreenOut ph_fullscreenVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut out;
    out.position = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
    out.uv = p;
    return out;
}

// Baked once per level into a texture: gradient, nebula, stars.
fragment float4 ph_backgroundFragment(FullscreenOut in [[stage_in]],
                                      constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]],
                                      constant PHBackgroundUniforms &bg [[buffer(PHBufferIndexExtra)]]) {
    float2 px = in.uv * frame.drawableSize;
    float2 p = px / frame.drawableSize.x;
    float3 color = mix(float3(0.0035, 0.004, 0.010), float3(0.008, 0.006, 0.018), in.uv.y);

    float n = fbm(p * 2.4 + bg.seed);
    float n2 = fbm(p * 4.5 - bg.seed * 1.7 + n * 1.5);
    float cloud = smoothstep(0.42, 0.9, n2) * smoothstep(0.35, 0.75, n);
    color += bg.tint.rgb * cloud * 0.045;
    color += float3(0.20, 0.16, 0.42) * pow(n, 4.0) * 0.03;

    const float cellPoints[3] = { 9.0, 24.0, 70.0 };
    const float density[3] = { 0.12, 0.14, 0.22 };
    for (int layer = 0; layer < 3; layer++) {
        float cell = cellPoints[layer] * bg.pixelsPerPoint;
        float2 id = floor(px / cell);
        float h = hash12(id + float(layer) * 31.7 + bg.seed);
        if (h > density[layer]) continue;
        float2 center = (id + 0.2 + 0.6 * hash22(id + float(layer) * 7.3)) * cell;
        float r = (0.35 + 0.55 * float(layer)) * bg.pixelsPerPoint * (0.6 + h / density[layer]);
        float d = length(px - center);
        float light = exp(-d * d / (r * r)) * (0.25 + 0.75 * pow(hash12(id * 1.37), 3.0)) * (0.5 + float(layer) * 0.6);
        // mostly cool white: warm points would read as motes
        float temperature = pow(hash12(id * 2.11 + 5.0), 4.0);
        float3 tint = mix(float3(0.62, 0.72, 1.0), float3(1.0, 0.9, 0.8), temperature);
        color += tint * light * 0.3;
    }
    return float4(color, 1);
}

fragment float4 ph_blitFragment(FullscreenOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return float4(source.sample(s, in.uv).rgb, 1);
}

// MARK: - Spacetime grid

struct GridOut {
    float4 position [[position]];
    float alpha;
};

vertex GridOut ph_gridVertex(uint vid [[vertex_id]],
                             constant PHGridVertex *vertices [[buffer(PHBufferIndexVertices)]],
                             constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]],
                             constant PHGridUniforms &grid [[buffer(PHBufferIndexExtra)]]) {
    float2 p = vertices[vid].position;
    float2 offset = 0;
    float curvature = 0;
    for (int i = 0; i < grid.count; i++) {
        float2 d = grid.masses[i].xy - p;
        float r = length(d) + 1e-3;
        float mu = grid.masses[i].z;
        // An embedding-diagram look, not a physical quantity: lines sag toward mass.
        float sag = min(0.8 * r, 2.4e-4 * mu / (r + 60.0));
        offset += d / r * sag;
        curvature += mu / (r * r + 4000.0);
    }
    GridOut out;
    out.position = frame.worldToClip * float4(p + offset, 0, 1);
    float edge = min(min(p.x, 1600.0 - p.x), min(p.y, 1000.0 - p.y));
    out.alpha = grid.intensity * smoothstep(-40.0, 140.0, edge) * (1.0 + min(curvature * 4e-4, 3.0));
    return out;
}

fragment float4 ph_gridFragment(GridOut in [[stage_in]]) {
    return float4(float3(0.32, 0.36, 0.9) * in.alpha, 0);
}

// MARK: - Ribbons (trails)

struct RibbonOut {
    float4 position [[position]];
    float across;
    float4 color;
};

vertex RibbonOut ph_ribbonVertex(uint vid [[vertex_id]],
                                 constant PHRibbonVertex *vertices [[buffer(PHBufferIndexVertices)]],
                                 constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]]) {
    RibbonOut out;
    out.position = frame.worldToClip * float4(vertices[vid].position, 0, 1);
    out.across = vertices[vid].across;
    out.color = vertices[vid].color;
    return out;
}

fragment float4 ph_ribbonFragment(RibbonOut in [[stage_in]]) {
    float a = 1.0 - in.across * in.across;
    return float4(in.color.rgb * in.color.a * a * a, 0);
}

// MARK: - Sprites

struct SpriteOut {
    float4 position [[position]];
    float2 uv;  // -1 … 1, y up
    float4 color;
    float4 params;
    int kind [[flat]];
    float pixelRadius;
};

vertex SpriteOut ph_spriteVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                 constant PHSprite *sprites [[buffer(PHBufferIndexVertices)]],
                                 constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    PHSprite s = sprites[iid];
    float2 corner = corners[vid];
    float4 center = frame.worldToClip * float4(s.position, 0, 1);
    float pixels = s.radius * frame.pixelsPerUnit;
    SpriteOut out;
    out.position = float4(center.xy + corner * pixels * 2.0 / frame.drawableSize, 0, 1);
    out.uv = corner;
    out.color = s.color;
    out.params = s.params;
    out.kind = s.kind;
    out.pixelRadius = pixels;
    return out;
}

static float2 rotate(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

fragment float4 ph_spriteFragment(SpriteOut in [[stage_in]],
                                  constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]]) {
    float2 uv = in.uv;
    float d = length(uv);
    float aa = 1.5 / max(in.pixelRadius, 1.0);

    switch (in.kind) {
    case PHSpriteGlow: {
        float core = exp(-d * d * 22.0);
        float halo = 0.025 / (d * d + 0.025);
        float a = (core * 0.55 + halo * 0.45) * (1.0 - smoothstep(0.5, 1.0, d));
        return float4(in.color.rgb * a, 0);
    }
    case PHSpriteDisc: {
        float cover = 1.0 - smoothstep(1.0 - aa, 1.0, d);
        return float4(in.color.rgb * cover, in.color.a * cover);
    }
    case PHSpriteSparkle: {
        float2 q = rotate(uv, in.params.x);
        float rays = max(exp(-abs(q.y) * 26.0) * (1.0 - abs(q.x)),
                         exp(-abs(q.x) * 26.0) * (1.0 - abs(q.y)));
        float core = exp(-d * d * 36.0);
        float a = (rays * 0.75 + core) * (1.0 - smoothstep(0.75, 1.0, d));
        return float4(in.color.rgb * a, 0);
    }
    case PHSpriteRing: {
        float width = max(in.params.y, aa);
        float x = (d - in.params.x) / width;
        return float4(in.color.rgb * exp(-x * x), 0);
    }
    case PHSpriteStar: {
        float cover = 1.0 - smoothstep(1.0 - aa, 1.0, d);
        if (cover <= 0.0) discard_fragment();
        float z = sqrt(max(0.0, 1.0 - d * d));
        float limb = 0.3 + 0.7 * pow(z, 0.55);
        // boiling granulation, slow
        float2 flow = float2(frame.time * 0.12, in.params.x);
        float granules = fbm(uv * 4.0 / max(z, 0.35) + flow) * 0.6 + fbm(uv * 11.0 - flow * 1.7) * 0.4;
        float3 color = in.color.rgb * limb * (0.72 + 0.6 * granules);
        return float4(color * cover, cover);
    }
    case PHSpritePlanet: {
        float cover = 1.0 - smoothstep(1.0 - aa, 1.0, d);
        if (cover <= 0.0) discard_fragment();
        float z = sqrt(max(0.0, 1.0 - d * d));
        float3 n = float3(uv, z);
        float3 light = normalize(float3(in.params.xy, 0.35));
        float lambert = dot(n, light);
        float diffuse = smoothstep(-0.12, 0.75, lambert);
        float bands = 0.78 + 0.22 * sin(uv.y * in.params.z + fbm(uv * 2.5 + in.params.w) * 4.0);
        float rim = pow(1.0 - z, 2.5) * smoothstep(-0.4, 0.4, lambert);
        float3 color = in.color.rgb * (0.015 + diffuse * bands) + in.color.rgb * rim * 1.4;
        return float4(color * cover, cover);
    }
    case PHSpriteHole: {
        float r = d * 3.0;  // in horizon radii
        if (r > 3.0) discard_fragment();
        float spin = frame.time * 1.4 / (0.4 + r * r * 0.25);
        float2 q = rotate(uv, spin);
        float swirl = fbm(q * float2(7.0, 2.2) + 3.0) * fbm(q * 13.0);
        float disk = smoothstep(1.25, 1.7, r) * (1.0 - smoothstep(1.9, 3.0, r)) * (0.25 + swirl * 2.2);
        float photon = exp(-pow((r - 1.1) / 0.07, 2.0)) * 2.4;
        float shadow = 1.0 - smoothstep(1.0 - aa * 3.0, 1.0, r);
        float3 glow = in.color.rgb * (disk + photon) * (1.0 - shadow);
        return float4(glow, shadow);
    }
    default:
        return float4(0);
    }
}

// MARK: - Bloom (Jimenez 2014: 13-tap downsample, tent upsample)

fragment float4 ph_downsampleFragment(FullscreenOut in [[stage_in]],
                                      texture2d<float> source [[texture(0)]],
                                      constant PHBloomUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 t = u.texelSize, uv = in.uv;
    float3 a = source.sample(s, uv + t * float2(-2, -2)).rgb;
    float3 b = source.sample(s, uv + t * float2( 0, -2)).rgb;
    float3 c = source.sample(s, uv + t * float2( 2, -2)).rgb;
    float3 d = source.sample(s, uv + t * float2(-1, -1)).rgb;
    float3 e = source.sample(s, uv + t * float2( 1, -1)).rgb;
    float3 f = source.sample(s, uv + t * float2(-2,  0)).rgb;
    float3 g = source.sample(s, uv).rgb;
    float3 h = source.sample(s, uv + t * float2( 2,  0)).rgb;
    float3 i = source.sample(s, uv + t * float2(-1,  1)).rgb;
    float3 j = source.sample(s, uv + t * float2( 1,  1)).rgb;
    float3 k = source.sample(s, uv + t * float2(-2,  2)).rgb;
    float3 l = source.sample(s, uv + t * float2( 0,  2)).rgb;
    float3 m = source.sample(s, uv + t * float2( 2,  2)).rgb;
    float3 color = (d + e + i + j) * 0.125 + (a + c + k + m) * 0.03125 + (b + f + h + l) * 0.0625 + g * 0.125;
    if (u.threshold > 0) {
        float brightness = max(color.r, max(color.g, color.b));
        color *= max(brightness - u.threshold, 0.0) / max(brightness, 1e-4);
    }
    return float4(color, 1);
}

fragment float4 ph_upsampleFragment(FullscreenOut in [[stage_in]],
                                    texture2d<float> source [[texture(0)]],
                                    constant PHBloomUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 t = u.texelSize, uv = in.uv;
    float3 color = source.sample(s, uv).rgb * 4.0;
    color += (source.sample(s, uv + t * float2(-1, 0)).rgb + source.sample(s, uv + t * float2(1, 0)).rgb
            + source.sample(s, uv + t * float2(0, -1)).rgb + source.sample(s, uv + t * float2(0, 1)).rgb) * 2.0;
    color += source.sample(s, uv + t * float2(-1, -1)).rgb + source.sample(s, uv + t * float2(1, -1)).rgb
           + source.sample(s, uv + t * float2(-1, 1)).rgb + source.sample(s, uv + t * float2(1, 1)).rgb;
    return float4(color / 16.0 * u.intensity, 1);
}

fragment float4 ph_compositeFragment(FullscreenOut in [[stage_in]],
                                     texture2d<float> scene [[texture(0)]],
                                     texture2d<float> bloom [[texture(1)]],
                                     constant PHCompositeUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 hdr = scene.sample(s, in.uv).rgb + bloom.sample(s, in.uv).rgb * u.bloomStrength;
    float3 x = hdr * u.exposure;
    float3 mapped = saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)); // ACES fit (Narkowicz)
    float2 c = in.uv - 0.5;
    mapped *= 1.0 - dot(c, c) * u.vignette;
    mapped += (hash12(in.position.xy + fract(u.time) * 91.0) - 0.5) / 255.0; // dither against banding
    return float4(mapped, 1);
}
