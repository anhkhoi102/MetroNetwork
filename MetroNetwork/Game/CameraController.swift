import SpriteKit
import MetroCore

/// Zoom and pan. `camera.xScale` = world units per screen point (bigger = zoomed out).
@MainActor
final class CameraController {
    let camera = SKCameraNode()
    private let mapBounds: CGRect
    var viewSize: CGSize = CGSize(width: 1024, height: 768) {
        didSet { clamp() }
    }
    let minScale: CGFloat = 0.3
    /// True once the player has panned or zoomed; until then the scene keeps re-framing the city on resize.
    private(set) var userMoved = false

    init(mapSize: Vec2) {
        mapBounds = CGRect(x: 0, y: 0, width: mapSize.x, height: mapSize.y)
        camera.position = CGPoint(x: mapBounds.midX, y: mapBounds.midY)
    }

    var scale: CGFloat { camera.xScale }

    /// Zoomed out far enough to see the whole map with a margin.
    var maxScale: CGFloat {
        guard viewSize.width > 0, viewSize.height > 0 else { return 4 }
        return max(minScale, max(mapBounds.width / viewSize.width, mapBounds.height / viewSize.height) * 1.1)
    }

    func pan(byWorld delta: CGPoint) {
        userMoved = true
        camera.removeAction(forKey: "fit")
        camera.position = CGPoint(x: camera.position.x + delta.x, y: camera.position.y + delta.y)
        clamp()
    }

    /// Multiplies the scale by `factor` (> 1 zooms out) keeping `anchor` (world point) under the pointer.
    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        userMoved = true
        camera.removeAction(forKey: "fit")
        let old = scale
        let new = min(maxScale, max(minScale, old * factor))
        guard new != old else { return }
        let k = new / old
        camera.setScale(new)
        camera.position = CGPoint(x: anchor.x + (camera.position.x - anchor.x) * k,
                                  y: anchor.y + (camera.position.y - anchor.y) * k)
        clamp()
    }

    /// Frames `rect` (world) with a margin.
    /// - Parameter fitMaxScale: never zoom out further than this while fitting.
    func fit(_ rect: CGRect, animated: Bool, maxScale fitMaxScale: CGFloat = .infinity) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let margin: CGFloat = 1.25
        let wanted = max(rect.width / viewSize.width, rect.height / viewSize.height) * margin
        let target = min(maxScale, fitMaxScale, max(minScale, wanted))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        camera.removeAction(forKey: "fit")
        if animated {
            let move = SKAction.group([.move(to: center, duration: 0.35), .scale(to: target, duration: 0.35)])
            move.timingMode = .easeInEaseOut
            camera.run(.sequence([move, .run { [weak self] in self?.clamp() }]), withKey: "fit")
        } else {
            camera.setScale(target)
            camera.position = center
            clamp()
        }
    }

    /// Keeps the camera centre over the map and the scale within limits.
    func clamp() {
        let s = min(maxScale, max(minScale, scale))
        if s != scale { camera.setScale(s) }
        let halfW = viewSize.width * s / 2, halfH = viewSize.height * s / 2
        func clampAxis(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ half: CGFloat) -> CGFloat {
            // When the view is wider than the map, centre it; otherwise keep the edges on screen.
            if hi - lo <= 2 * half { return (lo + hi) / 2 }
            return min(hi - half * 0.5, max(lo + half * 0.5, value))
        }
        camera.position = CGPoint(x: clampAxis(camera.position.x, mapBounds.minX, mapBounds.maxX, halfW),
                                  y: clampAxis(camera.position.y, mapBounds.minY, mapBounds.maxY, halfH))
    }
}
