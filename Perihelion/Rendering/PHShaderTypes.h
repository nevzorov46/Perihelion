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
    PHStyleObservatory = 0,  // telescope photograph: nebulae, diffraction spikes, lensing
    PHStyleLight = 1,        // long-exposure light painting on black
    PHStyleAtlas = 2,        // engraved celestial atlas, gold ink on navy paper
} PHStyle;

typedef enum {
    PHSpriteGlow = 0,            // soft emissive falloff
    PHSpriteDisc = 1,            // antialiased disc; alpha = opacity
    PHSpriteSparkle = 2,         // four-point star; params.x = rotation
    PHSpriteRing = 3,            // params.x = radius (0…1), params.y = width
    PHSpriteStar = 4,            // stellar surface; params.x = seed
    PHSpritePlanet = 5,          // lit sphere; params.xy = light (screen, y up), .z = bands, .w = seed
    PHSpriteHole = 6,            // horizon + photon ring + accretion; quad is 3× the horizon
    PHSpriteSpikes = 7,          // telescope diffraction spikes; params.x = rotation
    PHSpriteEngravedSun = 8,     // params.x = disc radius (0…1), .y = rotation
    PHSpriteEngravedPlanet = 9,  // params.xy = light, .z = disc radius (0…1)
    PHSpriteGlyph = 10,          // eight-point star glyph; params.x = rotation
    PHSpriteChartRing = 11,      // params.x = radius, .y = tick count, .z = tick length, .w = dashes
    PHSpriteHaze = 12,           // soft gaussian with no bright core: many overlap into a veil
    PHSpriteStreak = 13,         // glow stretched along params.xy (screen, y up) by params.z
} PHSpriteKind;

typedef enum {
    PHRibbonGlow = 0,        // soft additive light
    PHRibbonDoubleRule = 1,  // two parallel engraved lines
    PHRibbonHairline = 2,    // one engraved line
    PHRibbonFilament = 3,    // hot core with a soft sheath
    PHRibbonSheet = 4,       // no falloff across: strips tile into one smooth surface
} PHRibbonProfile;

typedef struct {
    simd_float4x4 worldToClip;
    simd_float2 drawableSize;  // pixels
    float pixelsPerUnit;       // drawable pixels per world unit
    float time;
    int32_t style;             // PHStyle
    float pad0;
    float pad1;
    float pad2;
} PHFrameUniforms;

// Colours are linear and premultiplied. Light has alpha 0 and simply adds;
// ink and solid bodies carry their coverage in alpha.
typedef struct {
    simd_float2 position;  // world
    float radius;          // world units: half the quad's side
    int32_t kind;          // PHSpriteKind
    simd_float4 color;     // rgb; a = opacity for ink and solid kinds
    simd_float4 params;
} PHSprite;

typedef struct {
    simd_float2 position;  // world
    float across;          // -1 … +1 from one edge of the ribbon to the other
    float along;           // world units from the start of the ribbon
    simd_float4 color;     // rgb; a = intensity (light) or opacity (ink)
    simd_float4 params;    // x = PHRibbonProfile, y = dash period (0 = solid)
} PHRibbonVertex;

typedef struct {
    simd_float2 position;  // world, before the masses bend it
} PHGridVertex;

#define PH_MAX_MASSES 8

typedef struct {
    simd_float4 masses[PH_MAX_MASSES];  // x, y, μ, radius
    simd_float4 color;                  // rgb × intensity; a = 1 for ink, 0 for light
    int32_t count;
    float pad0;
    float pad1;
    float pad2;
} PHGridUniforms;

typedef struct {
    simd_float4 lenses[PH_MAX_MASSES];  // screen uv x, y; Einstein radius² in height units; unused
    simd_float2 parallax;               // background uv offset from the camera's travel
    float zoom;                         // background magnification (a fraction of the camera's)
    float aspect;                       // drawable width / height
    int32_t count;
    float time;                         // seconds, for the nebula's drift
    float pad0;
    float pad1;
} PHLensUniforms;

typedef struct {
    simd_float4 tint;      // nebula colour, linear
    float seed;
    float pixelsPerPoint;
    int32_t style;
    float pad;
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
    int32_t style;
    float grain;
    float aberration;
    float pad;
} PHCompositeUniforms;

#endif /* PHShaderTypes_h */
