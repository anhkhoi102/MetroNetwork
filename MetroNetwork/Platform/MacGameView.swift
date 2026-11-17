#if os(macOS)
import AppKit
import SpriteKit

/// macOS input: left-drag edits or pans, right/middle-drag pans, two-finger scroll pans,
/// pinch or mouse wheel zooms, keyboard shortcuts. Everything is forwarded to the shared InputController.
final class MacGameView: SKView {
    private var gameScene: GameScene? { scene as? GameScene }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI may still hold focus on the button that opened the game; take it on the next turn so
        // keyboard shortcuts work immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    private func viewPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        gameScene?.input.pointerDown(at: viewPoint(event))
    }

    override func mouseDragged(with event: NSEvent) {
        gameScene?.input.pointerMoved(to: viewPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        gameScene?.input.pointerUp(at: viewPoint(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        gameScene?.input.pointerDown(at: viewPoint(event), forcePan: true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        gameScene?.input.pointerMoved(to: viewPoint(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        gameScene?.input.pointerUp(at: viewPoint(event))
    }

    override func otherMouseDown(with event: NSEvent) { rightMouseDown(with: event) }
    override func otherMouseDragged(with event: NSEvent) { rightMouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { rightMouseUp(with: event) }

    // MARK: Trackpad and wheel

    override func scrollWheel(with event: NSEvent) {
        guard let scene = gameScene else { return }
        let point = viewPoint(event)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Two-finger trackpad scroll pans the map.
            let s = scene.cameraController.scale
            scene.cameraController.pan(byWorld: CGPoint(x: -event.scrollingDeltaX * s, y: event.scrollingDeltaY * s))
        } else {
            // Mouse wheel (or ⌘ + scroll) zooms around the cursor.
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            scene.zoom(by: CGFloat(exp(-step)), aroundView: point)
        }
    }

    override func magnify(with event: NSEvent) {
        gameScene?.zoom(by: 1 / (1 + event.magnification), aroundView: viewPoint(event))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let controller = gameScene?.controller else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: controller.togglePause()                       // space
        case 51, 117: controller.deleteSelectedLine()           // delete, forward delete
        case 53: controller.cancelOrDeselect()                  // escape
        case 48: controller.cycleSpeed()                        // tab
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": controller.fitCity()
            case "d": controller.toggleDepot()
            case "=", "+": controller.zoomIn()
            case "-", "_": controller.zoomOut()
            case let c? where c.count == 1 && ("1"..."7").contains(c):
                controller.selectLineSlot(Int(c)! - 1)
            default: super.keyDown(with: event)
            }
        }
    }
}
#endif
