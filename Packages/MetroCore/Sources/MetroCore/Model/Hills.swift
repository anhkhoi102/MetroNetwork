import Foundation

/// Campaign part 2: hill country. A hill is a smooth bump; elevation is 0 on the flat and up to `height`
/// (at most 1) at its top. Hills belong to the map, so a hilly city is hilly in every mode.
public struct Hill: Hashable, Codable, Sendable {
    public var center: Vec2
    public var radius: Double
    /// 0…1.
    public var height: Double

    public init(center: Vec2, radius: Double, height: Double) {
        self.center = center
        self.radius = radius
        self.height = height
    }

    /// This hill's elevation at `p` (a smooth dome, 0 beyond its radius).
    public func elevation(at p: Vec2) -> Double {
        let d = p.distanceSquared(to: center) / (radius * radius)
        guard d < 1 else { return 0 }
        let f = 1 - d
        return height * f * f
    }
}

/// How hills affect play. The defaults apply on any hilly map; a level may tune them.
public struct HillRules: Codable, Hashable, Sendable {
    /// A train climbing a full hill (elevation 0 → 1) runs at 1 / (1 + climbPenalty) of its top speed;
    /// a fast motor halves the penalty. Downhill and on the flat, nothing changes.
    public var climbPenalty = 1.6
    public var motorClimbFactor = 0.5
    /// Hillside homes with a view: a station's demand grows by up to this much at the top of a hill.
    public var hillDemandBonus = 0.3

    public init() {}
}

extension MapDefinition {
    /// Elevation 0…1 at `p` (the highest hill there).
    public func elevation(at p: Vec2) -> Double {
        guard let hills, !hills.isEmpty else { return 0 }
        return min(1, hills.reduce(0) { max($0, $1.elevation(at: p)) })
    }
}
