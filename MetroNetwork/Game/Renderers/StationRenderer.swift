import SpriteKit
import MetroCore

/// One small node group per station: shadow, body, selection ring. Nodes are created once and reused.
@MainActor
final class StationRenderer {
    let layer = SKNode()
    private var nodes: [StationID: StationNode] = [:]
    private var selected: StationID?

    init() {
        layer.name = "stations"
    }

    /// Adds nodes for new stations. `animate` = stations that just spawned (pop-in).
    func sync(_ stations: [Station], animate: Set<StationID>) {
        for station in stations where nodes[station.id] == nil {
            let node = StationNode(station: station)
            nodes[station.id] = node
            layer.addChild(node)
            if animate.contains(station.id) { node.playSpawnAnimation() }
        }
        let alive = Set(stations.map(\.id))
        for (id, node) in nodes where !alive.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    /// Overcrowding timers and expansions; cheap to call every frame (nodes only change when values do).
    func updateCongestion(_ stations: [Station]) {
        for station in stations {
            nodes[station.id]?.setExpansions(station.expansions)
            nodes[station.id]?.setOvercrowding(station.overcrowding)
        }
    }

    /// Closures, surges and warnings of upcoming events.
    func updateEvents(_ state: GameState) {
        var status: [StationID: StationNode.EventStatus] = [:]
        for event in state.events {
            guard let id = event.station else { continue }
            let running = event.isActive(at: state.elapsed)
            switch event.kind {
            case .closure: status[id] = running ? .closed : .warning
            case .surge: status[id] = running ? .surge : .warning
            case .touristGroup: status[id] = .warning
            case .maintenance: break
            }
        }
        if let match = VenueManager.nextMatch(in: state), let warning = state.config.venues?.matchWarning {
            if state.elapsed >= match.fullTime { status[match.stadium] = .surge }
            else if match.fullTime - state.elapsed <= warning { status[match.stadium] = .warning }
        }
        for (id, node) in nodes { node.setEventStatus(status[id] ?? .none) }
    }

    /// The station that ended the game: a red pulse that keeps going.
    func markFailed(_ id: StationID) {
        nodes[id]?.playFailure()
    }

    func setSelected(_ id: StationID?) {
        guard id != selected else { return }
        if let old = selected { nodes[old]?.setSelected(false) }
        selected = id
        if let id { nodes[id]?.setSelected(true) }
    }

    /// Emphasises the station a drag would snap to.
    func setHighlighted(_ id: StationID?) {
        for (sid, node) in nodes { node.setHighlighted(sid == id) }
    }
}

@MainActor
private final class StationNode: SKNode {
    private let body: SKShapeNode
    private let ring: SKShapeNode
    private let halo: SKSpriteNode
    private var isHighlighted = false
    /// Overcrowding timer: a faint track and an arc that fills clockwise from the top.
    private let crowdTrack: SKShapeNode
    private let crowdArc = SKShapeNode()
    private let crowdGlow: SKSpriteNode
    private var drawnOvercrowding = 0.0
    /// One outer platform ring per expansion.
    private let platforms = SKShapeNode()
    private var drawnExpansions = 0

    private static let crowdRadius = VisualTheme.stationRadius * 1.55

    enum EventStatus { case none, warning, closed, surge }
    private var eventStatus = EventStatus.none
    /// Event marker: dashed ring (warning), orange pulse (surge), grey bar across the station (closed).
    private let eventRing = SKShapeNode(circleOfRadius: VisualTheme.stationRadius * 2.1)
    private let closedBar = SKShapeNode()

    init(station: Station) {
        let r = VisualTheme.stationRadius
        let path = ShapePaths.path(for: station.shape, radius: r)

        // Soft contact shadow instead of a hard offset copy.
        let shadow = Textures.sprite(Textures.glow, size: r * 3.4, color: .black, alpha: 0.32)
        shadow.position = CGPoint(x: 1.5, y: -3.5)
        shadow.zPosition = -0.6   // the view ignores sibling order, so layering is explicit

        body = SKShapeNode(path: path)
        body.fillColor = VisualTheme.stationFill.sk
        body.strokeColor = VisualTheme.stationStroke.sk
        body.lineWidth = VisualTheme.stationStrokeWidth
        body.lineJoin = .round
        body.zPosition = 0.5

        ring = SKShapeNode(circleOfRadius: r * 1.85)
        ring.strokeColor = VisualTheme.selection.sk
        ring.fillColor = VisualTheme.selection.sk(alpha: 0.12)
        ring.lineWidth = 3.5
        ring.isHidden = true
        ring.zPosition = -1

        halo = Textures.sprite(Textures.glow, size: r * 6, color: VisualTheme.selection.sk, alpha: 0.45)
        halo.zPosition = -1.2
        halo.isHidden = true

        crowdTrack = SKShapeNode(circleOfRadius: Self.crowdRadius)
        crowdTrack.strokeColor = VisualTheme.warning.sk(alpha: 0.22)
        crowdTrack.lineWidth = 5
        crowdTrack.fillColor = .clear
        crowdTrack.zPosition = 0.2
        crowdTrack.isHidden = true
        crowdArc.lineWidth = 5
        crowdArc.lineCap = .round
        crowdArc.fillColor = .clear
        crowdArc.zPosition = 0.3
        crowdArc.isHidden = true
        crowdGlow = Textures.sprite(Textures.glow, size: r * 6.5, color: VisualTheme.danger.sk, alpha: 0.5)
        crowdGlow.zPosition = -1.3
        crowdGlow.isHidden = true

        platforms.strokeColor = VisualTheme.stationStroke.sk(alpha: 0.85)
        platforms.fillColor = .clear
        platforms.lineWidth = 2.5
        platforms.zPosition = 0.1

        super.init()
        position = CGPoint(station.position)

        eventRing.fillColor = .clear
        eventRing.lineWidth = 3
        eventRing.isHidden = true
        eventRing.zPosition = -0.9
        let bar = CGMutablePath()
        bar.move(to: CGPoint(x: -r * 1.1, y: -r * 1.1))
        bar.addLine(to: CGPoint(x: r * 1.1, y: r * 1.1))
        closedBar.path = bar
        closedBar.strokeColor = VisualTheme.danger.sk
        closedBar.lineWidth = 5
        closedBar.lineCap = .round
        closedBar.zPosition = 0.8
        closedBar.isHidden = true
        addChild(eventRing)
        addChild(closedBar)

        if let special = station.special {
            let badge = Self.badge(for: special)
            badge.position = CGPoint(x: -r * 1.05, y: r * 1.05)
            badge.zPosition = 0.9
            addChild(badge)
        }
        addChild(halo)
        addChild(ring)
        addChild(shadow)
        addChild(body)
        addChild(platforms)
        addChild(crowdGlow)
        addChild(crowdTrack)
        addChild(crowdArc)
    }

    func setEventStatus(_ status: EventStatus) {
        guard status != eventStatus else { return }
        eventStatus = status
        eventRing.removeAllActions()
        eventRing.setScale(1)
        eventRing.alpha = 1
        closedBar.isHidden = status != .closed
        body.fillColor = status == .closed ? SKColor(white: 0.86, alpha: 1) : VisualTheme.stationFill.sk
        switch status {
        case .none, .closed:
            eventRing.isHidden = true
        case .warning:
            eventRing.isHidden = false
            eventRing.strokeColor = VisualTheme.ink.sk(alpha: 0.7)
            eventRing.path = Self.dashedCircle(radius: VisualTheme.stationRadius * 2.1)
            eventRing.run(.repeatForever(.rotate(byAngle: -.pi, duration: 3)))
        case .surge:
            eventRing.isHidden = false
            eventRing.strokeColor = VisualTheme.warning.sk
            eventRing.path = CGPath(ellipseIn: CGRect(x: -VisualTheme.stationRadius * 2.1, y: -VisualTheme.stationRadius * 2.1,
                                                     width: VisualTheme.stationRadius * 4.2, height: VisualTheme.stationRadius * 4.2),
                                    transform: nil)
            let pulse = SKAction.sequence([.group([.scale(to: 1.3, duration: 0.8), .fadeAlpha(to: 0.2, duration: 0.8)]),
                                           .group([.scale(to: 1, duration: 0), .fadeAlpha(to: 1, duration: 0)])])
            eventRing.run(.repeatForever(pulse))
        }
    }

    private static func dashedCircle(radius: CGFloat) -> CGPath {
        let circle = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius), transform: nil)
        return circle.copy(dashingWithPhase: 0, lengths: [7, 6])
    }

    /// Small white disc with the special station's symbol.
    private static func badge(for special: SpecialStation) -> SKNode {
        let node = SKNode()
        let disc = SKShapeNode(circleOfRadius: 9.5)
        disc.fillColor = .white
        disc.strokeColor = VisualTheme.specialColor(special).sk
        disc.lineWidth = 2
        node.addChild(disc)
        let texture = Textures.symbol(VisualTheme.specialSymbol(special), color: VisualTheme.specialColor(special))
        let icon = SKSpriteNode(texture: texture)
        let size = texture.size()
        let scale = 11 / max(size.width, size.height, 1)
        icon.size = CGSize(width: size.width * scale, height: size.height * scale)
        icon.zPosition = 0.1
        node.addChild(icon)
        return node
    }

    func setExpansions(_ count: Int) {
        guard count != drawnExpansions else { return }
        drawnExpansions = count
        let path = CGMutablePath()
        let r = VisualTheme.stationRadius
        for k in 0..<count {
            let radius = r * 1.12 + CGFloat(k) * 4.5
            path.addEllipse(in: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
        }
        platforms.path = path
        body.setScale(1)
        body.run(.sequence([.scale(to: 1.2, duration: 0.12), .scale(to: 1, duration: 0.18)]))
    }

    func setOvercrowding(_ value: Double) {
        guard abs(value - drawnOvercrowding) > 0.004 || (value == 0) != (drawnOvercrowding == 0) else { return }
        drawnOvercrowding = value
        let active = value > 0
        crowdTrack.isHidden = !active
        crowdArc.isHidden = !active
        crowdGlow.isHidden = value < 0.5
        guard active else {
            crowdGlow.removeAllActions()
            return
        }
        let start = CGFloat.pi / 2
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: Self.crowdRadius, startAngle: start,
                    endAngle: start - CGFloat(value) * 2 * .pi, clockwise: true)
        crowdArc.path = path
        // Amber while there is time, red when it's urgent.
        let t = min(1, max(0, (value - 0.3) / 0.5))
        crowdArc.strokeColor = VisualTheme.warning.mixed(with: VisualTheme.danger, t).sk
        if value >= 0.5, crowdGlow.action(forKey: "pulse") == nil {
            let pulse = SKAction.sequence([.fadeAlpha(to: 0.15, duration: 0.45), .fadeAlpha(to: 0.6, duration: 0.45)])
            crowdGlow.run(.repeatForever(pulse), withKey: "pulse")
        }
    }

    func playFailure() {
        crowdGlow.isHidden = false
        crowdGlow.removeAllActions()
        crowdGlow.alpha = 0.7
        let pulse = SKAction.sequence([.scale(to: 1.5, duration: 0.6), .scale(to: 1, duration: 0.6)])
        pulse.timingMode = .easeInEaseOut
        crowdGlow.run(.repeatForever(pulse))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setSelected(_ selected: Bool) {
        ring.isHidden = !selected
        halo.isHidden = !selected
        ring.removeAllActions()
        halo.removeAllActions()
        if selected {
            ring.setScale(0.7)
            ring.run(.scale(to: 1, duration: 0.15))
            let breathe = SKAction.sequence([.scale(to: 1.12, duration: 0.9), .scale(to: 0.94, duration: 0.9)])
            breathe.timingMode = .easeInEaseOut
            halo.run(.repeatForever(breathe))
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        body.removeAction(forKey: "hl")
        body.run(.scale(to: highlighted ? 1.25 : 1, duration: 0.08), withKey: "hl")
    }

    func playSpawnAnimation() {
        setScale(0.01)
        let pop = SKAction.sequence([
            .scale(to: 1.25, duration: 0.22),
            .scale(to: 1.0, duration: 0.14),
        ])
        pop.timingMode = .easeOut
        run(pop)

        let pulse = Textures.sprite(Textures.glow, size: VisualTheme.stationRadius * 3, color: VisualTheme.ink.sk, alpha: 0.35)
        pulse.zPosition = -2
        addChild(pulse)
        let grow = SKAction.group([.scale(to: 3.4, duration: 1.0), .fadeOut(withDuration: 1.0)])
        grow.timingMode = .easeOut
        pulse.run(.sequence([grow, .removeFromParent()]))
    }
}
