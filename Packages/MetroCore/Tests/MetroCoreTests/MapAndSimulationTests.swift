import Foundation
import Testing
@testable import MetroCore

@Suite("Map generation")
struct MapGenerationTests {

    @Test(arguments: MapArchetype.allCases)
    func sameSeedSameMap(archetype: MapArchetype) {
        let a = MapGenerator.generate(archetype: archetype, seed: 42)
        let b = MapGenerator.generate(archetype: archetype, seed: 42)
        let c = MapGenerator.generate(archetype: archetype, seed: 43)
        #expect(a == b)
        #expect(a != c)
        #expect(!a.water.isEmpty)
        #expect(!a.parks.isEmpty)
        #expect(a.districts.count >= 2)
    }

    @Test(arguments: MapArchetype.allCases)
    func cityCentreIsDryLand(archetype: MapArchetype) {
        for seed in UInt64(1)...20 {
            let map = MapGenerator.generate(archetype: archetype, seed: seed)
            #expect(map.isBuildable(map.cityCenter, clearance: 60), "seed \(seed)")
        }
    }

    @Test func polygonContainment() {
        let square = Polygon(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)])
        #expect(square.contains(Vec2(5, 5)))
        #expect(!square.contains(Vec2(15, 5)))
        #expect(abs(square.distanceToEdge(from: Vec2(5, 5)) - 5) < 1e-9)
    }
}

@Suite("Stations and simulation")
struct SimulationTests {

    @Test(arguments: MapPreset.builtIn)
    func stationsRespectWaterAndSpacing(preset: MapPreset) {
        let engine = GameSessionManager.newSession(preset: preset, config: .noGameOver)
        #expect(engine.state.stations.count == 3)
        #expect(engine.state.stations.map(\.shape) == [.circle, .triangle, .square])

        for _ in 0..<(60 * 60 * 8) { engine.update(realDelta: 1.0 / 60) }   // 8 simulated minutes
        let state = engine.state
        #expect(state.stations.count > 20)
        #expect(state.stations.count <= state.config.maxStations)
        let minSpacing = state.config.stationMinSpacing * 0.85 - 1e-6
        for (i, s) in state.stations.enumerated() {
            #expect(state.map.isBuildable(s.position, clearance: state.config.stationWaterClearance - 1e-6))
            for t in state.stations[(i + 1)...] {
                #expect(s.position.distance(to: t.position) >= minSpacing)
            }
        }
        for shape in state.config.rareShapes {
            #expect(state.stations.filter { $0.shape == shape }.count <= state.config.maxStationsPerRareShape)
        }
    }

    @Test func simulationIsIndependentOfFrameRate() {
        let preset = MapPreset.builtIn[0]
        let a = GameSessionManager.newSession(preset: preset)
        let b = GameSessionManager.newSession(preset: preset)
        // 120 seconds at 120 Hz vs. an irregular frame pattern adding up to the same total.
        for _ in 0..<(120 * 120) { a.update(realDelta: 1.0 / 120) }
        let pattern = [1.0 / 30, 1.0 / 60, 1.0 / 20, 1.0 / 60]
        var total = 0.0
        var i = 0
        while total < 120 - 1e-9 {
            let d = min(pattern[i % pattern.count], 120 - total)
            b.update(realDelta: d)
            total += d
            i += 1
        }
        // Allow one step of floating-point slack in the accumulator.
        b.update(realDelta: 0.001)
        #expect(a.state.stations == b.state.stations)
        #expect(abs(a.state.elapsed - b.state.elapsed) < a.state.config.simulationStep + 1e-9)
    }

    @Test func pauseAndSpeed() {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[1])
        engine.isPaused = true
        engine.update(realDelta: 0.05)
        #expect(engine.state.elapsed == 0)
        engine.isPaused = false
        engine.setSpeedIndex(1)
        for _ in 0..<60 { engine.update(realDelta: 1.0 / 60) }
        #expect(abs(engine.state.elapsed - 2.0) < 0.05)
    }

    @Test func hugeFrameDeltaIsClamped() {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[2])
        engine.update(realDelta: 30)  // app was suspended
        #expect(engine.state.elapsed <= engine.state.config.maxFrameDelta + 1e-9)
    }

    @Test func spawnEventsAreReported() {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0])
        #expect(engine.drainEvents().count == 3)
        for _ in 0..<(60 * 30) { engine.update(realDelta: 1.0 / 60) }
        let spawned = engine.drainEvents().filter { if case .stationSpawned = $0 { true } else { false } }
        #expect(spawned.count == engine.state.stations.count - 3)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0])
        _ = engine.apply(.createLine(stations: engine.state.stations.prefix(3).map(\.id), colorIndex: nil, isLoop: true))
        for _ in 0..<600 { engine.update(realDelta: 1.0 / 60) }
        let data = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == engine.state)

        // The restored state continues identically (stepped directly, so no frame accumulator is involved).
        var original = engine.state, restored = decoded
        var simA = SimulationEngine(), simB = SimulationEngine()
        var events: [GameEvent] = []
        for _ in 0..<1200 {
            simA.step(&original, events: &events)
            simB.step(&restored, events: &events)
        }
        #expect(restored == original)
        #expect(original.passengersSpawned > 0 && !original.trains.isEmpty)
    }

    @Test func configurationRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(GameConfiguration.standard)
        #expect(try JSONDecoder().decode(GameConfiguration.self, from: data) == .standard)
    }
}
