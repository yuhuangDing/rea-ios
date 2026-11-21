import SwiftUI
import SpriteKit
import UIKit.UIGestureRecognizerSubclass

private final class FieldTap: UITapGestureRecognizer {
    private(set) var tapCount = 1
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        tapCount = touches.first?.tapCount ?? 1
        super.touchesBegan(touches,with:event)
    }
}

struct FieldView: UIViewRepresentable {
    let session: GameSession
    func makeCoordinator() -> Gestures { Gestures(session) }
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true; view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = true; view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = true
        view.accessibilityLabel = "战场"
        view.accessibilityHint = "拖动平移，双指缩放。点单位选择，再点地面移动。"
        view.accessibilityIdentifier = "battlefield"
        view.accessibilityTraits = [.allowsDirectInteraction]
        let scene = BattleScene(session); view.presentScene(scene)
        context.coordinator.attach(view,scene); return view
    }
    func updateUIView(_ view: SKView, context: Context) {}
    static func dismantleUIView(_ view: SKView, coordinator: Gestures) { view.presentScene(nil) }

    final class Gestures: NSObject, UIGestureRecognizerDelegate {
        let session: GameSession
        weak var scene: BattleScene?
        var start: CGPoint = .zero
        var selecting = false
        init(_ session: GameSession) { self.session = session }
        func attach(_ view: SKView, _ scene: BattleScene) {
            self.scene = scene
            // The first tap issues its order immediately. UIKit counts a subsequent tap for group selection.
            let tap = FieldTap(target:self,action:#selector(tapped))
            let drag = UIPanGestureRecognizer(target:self,action:#selector(dragged))
            let pinch = UIPinchGestureRecognizer(target:self,action:#selector(pinched))
            for g: UIGestureRecognizer in [tap,drag,pinch] { g.delegate = self; view.addGestureRecognizer(g) }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) ||
            (other is UIPinchGestureRecognizer && gestureRecognizer is UIPanGestureRecognizer)
        }
        @objc private func tapped(_ g: FieldTap) { scene?.pointTap(g.location(in:g.view),double:g.tapCount == 2) }
        @objc func pinched(_ g: UIPinchGestureRecognizer) {
            guard !session.paused else { return }
            if g.state == .changed { scene?.zoom(g.scale,at:g.location(in:g.view)); g.scale = 1 }
        }
        @objc func dragged(_ g: UIPanGestureRecognizer) {
            guard !session.paused else { return }
            let position = g.location(in:g.view)
            switch g.state {
            case .began:
                let delta = g.translation(in:g.view)
                start = CGPoint(x:position.x-delta.x,y:position.y-delta.y); selecting = session.boxSelect && g.numberOfTouches == 1
            case .changed:
                if selecting { scene?.selectBox(start,position,done:false) }
                else { scene?.pan(g.translation(in:g.view)); g.setTranslation(.zero,in:g.view) }
            case .ended, .cancelled:
                if selecting { scene?.selectBox(start,position,done:true) }; selecting = false
            default: break
            }
        }
    }
}
