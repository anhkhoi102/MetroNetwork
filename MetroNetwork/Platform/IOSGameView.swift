#if os(iOS)
import UIKit
import SpriteKit

/// iOS input: one finger edits (on stations, handles, lines) or pans (on empty map);
/// pinch zooms; two fingers pan. A second finger always cancels an edit in progress.
final class IOSGameView: SKView, UIGestureRecognizerDelegate {
    private var gameScene: GameScene? { scene as? GameScene }
    private weak var trackedTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Single-finger pointer

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count
        if trackedTouch == nil, active == 1, let touch = touches.first {
            trackedTouch = touch
            gameScene?.input.pointerDown(at: touch.location(in: self))
        } else {
            trackedTouch = nil
            gameScene?.input.cancel()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        gameScene?.input.pointerMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        trackedTouch = nil
        gameScene?.input.pointerUp(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedTouch = nil
        gameScene?.input.cancel()
    }

    // MARK: Gestures

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .changed, recognizer.scale > 0 else { return }
        gameScene?.zoom(by: 1 / recognizer.scale, aroundView: recognizer.location(in: self))
        recognizer.scale = 1
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed, let scene = gameScene else { return }
        let t = recognizer.translation(in: self)
        let s = scene.cameraController.scale
        scene.cameraController.pan(byWorld: CGPoint(x: -t.x * s, y: t.y * s))
        recognizer.setTranslation(.zero, in: self)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
