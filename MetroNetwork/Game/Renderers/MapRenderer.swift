import SpriteKit
import MetroCore

/// Draws the static geography once: land, streets, city blocks, parks with trees, water with ripples.
/// Every layer is a single shape node built from the map's seed (original vector art, no image assets).
@MainActor
enum MapRenderer {

    static func makeNode(for map: MapDefinition) -> SKNode {
        let root = SKNode()
        root.name = "map"

        let land = SKShapeNode(rect: CGRect(x: 0, y: 0, width: map.size.x, height: map.size.y))
        land.fillColor = VisualTheme.land.sk
        land.strokeColor = .clear
        land.zPosition = 0
        root.addChild(land)

        for hill in map.hills ?? [] {
            let node = hillNode(hill)
            node.zPosition = 0.5
            root.addChild(node)
        }
        root.addChild(streetGrid(size: map.size))

        // Decorative detail is seeded from the map, so a city always looks the same.
        var rng = SeededRandom(seed: map.seed ^ 0xB10C_5EED)
        let blocks = cityBlocks(for: map, rng: &rng)
        blocks.zPosition = 2
        root.addChild(blocks)

        for park in map.parks {
            let node = shape(park, fill: VisualTheme.park.sk, stroke: VisualTheme.parkEdge.sk, lineWidth: 2)
            node.zPosition = 3
            root.addChild(node)
        }
        let trees = parkTrees(for: map, rng: &rng)
        trees.zPosition = 3.5
        root.addChild(trees)

        for body in map.water {
            // A soft shoreline halo under the water body.
            let halo = shape(body, fill: .clear, stroke: VisualTheme.shore.sk, lineWidth: 22)
            halo.zPosition = 4
            root.addChild(halo)
            let water = shape(body, fill: VisualTheme.water.sk, stroke: VisualTheme.waterEdge.sk, lineWidth: 3)
            water.zPosition = 5
            root.addChild(water)
        }
        let ripples = waterRipples(for: map, rng: &rng)
        ripples.zPosition = 5.5
        root.addChild(ripples)
        root.addChild(outsideFrame(size: map.size))
        return root
    }

    /// A hill: stacked tinted discs (darker towards the top) with a thin contour line each.
    private static func hillNode(_ hill: Hill) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(hill.center)
        for level in HillContours.levels(for: hill) {
            let r = CGFloat(level.radius)
            let disc = SKShapeNode(circleOfRadius: r)
            disc.fillColor = VisualTheme.hill.sk.withAlphaComponent(0.15)
            disc.strokeColor = VisualTheme.hillEdge.sk.withAlphaComponent(0.4)
            disc.lineWidth = 1.5
            disc.isAntialiased = true
            node.addChild(disc)
        }
        return node
    }

    /// Covers everything past the map edge (rivers, coasts and district tints extend beyond it).
    /// Four plain rectangles are cheaper than a crop node.
    private static func outsideFrame(size: Vec2) -> SKNode {
        let frame = SKNode()
        frame.zPosition = 6
        let m: CGFloat = 6000
        let w = CGFloat(size.x), h = CGFloat(size.y)
        for rect in [CGRect(x: -m, y: -m, width: w + 2 * m, height: m),     // below
                     CGRect(x: -m, y: h, width: w + 2 * m, height: m),      // above
                     CGRect(x: -m, y: 0, width: m, height: h),              // left
                     CGRect(x: w, y: 0, width: m, height: h)] {             // right
            let node = SKShapeNode(rect: rect)
            node.fillColor = VisualTheme.outside.sk
            node.strokeColor = .clear
            frame.addChild(node)
        }
        return frame
    }

    static let blockSpacing = 90.0

    /// Building blocks between the streets, dense around neighbourhood centres and thinning out towards the
    /// edge of town. Blocks never sit on water or in parks.
    private static func cityBlocks(for map: MapDefinition, rng: inout SeededRandom) -> SKShapeNode {
        let path = CGMutablePath()
        let spacing = blockSpacing
        let street = 11.0
        let columns = Int(map.size.x / spacing), rows = Int(map.size.y / spacing)
        for col in 0..<columns {
            for row in 0..<rows {
                let cell = CGRect(x: Double(col) * spacing, y: Double(row) * spacing, width: spacing, height: spacing)
                let center = Vec2(cell.midX, cell.midY)
                let density = map.districts.reduce(0.0) { best, d in
                    let t = center.distance(to: d.center) / (d.radius * 1.7)
                    return max(best, (1 - t) * min(1, 0.45 + d.weight * 0.35))
                }
                guard rng.chance(min(0.9, max(0.04, density))) else { continue }
                guard map.isBuildable(center, clearance: spacing * 0.75),
                      !map.parks.contains(where: { $0.bounds.insetBy(-20).contains(center) && $0.distanceToEdge(from: center) < 70 || $0.contains(center) }) else { continue }
                let lot = cell.insetBy(dx: street / 2, dy: street / 2)
                // Split the lot into 1, 2 or 4 buildings.
                let split = rng.int(in: 0...3)
                let gap = 6.0
                var parts: [CGRect] = [lot]
                if split == 1 || split == 3 {
                    let w = (lot.width - gap) / 2
                    parts = [CGRect(x: lot.minX, y: lot.minY, width: w, height: lot.height),
                             CGRect(x: lot.minX + w + gap, y: lot.minY, width: w, height: lot.height)]
                }
                if split >= 2 {
                    parts = parts.flatMap { r -> [CGRect] in
                        let h = (r.height - gap) / 2
                        return [CGRect(x: r.minX, y: r.minY, width: r.width, height: h),
                                CGRect(x: r.minX, y: r.minY + h + gap, width: r.width, height: h)]
                    }
                }
                for part in parts where rng.chance(0.88) {
                    path.addRoundedRect(in: part, cornerWidth: 4, cornerHeight: 4)
                }
            }
        }
        let node = SKShapeNode(path: path)
        node.fillColor = VisualTheme.block.sk
        node.strokeColor = VisualTheme.blockEdge.sk
        node.lineWidth = 1
        return node
    }

    /// Round tree crowns scattered inside parks.
    private static func parkTrees(for map: MapDefinition, rng: inout SeededRandom) -> SKShapeNode {
        let path = CGMutablePath()
        for park in map.parks {
            let b = park.bounds
            let count = Int(b.width * b.height / 900)
            var placed: [(Vec2, Double)] = []
            for _ in 0..<count {
                let p = Vec2(rng.double(in: b.minX...b.maxX), rng.double(in: b.minY...b.maxY))
                let r = rng.double(in: 5...9)
                guard park.contains(p), park.distanceToEdge(from: p) > r + 3 else { continue }
                // Crowns must not overlap: SpriteKit fills overlapping subpaths even-odd (holes).
                guard placed.allSatisfy({ $0.0.distance(to: p) > $0.1 + r + 2 }) else { continue }
                placed.append((p, r))
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }
        let node = SKShapeNode(path: path)
        node.fillColor = VisualTheme.tree.sk
        node.strokeColor = VisualTheme.tree.sk(alpha: 0.0)
        return node
    }

    /// Short wave marks on open water.
    private static func waterRipples(for map: MapDefinition, rng: inout SeededRandom) -> SKShapeNode {
        let path = CGMutablePath()
        for body in map.water {
            let b = Rect(minX: max(body.bounds.minX, 0), minY: max(body.bounds.minY, 0),
                         maxX: min(body.bounds.maxX, map.size.x), maxY: min(body.bounds.maxY, map.size.y))
            guard b.width > 0, b.height > 0 else { continue }
            let count = Int(b.width * b.height / 26_000) + 2
            for _ in 0..<count {
                let p = Vec2(rng.double(in: b.minX...b.maxX), rng.double(in: b.minY...b.maxY))
                let w = rng.double(in: 14...24)
                guard body.contains(p), body.distanceToEdge(from: p) > w + 6 else { continue }
                path.move(to: CGPoint(x: p.x - w, y: p.y))
                path.addQuadCurve(to: CGPoint(x: p.x, y: p.y), control: CGPoint(x: p.x - w / 2, y: p.y + 5))
                path.addQuadCurve(to: CGPoint(x: p.x + w, y: p.y), control: CGPoint(x: p.x + w / 2, y: p.y + 5))
            }
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = VisualTheme.ripple.sk
        node.lineWidth = 2.5
        node.lineCap = .round
        node.fillColor = .clear
        return node
    }

    private static func streetGrid(size: Vec2) -> SKNode {
        let path = CGMutablePath()
        let spacing = blockSpacing
        var x = spacing
        while x < size.x {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.y))
            x += spacing
        }
        var y = spacing
        while y < size.y {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.x, y: y))
            y += spacing
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = VisualTheme.street.sk
        node.lineWidth = 2
        node.zPosition = 1
        return node
    }

    private static func shape(_ polygon: MetroCore.Polygon, fill: SKColor, stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        if let first = polygon.points.first {
            path.move(to: CGPoint(first))
            for p in polygon.points.dropFirst() { path.addLine(to: CGPoint(p)) }
            path.closeSubpath()
        }
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        node.lineJoin = .round
        return node
    }
}

extension CGPoint {
    init(_ v: Vec2) { self.init(x: v.x, y: v.y) }
    var vec2: Vec2 { Vec2(Double(x), Double(y)) }
}
