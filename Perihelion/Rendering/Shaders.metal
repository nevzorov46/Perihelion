#include <metal_stdlib>
#include "PHShaderTypes.h"

using namespace metal;

// MARK: - Noise and helpers

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

static float2 rotate(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/// 1 on a line of half-width `halfWidth` around `center`, antialiased over `px`.
static float band(float x, float center, float halfWidth, float px) {
    return 1.0 - smoothstep(halfWidth, halfWidth + px, abs(x - center));
}

/// Premultiplied ink: coverage goes to alpha so it covers what lies beneath.
static float4 ink(float3 color, float coverage) {
    return float4(color * coverage, coverage);
}

constant float3 kPaper = float3(0.0055, 0.0105, 0.032);

/// Telescope diffraction spikes: six from a hexagonal mirror, two short from the struts.
static float spikes(float2 q, float sharpness) {
    float sum = 0;
    for (int k = 0; k < 3; k++) {
        float angle = M_PI_F / 6.0 + float(k) * M_PI_F / 3.0;
        float2 dir = float2(cos(angle), sin(angle));
        float along = abs(dot(q, dir));
        float perp = abs(dot(q, float2(-dir.y, dir.x)));
        sum += exp(-perp / (0.003 + 0.012 * along) * sharpness) * pow(max(1.0 - along, 0.0), 2.2);
    }
    float alongH = abs(q.x), perpH = abs(q.y);
    sum += 0.4 * exp(-perpH / (0.003 + 0.01 * alongH) * sharpness) * pow(max(1.0 - alongH * 1.7, 0.0), 2.2);
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

// MARK: - Background (baked once per level and style)

static float3 starfield(float2 px, float seed, float ppp, int style) {
    float3 color = 0;
    const float cellPoints[3] = { 9.0, 24.0, 70.0 };
    const float density[3] = { 0.12, 0.14, 0.24 };
    for (int layer = 0; layer < 3; layer++) {
        float cell = cellPoints[layer] * ppp;
        float2 id = floor(px / cell);
        float h = hash12(id + float(layer) * 31.7 + seed);
        if (h > density[layer]) continue;
        float2 center = (id + 0.2 + 0.6 * hash22(id + float(layer) * 7.3)) * cell;
        float2 delta = px - center;
        float d = length(delta);
        float brightness = (0.25 + 0.75 * pow(hash12(id * 1.37), 3.0)) * (0.5 + float(layer) * 0.6);

        if (style == PHStyleAtlas) {
            // engraved cross-stars, gold
            float size = (1.2 + 2.2 * float(layer)) * ppp * (0.7 + brightness);
            float w = 0.45 * ppp;
            float crossMark = max(band(delta.x, 0, w, ppp * 0.6) * step(abs(delta.y), size),
                                  band(delta.y, 0, w, ppp * 0.6) * step(abs(delta.x), size));
            float pin = 1.0 - smoothstep(0.6 * ppp, 1.2 * ppp, d);
            color += float3(0.80, 0.58, 0.26) * max(crossMark * (layer == 0 ? 0.0 : 1.0), pin) * 0.28 * brightness;
            continue;
        }

        float r = (0.35 + 0.55 * float(layer)) * ppp * (0.6 + h / density[layer]);
        float light = exp(-d * d / (r * r)) * brightness;
        float temperature = pow(hash12(id * 2.11 + 5.0), 4.0);
        float3 tint = mix(float3(0.62, 0.72, 1.0), float3(1.0, 0.9, 0.8), temperature);
        float gain = style == PHStyleLight ? 0.05 : 0.26;
        color += tint * light * gain;
        // only the brightest few carry spikes, and quietly: spikes belong to the level's stars
        if (style == PHStyleObservatory && layer == 2 && brightness > 0.95) {
            float2 q = delta / (r * 16.0);
            color += tint * spikes(q, 1.0) * 0.05 * brightness;
        }
    }
    return color;
}

fragment float4 ph_backgroundFragment(FullscreenOut in [[stage_in]],
                                      constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]],
                                      constant PHBackgroundUniforms &bg [[buffer(PHBufferIndexExtra)]]) {
    float2 px = in.uv * frame.drawableSize;
    float2 p = px / frame.drawableSize.x;
    float3 color;

    switch (bg.style) {
    case PHStyleObservatory: {
        color = mix(float3(0.002, 0.003, 0.007), float3(0.005, 0.004, 0.011), in.uv.y);
        float2 q = p * 1.7 + bg.seed;
        float warp = fbm(q + fbm(q * 1.4 + 3.1) * 1.7);
        float density = smoothstep(0.36, 0.95, warp);
        float hue = fbm(q * 0.6 - bg.seed * 0.37);
        float3 gas = mix(float3(0.04, 0.32, 0.42), float3(0.78, 0.32, 0.09), smoothstep(0.38, 0.62, hue));
        gas = mix(gas, float3(0.42, 0.09, 0.34), smoothstep(0.55, 0.8, fbm(q * 1.1 + 7.7)) * 0.6);
        float dust = smoothstep(0.48, 0.78, fbm(q * 3.3 - bg.seed * 2.3 + warp * 1.2));
        color += gas * density * density * 0.18 * (1.0 - 0.85 * dust);
        color += float3(0.9, 0.72, 0.5) * pow(density, 7.0) * 0.12 * (1.0 - dust);
        color += bg.tint.rgb * pow(fbm(q * 0.5 + 9.0), 3.0) * 0.02;
        color += starfield(px, bg.seed, bg.pixelsPerPoint, bg.style) * (1.0 - 0.7 * dust);
        break;
    }
    case PHStyleLight: {
        color = float3(0.0035, 0.003, 0.0035);
        float glow = saturate(1.0 - length((in.uv - float2(0.5, 0.52)) * float2(1.0, 0.8)) * 1.3);
        color += float3(0.008, 0.006, 0.011) * glow * glow;
        color *= 0.9 + 0.2 * fbm(p * 2.5 + bg.seed);
        color += starfield(px, bg.seed, bg.pixelsPerPoint, bg.style);
        break;
    }
    default: { // atlas
        float mottling = fbm(p * 2.6 + bg.seed);
        float fibers = valueNoise(float2(px.x * 0.018, px.y * 0.45) / bg.pixelsPerPoint);
        float speckle = step(0.985, hash12(floor(px / bg.pixelsPerPoint))) * 0.25;
        color = kPaper * (0.78 + 0.45 * mottling) * (0.94 + 0.12 * fibers) * (1.0 + speckle);
        color += starfield(px, bg.seed, bg.pixelsPerPoint, bg.style);
        break;
    }
    }
    return float4(color, 1);
}

/// Draws the baked background as seen through the masses: each one is a
/// gravitational lens, so a source at β appears at θ with β = θ − θE²/θ.
fragment float4 ph_lensFragment(FullscreenOut in [[stage_in]],
                                texture2d<float> source [[texture(0)]],
                                constant PHLensUniforms &lens [[buffer(PHBufferIndexExtra)]]) {
    constexpr sampler s(filter::linear, address::mirrored_repeat);
    float2 uv = in.uv;
    float2 shift = 0;
    for (int i = 0; i < lens.count; i++) {
        float2 d = (uv - lens.lenses[i].xy) * float2(lens.aspect, 1.0);
        float r2 = max(dot(d, d), 1e-5);
        shift += d * (lens.lenses[i].z / r2);
    }
    shift.x /= lens.aspect;
    float2 sky = (uv - shift - 0.5) / lens.zoom + 0.5 + lens.parallax;
    return float4(source.sample(s, sky).rgb, 1);
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
    out.alpha = smoothstep(-40.0, 140.0, edge) * (1.0 + min(curvature * 4e-4, 3.0));
    return out;
}

fragment float4 ph_gridFragment(GridOut in [[stage_in]],
                                constant PHGridUniforms &grid [[buffer(PHBufferIndexExtra)]]) {
    return float4(grid.color.rgb * in.alpha, grid.color.a * in.alpha);
}

// MARK: - Ribbons

struct RibbonOut {
    float4 position [[position]];
    float across;
    float along;
    float4 color;
    float4 params;
};

vertex RibbonOut ph_ribbonVertex(uint vid [[vertex_id]],
                                 constant PHRibbonVertex *vertices [[buffer(PHBufferIndexVertices)]],
                                 constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]]) {
    RibbonOut out;
    out.position = frame.worldToClip * float4(vertices[vid].position, 0, 1);
    out.across = vertices[vid].across;
    out.along = vertices[vid].along;
    out.color = vertices[vid].color;
    out.params = vertices[vid].params;
    return out;
}

fragment float4 ph_ribbonFragment(RibbonOut in [[stage_in]]) {
    float x = in.across;
    float dash = 1.0;
    if (in.params.y > 0) {
        float phase = fract(in.along / in.params.y);
        dash = smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.5, 0.56, phase));
    }
    switch (int(in.params.x)) {
    case PHRibbonDoubleRule: {
        float line = max(band(x, -0.62, 0.14, 0.2), band(x, 0.62, 0.14, 0.2));
        return ink(in.color.rgb, line * in.color.a * dash);
    }
    case PHRibbonHairline: {
        return ink(in.color.rgb, band(x, 0, 0.3, 0.45) * in.color.a * dash);
    }
    case PHRibbonFilament: {
        float core = exp(-x * x * 14.0);
        float sheath = (1.0 - x * x) * (1.0 - x * x);
        return float4(in.color.rgb * in.color.a * (core * 1.3 + sheath * 0.35) * dash, 0);
    }
    default: {
        float a = 1.0 - x * x;
        return float4(in.color.rgb * in.color.a * a * a * dash, 0);
    }
    }
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

fragment float4 ph_spriteFragment(SpriteOut in [[stage_in]],
                                  constant PHFrameUniforms &frame [[buffer(PHBufferIndexFrame)]]) {
    float2 uv = in.uv;
    float d = length(uv);
    float px = 1.0 / max(in.pixelRadius, 1.0);  // one pixel, in quad units
    float aa = 1.5 * px;

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
        float2 flow = float2(frame.time * 0.12, in.params.x);
        float granules = fbm(uv * 4.0 / max(z, 0.35) + flow) * 0.6 + fbm(uv * 11.0 - flow * 1.7) * 0.4;
        return float4(in.color.rgb * limb * (0.72 + 0.6 * granules) * cover, cover);
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
        return float4(in.color.rgb * (disk + photon) * (1.0 - shadow), shadow);
    }
    case PHSpriteSpikes: {
        float2 q = rotate(uv, in.params.x);
        float light = spikes(q, 1.0) + exp(-d * d * 60.0) * 0.5;
        return float4(in.color.rgb * light, 0);
    }
    case PHSpriteEngravedSun: {
        float rd = in.params.x;
        float2 q = rotate(uv, in.params.y);
        float mask = band(d, rd, px * 0.8, px);                       // rim
        mask = max(mask, band(d, rd * 0.8, px * 0.45, px) * 0.8);     // inner rule
        if (d < rd * 0.8) {                                           // engraved shading
            float spacing = rd * 0.12;
            float hatch = band(fract(q.y / spacing), 0.5, 0.1, px / spacing);
            mask = max(mask, hatch * 0.55 * smoothstep(-0.9, 0.4, (q.x + q.y) / rd));
        }
        // sixteen rays: straight wedges alternate with wavy flames
        const float n = 16.0;
        float sector = 2.0 * M_PI_F / n;
        float index = round(atan2(q.y, q.x) / sector);
        float angle = index * sector;
        float2 dir = float2(cos(angle), sin(angle));
        float along = dot(q, dir), across = dot(q, float2(-dir.y, dir.x));
        float start = rd * 1.2;
        bool wavy = fmod(abs(index), 2.0) > 0.5;
        float end = wavy ? 0.74 : 0.98;
        float t = (along - start) / (end - start);
        if (t > 0.0 && t < 1.0) {
            if (wavy) {
                float wave = sin(t * 15.0) * rd * 0.09 * (1.0 - 0.5 * t);
                mask = max(mask, band(across, wave, px * 0.7, px) * (1.0 - 0.4 * t));
            } else {
                float halfWidth = rd * 0.17 * (1.0 - t);
                mask = max(mask, 1.0 - smoothstep(halfWidth, halfWidth + px, abs(across)));
            }
        }
        float cover = 1.0 - smoothstep(rd, rd + px, d);
        float alpha = max(mask * in.color.a, cover);
        return float4(in.color.rgb * mask * in.color.a + kPaper * cover * (1.0 - mask), alpha);
    }
    case PHSpriteEngravedPlanet: {
        float rd = in.params.z;
        float cover = 1.0 - smoothstep(rd, rd + px, d);
        float outline = band(d, rd, px * 0.8, px);
        if (cover <= 0.0 && outline <= 0.0) discard_fragment();
        float2 L = normalize(in.params.xy);
        float2 s = uv / rd;
        float z = sqrt(max(0.0, 1.0 - dot(s, s)));
        float lambert = dot(float3(s, z), normalize(float3(L, 0.4)));
        float light = saturate(0.45 + lambert * 0.8);
        // engraving: lines across the light, thicker where it is brighter; cross-hatch at the peak
        float spacing = rd * 0.15;
        float fpx = px / spacing;
        float coord = dot(uv, float2(-L.y, L.x)) / spacing;
        float hatch = band(fract(coord), 0.5, 0.03 + 0.3 * light, fpx) * step(0.12, light);
        float coord2 = dot(uv, L) / spacing;
        float crossHatch = band(fract(coord2), 0.5, max(light - 0.7, 0.0) * 0.6, fpx) * step(0.72, light);
        float mask = max(max(hatch, crossHatch) * cover, outline);
        float alpha = max(mask * in.color.a, cover);
        return float4(in.color.rgb * mask * in.color.a + kPaper * cover * (1.0 - mask), alpha);
    }
    case PHSpriteGlyph: {
        float2 q = rotate(uv, in.params.x);
        float theta = atan2(q.y, q.x);
        float major = pow(abs(cos(2.0 * theta)), 14.0);
        float minor = pow(abs(sin(2.0 * theta)), 14.0) * 0.55;
        float r = 0.12 + 0.88 * max(major, minor);
        float fill = 1.0 - smoothstep(r - px, r + px * 0.5, d);
        // engraved glyphs are half-shaded: one flank of every point is left open
        float flank = step(0.0, sin(4.0 * theta)) * step(0.18, d);
        return ink(in.color.rgb, fill * (1.0 - flank * 0.75) * in.color.a);
    }
    case PHSpriteChartRing: {
        float radius = in.params.x;
        float mask = band(d, radius, px * 0.55, px);
        float count = in.params.y;
        if (count > 0.0) {
            float a = (atan2(uv.y, uv.x) / (2.0 * M_PI_F) + 0.5) * count;
            float nearest = round(a);
            float distance = abs(a - nearest) * (2.0 * M_PI_F / count) * d;
            bool major = fmod(nearest, 5.0) < 0.5;
            float tickLength = in.params.z * (major ? 2.0 : 1.0);
            float tick = (1.0 - smoothstep(px * 0.5, px * 1.4, distance))
                * step(radius, d) * (1.0 - smoothstep(radius + tickLength, radius + tickLength + px, d));
            mask = max(mask, tick);
        }
        if (in.params.w > 0.0) {
            float a = (atan2(uv.y, uv.x) / (2.0 * M_PI_F) + 0.5) * in.params.w;
            mask *= step(fract(a), 0.55);
        }
        return ink(in.color.rgb, mask * in.color.a);
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
    float2 uv = in.uv;
    float3 hdr;
    if (u.aberration > 0) {
        float2 shift = (uv - 0.5) * u.aberration;
        hdr = float3(scene.sample(s, uv + shift).r, scene.sample(s, uv).g, scene.sample(s, uv - shift).b);
    } else {
        hdr = scene.sample(s, uv).rgb;
    }
    hdr += bloom.sample(s, uv).rgb * u.bloomStrength;
    float3 x = hdr * u.exposure;
    float3 mapped = u.style == PHStyleAtlas
        ? 1.0 - exp(-x * 1.3)                                                    // soft, print-like shoulder
        : saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));   // ACES fit (Narkowicz)
    float2 c = uv - 0.5;
    mapped *= 1.0 - dot(c, c) * u.vignette;
    if (u.grain > 0) {
        float seed = u.style == PHStyleAtlas ? 0.0 : floor(u.time * 24.0) * 13.0; // paper is still, film is not
        mapped *= 1.0 + (hash12(in.position.xy * 0.71 + seed) - 0.5) * u.grain;
    }
    mapped += (hash12(in.position.xy + fract(u.time) * 91.0) - 0.5) / 255.0;
    return float4(mapped, 1);
}
