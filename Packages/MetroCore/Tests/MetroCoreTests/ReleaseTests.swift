import Foundation
import Testing
@testable import MetroCore

/// Phase 7: correctness checks across the whole game rather than one system at a time.

/// Stations reachable from `start` along lines that are actually running (a train in service and at least two
/// stops), computed independently of `NetworkGraph`.
private func reachable(from start: StationID, in state: GameState) -> Set<StationID> {
    var adjacency: [StationID: Set<StationID>] = [:]
    for line in state.lines {
        let running = state.trains.contains { $0.lineID == line.id && $0.maintenanceUntil == nil }
        let stops = zip(line.stations, StopRules.stopMask(for: line, in: state)).filter(\.1).map(\.0)
        guard running, stops.count >= 2 else { continue }
        for a in stops { adjacency[a, default: []].formUnion(stops.filter { $0 != a }) }
    }
    var seen: Set<StationID> = [start]
    var queue = [start]
    while let s = queue.popLast() {
        for t in adjacency[s] ?? [] where seen.insert(t).inserted { queue.append(t) }
    }
    return seen
}

@Suite("Pathfinding properties")
struct PathfindingPropertyTests {

    /// On random networks: a route exists exactly when the destination shape is reachable by riding lines;
    /// a passenger already at their shape costs nothing; and boarding is only advised onto a usable route.
    @Test func costsMatchReachability() {
        var rng = SeededRandom(seed: 77)
        for round in 0..<40 {
            var state = makeState(stations: 10)
            for i in state.stations.indices {
                state.stations[i].shape = StationShape.allCases[rng.int(in: 0...4)]
                state.stations[i].position = Vec2(rng.double(in: 200...2800), rng.double(in: 200...1800))
            }
            for _ in 0..<rng.int(in: 1...4) {
                var picks: [StationID] = []
                for _ in 0..<rng.int(in: 2...5) {
                    let s = StationID(rng.int(in: 1...10))
                    if !picks.contains(s) { picks.append(s) }
                }
                if let line = try? RouteManager.createLine(stations: picks, colorIndex: nil, isLoop: false, in: &state),
                   rng.chance(0.3) {
                    _ = try? RouteManager.apply(.setExpress(line, true), to: &state)
                }
            }
            if rng.chance(0.3), let t = state.trains.first { state.trains.removeAll { $0.id == t.id } }
            state.revision += 1
            let graph = NetworkGraph(state: state)
            for station in state.stations {
                let canReach = reachable(from: station.id, in: state)
                for shape in Set(state.stations.map(\.shape)) {
                    let cost = graph.cost(from: station.id, to: shape)
                    if station.shape == shape {
                        #expect(cost == 0, "round \(round)")
                        continue
                    }
                    let expected = state.stations.contains { $0.shape == shape && canReach.contains($0.id) }
                    #expect(cost.isFinite == expected, "round \(round): \(station.id) → \(shape)")
                    for line in state.lines(serving: station.id) {
                        for d in [1, -1] where graph.shouldBoard(at: station.id, line: line.id, direction: d, to: shape) {
                            #expect(graph.rideOnCost(at: station.id, line: line.id, direction: d, to: shape).isFinite)
                        }
                    }
                }
            }
        }
    }

    /// Adding a line can only make journeys cheaper or newly possible, never worse.
    @Test func addingALineNeverMakesJourneysWorse() throws {
        var rng = SeededRandom(seed: 5)
        for _ in 0..<25 {
            var state = makeState(stations: 8)
            for i in state.stations.indices {
                state.stations[i].position = Vec2(rng.double(in: 200...2800), rng.double(in: 200...1800))
            }
            try RouteManager.createLine(stations: ids(1, 2, 3, 4), colorIndex: nil, isLoop: false, in: &state)
            let before = NetworkGraph(state: state)
            let a = rng.int(in: 1...8), b = (a % 8) + 1
            _ = try? RouteManager.createLine(stations: [StationID(a), StationID(b)], colorIndex: nil, isLoop: false, in: &state)
            let after = NetworkGraph(state: state)
            for s in state.stations {
                for shape in StationShape.allCases.prefix(3) {
                    #expect(after.cost(from: s.id, to: shape) <= before.cost(from: s.id, to: shape) + 1e-9)
                }
            }
        }
    }
}

@Suite("Save and load")
struct SaveLoadTests {

    /// Progress files written before Phase 6 (no sound, theme or language settings) still load.
    @Test func phase5ProgressFileStillLoads() throws {
        let old = #"{"defaultDifficulty":"hard","campaign":{"c1-first-line":{"bestScore":1174,"attempts":1,"stars":2}},"#
            + #""endless":{"riverside|normal":{"bestEfficiency":0,"games":5,"mostDelivered":91,"mostStations":14,"#
            + #""bestScore":1364,"longestWeeks":3}},"totals":{"passengers":79,"games":1,"playTime":180},"challenges":{}}"#
        let p = try JSONDecoder().decode(PlayerProgress.self, from: Data(old.utf8))
        #expect(p.campaign["c1-first-line"]?.stars == 2)
        #expect(p.defaultDifficulty == .hard)
        #expect(p.musicVolume == 0.6 && p.theme == "metropolitan" && p.language == nil && !p.muted)
        #expect(p.levelsPassed == 1)
    }

    /// Damaged files are rejected cleanly (the app then starts fresh instead of crashing).
    @Test func damagedFilesAreRejected() throws {
        let good = try JSONEncoder().encode(SavedSession(mode: .scenario("c1-first-line"),
                                                         state: GameSessionManager.newSession(mode: .scenario("c1-first-line"))!.state))
        for damaged in [good.prefix(good.count / 2), Data("{}".utf8), Data("not json".utf8), Data()] {
            #expect((try? JSONDecoder().decode(SavedSession.self, from: Data(damaged))) == nil)
        }
        #expect((try? JSONDecoder().decode(PlayerProgress.self, from: Data("[1,2]".utf8))) == nil)
    }

    /// A game saved in the middle of a rush hour, a network event and express service resumes identically.
    @Test func busyGameResumesIdentically() throws {
        var state = Benchmark.fullCity()
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.events.isEmpty || state.activeRushHour == nil {
            sim.step(&state, events: &events)
            #expect(state.elapsed < 3_600)
            if state.elapsed > 3_600 { return }
        }
        let data = try JSONEncoder().encode(SavedSession(mode: .endless(MapPreset.builtIn[0], .normal), state: state))
        var restored = try JSONDecoder().decode(SavedSession.self, from: data).state
        #expect(restored == state)
        var simB = SimulationEngine()
        for _ in 0..<1_800 {
            sim.step(&state, events: &events)
            simB.step(&restored, events: &events)
        }
        #expect(restored == state)
    }
}

@Suite("Long runs")
struct SoakTests {

    /// 30 weeks of a busy city on each difficulty (game over switched off so it keeps going): every invariant
    /// holds at every simulated second.
    @Test(arguments: Difficulty.allCases)
    func thirtyWeeksKeepEveryInvariant(difficulty: Difficulty) {
        var config = GameConfiguration.make(difficulty)
        config.overcrowdTime = 1e12
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[1], config: config)
        var player = AutoPlayer()
        let start = engine.state.resources
        var bought: [Purchase: Int] = [:]
        var nextCheck = 0.0
        while engine.state.week <= 30 {
            player.act(on: engine)
            engine.update(realDelta: config.simulationStep * 3)
            for case .purchased(let item) in engine.drainEvents() { bought[item, default: 0] += 1 }
            let s = engine.state
            guard s.elapsed >= nextCheck else { continue }
            nextCheck = s.elapsed + 1
            let problems = invariantProblems(s, start: start, bought: bought)
            guard problems.isEmpty else {
                Issue.record("\(difficulty) week \(s.week): \(problems.joined(separator: "; "))")
                return
            }
        }
        let s = engine.state
        print("\(difficulty.displayName): 30 weeks, \(s.stations.count) stations, \(s.lines.count) lines, "
              + "\(s.trains.count) trains, \(s.passengersDelivered) delivered, efficiency \(Int(s.efficiency.score))%")
    }
}

/// Everything that must always be true about a game state.
func invariantProblems(_ s: GameState, start: ResourceStock, bought: [Purchase: Int]) -> [String] {
    var p: [String] = []
    if s.passengersSpawned != s.passengersDelivered + s.passengersInNetwork { p.append("passengers not conserved") }
    if s.resources.locomotives + s.trains.count != start.locomotives + bought[.locomotive, default: 0] { p.append("trains") }
    let carriages = s.trains.reduce(0) { $0 + $1.carriages }
    if s.resources.carriages + carriages != start.carriages + bought[.carriage, default: 0] { p.append("carriages") }
    if ResourceManager.crossingsUsed(in: s) > s.resources.crossings { p.append("tunnels over budget") }
    if s.lines.count > s.resources.lineSlots { p.append("too many lines") }
    if s.resources.credits < 0 { p.append("negative credits") }
    for t in s.trains {
        if t.passengers.count > t.capacity { p.append("train over capacity") }
        if s.station(t.from) == nil || s.station(t.to) == nil { p.append("train at a missing station") }
        if !t.progress.isFinite || !t.speed.isFinite || t.progress < 0 { p.append("train position invalid") }
        if let line = t.lineID, s.line(line) == nil { p.append("train on a missing line") }
    }
    for line in s.lines {
        if line.stations.count < 2 || Set(line.stations).count != line.stations.count { p.append("malformed line") }
        if s.trains(on: line.id).count > s.config.maxTrainsPerLine { p.append("too many trains on a line") }
    }
    // (Queues may pass the safety cap through passengers changing trains: the cap only limits new passengers.)
    for st in s.stations where st.overcrowding < 0 || st.overcrowding > 1 || !st.overcrowding.isFinite {
        p.append("station \(st.id) out of range (overcrowding \(st.overcrowding), waiting \(st.waiting.count))")
    }
    if s.efficiency.score < 0 || s.efficiency.score > 100 || !s.efficiency.score.isFinite { p.append("efficiency out of range") }
    if s.events.count > 1 { p.append("overlapping events") }
    return p
}
