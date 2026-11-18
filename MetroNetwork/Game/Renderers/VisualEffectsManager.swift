import SpriteKit
import MetroCore

/// Short-lived feedback effects driven by simulation events. Sprites come from shared CC0 textures; effects
/// are throttled per station so a busy interchange never floods the scene with nodes.
@MainActor
final class VisualEffectsManager {
    let layer = SKNode()
    private var lastSparkle: [StationID: TimeInterval] = [:]
    private var clock: TimeInterval = 0

    init() {
        layer.name = "effects"
    }

    /// Points waiting to be shown per station (deliveries close together are summed into one "+N").
    private var pendingPoints: [StationID: (points: Int, position: Vec2, due: TimeInterval)] = [:]
    /// Keeps on-screen effects legible when zoomed out.
    var cameraScale: CGFloat = 1

    func advance(_ dt: TimeInterval) {
        clock += dt
        for (station, entry) in pendingPoints where clock >= entry.due {
            pendingPoints[station] = nil
            showPoints(entry.points, at: entry.position)
        }
    }

    /// Passengers getting on or off: a few small dots travel between the platform and the train.
    func passengersMoved(from: Vec2, to: Vec2, count: Int) {
        let scale = max(1, min(2, cameraScale))
        for i in 0..<min(count, 3) {
            let dot = SKShapeNode(circleOfRadius: 3.6 * scale)
            dot.fillColor = .white
            dot.strokeColor = VisualTheme.ink.sk
            dot.lineWidth = 1.4 * scale
            dot.position = CGPoint(from)
            dot.alpha = 0
            layer.addChild(dot)
            let move = SKAction.move(to: CGPoint(to), duration: 0.32)
            move.timingMode = .easeInEaseOut
            dot.run(.sequence([
                .wait(forDuration: Double(i) * 0.07),
                .fadeIn(withDuration: 0.05),
                move,
                .group([.fadeOut(withDuration: 0.12), .scale(to: 0.4, duration: 0.12)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Points from a delivery: shown as a rising "+N" shortly after (summed per station).
    func pointsScored(_ points: Int, at station: StationID, position: Vec2) {
        if var entry = pendingPoints[station] {
            entry.points += points
            pendingPoints[station] = entry
        } else {
            pendingPoints[station] = (points, position, clock + 0.25)
        }
    }

    /// Airport travellers who gave up: a grey "−N" with a car, sinking away.
    func travellersLeft(_ count: Int, position: Vec2) {
        let label = SKLabelNode(fontNamed: AppFonts.boldFontName)
        label.text = "−\(count) 🚕"
        label.fontSize = 15 * max(1, min(2.2, cameraScale))
        label.fontColor = VisualTheme.danger.darkened(0.15).sk
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: position.x, y: position.y - VisualTheme.stationRadius * 1.9)
        layer.addChild(label)
        let sink = SKAction.group([
            .moveBy(x: 0, y: -22 * max(1, cameraScale), duration: 1.1),
            .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.4)]),
        ])
        sink.timingMode = .easeOut
        label.run(.sequence([sink, .removeFromParent()]))
    }

    private func showPoints(_ points: Int, at position: Vec2) {
        let label = SKLabelNode(fontNamed: AppFonts.boldFontName)
        label.text = "+\(points)"
        label.fontSize = 17 * max(1, min(2.2, cameraScale))
        label.fontColor = VisualTheme.delivered.darkened(0.35).sk
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: position.x, y: position.y + VisualTheme.stationRadius * 1.9)
        label.setScale(0.6)
        layer.addChild(label)
        let rise = SKAction.group([
            .moveBy(x: 0, y: 26 * max(1, cameraScale), duration: 0.9),
            .sequence([.scale(to: 1, duration: 0.15), .wait(forDuration: 0.45), .fadeOut(withDuration: 0.3)]),
        ])
        rise.timingMode = .easeOut
        label.run(.sequence([rise, .removeFromParent()]))
    }

    /// A passenger reached their destination at `position`.
    func passengerDelivered(at station: StationID, position: Vec2) {
        guard clock - (lastSparkle[station] ?? -1) > 0.35 else { return }
        lastSparkle[station] = clock
        let sparkle = Textures.sprite(Textures.sparkle, size: VisualTheme.stationRadius * 3.2,
                                      color: VisualTheme.delivered.sk, alpha: 0.95)
        sparkle.position = CGPoint(x: position.x, y: position.y + VisualTheme.stationRadius * 0.4)
        sparkle.setScale(0.3)
        sparkle.zRotation = .pi / 8
        layer.addChild(sparkle)
        let pop = SKAction.group([
            .scale(to: 1.1, duration: 0.45),
            .rotate(byAngle: .pi / 4, duration: 0.6),
            .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.4)]),
            .moveBy(x: 0, y: VisualTheme.stationRadius * 0.8, duration: 0.6),
        ])
        pop.timingMode = .easeOut
        sparkle.run(.sequence([pop, .removeFromParent()]))
    }
}
