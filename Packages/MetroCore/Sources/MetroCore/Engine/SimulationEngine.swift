import Foundation

/// Advances the world in fixed steps so results don't depend on frame rate.
public struct SimulationEngine: Sendable {
    /// Unsimulated time carried over between frames.
    public private(set) var accumulator: Double = 0
    public private(set) var stepsRun: Int = 0
    /// Route-planning graph, rebuilt when `GameState.revision` changes. Derived data, never saved.
    public private(set) var network: NetworkGraph?

    public init() {}

    /// Converts a real frame delta into zero or more fixed steps.
    /// - Returns: number of steps run this frame.
    @discardableResult
    public mutating func advance(_ state: inout GameState, realDelta: Double, speed: Double,
                                 events: inout [GameEvent]) -> Int {
        guard !state.isOver else { return 0 }
        let config = state.config
        let clamped = min(max(realDelta, 0), config.maxFrameDelta)
        accumulator += clamped * speed
        var steps = 0
        while accumulator >= config.simulationStep, !state.isOver {
            accumulator -= config.simulationStep
            step(&state, events: &events)
            steps += 1
        }
        stepsRun += steps
        return steps
    }

    /// One fixed simulation step: new week, grow the city, generate passengers, run the trains, then
    /// check for overcrowding. Does nothing once the session is over.
    public mutating func step(_ state: inout GameState, events: inout [GameEvent]) {
        guard !state.isOver else { return }
        let dt = state.config.simulationStep
        state.elapsed += dt
        // A scenario ends exactly at its time limit, before the next week (and its credits) begins.
        ScenarioManager.checkTimeLimit(&state, events: &events)
        guard !state.isOver else { return }
        DifficultyManager.update(&state, events: &events)
        EventManager.update(&state, events: &events)
        StationManager.update(&state, events: &events)
        PassengerManager.update(&state, events: &events)
        VenueManager.update(&state, events: &events)
        TrainManager.update(&state, dt: dt, network: currentNetwork(for: state), events: &events)
        StationManager.updateCongestion(&state, dt: dt, events: &events)
        EfficiencyManager.update(&state)
        ScenarioManager.update(&state, events: &events)
    }

    /// The graph for the current network, rebuilding it if lines or stations changed.
    public mutating func currentNetwork(for state: GameState) -> NetworkGraph {
        if let network, network.revision == state.revision { return network }
        let fresh = NetworkGraph(state: state)
        network = fresh
        return fresh
    }
}
