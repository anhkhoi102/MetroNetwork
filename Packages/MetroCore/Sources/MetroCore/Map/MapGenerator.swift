import Foundation

/// Procedural city maps. The same `(archetype, seed)` always yields the same map on every platform.
public enum MapGenerator {

    public static let defaultSize = Vec2(3200, 2000)

    public static func generate(archetype: MapArchetype, seed: UInt64, name: String? = nil,
                                size: Vec2 = defaultSize) -> MapDefinition {
        var rng = SeededRandom(seed: seed &* 0x2545_F491_4F6C_DD1D &+ UInt64(archetype.hashSalt))
        let center = size / 2

        let water: [Polygon]
        switch archetype {
        case .river: water = riverWater(size: size, center: center, rng: &rng)
        case .coastal: water = coastalWater(size: size, center: center, rng: &rng)
        case .lakes: water = lakeWater(center: center, rng: &rng)
        }

        var map = MapDefinition(name: name ?? archetype.displayName, archetype: archetype, seed: seed,
                                size: size, cityCenter: center, water: water, parks: [], districts: [])
        // The river or bay may pass close to the middle; move the centre onto dry land with room around it.
        map.cityCenter = nearestBuildable(to: center, in: map, clearance: 120) ?? center
        map.districts = districts(for: map, rng: &rng)
        map.parks = parks(for: map, rng: &rng)
        return map
    }

    // MARK: Water

    private static func riverWater(size: Vec2, center: Vec2, rng: inout SeededRandom) -> [Polygon] {
        // Built along the local x axis, then rotated so rivers run in different directions.
        let angle = rng.chance(0.5) ? rng.double(in: -0.55...0.55) : .pi / 2 + rng.double(in: -0.45...0.45)
        let rotation = Vec2(cos(angle), sin(angle))
        let halfLength = size.length / 2 + 200
        let offset = (rng.chance(0.5) ? 1.0 : -1.0) * rng.double(in: 170...260)
        let waves = (0..<3).map { _ in (amp: rng.double(in: 40...130), freq: rng.double(in: 0.0012...0.0042),
                                        phase: rng.double(in: 0...(2 * .pi))) }
        let baseWidth = rng.double(in: 70...95)

        var upper: [Vec2] = []
        var lower: [Vec2] = []
        let steps = 90
        for i in 0...steps {
            let t = -halfLength + 2 * halfLength * Double(i) / Double(steps)
            var y = offset
            for w in waves { y += w.amp * sin(t * w.freq + w.phase) }
            let width = baseWidth * (1 + 0.25 * sin(t * 0.003 + waves[0].phase))
            upper.append(Vec2(t, y + width / 2))
            lower.append(Vec2(t, y - width / 2))
        }
        func place(_ p: Vec2) -> Vec2 {
            center + Vec2(p.x * rotation.x - p.y * rotation.y, p.x * rotation.y + p.y * rotation.x)
        }
        let outline = (upper + lower.reversed()).map(place)
        return [Polygon(points: outline)]
    }

    private static func coastalWater(size: Vec2, center: Vec2, rng: inout SeededRandom) -> [Polygon] {
        let seaAtBottom = rng.chance(0.5)
        let distance = rng.double(in: 300...430)       // coast distance from the city centre
        let slant = rng.double(in: -0.18...0.18)
        let bayX = rng.double(in: size.x * 0.2...size.x * 0.8)
        let bayDepth = rng.double(in: 160...300)
        let bayWidth = rng.double(in: 160...260)
        let waves = (0..<3).map { _ in (amp: rng.double(in: 15...55), freq: rng.double(in: 0.002...0.008),
                                        phase: rng.double(in: 0...(2 * .pi))) }

        var coast: [Vec2] = []
        let steps = 100
        for i in 0...steps {
            let x = -100 + (size.x + 200) * Double(i) / Double(steps)
            var d = distance + slant * (x - center.x)
            for w in waves { d += w.amp * sin(x * w.freq + w.phase) }
            let bay = bayDepth * exp(-pow((x - bayX) / bayWidth, 2))
            d -= bay
            coast.append(Vec2(x, seaAtBottom ? center.y - d : center.y + d))
        }
        let farY = seaAtBottom ? -200.0 : size.y + 200
        var sea = coast
        sea.append(Vec2(size.x + 100, farY))
        sea.append(Vec2(-100, farY))
        var bodies = [Polygon(points: sea)]

        // A lagoon inland on the other side of the city gives the map a second water feature.
        if rng.chance(0.6) {
            let side: Double = seaAtBottom ? 1 : -1
            let c = center + Vec2(rng.double(in: -900...900), side * rng.double(in: 450...700))
            bodies.append(blob(center: c, radius: rng.double(in: 90...150), roughness: 0.2, rng: &rng))
        }
        return bodies
    }

    private static func lakeWater(center: Vec2, rng: inout SeededRandom) -> [Polygon] {
        var lakes: [(Vec2, Double)] = []
        let count = rng.int(in: 3...5)
        var attempts = 0
        while lakes.count < count, attempts < 200 {
            attempts += 1
            let angle = rng.double(in: 0...(2 * .pi))
            let dist = rng.double(in: 260...1100)
            let radius = rng.double(in: 90...200)
            let c = center + Vec2(cos(angle), sin(angle)) * dist
            guard dist - radius > 200 else { continue }
            guard lakes.allSatisfy({ $0.0.distance(to: c) > $0.1 + radius + 160 }) else { continue }
            lakes.append((c, radius))
        }
        return lakes.map { blob(center: $0.0, radius: $0.1, roughness: 0.18, rng: &rng) }
    }

    // MARK: Districts and parks

    private static func districts(for map: MapDefinition, rng: inout SeededRandom) -> [District] {
        var result = [District(center: map.cityCenter, radius: 320, weight: 2.0)]
        let count = rng.int(in: 5...8)
        var attempts = 0
        while result.count < count + 1, attempts < 300 {
            attempts += 1
            let angle = rng.double(in: 0...(2 * .pi))
            let dist = rng.double(in: 300...1250)
            let c = map.cityCenter + Vec2(cos(angle), sin(angle)) * dist
            guard map.isBuildable(c, clearance: 60) else { continue }
            guard result.allSatisfy({ $0.center.distance(to: c) > 300 }) else { continue }
            result.append(District(center: c, radius: rng.double(in: 160...330), weight: rng.double(in: 0.5...1.5)))
        }
        return result
    }

    private static func parks(for map: MapDefinition, rng: inout SeededRandom) -> [Polygon] {
        var result: [Polygon] = []
        var centers: [Vec2] = []
        let count = rng.int(in: 6...10)
        var attempts = 0
        while result.count < count, attempts < 300 {
            attempts += 1
            let c = Vec2(rng.double(in: 100...(map.size.x - 100)), rng.double(in: 100...(map.size.y - 100)))
            let radius = rng.double(in: 45...110)
            guard map.isBuildable(c, clearance: radius + 10) else { continue }
            guard c.distance(to: map.cityCenter) > 160 else { continue }
            guard centers.allSatisfy({ $0.distance(to: c) > 260 }) else { continue }
            centers.append(c)
            result.append(blob(center: c, radius: radius, roughness: 0.22, rng: &rng))
        }
        return result
    }

    // MARK: Helpers

    /// A smooth irregular closed shape.
    static func blob(center: Vec2, radius: Double, roughness: Double, rng: inout SeededRandom) -> Polygon {
        let harmonics = (2...4).map { _ in (amp: rng.double(in: 0...roughness), phase: rng.double(in: 0...(2 * .pi))) }
        let segments = 36
        let points = (0..<segments).map { i -> Vec2 in
            let theta = 2 * Double.pi * Double(i) / Double(segments)
            var r = 1.0
            for (k, h) in harmonics.enumerated() { r += h.amp * sin(Double(k + 2) * theta + h.phase) }
            return center + Vec2(cos(theta), sin(theta)) * (radius * r)
        }
        return Polygon(points: points)
    }

    /// Spiral search for the closest land point with the given clearance.
    static func nearestBuildable(to p: Vec2, in map: MapDefinition, clearance: Double) -> Vec2? {
        if map.isBuildable(p, clearance: clearance) { return p }
        for ring in 1...40 {
            let r = Double(ring) * 25
            let samples = 12 + ring * 2
            for i in 0..<samples {
                let a = 2 * Double.pi * Double(i) / Double(samples)
                let q = p + Vec2(cos(a), sin(a)) * r
                if map.isBuildable(q, clearance: clearance) { return q }
            }
        }
        return nil
    }
}

private extension MapArchetype {
    var hashSalt: Int {
        switch self {
        case .river: 0x51
        case .coastal: 0xC0
        case .lakes: 0x1A
        }
    }
}
