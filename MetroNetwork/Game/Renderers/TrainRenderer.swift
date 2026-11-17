import SpriteKit
import MetroCore

/// Trains: a small car in the line colour carrying its passengers as glyphs. Positions come from the
/// simulation (`from`, `to`, `progress`) mapped onto the line as it is drawn (offsets and bends included).
@MainActor
final class TrainRenderer {
    let layer = SKNode()
    private var nodes: [TrainID: TrainNode] = [:]
    /// World position of every train this frame (for hit testing).
    private(set) var positions: [TrainID: Vec2] = [:]
    private var selected: TrainID?
    /// Line each train last served, so a withdrawn train keeps following its line's drawn path to the next stop.
    private var servedLine: [TrainID: LineID] = [:]
    /// Last drawn path of each train's current trip; reused if its line disappears mid-trip (deleted).
    private var tripPath: [TrainID: (from: StationID, to: StationID, points: [Vec2])] = [:]

    init() {
        layer.name = "trains"
    }

    func sync(state: GameState, geometry: [LineID: LineGeometry], dt: Double) {
        var alive = Set<TrainID>()
        // Stations never move: rebuild the lookup only when one is added.
        if stationPositions.count != state.stations.count { stationPositions = state.stationPositions }
        for train in state.trains {
            alive.insert(train.id)
            let node: TrainNode
            if let existing = nodes[train.id], existing.matches(train) {
                node = existing
            } else {
                let colorIndex = train.lineID.flatMap { state.line($0)?.colorIndex } ?? 0
                node = TrainNode(train: train, color: VisualTheme.lineColor(colorIndex).rgb,
                                 baseCapacity: state.config.trainCapacity)
                if let old = nodes[train.id] {
                    // Carriage coupled or motor fitted: swap in the new car where the old one was.
                    node.adopt(from: old)
                    old.removeFromParent()
                    node.setScale(trainScale)
                    node.playUpgrade(to: trainScale)
                } else {
                    node.playAppear(to: trainScale)
                }
                nodes[train.id] = node
                layer.addChild(node)
            }
            if let line = train.lineID.flatMap({ state.line($0) }) {
                node.setColor(VisualTheme.lineColor(line.colorIndex).rgb)
            }
            node.setRetiring(train.isRetiring || train.maintenanceUntil != nil)   // faded while out of service
            node.setPassengers(train.passengers.map(\.destination))
            if let line = train.lineID { servedLine[train.id] = line }

            let (point, direction) = placement(of: train, line: train.lineID ?? servedLine[train.id],
                                               in: state, geometry: geometry)
            node.position = CGPoint(point)
            positions[train.id] = point
            node.turn(towards: direction, dt: dt)
            node.setSelected(train.id == selected)
        }
        for (id, node) in nodes where !alive.contains(id) {
            node.playDisappear()
            nodes[id] = nil
            positions[id] = nil
            servedLine[id] = nil
            tripPath[id] = nil
            lastHeading[id] = nil
        }
    }

    /// A small bounce when passengers get on or off.
    func bump(_ id: TrainID) {
        guard let node = nodes[id], node.action(forKey: "appear") == nil else { return }
        let s = trainScale
        node.run(.sequence([.scale(to: s * 1.12, duration: 0.08), .scale(to: s, duration: 0.14)]), withKey: "appear")
    }

    func setSelected(_ id: TrainID?) {
        selected = id
    }

    private var trainScale: CGFloat = 1
    private var stationPositions: [StationID: Vec2] = [:]

    /// Trains grow a little when zoomed out (up to 1.6×) so their load stays readable on small screens.
    func setCameraScale(_ cameraScale: CGFloat) {
        let target = min(1.6, max(1, cameraScale / 1.4))
        guard abs(target - trainScale) > 0.02 else { return }
        trainScale = target
        for node in nodes.values where node.action(forKey: "appear") == nil { node.setScale(target) }
    }

    /// Where a train is drawn: along its line's drawn segment if there is one (or the one it was on when its
    /// line was deleted), else the plain octilinear path.
    private func placement(of train: Train, line: LineID?, in state: GameState,
                           geometry: [LineID: LineGeometry]) -> (Vec2, Vec2) {
        guard let a = stationPositions[train.from], let b = stationPositions[train.to] else {
            return (.zero, Vec2(1, 0))
        }
        guard train.from != train.to else {
            // Waiting at its first stop: face along the line, towards the next station.
            return (b, Self.departureDirection(at: train.to, line: line, geometry: geometry) ?? lastDirection(train.id))
        }

        var points: [Vec2]?
        if let lineID = line, let segments = geometry[lineID]?.segments {
            if let s = segments.first(where: { $0.from == train.from && $0.to == train.to }) {
                points = s.points
            } else if let s = segments.first(where: { $0.from == train.to && $0.to == train.from }) {
                points = s.points.reversed()
            }
        }
        if points == nil, let cached = tripPath[train.id], cached.from == train.from, cached.to == train.to {
            points = cached.points
        }
        let path = points ?? RouteGeometry.octilinearPoints(from: a, to: b)
        tripPath[train.id] = (train.from, train.to, path)

        let drawnLength = zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let tripLength = TrainManager.tripLength(train, in: state)
        let fraction = tripLength > 0 ? min(1, train.progress / tripLength) : 1
        let placed = RouteGeometry.point(along: path, distance: fraction * drawnLength)
        lastHeading[train.id] = placed.direction
        return placed
    }

    private var lastHeading: [TrainID: Vec2] = [:]

    private func lastDirection(_ id: TrainID) -> Vec2 { lastHeading[id] ?? Vec2(1, 0) }

    /// Direction of the drawn line leaving `station`, if the line has a segment there.
    private static func departureDirection(at station: StationID, line: LineID?,
                                           geometry: [LineID: LineGeometry]) -> Vec2? {
        guard let line, let segments = geometry[line]?.segments else { return nil }
        if let s = segments.first(where: { $0.from == station }), s.points.count > 1 {
            return (s.points[1] - s.points[0]).normalized
        }
        if let s = segments.first(where: { $0.to == station }), s.points.count > 1 {
            return (s.points[s.points.count - 2] - s.points[s.points.count - 1]).normalized
        }
        return nil
    }
}

@MainActor
private final class TrainNode: SKNode {
    /// The car turns with the track; passenger glyphs stay upright (a rotated triangle reads as an arrow).
    private let car = SKNode()
    private let body: SKShapeNode
    private let glyphs = SKShapeNode()
    private let outline: SKShapeNode
    private let shadow: SKSpriteNode
    /// Lamp at the leading end, so you can see which way a train is going.
    private let headlight: SKShapeNode
    private let carLength: CGFloat
    private var facing: CGFloat = 1
    private var color: RGB
    private var shapes: [StationShape] = []
    private var heading: CGFloat = 0
    private var glyphHeading: CGFloat = .nan
    private let columns: Int
    let capacity: Int
    let hasMotor: Bool

    static let width: CGFloat = 25
    static let glyphSpacing: CGFloat = 12

    init(train: Train, color: RGB, baseCapacity: Int) {
        self.color = color
        capacity = train.capacity
        hasMotor = train.hasMotor
        columns = max(1, (train.capacity + 1) / 2)
        let length = CGFloat(columns) * Self.glyphSpacing + 10
        carLength = length
        let rect = CGRect(x: -length / 2, y: -Self.width / 2, width: length, height: Self.width)
        body = SKShapeNode(rect: rect, cornerRadius: 6)
        body.fillColor = color.sk
        body.strokeColor = color.darkened(0.25).sk
        body.lineWidth = 2
        shadow = Textures.sprite(Textures.glow, size: 1, color: .black, alpha: 0.3)
        shadow.size = CGSize(width: length * 1.5, height: Self.width * 1.9)
        shadow.position = CGPoint(x: 1.5, y: -3)
        shadow.zPosition = -0.8
        headlight = SKShapeNode(rect: CGRect(x: -2, y: -Self.width / 2 + 5, width: 4, height: Self.width - 10),
                                cornerRadius: 2)
        headlight.fillColor = SKColor(red: 1, green: 0.97, blue: 0.82, alpha: 1)
        headlight.strokeColor = .clear
        headlight.position = CGPoint(x: length / 2 - 3.5, y: 0)
        headlight.zPosition = 0.2
        outline = SKShapeNode(rect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 8)
        outline.strokeColor = .white
        outline.lineWidth = 3
        outline.fillColor = .clear
        outline.isHidden = true
        outline.zPosition = -0.5
        // Couplings between the locomotive and each carriage.
        let joints = CGMutablePath()
        let baseColumns = max(1, (baseCapacity + 1) / 2)
        if columns > baseColumns {
            let perCarriage = max(1, (columns - baseColumns) / max(1, train.carriages))
            var col = baseColumns
            while col < columns {
                let x = -length / 2 + 5 + CGFloat(col) * Self.glyphSpacing
                joints.move(to: CGPoint(x: x, y: -Self.width / 2 + 1))
                joints.addLine(to: CGPoint(x: x, y: Self.width / 2 - 1))
                col += perCarriage
            }
        }
        let jointNode = SKShapeNode(path: joints)
        jointNode.strokeColor = color.darkened(0.3).sk
        jointNode.lineWidth = 2
        jointNode.zPosition = 0.1
        // Fast motor: a white speed stripe along both sides.
        let stripe = SKShapeNode()
        if train.hasMotor {
            let p = CGMutablePath()
            for y in [-Self.width / 2 + 3.5, Self.width / 2 - 3.5] {
                p.move(to: CGPoint(x: -length / 2 + 6, y: y))
                p.addLine(to: CGPoint(x: length / 2 - 6, y: y))
            }
            stripe.path = p
            stripe.strokeColor = SKColor(white: 1, alpha: 0.85)
            stripe.lineWidth = 2
            stripe.lineCap = .round
            stripe.zPosition = 0.15
        }
        super.init()
        car.addChild(jointNode)
        car.addChild(stripe)
        glyphs.fillColor = .white
        glyphs.strokeColor = .clear
        glyphs.zPosition = 0.5
        car.addChild(shadow)
        car.addChild(outline)
        car.addChild(body)
        car.addChild(headlight)
        addChild(car)
        addChild(glyphs)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func matches(_ train: Train) -> Bool {
        capacity == train.capacity && hasMotor == train.hasMotor
    }

    /// Takes over another node's place and heading (used when a train is rebuilt after an upgrade).
    func adopt(from other: TrainNode) {
        position = other.position
        heading = other.heading
        car.zRotation = heading
        facing = other.facing
        headlight.position.x = facing * (carLength / 2 - 3.5)
    }

    func playUpgrade(to scale: CGFloat) {
        run(.sequence([.scale(to: scale * 1.25, duration: 0.12), .scale(to: scale, duration: 0.18)]), withKey: "appear")
    }

    func setColor(_ rgb: RGB) {
        guard rgb != color else { return }
        color = rgb
        body.fillColor = rgb.sk
    }

    func setRetiring(_ retiring: Bool) {
        alpha = retiring ? 0.55 : 1
    }

    func setSelected(_ selected: Bool) {
        outline.isHidden = !selected
    }

    func setPassengers(_ new: [StationShape]) {
        guard new != shapes else { return }
        shapes = new
        rebuildGlyphs()
    }

    /// Rotates smoothly towards the travel direction. The car is symmetric, so it never spins 180°.
    func turn(towards direction: Vec2, dt: Double) {
        guard direction.lengthSquared > 1e-9 else { return }
        let travel = CGFloat(atan2(direction.y, direction.x))
        var target = travel
        while target - heading > .pi / 2 { target -= .pi }
        while target - heading < -.pi / 2 { target += .pi }
        // The car is drawn symmetric; the headlight goes on whichever end is in front.
        let newFacing: CGFloat = cos(travel - target) >= 0 ? 1 : -1
        if newFacing != facing {
            facing = newFacing
            headlight.position.x = facing * (carLength / 2 - 3.5)
        }
        let k = min(1, CGFloat(dt) * 14)
        heading += (target - heading) * k
        car.zRotation = heading
        if !(abs(heading - glyphHeading) < 0.02) { rebuildGlyphs() }
    }

    /// Glyph slots follow the car's rotation; each glyph shape stays upright.
    private func rebuildGlyphs() {
        glyphHeading = heading
        guard !shapes.isEmpty else { glyphs.path = nil; return }
        let path = CGMutablePath()
        let rotation = CGAffineTransform(rotationAngle: heading)
        let x0 = -CGFloat(columns - 1) * Self.glyphSpacing / 2
        for (i, shape) in shapes.enumerated() {
            let slot = CGPoint(x: x0 + CGFloat(i % columns) * Self.glyphSpacing,
                               y: (i < columns ? 1 : -1) * Self.glyphSpacing / 2).applying(rotation)
            path.addPath(ShapePaths.path(for: shape, radius: 4.1),
                         transform: CGAffineTransform(translationX: slot.x, y: slot.y))
        }
        glyphs.path = path
    }

    func playAppear(to scale: CGFloat) {
        setScale(0.2)
        run(.scale(to: scale, duration: 0.2), withKey: "appear")
    }

    func playDisappear() {
        run(.sequence([.group([.scale(to: 0.2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }
}
