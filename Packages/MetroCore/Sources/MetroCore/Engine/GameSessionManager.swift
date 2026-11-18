import Foundation

/// A map the player can choose: a named archetype + seed.
public struct MapPreset: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var archetype: MapArchetype
    public var seed: UInt64
    /// Hill country (campaign part 2). Nil, not false, on flat maps, so presets saved before hills existed
    /// compare equal to today's.
    public var hilly: Bool?

    public init(id: String, name: String, archetype: MapArchetype, seed: UInt64, hilly: Bool = false) {
        self.id = id
        self.name = name
        self.archetype = archetype
        self.seed = seed
        self.hilly = hilly ? true : nil
    }

    /// Phase 1 sandbox maps.
    public static let builtIn: [MapPreset] = [
        MapPreset(id: "riverside", name: "Riverside", archetype: .river, seed: 1_107),
        MapPreset(id: "harbour", name: "Harbour Bay", archetype: .coastal, seed: 2_311),
        MapPreset(id: "lakeland", name: "Lakeland", archetype: .lakes, seed: 3_779),
    ]

    public static func random(seed: UInt64) -> MapPreset {
        var rng = SeededRandom(seed: seed)
        let archetype = MapArchetype.allCases[rng.int(in: 0...(MapArchetype.allCases.count - 1))]
        return MapPreset(id: "random-\(seed)", name: "\(archetype.displayName) #\(seed % 10_000)",
                         archetype: archetype, seed: seed)
    }
}

/// Creates game sessions, and restores saved ones.
public enum GameSessionManager {

    /// A new session for a mode: Endless at a difficulty, or a campaign level / challenge (fixed rules).
    /// - Parameter adjust: optional tweak to the rules (debug tools only).
    public static func newSession(mode: SessionMode, adjust: ((inout GameConfiguration) -> Void)? = nil) -> GameEngine? {
        switch mode {
        case let .endless(preset, difficulty):
            var config = GameConfiguration.make(difficulty)
            adjust?(&config)
            return newSession(preset: preset, config: config)
        case .scenario(let id):
            guard let scenario = Scenarios.definition(id) else { return nil }
            var config = scenario.config
            adjust?(&config)
            let engine = newSession(preset: scenario.preset, config: config)
            engine.attachScenario(scenario.state)
            return engine
        }
    }

    /// Resumes a saved session exactly where it was (paused).
    public static func resume(_ saved: SavedSession) -> GameEngine {
        let engine = GameEngine(state: saved.state)
        engine.isPaused = true
        return engine
    }

    public static func newSession(preset: MapPreset, config: GameConfiguration = .standard) -> GameEngine {
        let map = MapGenerator.generate(preset: preset)
        var spawnRNG = SeededRandom(seed: preset.seed ^ 0xA5A5_5A5A_1234_4321)
        let spawn = SpawnState(rng: spawnRNG.fork(), nextSpawnTime: 0)
        var state = GameState(config: config, map: map, spawn: spawn)
        var events: [GameEvent] = []
        StationManager.spawnInitialStations(in: &state, events: &events)
        return GameEngine(state: state, initialEvents: events)
    }
}
