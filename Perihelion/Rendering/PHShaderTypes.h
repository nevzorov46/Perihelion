// GPU data layout shared by Swift (via the bridging header) and the shaders.
//
// Layout rule: every float4 starts on a 16-byte boundary and every struct is a
// multiple of 16 bytes, so C and MSL agree on offsets without packed types.
// No float3 anywhere - its size differs between the two languages.

#ifndef PHShaderTypes_h
#define PHShaderTypes_h

#include <simd/simd.h>

typedef enum {
    PHBufferIndexVertices = 0,
    PHBufferIndexFrame = 1,
    PHBufferIndexExtra = 2,
} PHBufferIndex;

typedef enum {
    PHSpriteGlow = 0,     // soft emissive falloff
    PHSpriteDisc = 1,     // solid antialiased disc
    PHSpriteSparkle = 2,  // four-point star; params.x = rotation
    PHSpriteRing = 3,     // params.x = radius (0…1), params.y = width
    PHSpriteStar = 4,     // stellar surface; params.x = seed
    PHSpritePlanet = 5,   // lit sphere; params.xy = light direction (screen, y up), .z = band frequency, .w = seed
    PHSpriteHole = 6,     // horizon + photon ring + accretion; quad is 3× the horizon
} PHSpriteKind;

typedef struct {
    simd_float4x4 worldToClip;
    simd_float2 drawableSize;  // pixels
    float pixelsPerUnit;       // drawable pixels per world unit
    float time;
} PHFrameUniforms;

// Colours are linear and premultiplied. A sprite that only emits light has
// alpha 0 and simply adds; one that occludes carries its coverage in alpha.
typedef struct {
    simd_float2 position;  // world
    float radius;          // world units: half the quad's side
    int32_t kind;          // PHSpriteKind
    simd_float4 color;
    simd_float4 params;
} PHSprite;

typedef struct {
    simd_float2 position;  // world
    float across;          // -1 … +1 from one edge of the ribbon to the other
    float pad;
    simd_float4 color;     // linear rgb × a, additive
} PHRibbonVertex;

typedef struct {
    simd_float2 position;  // world, before the masses bend it
} PHGridVertex;

#define PH_MAX_GRID_MASSES 8

typedef struct {
    simd_float4 masses[PH_MAX_GRID_MASSES];  // x, y, μ, radius
    int32_t count;
    float intensity;
    float pad0;
    float pad1;
} PHGridUniforms;

typedef struct {
    simd_float4 tint;      // nebula colour, linear
    float seed;
    float pixelsPerPoint;
    float pad0;
    float pad1;
} PHBackgroundUniforms;

typedef struct {
    simd_float2 texelSize;  // of the texture being sampled
    float threshold;        // > 0 only on the first downsample
    float intensity;        // upsample weight
} PHBloomUniforms;

typedef struct {
    float bloomStrength;
    float exposure;
    float vignette;
    float time;
} PHCompositeUniforms;

#endif /* PHShaderTypes_h */
