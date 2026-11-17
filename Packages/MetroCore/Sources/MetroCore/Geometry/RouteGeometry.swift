import Foundation

/// Sizes that affect where lines are drawn — and therefore where they can be hit.
public struct RouteMetrics: Hashable, Sendable {
    public var lineWidth: Double
    /// Centre-to-centre distance between parallel lines sharing a station pair.
    public var lineSpacing: Double
    /// Corner radius used when drawing bends (rendering only).
    public var bendRadius: Double
    /// Length of the drag handle that sticks out of a line's terminal station.
    public var handleLength: Double
    /// Half-width of the T-bar at the end of a handle.
    public var handleBarHalfWidth: Double

    public init(lineWidth: Double = 9, lineSpacing: Double = 11, bendRadius: Double = 28,
                handleLength: Double = 38, handleBarHalfWidth: Double = 13) {
        self.lineWidth = lineWidth
        self.lineSpacing = lineSpacing
        self.bendRadius = bendRadius
        self.handleLength = handleLength
        self.handleBarHalfWidth = handleBarHalfWidth
    }

    public static let standard = RouteMetrics()
}

/// Undirected station pair.
public struct SegmentKey: Hashable, Sendable {
    public let low: StationID
    public let high: StationID

    public init(_ a: StationID, _ b: StationID) {
        if a < b { low = a; high = b } else { low = b; high = a }
    }
}

/// Drawn shape of one segment of a line, in the line's travel direction.
public struct SegmentPath: Hashable, Sendable {
    /// Matches the index in `MetroLine.segments` (a loop's closing segment is last).
    public var index: Int
    public var from: StationID
    public var to: StationID
    /// 2 points (straight) or 3 points (one 45° bend).
    public var points: [Vec2]
}

/// The drag handle at a line's terminal.
public struct TerminalHandle: Hashable, Sendable {
    public var end: LineEnd
    public var station: StationID
    public var anchor: Vec2
    public var tip: Vec2
    /// Unit vector pointing outward from the station.
    public var direction: Vec2
}

public struct LineGeometry: Hashable, Sendable {
    public var lineID: LineID
    public var segments: [SegmentPath]
    public var handles: [TerminalHandle]

    /// All points of the line in travel order (consecutive segments may jog sideways at a station when
    /// their parallel offsets differ).
    public var polyline: [Vec2] {
        var result: [Vec2] = []
        for segment in segments {
            for (i, p) in segment.points.enumerated() {
                if i == 0, let last = result.last, last.distanceSquared(to: p) < 1e-6 { continue }
                result.append(p)
            }
        }
        return result
    }
}

public enum RouteGeometry {

    /// Octilinear path from `a` to `b` with at most one bend. By default the 45° leg comes first;
    /// with `straightFirst` the horizontal/vertical leg comes first. Straight when the points are already
    /// aligned on one of the eight directions.
    public static func octilinearPoints(from a: Vec2, to b: Vec2, straightFirst: Bool = false) -> [Vec2] {
        let d = b - a
        let ax = abs(d.x), ay = abs(d.y)
        let tolerance = 0.5
        if ax < tolerance || ay < tolerance || abs(ax - ay) < tolerance { return [a, b] }
        let bend: Vec2
        if straightFirst {
            bend = ax > ay
                ? Vec2(a.x + (d.x < 0 ? -(ax - ay) : ax - ay), a.y)
                : Vec2(a.x, a.y + (d.y < 0 ? -(ay - ax) : ay - ax))
        } else {
            let m = min(ax, ay)
            bend = a + Vec2(d.x < 0 ? -m : m, d.y < 0 ? -m : m)
        }
        return [a, bend, b]
    }

    /// Length of the octilinear path between two points. Identical for both bend orientations
    /// (one 45° leg plus one straight leg), so train timing never depends on how a segment is drawn.
    public static func octilinearLength(_ a: Vec2, _ b: Vec2) -> Double {
        let ax = abs(b.x - a.x), ay = abs(b.y - a.y)
        let m = min(ax, ay)
        return m * 2.0.squareRoot() + (max(ax, ay) - m)
    }

    /// Point at `distance` along a polyline, and the unit direction of travel there.
    /// Distances outside the polyline clamp to its ends.
    public static func point(along points: [Vec2], distance: Double) -> (point: Vec2, direction: Vec2) {
        guard let first = points.first else { return (.zero, Vec2(1, 0)) }
        guard points.count > 1 else { return (first, Vec2(1, 0)) }
        var remaining = max(0, distance)
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let len = a.distance(to: b)
            if remaining <= len || i == points.count - 2 {
                let t = len > 1e-9 ? min(1, remaining / len) : 0
                return (Vec2.lerp(a, b, t), (b - a).normalized)
            }
            remaining -= len
        }
        return (points[points.count - 1], (points[points.count - 1] - points[points.count - 2]).normalized)
    }

    /// Geometry for every line. Lines that share a station pair get parallel offsets ordered by line id,
    /// and every line uses the same bend direction for a given pair, so they stay parallel.
    /// - Parameter map: when given, a pair that stays on land with only one bend orientation is always
    ///   drawn that way (so a line only crosses water when it really has to).
    public static func build(lines: [MetroLine], positions: [StationID: Vec2],
                             metrics: RouteMetrics = .standard, map: MapDefinition? = nil) -> [LineID: LineGeometry] {
        // Which lines use each undirected station pair.
        var users: [SegmentKey: [LineID]] = [:]
        for line in lines {
            for (a, b) in line.segments {
                users[SegmentKey(a, b), default: []].append(line.id)
            }
        }
        for key in users.keys { users[key]?.sort() }
        var forced: [SegmentKey: Bool] = [:]
        if let map {
            for key in users.keys {
                if case .dryOnlyIf(let straight) = terrain(key, positions: positions, map: map) { forced[key] = straight }
            }
        }
        let straightFirst = chooseBendOrientations(lines: lines, positions: positions, keys: Array(users.keys),
                                                   forced: forced)

        var result: [LineID: LineGeometry] = [:]
        for line in lines {
            var segments: [SegmentPath] = []
            for (index, (a, b)) in line.segments.enumerated() {
                guard let pa = positions[a], let pb = positions[b] else { continue }
                let key = SegmentKey(a, b)
                let lowPos = key.low == a ? pa : pb
                let highPos = key.low == a ? pb : pa
                var points = octilinearPoints(from: lowPos, to: highPos, straightFirst: straightFirst.contains(key))

                let sharing = users[key] ?? [line.id]
                if sharing.count > 1, let slot = sharing.firstIndex(of: line.id) {
                    let normal = (highPos - lowPos).normalized.perpendicular
                    let shift = normal * ((Double(slot) - Double(sharing.count - 1) / 2) * metrics.lineSpacing)
                    points = points.map { $0 + shift }
                }
                if key.low != a { points.reverse() }
                segments.append(SegmentPath(index: index, from: a, to: b, points: points))
            }
            result[line.id] = LineGeometry(lineID: line.id, segments: segments,
                                           handles: handles(for: line, segments: segments, metrics: metrics))
        }
        return result
    }

    /// Picks, per station pair, which way the bend goes so that a line passing through a station turns as
    /// gently as possible (no hairpins where both legs leave the station in the same direction).
    /// Decided per undirected pair, so every line sharing the pair still uses identical, parallel shapes.
    /// - Returns: the pairs drawn straight-leg-first (all others are diagonal-first).
    /// - Parameter forced: pairs whose orientation is fixed (true = straight-leg-first), e.g. to stay dry.
    static func chooseBendOrientations(lines: [MetroLine], positions: [StationID: Vec2],
                                       keys: [SegmentKey], forced: [SegmentKey: Bool] = [:]) -> Set<SegmentKey> {
        let fixedStraight = Set(forced.filter(\.value).keys)
        // Consecutive segment pairs of every line, meeting at a station.
        struct Turn { let a: SegmentKey; let b: SegmentKey; let station: StationID }
        var turns: [Turn] = []
        var turnsByKey: [SegmentKey: [Int]] = [:]
        for line in lines {
            let segs = line.segments.map { SegmentKey($0.0, $0.1) }
            let stationsAt = line.segments.map(\.1)
            guard segs.count > 1 else { continue }
            let count = line.isLoop ? segs.count : segs.count - 1
            for i in 0..<count {
                let next = (i + 1) % segs.count
                turns.append(Turn(a: segs[i], b: segs[next], station: stationsAt[i]))
                turnsByKey[segs[i], default: []].append(turns.count - 1)
                turnsByKey[segs[next], default: []].append(turns.count - 1)
            }
        }
        guard !turns.isEmpty else { return fixedStraight }

        var straight = fixedStraight
        func leaving(_ key: SegmentKey, from station: StationID) -> Vec2? {
            guard let lo = positions[key.low], let hi = positions[key.high] else { return nil }
            let p = octilinearPoints(from: lo, to: hi, straightFirst: straight.contains(key))
            return station == key.low ? (p[1] - p[0]).normalized : (p[p.count - 2] - p[p.count - 1]).normalized
        }
        // Cost of a turn: +1 = hairpin, 0 = right angle, -1 = straight through.
        func cost(of key: SegmentKey) -> Double {
            (turnsByKey[key] ?? []).reduce(0) { sum, index in
                let t = turns[index]
                guard let u = leaving(t.a, from: t.station), let v = leaving(t.b, from: t.station) else { return sum }
                let c = u.dot(v)
                return sum + (c > 0.5 ? c * 4 : c)   // sharp turns are much worse than mild ones
            }
        }
        let ordered = keys.filter { turnsByKey[$0] != nil && forced[$0] == nil }.sorted { ($0.low, $0.high) < ($1.low, $1.high) }
        for _ in 0..<3 {
            var changed = false
            for key in ordered {
                let current = cost(of: key)
                straight.formSymmetricDifference([key])
                if cost(of: key) < current - 1e-9 {
                    changed = true
                } else {
                    straight.formSymmetricDifference([key])
                }
            }
            if !changed { break }
        }
        return straight
    }

    private static func handles(for line: MetroLine, segments: [SegmentPath], metrics: RouteMetrics) -> [TerminalHandle] {
        guard !line.isLoop, let first = segments.first, let last = segments.last else { return [] }
        var result: [TerminalHandle] = []
        if first.points.count >= 2 {
            let anchor = first.points[0]
            let dir = (anchor - first.points[1]).normalized
            result.append(TerminalHandle(end: .start, station: first.from, anchor: anchor,
                                         tip: anchor + dir * metrics.handleLength, direction: dir))
        }
        if last.points.count >= 2 {
            let anchor = last.points[last.points.count - 1]
            let dir = (anchor - last.points[last.points.count - 2]).normalized
            result.append(TerminalHandle(end: .end, station: last.to, anchor: anchor,
                                         tip: anchor + dir * metrics.handleLength, direction: dir))
        }
        return result
    }

    // MARK: Hit testing

    /// Closest station within `radius` of `p`.
    public static func station(at p: Vec2, in stations: [Station], radius: Double) -> StationID? {
        var best: (StationID, Double)?
        let r2 = radius * radius
        for s in stations {
            let d2 = s.position.distanceSquared(to: p)
            if d2 <= r2, d2 < (best?.1 ?? .infinity) { best = (s.id, d2) }
        }
        return best?.0
    }

    /// Terminal handle near `p`. Only the outer half of the handle counts, so the station itself stays tappable.
    public static func handle(at p: Vec2, in geometry: [LineID: LineGeometry],
                              tolerance: Double) -> (LineID, TerminalHandle)? {
        var best: (LineID, TerminalHandle, Double)?
        for (id, g) in geometry {
            for h in g.handles {
                let mid = Vec2.lerp(h.anchor, h.tip, 0.45)
                let d = Geometry2D.distance(from: p, toSegment: mid, h.tip + h.direction * (tolerance * 0.5))
                if d <= tolerance, d < (best?.2 ?? .infinity) { best = (id, h, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Line segment near `p`, as (line, segment index).
    public static func segment(at p: Vec2, in geometry: [LineID: LineGeometry],
                               tolerance: Double) -> (LineID, Int)? {
        var best: (LineID, Int, Double)?
        for (id, g) in geometry {
            for s in g.segments {
                let d = Geometry2D.distance(from: p, toPolyline: s.points)
                if d <= tolerance, d < (best?.2 ?? .infinity) { best = (id, s.index, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }
}
