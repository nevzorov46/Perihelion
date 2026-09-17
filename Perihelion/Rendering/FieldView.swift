import MetalKit
import SwiftUI

/// The playfield: an MTKView that reports its layout and forwards one finger.
struct FieldView: UIViewRepresentable {
    let renderer: Renderer
    let session: GameSession

    func makeUIView(context: Context) -> FieldMTKView {
        let view = FieldMTKView(frame: .zero, device: renderer.device)
        renderer.configure(view)
        view.isMultipleTouchEnabled = false
        view.onLayout = { [session] size, insets in
            session.layout(size: size, safeTop: insets.top, safeBottom: insets.bottom)
        }
        view.onTouch = { [session] phase, point in
            switch phase {
            case .began: session.touchBegan(at: point)
            case .moved: session.touchMoved(to: point)
            case .ended: session.touchEnded(at: point)
            case .cancelled: session.touchCancelled()
            }
        }
        return view
    }

    func updateUIView(_ view: FieldMTKView, context: Context) {}
}

final class FieldMTKView: MTKView {
    enum TouchPhase { case began, moved, ended, cancelled }

    var onTouch: ((TouchPhase, CGPoint) -> Void)?
    var onLayout: ((CGSize, UIEdgeInsets) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size, safeAreaInsets)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onLayout?(bounds.size, safeAreaInsets)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(.began, touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(.moved, touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(.ended, touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        report(.cancelled, touches)
    }

    private func report(_ phase: TouchPhase, _ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        onTouch?(phase, touch.location(in: self))
    }
}
