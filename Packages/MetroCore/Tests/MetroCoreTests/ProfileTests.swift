import Foundation
import Testing
@testable import MetroCore

/// Thread CPU time (seconds), unaffected by other tests running in parallel.
func threadCPUTime() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
}

func worstCaseState() throws -> GameState { Benchmark.fullCity() }

@Suite("Profile")
struct ProfileTests {

    /// Breaks one simulated minute of the worst case down by system, so slow parts are visible.
    @Test func stepCostBreakdown() throws {
        var state = try worstCaseState()
        var sim = SimulationEngine()
        var events: [GameEvent] = []
        var cost: [String: Double] = [:]
        func time(_ name: String, _ body: () -> Void) {
            let t = threadCPUTime()
            body()
            cost[name, default: 0] += threadCPUTime() - t
        }
        let steps = 30 * 60
        let dt = state.config.simulationStep
        for i in 0..<steps {
            if i % 90 == 0, let line = state.lines.first {
                _ = try? RouteManager.setStations(line.id, stations: line.stations.reversed(), isLoop: line.isLoop, in: &state)
            }
            state.elapsed += dt
            time("difficulty") { DifficultyManager.update(&state, events: &events) }
            time("events") { EventManager.update(&state, events: &events) }
            time("stations") { StationManager.update(&state, events: &events) }
            time("passengers") { PassengerManager.update(&state, events: &events) }
            var network: NetworkGraph!
            time("graph") { network = sim.currentNetwork(for: state) }
            time("trains") { TrainManager.update(&state, dt: dt, network: network, events: &events) }
            time("congestion") { StationManager.updateCongestion(&state, dt: dt, events: &events) }
            time("efficiency") { EfficiencyManager.update(&state) }
            time("scenario") { ScenarioManager.update(&state, events: &events) }
            events.removeAll(keepingCapacity: true)
        }
        let total = cost.values.reduce(0, +)
        let report = cost.sorted { $0.value > $1.value }
            .map { "\($0.key) \(String(format: "%.4f", $0.value / Double(steps) * 1000)) ms" }.joined(separator: ", ")
        print("Step breakdown (total \(String(format: "%.4f", total / Double(steps) * 1000)) ms/step): \(report)")
        print("Graph rebuilds: revision \(state.revision), passengers in network \(state.passengersInNetwork)")
    }
}
