import Foundation

/// Whether the path between two stations has to cross water.
public enum SegmentTerrain: Hashable, Sendable {
    /// Both bend orientations stay on land.
    case dry
    /// Only one bend orientation stays on land; the line is always drawn that way.
    case dryOnlyIf(straightFirst: Bool)
    /// Both orientations cross water: the segment needs a water crossing (tunnel).
    case water
}

extension RouteGeometry {

    /// Terrain of the station pair `key`, with paths computed low → high (as `build` draws them).
    /// Independent of the rest of the network, so a line's crossing needs never change behind its back.
    public static func terrain(_ key: SegmentKey, positions: [StationID: Vec2], map: MapDefinition) -> SegmentTerrain {
        guard !map.water.isEmpty, let a = positions[key.low], let b = positions[key.high] else { return .dry }
        let diagonalWet = crossesWater(octilinearPoints(from: a, to: b, straightFirst: false), map: map)
        let straightWet = crossesWater(octilinearPoints(from: a, to: b, straightFirst: true), map: map)
        switch (diagonalWet, straightWet) {
        case (false, false): return .dry
        case (true, true): return .water
        case (true, false): return .dryOnlyIf(straightFirst: true)
        case (false, true): return .dryOnlyIf(straightFirst: false)
        }
    }

    /// True when a polyline touches any water body.
    public static func crossesWater(_ points: [Vec2], map: MapDefinition) -> Bool {
        guard points.count > 1 else { return false }
        for body in map.water {
            if points.contains(where: { body.contains($0) }) { return true }
            for i in 0..<(points.count - 1) where !waterHits(points[i], points[i + 1], body).isEmpty {
                return true
            }
        }
        return false
    }

    /// The parts of a polyline that lie over water, as separate sub-polylines (for drawing bridges).
    public static func waterSpans(of points: [Vec2], map: MapDefinition) -> [[Vec2]] {
        guard points.count > 1, !map.water.isEmpty else { return [] }
        var spans: [[Vec2]] = []
        var current: [Vec2] = []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            // Split the leg at every shoreline it crosses; each piece is entirely wet or entirely dry.
            var ts: [Double] = [0, 1]
            for body in map.water { ts += waterHits(a, b, body) }
            ts.sort()
            for k in 0..<(ts.count - 1) where ts[k + 1] - ts[k] > 1e-9 {
                let p = Vec2.lerp(a, b, ts[k]), q = Vec2.lerp(a, b, ts[k + 1])
                if map.isWater(Vec2.lerp(a, b, (ts[k] + ts[k + 1]) / 2)) {
                    if current.isEmpty { current = [p] }
                    current.append(q)
                } else if !current.isEmpty {
                    spans.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty { spans.append(current) }
        return spans
    }

    /// Parameters t ∈ (0, 1) where segment a→b crosses the outline of `body`.
    private static func waterHits(_ a: Vec2, _ b: Vec2, _ body: Polygon) -> [Double] {
        let box = body.bounds
        guard max(a.x, b.x) >= box.minX, min(a.x, b.x) <= box.maxX,
              max(a.y, b.y) >= box.minY, min(a.y, b.y) <= box.maxY else { return [] }
        let pts = body.points
        guard pts.count >= 3 else { return [] }
        var hits: [Double] = []
        let r = b - a
        var j = pts.count - 1
        for i in 0..<pts.count {
            let c = pts[j], s = pts[i] - pts[j]
            let denom = r.x * s.y - r.y * s.x
            if abs(denom) > 1e-12 {
                let ac = c - a
                let t = (ac.x * s.y - ac.y * s.x) / denom
                let u = (ac.x * r.y - ac.y * r.x) / denom
                if t > 0, t < 1, u >= 0, u <= 1 { hits.append(t) }
            }
            j = i
        }
        return hits
    }
}
