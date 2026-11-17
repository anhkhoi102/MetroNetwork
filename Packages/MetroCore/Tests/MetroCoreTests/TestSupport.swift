@testable import MetroCore

/// A state with `count` hand-placed stations in a row (no water involved) and no lines.
func makeState(stations count: Int, config: GameConfiguration = .standard) -> GameState {
    let map = MapDefinition(name: "Test", archetype: .river, seed: 1, size: Vec2(3000, 2000),
                            cityCenter: Vec2(1500, 1000), water: [], parks: [], districts: [])
    var state = GameState(config: config, map: map, spawn: SpawnState(rng: SeededRandom(seed: 9), nextSpawnTime: 1e9))
    for i in 0..<count {
        let shape = StationShape.allCases[i % 3]
        state.stations.append(Station(id: StationID(i + 1), shape: shape,
                                      position: Vec2(500 + Double(i) * 200, 1000 + Double(i % 2) * 120),
                                      spawnTime: 0))
    }
    state.nextStationID = count + 1
    state.resources = .plenty(config)
    return state
}

extension ResourceStock {
    /// Every line slot and far more trains and crossings than a test needs, so older route and train
    /// tests are not limited by Phase 3 resources (resource tests set their own stock).
    static func plenty(_ config: GameConfiguration) -> ResourceStock {
        ResourceStock(credits: 0, lineSlots: config.maxLines, locomotives: 99, carriages: 0, crossings: 99)
    }
}

extension GameConfiguration {
    /// Standard rules with overcrowding switched off, for long simulations without any lines.
    static var noGameOver: GameConfiguration {
        var c = GameConfiguration.standard
        c.overcrowdTime = 1e12
        return c
    }
}

func ids(_ raws: Int...) -> [StationID] { raws.map(StationID.init) }
