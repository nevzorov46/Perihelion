import MetalKit
import QuartzCore

/// Draws a frame in four stages:
///
///   1. scene     rgba16Float: lensed background, bent grid, ribbons, sprites
///   2. bloom     13-tap downsample ×5, tent upsample ×4 (Jimenez, SIGGRAPH 2014)
///   3. composite scene + bloom → ACES tonemap → vignette → sRGB drawable
///
/// The background (nebula + stars) is expensive per pixel and never moves, so it
/// is rendered once per level into its own texture and blitted afterwards.
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice

    private static let sceneFormat = MTLPixelFormat.rgba16Float
    private static let drawableFormat = MTLPixelFormat.bgra8Unorm_srgb
    private static let bloomLevels = 5
    private static let ribbonCapacity = 40_000
    private static let spriteCapacity = 6_000

    private let queue: MTLCommandQueue
    private let session: GameSession
    private let builder = SceneBuilder()

    private let backgroundPipeline: MTLRenderPipelineState
    private let lensPipeline: MTLRenderPipelineState
    private let gridPipeline: MTLRenderPipelineState
    private let ribbonPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let downsamplePipeline: MTLRenderPipelineState
    private let upsamplePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    private let gridBuffer: MTLBuffer
    private let gridVertexCount: Int
    // Three sets of dynamic buffers, cycled, so the CPU never writes a buffer
    // the GPU is still reading. The semaphore caps frames in flight at three.
    private let ribbonBuffers: [MTLBuffer]
    private let spriteBuffers: [MTLBuffer]
    private let inflight = DispatchSemaphore(value: 3)
    private var bufferIndex = 0

    private var sceneTexture: MTLTexture?
    private var backgroundTexture: MTLTexture?
    private var bloomTextures: [MTLTexture] = []
    private var bakedBackgroundFor: String?
    private var lastFrameTime: CFTimeInterval?

    init?(session: GameSession) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }
        self.device = device
        self.queue = queue
        self.session = session

        do {
            func make(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat, _ blend: Blend) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: vertex)
                d.fragmentFunction = library.makeFunction(name: fragment)
                let a = d.colorAttachments[0]!
                a.pixelFormat = format
                switch blend {
                case .none:
                    a.isBlendingEnabled = false
                case .premultiplied:
                    a.isBlendingEnabled = true
                    a.sourceRGBBlendFactor = .one
                    a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    a.sourceAlphaBlendFactor = .one
                    a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                case .additive:
                    a.isBlendingEnabled = true
                    a.sourceRGBBlendFactor = .one
                    a.destinationRGBBlendFactor = .one
                    a.sourceAlphaBlendFactor = .one
                    a.destinationAlphaBlendFactor = .one
                }
                return try device.makeRenderPipelineState(descriptor: d)
            }
            backgroundPipeline = try make("ph_fullscreenVertex", "ph_backgroundFragment", Self.sceneFormat, .none)
            lensPipeline = try make("ph_fullscreenVertex", "ph_lensFragment", Self.sceneFormat, .none)
            gridPipeline = try make("ph_gridVertex", "ph_gridFragment", Self.sceneFormat, .premultiplied)
            ribbonPipeline = try make("ph_ribbonVertex", "ph_ribbonFragment", Self.sceneFormat, .premultiplied)
            spritePipeline = try make("ph_spriteVertex", "ph_spriteFragment", Self.sceneFormat, .premultiplied)
            downsamplePipeline = try make("ph_fullscreenVertex", "ph_downsampleFragment", Self.sceneFormat, .none)
            upsamplePipeline = try make("ph_fullscreenVertex", "ph_upsampleFragment", Self.sceneFormat, .additive)
            compositePipeline = try make("ph_fullscreenVertex", "ph_compositeFragment", Self.drawableFormat, .none)
        } catch {
            assertionFailure("Pipeline creation failed: \(error)")
            return nil
        }

        let grid = Self.gridVertices()
        guard let gridBuffer = device.makeBuffer(bytes: grid, length: MemoryLayout<PHGridVertex>.stride * grid.count)
        else { return nil }
        self.gridBuffer = gridBuffer
        gridVertexCount = grid.count

        var ribbons: [MTLBuffer] = [], sprites: [MTLBuffer] = []
        for _ in 0..<3 {
            guard let r = device.makeBuffer(length: MemoryLayout<PHRibbonVertex>.stride * Self.ribbonCapacity, options: .storageModeShared),
                  let s = device.makeBuffer(length: MemoryLayout<PHSprite>.stride * Self.spriteCapacity, options: .storageModeShared)
            else { return nil }
            ribbons.append(r)
            sprites.append(s)
        }
        ribbonBuffers = ribbons
        spriteBuffers = sprites
        super.init()
    }

    private enum Blend { case none, premultiplied, additive }

    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = Self.drawableFormat
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    /// Grid lines every 50 world units, subdivided every 10 so they can bend.
    private static func gridVertices() -> [PHGridVertex] {
        var v: [PHGridVertex] = []
        let spacing = 50.0, step = 10.0
        var y = 0.0
        while y <= Sim.height {
            var x = 0.0
            while x < Sim.width {
                v.append(PHGridVertex(position: SIMD2(Float(x), Float(y))))
                v.append(PHGridVertex(position: SIMD2(Float(x + step), Float(y))))
                x += step
            }
            y += spacing
        }
        var x = 0.0
        while x <= Sim.width {
            var y = 0.0
            while y < Sim.height {
                v.append(PHGridVertex(position: SIMD2(Float(x), Float(y))))
                v.append(PHGridVertex(position: SIMD2(Float(x), Float(y + step))))
                y += step
            }
            x += spacing
        }
        return v
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeTargets(size)
    }

    private func makeTargets(_ size: CGSize) {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return }
        func texture(_ w: Int, _ h: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.sceneFormat, width: max(w, 1), height: max(h, 1), mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        sceneTexture = texture(width, height)
        backgroundTexture = texture(width, height)
        bloomTextures = (1...Self.bloomLevels).compactMap { texture(width >> $0, height >> $0) }
        bakedBackgroundFor = nil
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = lastFrameTime.map { now - $0 } ?? 1.0 / 60
        lastFrameTime = now
        session.advance(dt: min(dt, 1.0 / 20))

        let size = view.drawableSize
        if sceneTexture?.width != Int(size.width) || sceneTexture?.height != Int(size.height) { makeTargets(size) }
        guard let scene = sceneTexture, let background = backgroundTexture,
              bloomTextures.count == Self.bloomLevels,
              session.transform.viewSize.width > 0
        else { return }

        builder.build(session)

        inflight.wait()
        guard let commandBuffer = queue.makeCommandBuffer() else {
            inflight.signal()
            return
        }
        let semaphore = inflight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        let transform = session.transform
        let style = session.style
        var frame = PHFrameUniforms(
            worldToClip: transform.clipMatrix,
            drawableSize: SIMD2(Float(size.width), Float(size.height)),
            pixelsPerUnit: Float(transform.scale * Double(size.width) / Double(transform.viewSize.width)),
            time: Float(session.clock), style: style.rawValue, pad0: 0, pad1: 0, pad2: 0)

        let backgroundKey = "\(session.level.def.id)/\(style.rawValue)"
        if bakedBackgroundFor != backgroundKey {
            bakeBackground(into: background, commandBuffer: commandBuffer, frame: &frame, pixelsPerPoint: Float(size.width / transform.viewSize.width))
            bakedBackgroundFor = backgroundKey
        }

        encodeScene(into: scene, background: background, commandBuffer: commandBuffer, frame: &frame)
        encodeBloom(from: scene, commandBuffer: commandBuffer)

        if let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.label = "Composite"
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(scene, index: 0)
            encoder.setFragmentTexture(bloomTextures[0], index: 1)
            var composite = Self.composite(for: style, time: Float(session.clock), slowness: Float(session.slowness))
            encoder.setFragmentBytes(&composite, length: MemoryLayout<PHCompositeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private static func composite(for style: VisualStyle, time: Float, slowness: Float) -> PHCompositeUniforms {
        switch style {
        case .observatory:
            // diving close to a mass: the lens strains, the edges close in
            return PHCompositeUniforms(bloomStrength: 1.0 + 0.3 * slowness, exposure: 1.05 + 0.05 * slowness,
                                       vignette: 1.0 + 0.7 * slowness, time: time, style: style.rawValue,
                                       grain: 0.035, aberration: 0.004 + 0.012 * slowness, pad: 0)
        case .light:
            return PHCompositeUniforms(bloomStrength: 1.35, exposure: 1.0, vignette: 1.1, time: time,
                                       style: style.rawValue, grain: 0, aberration: 0, pad: 0)
        case .atlas:
            return PHCompositeUniforms(bloomStrength: 0.12, exposure: 1.0, vignette: 1.4, time: time,
                                       style: style.rawValue, grain: 0.06, aberration: 0, pad: 0)
        }
    }

    // MARK: - Passes

    private func bakeBackground(into target: MTLTexture, commandBuffer: MTLCommandBuffer, frame: inout PHFrameUniforms, pixelsPerPoint: Float) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Background bake"
        let tint = Palette.nebulae[session.levelIndex % Palette.nebulae.count]
        var uniforms = PHBackgroundUniforms(tint: SIMD4(tint, 0), seed: Float(session.levelIndex) * 7.31 + 3.7,
                                            pixelsPerPoint: pixelsPerPoint, style: session.style.rawValue, pad: 0)
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<PHFrameUniforms>.stride, index: Int(PHBufferIndexFrame.rawValue))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PHBackgroundUniforms>.stride, index: Int(PHBufferIndexExtra.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeScene(into target: MTLTexture, background: MTLTexture, commandBuffer: MTLCommandBuffer, frame: inout PHFrameUniforms) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Scene"
        let frameIndex = Int(PHBufferIndexFrame.rawValue)
        let verticesIndex = Int(PHBufferIndexVertices.rawValue)

        let extraIndex = Int(PHBufferIndexExtra.rawValue)
        var lens = builder.lens
        encoder.setRenderPipelineState(lensPipeline)
        encoder.setFragmentTexture(background, index: 0)
        encoder.setFragmentBytes(&lens, length: MemoryLayout<PHLensUniforms>.stride, index: extraIndex)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        var grid = builder.grid
        if grid.color != .zero {
            encoder.setRenderPipelineState(gridPipeline)
            encoder.setVertexBuffer(gridBuffer, offset: 0, index: verticesIndex)
            encoder.setVertexBytes(&frame, length: MemoryLayout<PHFrameUniforms>.stride, index: frameIndex)
            encoder.setVertexBytes(&grid, length: MemoryLayout<PHGridUniforms>.stride, index: extraIndex)
            encoder.setFragmentBytes(&grid, length: MemoryLayout<PHGridUniforms>.stride, index: extraIndex)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
        }

        bufferIndex = (bufferIndex + 1) % 3
        let ribbon = builder.ribbon
        if !ribbon.isEmpty {
            let buffer = ribbonBuffers[bufferIndex]
            let count = min(ribbon.count, Self.ribbonCapacity)
            ribbon.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<PHRibbonVertex>.stride * count) }
            encoder.setRenderPipelineState(ribbonPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: verticesIndex)
            encoder.setVertexBytes(&frame, length: MemoryLayout<PHFrameUniforms>.stride, index: frameIndex)
            for strip in builder.strips where strip.upperBound <= count {
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: strip.lowerBound, vertexCount: strip.count)
            }
        }

        let sprites = builder.sprites
        if !sprites.isEmpty {
            let buffer = spriteBuffers[bufferIndex]
            let count = min(sprites.count, Self.spriteCapacity)
            sprites.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: MemoryLayout<PHSprite>.stride * count) }
            encoder.setRenderPipelineState(spritePipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: verticesIndex)
            encoder.setVertexBytes(&frame, length: MemoryLayout<PHFrameUniforms>.stride, index: frameIndex)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<PHFrameUniforms>.stride, index: frameIndex)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        encoder.endEncoding()
    }

    private func encodeBloom(from scene: MTLTexture, commandBuffer: MTLCommandBuffer) {
        func pass(_ target: MTLTexture, _ source: MTLTexture, _ pipeline: MTLRenderPipelineState, load: MTLLoadAction, threshold: Float) {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = target
            descriptor.colorAttachments[0].loadAction = load
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            var uniforms = PHBloomUniforms(texelSize: SIMD2(1 / Float(source.width), 1 / Float(source.height)),
                                           threshold: threshold, intensity: 1)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PHBloomUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        var source = scene
        for (i, target) in bloomTextures.enumerated() {
            pass(target, source, downsamplePipeline, load: .dontCare, threshold: i == 0 ? 0.85 : 0)
            source = target
        }
        for i in stride(from: bloomTextures.count - 2, through: 0, by: -1) {
            pass(bloomTextures[i], bloomTextures[i + 1], upsamplePipeline, load: .load, threshold: 0)
        }
    }
}
