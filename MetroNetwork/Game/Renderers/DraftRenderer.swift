import SpriteKit
import MetroCore

/// The rubber band that follows the pointer while a line is being drawn or edited.
@MainActor
final class DraftRenderer {
    let node = SKShapeNode()

    init() {
        node.lineCap = .round
        node.lineJoin = .round
        node.fillColor = .clear
        node.lineWidth = VisualTheme.routeMetrics.lineWidth
        node.zPosition = 15
        node.isHidden = true
    }

    /// - Parameters:
    ///   - anchors: points the band starts from (one when drawing/extending, two when inserting).
    ///   - pointer: current pointer position in world space.
    func show(anchors: [Vec2], pointer: Vec2, colorIndex: Int) {
        guard !anchors.isEmpty else { hide(); return }
        let path = CGMutablePath()
        for a in anchors {
            let points = RouteGeometry.octilinearPoints(from: a, to: pointer)
            path.move(to: CGPoint(points[0]))
            for p in points.dropFirst() { path.addLine(to: CGPoint(p)) }
        }
        node.path = path
        node.strokeColor = VisualTheme.lineColor(colorIndex).rgb.sk(alpha: 0.55)
        node.isHidden = false
    }

    func hide() {
        node.isHidden = true
        node.path = nil
    }
}
