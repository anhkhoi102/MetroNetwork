import Testing
@testable import MetroCore

@Suite("RouteGeometry")
struct GeometryTests {

    @Test func octilinearPathsUseFortyFiveDegreeLegs() {
        let straight = RouteGeometry.octilinearPoints(from: Vec2(0, 0), to: Vec2(100, 0))
        #expect(straight.count == 2)
        let diagonal = RouteGeometry.octilinearPoints(from: Vec2(0, 0), to: Vec2(-80, 80))
        #expect(diagonal.count == 2)

        let bent = RouteGeometry.octilinearPoints(from: Vec2(0, 0), to: Vec2(300, -100))
        #expect(bent.count == 3)
        #expect(bent[1] == Vec2(100, -100))
        for i in 0..<2 {
            let d = bent[i + 1] - bent[i]
            let ax = abs(d.x), ay = abs(d.y)
            #expect(ax < 1e-9 || ay < 1e-9 || abs(ax - ay) < 1e-9)
        }
    }

    @Test func sharedSegmentsAreOffsetSymmetrically() throws {
        var state = makeState(stations: 3)
        let a = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let b = try RouteManager.createLine(stations: ids(2, 1, 3), colorIndex: nil, isLoop: false, in: &state)
        let metrics = RouteMetrics.standard
        let g = RouteGeometry.build(lines: state.lines, positions: state.stationPositions, metrics: metrics)

        let segA = try #require(g[a]?.segments.first)
        let segB = try #require(g[b]?.segments.first)       // 2 → 1, reversed direction
        #expect(segA.from == StationID(1) && segB.from == StationID(2))
        // Same shape, same bend, separated by exactly one spacing.
        let pa = segA.points
        let pb = Array(segB.points.reversed())
        #expect(pa.count == pb.count)
        for (p, q) in zip(pa, pb) {
            #expect(abs(p.distance(to: q) - metrics.lineSpacing) < 1e-6)
        }
        // Centred around the unshifted path.
        let raw = RouteGeometry.octilinearPoints(from: state.station(StationID(1))!.position,
                                                 to: state.station(StationID(2))!.position)
        #expect(((pa[0] + pb[0]) / 2).distance(to: raw[0]) < 1e-6)
    }

    @Test func straightFirstVariantKeepsLegsOctilinear() {
        let p = RouteGeometry.octilinearPoints(from: Vec2(0, 0), to: Vec2(300, -100), straightFirst: true)
        #expect(p == [Vec2(0, 0), Vec2(200, 0), Vec2(300, -100)])
        let q = RouteGeometry.octilinearPoints(from: Vec2(0, 0), to: Vec2(-50, 200), straightFirst: true)
        #expect(q == [Vec2(0, 0), Vec2(0, 150), Vec2(-50, 200)])
    }

    /// Both segments would leave the middle station heading left with diagonal-first bends;
    /// the orientation pass must remove that hairpin.
    @Test func bendsAvoidHairpinsAtStations() throws {
        var state = makeState(stations: 3)
        state.stations[0].position = Vec2(1000, 1000)
        state.stations[1].position = Vec2(1222, 1100)
        state.stations[2].position = Vec2(1014, 1267)
        let id = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: false, in: &state)
        let g = try #require(RouteGeometry.build(lines: state.lines, positions: state.stationPositions)[id])
        let into = g.segments[0].points, out = g.segments[1].points
        let arriving = (into[into.count - 2] - into[into.count - 1]).normalized   // leaving the middle station backwards
        let leaving = (out[1] - out[0]).normalized
        #expect(arriving.dot(leaving) < 0.5, "turn at the middle station is a hairpin")
    }

    @Test func handlesOnlyForOpenLines() throws {
        var state = makeState(stations: 3)
        let open = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let loop = try RouteManager.createLine(stations: ids(1, 2, 3), colorIndex: nil, isLoop: true, in: &state)
        let g = RouteGeometry.build(lines: state.lines, positions: state.stationPositions)
        let handles = try #require(g[open]?.handles)
        #expect(handles.map(\.end) == [.start, .end])
        #expect(g[loop]?.handles.isEmpty == true)
        for h in handles {
            #expect(abs(h.anchor.distance(to: h.tip) - RouteMetrics.standard.handleLength) < 1e-6)
        }
    }

    @Test func hitTesting() throws {
        var state = makeState(stations: 3)
        let id = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let g = RouteGeometry.build(lines: state.lines, positions: state.stationPositions)
        let p1 = state.station(StationID(1))!.position

        #expect(RouteGeometry.station(at: p1 + Vec2(5, 5), in: state.stations, radius: 20) == StationID(1))
        #expect(RouteGeometry.station(at: p1 + Vec2(60, 60), in: state.stations, radius: 20) == nil)

        let seg = try #require(g[id]?.segments.first)
        let mid = Vec2.lerp(seg.points[0], seg.points[seg.points.count - 1], 0.5)
        let onLine = Geometry2D.closestPoint(on: seg.points[0], seg.points[1], to: mid)
        #expect(RouteGeometry.segment(at: onLine + Vec2(0, 4), in: g, tolerance: 12)?.0 == id)

        let handle = try #require(g[id]?.handles.first)
        let hit = RouteGeometry.handle(at: handle.tip, in: g, tolerance: 15)
        #expect(hit?.0 == id && hit?.1.end == .start)
        #expect(RouteGeometry.handle(at: handle.anchor, in: g, tolerance: 15) == nil)
    }
}
