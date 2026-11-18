import Foundation
import Testing
@testable import MetroCore

/// Campaign part 2, batch 3: hill country, the finale and the new rewards.
@Suite("Hills")
struct HillTests {

    @Test func flatMapsStayFlat() {
        for preset in MapPreset.builtIn { #expect(MapGenerator.generate(preset: preset).hills == nil) }
        for s in CampaignManager.levels.prefix(12) + ChallengeManager.challenges {
            #expect(s.preset.hilly == nil, "\(s.id)")
        }
        #expect(MapPreset(id: "a", name: "A", archetype: .river, seed: 1) == MapPreset(id: "a", name: "A", archetype: .river, seed: 1, hilly: false))
    }

    @Test func hillsAreAddedWithoutChangingTheRestOfTheMap() throws {
        let flat = MapPreset(id: "h", name: "H", archetype: .lakes, seed: 13_131)
        var hilly = flat
        hilly.hilly = true
        let a = MapGenerator.generate(preset: flat), b = MapGenerator.generate(preset: hilly)
        #expect(a.water == b.water && a.parks == b.parks && a.districts == b.districts && a.cityCenter == b.cityCenter)
        let hills = try #require(b.hills)
        #expect((4...6).contains(hills.count))
        #expect(hills.allSatisfy { b.bounds.contains($0.center) && !b.isWater($0.center) && (0.6...1).contains($0.height) })
        #expect(MapGenerator.generate(preset: hilly) == b)                       // deterministic
    }

    @Test func elevation() {
        let hill = Hill(center: Vec2(100, 100), radius: 200, height: 0.8)
        var map = MapGenerator.generate(archetype: .lakes, seed: 1)
        map.hills = [hill]
        #expect(abs(map.elevation(at: Vec2(100, 100)) - 0.8) < 1e-12)
        #expect(map.elevation(at: Vec2(300, 100)) == 0)
        #expect(map.elevation(at: Vec2(150, 100)) > map.elevation(at: Vec2(250, 100)))
        map.hills = nil
        #expect(map.elevation(at: Vec2(100, 100)) == 0)
    }

    @Test func climbing() {
        let rules = HillRules()
        #expect(TrainManager.climbFactor(rise: 0, motor: false, rules: rules) == 1)
        #expect(TrainManager.climbFactor(rise: -0.8, motor: false, rules: rules) == 1)
        #expect(abs(TrainManager.climbFactor(rise: 1, motor: false, rules: rules) - 1 / 2.6) < 1e-12)
        #expect(abs(TrainManager.climbFactor(rise: 1, motor: true, rules: rules) - 1 / 1.8) < 1e-12)
    }

    /// The same trip takes longer uphill than downhill, and a motor shortens the climb.
    @Test func trainsAreSlowerUphill() throws {
        func tripTime(uphill: Bool, motor: Bool) throws -> Double {
            var state = makeState(stations: 2, config: .noGameOver)
            state.map.hills = [Hill(center: state.stations[1].position, radius: 260, height: 1)]
            let line = try RouteManager.createLine(stations: uphill ? ids(1, 2) : ids(2, 1), colorIndex: nil,
                                                   isLoop: false, in: &state)
            if motor { state.trains[0].hasMotor = true }
            var sim = SimulationEngine()
            var events: [GameEvent] = []
            while state.trains(on: line).first?.phase != .moving { sim.step(&state, events: &events) }
            let start = state.elapsed
            while state.trains(on: line).first?.phase == .moving { sim.step(&state, events: &events) }
            return state.elapsed - start
        }
        let up = try tripTime(uphill: true, motor: false)
        let down = try tripTime(uphill: false, motor: false)
        let upWithMotor = try tripTime(uphill: true, motor: true)
        #expect(up > down * 1.4)
        #expect(upWithMotor < up)
    }

    @Test func hillsideStationsAreBusier() throws {
        let engine = try #require(GameSessionManager.newSession(mode: .scenario("c13-hills")))
        var player = AutoPlayer()
        while engine.state.stations.count < 15 { player.act(on: engine); engine.update(realDelta: 0.1) }
        let s = engine.state
        let c = s.config
        for station in s.stations {
            // Demand without the hill, recomputed the way `characterize` does.
            let maxWeight = s.map.districts.map(\.weight).max() ?? 1
            let density = s.map.districts.reduce(0.0) { best, d in
                let falloff = max(0, 1 - station.position.distance(to: d.center) / max(d.radius * 1.4, 1))
                return max(best, falloff * d.weight / max(maxWeight, 1e-9))
            }
            let base = c.minStationDemand + (c.maxStationDemand - c.minStationDemand) * density
            let expected = base * (1 + HillRules().hillDemandBonus * s.map.elevation(at: station.position))
            #expect(abs(station.demand - expected) < 1e-9, "\(station.id)")
        }
        #expect(s.stations.contains { s.map.elevation(at: $0.position) > 0.3 })
    }

    // MARK: Saves and rewards

    @Test func presetsSavedBeforeHillsStillLoad() throws {
        let old = #"{"id":"riverside","name":"Riverside","archetype":"river","seed":1107}"#
        let preset = try JSONDecoder().decode(MapPreset.self, from: Data(old.utf8))
        #expect(preset == MapPreset.builtIn[0] && preset.hilly == nil)
        let hilly = try #require(PlayerProgress.endlessMaps.first { $0.preset.id == "rolling-hills" }?.preset)
        let roundTrip = try JSONDecoder().decode(MapPreset.self, from: JSONEncoder().encode(hilly))
        #expect(roundTrip.hilly == true)
    }

    @Test func rewards() {
        var progress = PlayerProgress()
        let hills = PlayerProgress.endlessMaps.first { $0.preset.id == "rolling-hills" }!.preset
        let summit = PlayerProgress.endlessMaps.first { $0.preset.id == "summit" }!.preset
        #expect(!progress.isMapUnlocked(hills) && !progress.isMapUnlocked(summit) && !progress.isThemeUnlocked("highland"))
        for level in CampaignManager.levels.prefix(13) {
            progress.campaign[level.id] = PlayerProgress.LevelRecord(stars: 1, bestScore: 1, attempts: 1)
        }
        #expect(progress.isMapUnlocked(hills) && !progress.isMapUnlocked(summit))
        progress.campaign["c14-megacity"] = PlayerProgress.LevelRecord(stars: 1, bestScore: 1, attempts: 1)
        #expect(progress.isMapUnlocked(summit) && progress.isThemeUnlocked("highland"))
        #expect(GameSessionManager.newSession(preset: summit).state.map.hills?.isEmpty == false)
    }

    // MARK: Whole levels

    @Test(arguments: ["c13-hills", "c14-megacity"])
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
            if saved == nil, s.week == 3 { saved = s }
            guard s.elapsed >= nextCheck else { continue }
            nextCheck = s.elapsed + 1
            let problems = invariantProblems(s, start: start, bought: bought)
            try #require(problems.isEmpty, "\(id) week \(s.week): \(problems.joined(separator: "; "))")
        }
        if id == "c14-megacity" {
            let s = engine.state
            #expect(s.venues?.stadium != nil && s.venues?.airport != nil)
            #expect((s.newDistricts?.opened ?? 0) >= 3)
        }
        let data = try JSONEncoder().encode(SavedSession(mode: .scenario(id), state: try #require(saved)))
        #expect(try JSONDecoder().decode(SavedSession.self, from: data).state == saved)
    }
}
