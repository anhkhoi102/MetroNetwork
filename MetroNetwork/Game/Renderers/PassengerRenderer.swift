import SpriteKit
import MetroCore

/// Waiting passengers: one glyph node per station, next to it, rebuilt only when that queue changes.
@MainActor
final class PassengerRenderer {
    let layer = SKNode()
    private var nodes: [StationID: SKShapeNode] = [:]
    private var drawn: [StationID: [StationShape]] = [:]
    private var glyphScale: CGFloat = 1

    static let glyphRadius: CGFloat = 5.4
    static let spacing: CGFloat = 14.5
    static let perRow = 6

    init() {
        layer.name = "passengers"
    }

    /// Keeps queues readable when zoomed out: glyphs grow with the camera scale (up to 2×).
    func setCameraScale(_ cameraScale: CGFloat) {
        let target = min(2, max(1, cameraScale / 1.3))
        guard abs(target - glyphScale) > 0.02 else { return }
        glyphScale = target
        for node in nodes.values { node.setScale(target) }
    }

    func sync(_ stations: [Station]) {
        for station in stations {
            let shapes = station.waiting.map(\.destination)
            guard drawn[station.id] != shapes else { continue }
            drawn[station.id] = shapes
            let node: SKShapeNode
            if let existing = nodes[station.id] {
                node = existing
            } else {
                node = SKShapeNode()
                node.fillColor = VisualTheme.ink.sk
                node.strokeColor = .clear
                // Anchored just right of the station, so scaling the queue never pushes it away.
                node.position = CGPoint(x: station.position.x + VisualTheme.stationRadius + 5,
                                        y: station.position.y)
                node.setScale(glyphScale)
                nodes[station.id] = node
                layer.addChild(node)
            }
            let origin = CGPoint(x: Self.glyphRadius + 2, y: VisualTheme.stationRadius * 0.45)
            node.path = shapes.isEmpty ? nil : PassengerGlyphs.path(for: shapes, origin: origin, perRow: Self.perRow,
                                                                    spacing: Self.spacing, radius: Self.glyphRadius)
        }
    }
}
