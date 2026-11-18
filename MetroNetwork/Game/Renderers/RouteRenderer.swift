import SpriteKit
import MetroCore

/// One `SKShapeNode` per line (body + terminal handles), rebuilt only when that line's geometry changes.
@MainActor
final class RouteRenderer {
    let layer = SKNode()
    /// Geometry of what is currently drawn — also used for hit testing, so taps match the picture.
    private(set) var geometry: [LineID: LineGeometry] = [:]
    private var nodes: [LineID: LineNode] = [:]
    /// Colour and express flag currently drawn per line.
    private var drawnColor: [LineID: Int] = [:]
    private var drawnExpress: [LineID: Bool] = [:]
    private var selected: LineID?
    private var draftID: LineID?
    /// Drawbridges: how the bridge decks are drawn right now.
    private var bridgeState: BridgeState = .down
    private let metrics = VisualTheme.routeMetrics
    private let map: MapDefinition

    init(map: MapDefinition) {
        self.map = map
        layer.name = "routes"
    }

    /// - Parameter draft: line being edited; replaces the committed line with the same id, or is added.
    func sync(lines: [MetroLine], positions: [StationID: Vec2], draft: MetroLine?) {
        var drawn = lines
        if let draft {
            if let i = drawn.firstIndex(where: { $0.id == draft.id }) { drawn[i] = draft } else { drawn.append(draft) }
        }
        draftID = draft?.id
        let newGeometry = RouteGeometry.build(lines: drawn, positions: positions, metrics: metrics, map: map)

        for line in drawn {
            guard let g = newGeometry[line.id] else { continue }
            let node: LineNode
            if let existing = nodes[line.id] {
                node = existing
            } else {
                node = LineNode()
                nodes[line.id] = node
                layer.addChild(node)
            }
            if geometry[line.id] != g || drawnColor[line.id] != line.colorIndex || drawnExpress[line.id] != line.isExpress {
                node.update(geometry: g, color: VisualTheme.lineColor(line.colorIndex).rgb, metrics: metrics, map: map,
                            express: line.isExpress)
                drawnColor[line.id] = line.colorIndex
                drawnExpress[line.id] = line.isExpress
            }
            // Lower line ids sit underneath; the draft always floats on top (stays within the layer's band).
            node.zPosition = line.id == draftID ? 0.45 : CGFloat(min(line.id.raw, 400)) * 0.001
        }
        let alive = Set(drawn.map(\.id))
        for (id, node) in nodes where !alive.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
            drawnColor[id] = nil
            drawnExpress[id] = nil
        }
        geometry = newGeometry
        for node in nodes.values { node.setBridge(bridgeState) }
        applyEmphasis()
    }

    /// A brief glow along a newly built line.
    /// Drawbridges: amber decks just before a lift, red while the bridges are up.
    func setBridges(_ state: BridgeState) {
        guard state != bridgeState else { return }
        bridgeState = state
        for node in nodes.values { node.setBridge(state) }
    }

    func flash(_ id: LineID) {
        nodes[id]?.flash()
    }

    func setSelected(_ id: LineID?) {
        selected = id
        applyEmphasis()
    }

    /// Selected (or edited) line stands out; others fade a little.
    private func applyEmphasis() {
        let focus = draftID ?? selected
        for (id, node) in nodes {
            node.setEmphasis(focus == nil ? .normal : (id == focus ? .focused : .dimmed))
        }
    }
}

@MainActor
private final class LineNode: SKNode {
    enum Emphasis { case normal, focused, dimmed }

    private let halo = SKShapeNode()
    /// Slightly darker edge under the line: keeps it crisp against the light map and where lines cross.
    private let casing = SKShapeNode()
    private let body = SKShapeNode()
    /// Bridge deck (light, with a grey edge) under the parts of the line that cross water.
    private let deckEdge = SKShapeNode()
    private let deck = SKShapeNode()
    /// Express lines: a thin white stripe down the middle.
    private let stripe = SKShapeNode()
    /// Drawbridges: a boat badge in the middle of each bridge, shown while the bridges are up.
    private let liftBadges = SKNode()
    private var bridge: BridgeState = .down

    override init() {
        super.init()
        for n in [deckEdge, deck, halo, casing, body, stripe] {
            n.lineCap = .round
            n.lineJoin = .round
            n.fillColor = .clear
            n.isAntialiased = true
            addChild(n)
        }
        halo.strokeColor = SKColor(white: 1, alpha: 0.85)
        halo.isHidden = true
        halo.zPosition = -0.5
        casing.zPosition = -0.25
        stripe.zPosition = 0.1
        stripe.strokeColor = SKColor(white: 1, alpha: 0.9)
        deckEdge.zPosition = -0.8
        deck.zPosition = -0.7
        deckEdge.strokeColor = VisualTheme.bridgeEdge.sk
        deck.strokeColor = VisualTheme.bridge.sk
        deckEdge.lineCap = .butt
        deck.lineCap = .butt
        liftBadges.zPosition = 0.3
        liftBadges.isHidden = true
        addChild(liftBadges)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setBridge(_ state: BridgeState) {
        bridge = state
        liftBadges.isHidden = state != .up
        switch state {
        case .down:
            deck.strokeColor = VisualTheme.bridge.sk
            deckEdge.strokeColor = VisualTheme.bridgeEdge.sk
        case .warning:
            deck.strokeColor = VisualTheme.warning.mixed(with: VisualTheme.bridge, 0.45).sk
            deckEdge.strokeColor = VisualTheme.warning.sk
        case .up:
            deck.strokeColor = VisualTheme.danger.mixed(with: VisualTheme.bridge, 0.35).sk
            deckEdge.strokeColor = VisualTheme.danger.sk
        }
    }

    /// White disc with a red boat, like a station badge.
    private static func liftBadge() -> SKNode {
        let node = SKNode()
        let disc = SKShapeNode(circleOfRadius: 11)
        disc.fillColor = .white
        disc.strokeColor = VisualTheme.danger.sk
        disc.lineWidth = 2.5
        node.addChild(disc)
        let texture = Textures.symbol("ferry.fill", color: VisualTheme.danger)
        let icon = SKSpriteNode(texture: texture)
        let size = texture.size()
        let scale = 13 / max(size.width, size.height, 1)
        icon.size = CGSize(width: size.width * scale, height: size.height * scale)
        icon.zPosition = 0.1
        node.addChild(icon)
        return node
    }

    func update(geometry: LineGeometry, color: RGB, metrics: RouteMetrics, map: MapDefinition, express: Bool) {
        let spans = geometry.segments.flatMap { RouteGeometry.waterSpans(of: $0.points, map: map) }
        let bridges = CGMutablePath()
        for span in spans {
            guard let first = span.first else { continue }
            // Extend the deck a little onto each bank.
            let lead = span.count > 1 ? (span[1] - first).normalized * 6 : Vec2(0, 0)
            let tail = span.count > 1 ? (span[span.count - 1] - span[span.count - 2]).normalized * 6 : Vec2(0, 0)
            bridges.move(to: CGPoint(first - lead))
            for p in span.dropFirst().dropLast() { bridges.addLine(to: CGPoint(p)) }
            if let last = span.last { bridges.addLine(to: CGPoint(last + tail)) }
        }
        deck.path = bridges
        deckEdge.path = bridges
        liftBadges.removeAllChildren()
        for span in spans where span.count > 1 {
            let mid = Vec2.lerp(span.first!, span.last!, 0.5)
            let badge = Self.liftBadge()
            badge.position = CGPoint(mid)
            liftBadges.addChild(badge)
        }
        deck.lineWidth = metrics.lineWidth + 8
        deckEdge.lineWidth = metrics.lineWidth + 12

        let path = Self.path(for: geometry, metrics: metrics)
        body.path = path
        body.strokeColor = color.sk
        stripe.path = express ? path : nil
        stripe.lineWidth = metrics.lineWidth * 0.28
        body.lineWidth = metrics.lineWidth
        casing.path = path
        casing.strokeColor = color.darkened(0.22).sk
        casing.lineWidth = metrics.lineWidth + 2.5
        halo.path = path
        halo.lineWidth = metrics.lineWidth + 7
    }

    func flash() {
        guard let path = body.path else { return }
        let glow = SKShapeNode(path: path)
        glow.strokeColor = body.strokeColor.withAlphaComponent(0.55)
        glow.lineWidth = body.lineWidth + 6
        glow.lineCap = .round
        glow.lineJoin = .round
        glow.fillColor = .clear
        glow.zPosition = -0.6
        addChild(glow)
        let base = body.lineWidth + 6
        let widen = SKAction.customAction(withDuration: 0.6) { node, t in
            (node as? SKShapeNode)?.lineWidth = base + 22 * t / 0.6
        }
        glow.run(.sequence([.group([widen, .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
    }

    func setEmphasis(_ emphasis: Emphasis) {
        halo.isHidden = emphasis != .focused
        alpha = emphasis == .dimmed ? 0.4 : 1
    }

    static func path(for g: LineGeometry, metrics: RouteMetrics) -> CGPath {
        let path = CGMutablePath()
        // Only the bend inside a segment is rounded. Station points stay sharp, so the line always passes
        // exactly through every station, even where it turns back sharply.
        for (index, segment) in g.segments.enumerated() {
            let points = segment.points.map(CGPoint.init)
            guard let first = points.first, let last = points.last else { continue }
            if index == 0 { path.move(to: first) } else { path.addLine(to: first) }
            if points.count >= 3 {
                for i in 1..<(points.count - 1) {
                    let prev = points[i - 1], p = points[i], next = points[i + 1]
                    let maxRadius = min(hypot(p.x - prev.x, p.y - prev.y), hypot(next.x - p.x, next.y - p.y)) / 2
                    path.addArc(tangent1End: p, tangent2End: next, radius: min(metrics.bendRadius, maxRadius))
                }
            }
            path.addLine(to: last)
        }
        for h in g.handles {
            let anchor = CGPoint(h.anchor), tip = CGPoint(h.tip)
            let bar = h.direction.perpendicular * metrics.handleBarHalfWidth
            path.move(to: anchor)
            path.addLine(to: tip)
            path.move(to: CGPoint(h.tip + bar))
            path.addLine(to: CGPoint(h.tip - bar))
        }
        return path
    }
}

/// How drawbridge decks are drawn.
enum BridgeState: Equatable {
    case down, warning, up
}
