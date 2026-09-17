//
//  Perihelion-Bridging-Header.h
//  Perihelion
//
//  Swift sees the GPU data layout through this header; the shaders include the
//  same file, so the two sides cannot drift apart.
//

#import "PHShaderTypes.h"
