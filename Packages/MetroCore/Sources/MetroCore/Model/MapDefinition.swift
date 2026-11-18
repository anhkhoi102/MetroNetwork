import Foundation

/// A simple (non self-intersecting) polygon in world units.
public struct Polygon: Hashable, Codable, Sendable {
    public var points: [Vec2]
    public var bounds: Rect

    public init(points: [Vec2]) {
        self.points = points
        self.bounds = Rect.bounding(points) ?? Rect(minX: 0, minY: 0, maxX: 0, maxY: 0)
    }

    /// Even-odd point-in-polygon test.
    public func contains(_ p: Vec2) -> Bool {
        guard points.count >= 3, bounds.contains(p) else { return false }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Distance from `p` to the polygon outline.
    public func distanceToEdge(from p: Vec2) -> Double {
        guard !points.isEmpty else { return .infinity }
        return Geometry2D.distance(from: p, toPolyline: points + [points[0]])
    }
}

public enum MapArchetype: String, Codable, CaseIterable, Sendable {
    /// A meandering river crosses the whole city.
    case river
    /// The city hugs a coastline with a bay.
    case coastal
    /// Several lakes break the city into neighbourhoods.
    case lakes

    public var displayName: String {
        switch self {
        case .river: "River City"
        case .coastal: "Coastal City"
        case .lakes: "Lake District"
        }
    }
}

/// A dense neighbourhood. Stations are more likely to appear near districts with a high weight.
public struct District: Hashable, Codable, Sendable {
    public var center: Vec2
    public var radius: Double
    public var weight: Double

    public init(center: Vec2, radius: Double, weight: Double) {
        self.center = center
        self.radius = radius
        self.weight = weight
    }
}

/// Static geography of a map. Generated once from a seed by `MapGenerator`.
public struct MapDefinition: Hashable, Codable, Sendable {
    public var name: String
    public var archetype: MapArchetype
    public var seed: UInt64
    /// Map extent; world coordinates run from (0, 0) to `size`.
    public var size: Vec2
    public var cityCenter: Vec2
    public var water: [Polygon]
    public var parks: [Polygon]
    public var districts: [District]
    /// Hill country (campaign part 2); nil on flat maps, and in maps saved before hills existed.
    public var hills: [Hill]?

    public init(name: String, archetype: MapArchetype, seed: UInt64, size: Vec2, cityCenter: Vec2,
                water: [Polygon], parks: [Polygon], districts: [District]) {
        self.name = name
        self.archetype = archetype
        self.seed = seed
        self.size = size
        self.cityCenter = cityCenter
        self.water = water
        self.parks = parks
        self.districts = districts
    }

    public var bounds: Rect { Rect(minX: 0, minY: 0, maxX: size.x, maxY: size.y) }

    public func isWater(_ p: Vec2) -> Bool {
        water.contains { $0.contains(p) }
    }

    /// True when `p` is on land, inside the map, and at least `clearance` away from any water.
    public func isBuildable(_ p: Vec2, clearance: Double) -> Bool {
        guard bounds.insetBy(clearance).contains(p) else { return false }
        for body in water {
            if body.contains(p) { return false }
            let expanded = Rect(minX: body.bounds.minX - clearance, minY: body.bounds.minY - clearance,
                                maxX: body.bounds.maxX + clearance, maxY: body.bounds.maxY + clearance)
            if expanded.contains(p), body.distanceToEdge(from: p) < clearance { return false }
        }
        return true
    }
}
