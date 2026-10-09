// Draws the app icon from the simulation: the curve is a real solution of the
// level's own proof shot, not an illustration of one. Run through tools/run.sh icon.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let levelID = CommandLine.arguments.dropFirst().first ?? "slingshot"

guard let def = LevelDef.campaign.first(where: { $0.id == levelID }), let shot = def.shot else {
    FileHandle.standardError.write(Data("no level \(levelID) with a proof shot\n".utf8))
    exit(1)
}

// MARK: - The trajectory, from the physics

let level = Level(def)
var flight = Flight(level: level, shot: shot)
var path: [SIMD2<Double>] = [flight.position]
var star = SIMD2<Double>.zero
var starRadius = 0.0
var closest = Double.greatestFiniteMagnitude

while flight.isFlying {
    flight.step()
    path.append(flight.position)
    // the heaviest body is the one the icon is about
    for i in level.bodies.indices where level.bodies[i].mu >= level.bodies.map(\.mu).max()! {
        let d = flight.bodyPositions[i] - flight.position
        let r = (d.x * d.x + d.y * d.y).squareRoot()
        if r < closest { closest = r; star = flight.bodyPositions[i]; starRadius = level.bodies[i].radius }
    }
}

// MARK: - Fit the pass into the square

/// The icon is the perihelion itself, so the frame is built around the closest
/// point rather than around the whole flight: centred on the star, holding the
/// stretch of curve on either side of the pass, and kept well inside the corners
/// that iOS rounds away.
let closestIndex = path.indices.min {
    let a = path[$0] - star, b = path[$1] - star
    return (a.x * a.x + a.y * a.y) < (b.x * b.x + b.y * b.y)
} ?? 0
let window = 125
let shown = Array(path[max(0, closestIndex - window)..<min(path.count, closestIndex + window)])

// Centre on what is drawn, not on the star: the swing is asymmetric, and
// centring on the body leaves the frame lopsided.
var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
for p in shown + [star] {
    minX = min(minX, p.x); maxX = max(maxX, p.x)
    minY = min(minY, p.y); maxY = max(maxY, p.y)
}
let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
// 1.3 keeps the curve clear of the corners iOS rounds away
let span = max(maxX - minX, maxY - minY, 1) * 1.5

/// World to icon. World +x is up the screen and world +y is to the right, the
/// same rotation the game uses, so the icon matches what the player sees.
func point(_ w: SIMD2<Double>) -> CGPoint {
    CGPoint(x: size / 2 + (w.y - midY) / span * size,
            y: size / 2 + (w.x - midX) / span * size)
}

// MARK: - Draw

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

func colour(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// ground: the game's night, a little blue in the middle so the square is not flat
ctx.setFillColor(colour(0.016, 0.020, 0.043))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
if let sky = CGGradient(colorsSpace: space,
                        colors: [colour(0.07, 0.10, 0.22, 1), colour(0.016, 0.020, 0.043, 0)] as CFArray,
                        locations: [0, 1]) {
    ctx.drawRadialGradient(sky, startCenter: point(star), startRadius: 0,
                           endCenter: point(star), endRadius: size * 0.72, options: [])
}

let starPoint = point(star)

// the star: a core with two halos, warm like the game's
for (radius, alpha) in [(size * 0.34, 0.16), (size * 0.19, 0.3), (size * 0.10, 0.55)] {
    if let glow = CGGradient(colorsSpace: space,
                             colors: [colour(1, 0.88, 0.64, alpha), colour(1, 0.76, 0.42, 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow, startCenter: starPoint, startRadius: 0,
                               endCenter: starPoint, endRadius: radius, options: [])
    }
}

let core = max(starRadius / span * size, size * 0.058)
ctx.setFillColor(colour(1, 0.97, 0.9))
ctx.fillEllipse(in: CGRect(x: starPoint.x - core, y: starPoint.y - core, width: core * 2, height: core * 2))

// the trajectory: drawn three times, wide and dim to narrow and bright, which
// reads as a glow without needing a blur
let curve = CGMutablePath()
curve.addLines(between: shown.map(point))

for (width, r, g, b, a) in [(size * 0.085, 0.45, 0.72, 1.0, 0.16),
                            (size * 0.044, 0.68, 0.85, 1.0, 0.34),
                            (size * 0.019, 0.95, 0.99, 1.0, 0.96)] {
    ctx.setStrokeColor(colour(r, g, b, a))
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(curve)
    ctx.strokePath()
}

// the comet, where the curve ends
if let head = shown.last.map(point) {
    for (radius, alpha) in [(size * 0.10, 0.33), (size * 0.045, 0.6)] {
        if let glow = CGGradient(colorsSpace: space,
                                 colors: [colour(0.8, 0.95, 1, alpha), colour(0.5, 0.8, 1, 0)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(glow, startCenter: head, startRadius: 0,
                                   endCenter: head, endRadius: radius, options: [])
        }
    }
    let r = size * 0.024
    ctx.setFillColor(colour(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
}

// MARK: - Write

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst(1).count > 1
              ? CommandLine.arguments[2]
              : "Perihelion/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path) from \(levelID), \(shown.count) steps of trajectory")
