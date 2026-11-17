import Foundation

/// The heaviest realistic session, for profiling (tests and the debug stress demo): a full city, every line
/// with the maximum trains, two express lines, and frequent rush hours and events.
public enum Benchmark {
    public static func fullCity(preset: MapPreset = MapPreset.builtIn[0]) -> GameState {
        var config = GameConfiguration.standard
        config.overcrowdTime = 1e12
        config.rushHoursFromWeek = 1
        config.eventsFromWeek = 1
        config.eventGapMin = 10
        config.eventGapMax = 15
        let engine = GameSessionManager.newSession(preset: preset, config: config)
        var state = engine.state
        state.resources = ResourceStock(credits: 0, lineSlots: config.maxLines, locomotives: 99, carriages: 0, crossings: 99)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.stations.count < config.maxStations { sim.step(&state, events: &events) }
        let ids = state.stations.map(\.id)
        for l in 0..<config.maxLines {
            let picks = stride(from: l, to: ids.count, by: 3).map { ids[$0] }
            guard let line = try? RouteManager.createLine(stations: Array(picks.prefix(12)), colorIndex: nil,
                                                          isLoop: l % 3 == 0, in: &state) else { continue }
            for _ in 1..<config.maxTrainsPerLine { _ = try? TrainManager.addTrain(to: line, in: &state) }
            if l % 3 == 1 { _ = try? RouteManager.apply(.setExpress(line, true), to: &state) }
        }
        return state
    }
}
