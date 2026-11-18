import Foundation
import Testing
@testable import MetroCore

/// Campaign part 2, batch 2: drawbridges and new districts.
@Suite("Drawbridges and new districts")
struct CityChangeTests {

    // MARK: Off by default

    @Test func onlyTheirLevelsUseThem() {
        #expect(GameConfiguration.standard.drawbridges == nil && GameConfiguration.standard.newDistricts == nil)
        for s in CampaignManager.levels + ChallengeManager.challenges {
            #expect((s.config.drawbridges != nil) == (s.id == "c11-drawbridge"), "\(s.id)")
            #expect((s.config.newDistricts != nil) == (s.id == "c12-new-district"), "\(s.id)")
        }
        #expect(GameSessionManager.newSession(preset: MapPreset.builtIn[0]).state.newDistricts == nil)
    }

    // MARK: Drawbridges

    /// Four stations in a row with a strip of water between the first and the second.
    private func riverState(lift: BridgeRules) -> GameState {
        var config = GameConfiguration.noGameOver
        config.drawbridges = lift
        var state = makeState(stations: 4, config: config)
        let strip = Polygon(points: [Vec2(580, 0), Vec2(620, 0), Vec2(620, 2000), Vec2(580, 2000)])
        state.map = MapDefinition(name: "Test", archetype: .river, seed: 1, size: Vec2(3000, 2000),
                                  cityCenter: Vec2(1500, 1000), water: [strip], parks: [], districts: [])
        return state
    }

    @Test func timetable() throws {
        var rules = BridgeRules()
        rules.firstLift = 25; rules.interval = 40; rules.duration = 16
        let state = riverState(lift: rules)
        let first = try #require(BridgeManager.lift(around: 0, in: state))
        #expect(first == BridgeLift(start: 25, end: 41))
        #expect(BridgeManager.lift(around: 30, in: state) == first)
        #expect(BridgeManager.lift(around: 41, in: state) == BridgeLift(start: 65, end: 81))
        #expect(BridgeManager.lift(around: 25 + 40 * 10 + 1, in: state) == BridgeLift(start: 425, end: 441))
        var later = rules
        later.fromWeek = 3
        #expect(BridgeManager.lift(around: 0, in: riverState(lift: later))?.start == 2 * state.config.weekLength + 25)
        #expect(BridgeManager.lift(around: 0, in: makeState(stations: 2)) == nil)
    }

    @Test func trainsWaitAtTheBankWhileTheBridgeIsUp() throws {
        var rules = BridgeRules()
        rules.firstLift = 0.5; rules.interval = 1_000; rules.duration = 10
        var state = riverState(lift: rules)
        let wet = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        let dry = try RouteManager.createLine(stations: ids(3, 4), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.elapsed < 10 { sim.step(&state, events: &events) }
        let held = try #require(state.trains(on: wet).first)
        #expect(held.to == StationID(1))
        guard case .dwelling = held.phase else { Issue.record("the train should be waiting"); return }
        #expect(events.filter { $0 == .bridgesRaised }.count == 1)
        // The line on dry land kept running.
        let other = try #require(state.trains(on: dry).first)
        #expect(other.to != StationID(3) || other.progress > 0 || state.elapsed > 1)
        while state.elapsed < 12 { sim.step(&state, events: &events) }
        let moving = try #require(state.trains(on: wet).first)
        #expect(moving.to == StationID(2) && moving.phase == .moving)
        #expect(events.filter { $0 == .bridgesLowered }.count == 1)
    }

    @Test func aLiftDoesNotStopTrainsAlreadyOnTheBridge() throws {
        var rules = BridgeRules()
        rules.firstLift = 1_000; rules.interval = 1_000; rules.duration = 10
        var state = riverState(lift: rules)
        let line = try RouteManager.createLine(stations: ids(1, 2), colorIndex: nil, isLoop: false, in: &state)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.trains(on: line).first?.phase != .moving { sim.step(&state, events: &events) }
        state.config.drawbridges?.firstLift = state.elapsed            // up right now, behind the train
        while state.elapsed < 1_000, state.trains(on: line).first?.to == StationID(2),
              state.trains(on: line).first?.phase == .moving { sim.step(&state, events: &events) }
        #expect(state.trains(on: line).first?.to == StationID(2))
        #expect(state.elapsed < 20)                                     // it arrived, it didn't stop on the bridge
    }

    // MARK: New districts

    @Test func aDistrictIsAnnouncedThenOpensWithItsStations() throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario("c12-new-district")) { $0.overcrowdTime = 1e12 })
        let rules = try #require(engine.state.config.newDistricts)
        let opensAt = Double(rules.fromWeek - 1) * engine.state.config.weekLength + rules.opensOnDay * engine.state.config.weekLength / 7
        var player = AutoPlayer()
        var announced: NewDistrict?
        var opened: NewDistrict?
        var before = 0
        while engine.state.elapsed < opensAt + 2 {
            player.act(on: engine)
            engine.update(realDelta: 0.1)
            for event in engine.drainEvents() {
                if case .districtAnnounced(let d) = event {
                    announced = d
                    #expect(abs(engine.state.elapsed - (opensAt - rules.warning)) < 0.2)
                    // Nobody lives there yet.
                    #expect(engine.state.stations.allSatisfy { $0.position.distance(to: d.center) > d.radius })
                }
                if case .districtOpened(let d) = event {
                    opened = d
                    before = engine.state.stations.filter { $0.position.distance(to: d.center) <= d.radius + 1 }.count
                }
            }
        }
        let d = try #require(announced)
        #expect(opened == d)
        #expect(before == rules.stations)
        #expect(engine.state.newDistricts?.opened == 1 && engine.state.newDistricts?.upcoming == nil)
    }

    @Test func oneDistrictAWeek() throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario("c12-new-district")) { $0.overcrowdTime = 1e12 })
        var player = AutoPlayer()
        while !engine.state.isOver { player.act(on: engine); engine.update(realDelta: 0.1) }
        let rules = engine.state.config.newDistricts!
        #expect(engine.state.newDistricts?.opened == 5 - rules.fromWeek + 1)            // weeks 2–5
    }

    /// With every mapped neighbourhood built up, the district opens just beyond the city's edge, on land
    /// and clear of existing stations.
    @Test func aBuiltUpMapStillGetsItsDistrict() throws {
        var config = GameConfiguration.noGameOver
        config.newDistricts = DistrictRules()
        let state = makeState(stations: 3, config: config)                 // the test map has no districts
        let p = try #require(DistrictManager.chooseArea(rules: config.newDistricts!, in: state))
        #expect(p.distance(to: state.map.cityCenter) > state.cityRadius)
        #expect(state.map.isBuildable(p, clearance: 1))
        #expect(state.stations.allSatisfy { $0.position.distance(to: p) > config.newDistricts!.radius })
    }

    // MARK: Whole levels

    @Test(arguments: ["c11-drawbridge", "c12-new-district"])
    func levelsKeepEveryInvariant(id: String) throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario(id)) { $0.overcrowdTime = 1e12 })
        var player = AutoPlayer()
        let start = engine.state.resources
        var bought: [Purchase: Int] = [:]
        var nextCheck = 0.0
        var saved: GameState?
        while !engine.state.isOver {
            player.act(on: engine)
            engine.update(realDelta: engine.state.config.simulationStep * 3)
            for case .purchased(let item) in engine.drainEvents() { bought[item, default: 0] += 1 }
            let s = engine.state
            if saved == nil, s.week == 2, s.newDistricts?.upcoming != nil || BridgeManager.isRaised(in: s) { saved = s }
            guard s.elapsed >= nextCheck else { continue }
            nextCheck = s.elapsed + 1
            let problems = invariantProblems(s, start: start, bought: bought)
            try #require(problems.isEmpty, "\(id) week \(s.week): \(problems.joined(separator: "; "))")
        }
        let data = try JSONEncoder().encode(SavedSession(mode: .scenario(id), state: try #require(saved)))
        #expect(try JSONDecoder().decode(SavedSession.self, from: data).state == saved)
    }
}
