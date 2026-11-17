import Foundation
import Testing
@testable import MetroCore

@Suite("Performance")
struct PerformanceTests {

    /// Worst case for Phase 2: a full city (45 stations), all 7 lines with the maximum 4 trains each,
    /// queues near their cap, lines edited every few seconds (each edit rebuilds the route graph).
    @Test func fullCityStepsWellWithinFrameBudget() throws {
        let engine = GameSessionManager.newSession(preset: MapPreset.builtIn[0], config: .noGameOver)
        var state = engine.state
        state.resources = .plenty(state.config)
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        while state.stations.count < state.config.maxStations {           // grow the whole city
            sim.step(&state, events: &events)
        }
        let ids = state.stations.map(\.id)
        for l in 0..<state.config.maxLines {                               // 7 long, overlapping lines
            let picks = stride(from: l, to: ids.count, by: 3).map { ids[$0] }
            let line = try RouteManager.createLine(stations: Array(picks.prefix(12)), colorIndex: nil,
                                                   isLoop: l % 3 == 0, in: &state)
            for _ in 1..<state.config.maxTrainsPerLine { try TrainManager.addTrain(to: line, in: &state) }
        }
        #expect(state.trains.count == 28)

        let steps = 30 * 60                                                // one simulated minute
        // CPU time of this thread only, so other tests running in parallel don't skew the measurement.
        func threadCPU() -> Double {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
        }
        let start = threadCPU()
        for i in 0..<steps {
            if i % 90 == 0, let line = state.lines.first {                 // an edit every 3 s
                _ = try? RouteManager.setStations(line.id, stations: line.stations.reversed(),
                                                  isLoop: line.isLoop, in: &state)
            }
            sim.step(&state, events: &events)
            events.removeAll(keepingCapacity: true)
        }
        let perStep = (threadCPU() - start) / Double(steps)
        print("Full city: \(String(format: "%.3f", perStep * 1000)) ms per step, "
              + "\(state.passengersDelivered) delivered, \(state.passengersInNetwork) in network")
        // A 120 Hz frame is 8.3 ms and runs up to ~1 step (4 at 2× speed). Generous bound for debug builds.
        #expect(perStep < 0.002)
    }
}
