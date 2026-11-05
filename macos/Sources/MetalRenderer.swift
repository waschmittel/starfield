// SPDX-License-Identifier: GPL-3.0-or-later
import Metal
import QuartzCore

/// GPU renderer for the starfield: every star is one instanced quad that the fragment shader turns into an
/// anti-aliased capsule (a line with round caps, or a dot when both ends coincide). The CPU only simulates
/// the stars and writes their endpoints into a shared buffer.
///
/// The shader is compiled from source at runtime: the Command Line Tools ship no `metal` compiler, and this
/// keeps `build.sh` a plain `swiftc` invocation.
final class MetalRenderer {
    /// Floats per star instance: endpoints a and b (x, y each), radius, gray. Matches `Inst` in the shader.
    static let floatsPerInstance = 6
    private static let framesInFlight = 3

    let layer = CAMetalLayer()

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let buffers: [MTLBuffer]
    private let inFlight = DispatchSemaphore(value: MetalRenderer.framesInFlight)
    private var bufferIndex = 0

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Inst { float2 a; float2 b; float r; float g; };
    struct Uniforms { float2 view; float px; };   // view size and size of one pixel, both in points
    struct VOut {
        float4 pos [[position]];
        float2 p;
        float2 a [[flat]];
        float2 b [[flat]];
        float r [[flat]];
        float g [[flat]];
    };

    vertex VOut starVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device Inst* inst [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        Inst s = inst[iid];
        float m = s.r + u.px;
        float2 lo = min(s.a, s.b) - m, hi = max(s.a, s.b) + m;
        float2 p = mix(lo, hi, float2(vid & 1, vid >> 1));
        VOut o;
        o.pos = float4(p / u.view * 2.0 - 1.0, 0.0, 1.0);
        o.p = p; o.a = s.a; o.b = s.b; o.r = s.r; o.g = s.g;
        return o;
    }

    fragment float4 starFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float2 ab = in.b - in.a;
        float l2 = dot(ab, ab);
        float t = l2 > 0.0 ? clamp(dot(in.p - in.a, ab) / l2, 0.0, 1.0) : 0.0;
        float d = length(in.p - in.a - ab * t) - in.r;
        return float4(in.g, in.g, in.g, clamp(0.5 - d / u.px, 0.0, 1.0));
    }
    """

    private struct Uniforms { var view: SIMD2<Float>; var px: Float }

    /// Returns nil if there is no usable Metal device or the shader fails to build; the caller then falls back
    /// to Core Graphics.
    init?(capacity: Int) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil),
              let vs = library.makeFunction(name: "starVertex"),
              let fs = library.makeFunction(name: "starFragment") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        let att = desc.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .sourceAlpha
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .zero
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        let length = capacity * Self.floatsPerInstance * MemoryLayout<Float>.stride
        var buffers: [MTLBuffer] = []
        for _ in 0..<Self.framesInFlight {
            guard let b = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
            buffers.append(b)
        }

        self.queue = queue
        self.pipeline = pipeline
        self.buffers = buffers
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.maximumDrawableCount = 3
        layer.contentsGravity = .resize
    }

    /// Sets the drawable size for a view of `size` points at `scale`. Must happen before the display link
    /// hands out drawables.
    func resize(size: CGSize, scale: CGFloat) {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        if pixels.width >= 1, pixels.height >= 1, layer.drawableSize != pixels { layer.drawableSize = pixels }
    }

    private var linkDelegate: AnyObject?

    /// A display link that delivers a ready drawable per refresh. Unlike calling `nextDrawable()` from a
    /// plain `CADisplayLink` callback, it never blocks the main thread waiting for a free drawable, which
    /// caused dropped frames (visible as periodic stutter).
    func makeDisplayLink(_ handler: @escaping (CAMetalDisplayLink.Update) -> Void) -> CAMetalDisplayLink {
        let delegate = LinkDelegate(handler)
        linkDelegate = delegate
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = delegate
        link.preferredFrameLatency = 2
        return link
    }

    /// Draws one frame into `drawable`. `fill` writes `floatsPerInstance` floats per star (in point
    /// coordinates, origin bottom left, brighter stars last) into the given pointer and returns the number
    /// of stars.
    func render(size: CGSize, scale: CGFloat, drawable: CAMetalDrawable, fill: (UnsafeMutablePointer<Float>) -> Int) {
        guard size.width >= 1, size.height >= 1 else { return }
        // Skip the frame rather than block the main run loop when the GPU is behind.
        guard inFlight.wait(timeout: .now()) == .success else { return }
        let inFlight = self.inFlight

        guard let cmd = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }

        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.count
        let count = fill(buffer.contents().bindMemory(to: Float.self, capacity: buffer.length / MemoryLayout<Float>.stride))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass) {
            if count > 0 {
                var u = Uniforms(view: SIMD2(Float(size.width), Float(size.height)), px: Float(1 / scale))
                enc.setRenderPipelineState(pipeline)
                enc.setVertexBuffer(buffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.size, index: 1)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.size, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
            }
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.addCompletedHandler { _ in inFlight.signal() }
        cmd.commit()
    }
}

private final class LinkDelegate: NSObject, CAMetalDisplayLinkDelegate {
    let handler: (CAMetalDisplayLink.Update) -> Void
    init(_ handler: @escaping (CAMetalDisplayLink.Update) -> Void) { self.handler = handler }
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) { handler(update) }
}
