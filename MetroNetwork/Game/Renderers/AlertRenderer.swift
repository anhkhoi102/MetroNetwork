import SpriteKit
import MetroCore

/// Arrows at the edge of the screen pointing to overcrowding stations that are out of view, so trouble is
/// never missed while the player looks elsewhere. Attached to the camera; nodes are pooled.
@MainActor
final class AlertRenderer {
    let layer = SKNode()
    private var arrows: [SKNode] = []

    init() {
        layer.name = "alerts"
        layer.zPosition = 50
    }

    /// - Parameters:
    ///   - center/scale: the camera (world units per point); `viewSize` in points. Children of the camera are
    ///     laid out in screen points, so world distances are divided by `scale`.
    func update(stations: [Station], center: CGPoint, scale: CGFloat, viewSize: CGSize) {
        let halfW = viewSize.width / 2 * scale, halfH = viewSize.height / 2 * scale
        // Keep clear of the HUD at the top and cards at the bottom.
        let marginX = 34 * scale, marginTop = 96 * scale, marginBottom = 60 * scale
        var used = 0
        for station in stations where station.overcrowding > 0.2 {
            let dx = station.position.x - center.x, dy = station.position.y - center.y
            let outside = abs(dx) > halfW - 10 * scale || abs(dy) > halfH - 10 * scale
            guard outside else { continue }
            let maxX = halfW - marginX
            let maxY = dy > 0 ? halfH - marginTop : halfH - marginBottom
            // Scale the direction vector onto the inset rectangle.
            let k = min(maxX / max(abs(dx), 1e-6), maxY / max(abs(dy), 1e-6))
            let arrow = node(at: used)
            used += 1
            arrow.position = CGPoint(x: dx * k / scale, y: dy * k / scale)
            arrow.zRotation = atan2(dy, dx)
            arrow.children.last?.zRotation = -arrow.zRotation       // keep the "!" upright
            let urgent = station.overcrowding > 0.6
            (arrow.children.first as? SKShapeNode)?.fillColor = (urgent ? VisualTheme.danger : VisualTheme.warning).sk
            arrow.isHidden = false
            if urgent, arrow.action(forKey: "pulse") == nil {
                arrow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.35), .fadeAlpha(to: 1, duration: 0.35)])),
                          withKey: "pulse")
            } else if !urgent {
                arrow.removeAction(forKey: "pulse")
                arrow.alpha = 1
            }
        }
        for i in used..<arrows.count { arrows[i].isHidden = true }
    }

    private func node(at index: Int) -> SKNode {
        if index < arrows.count { return arrows[index] }
        let node = SKNode()
        let disc = SKShapeNode(circleOfRadius: 15)
        disc.strokeColor = .white
        disc.lineWidth = 2.5
        node.addChild(disc)
        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: 20, y: 0))
        tip.addLine(to: CGPoint(x: 9, y: 8))
        tip.addLine(to: CGPoint(x: 9, y: -8))
        tip.closeSubpath()
        let arrowHead = SKShapeNode(path: tip)
        arrowHead.fillColor = .white
        arrowHead.strokeColor = .clear
        node.addChild(arrowHead)
        let mark = SKLabelNode(fontNamed: AppFonts.boldFontName)
        mark.text = "!"
        mark.fontSize = 18
        mark.fontColor = .white
        mark.verticalAlignmentMode = .center
        mark.horizontalAlignmentMode = .center
        node.addChild(mark)
        layer.addChild(node)
        arrows.append(node)
        return node
    }
}
