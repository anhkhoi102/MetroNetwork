import Foundation

/// The single entry point the app talks to. Owns the `GameState`, runs the simulation and applies
/// player commands. Not thread-safe: drive it from one thread (the main thread in the app).
public final class GameEngine {
    public private(set) var state: GameState
    public private(set) var simulation = SimulationEngine()
    public var isPaused = false
    /// Index into `state.config.speedOptions`.
    public private(set) var speedIndex = 0
    private var pendingEvents: [GameEvent] = []

    public init(state: GameState, initialEvents: [GameEvent] = []) {
        self.state = state
        self.pendingEvents = initialEvents
    }

    public var speed: Double {
        let options = state.config.speedOptions
        return options.indices.contains(speedIndex) ? options[speedIndex] : 1
    }

    public func setSpeedIndex(_ index: Int) {
        guard state.config.speedOptions.indices.contains(index) else { return }
        speedIndex = index
    }

    /// Advance by a real-time frame delta (seconds).
    public func update(realDelta: Double) {
        guard !isPaused else { return }
        simulation.advance(&state, realDelta: realDelta, speed: speed, events: &pendingEvents)
    }

    /// Validates and applies a command. On failure the state is untouched.
    @discardableResult
    public func apply(_ command: GameCommand) -> Result<CommandOutcome, RouteError> {
        var copy = state
        do {
            let outcome = try RouteManager.apply(command, to: &copy)
            state = copy
            switch outcome {
            case .lineCreated(let id): pendingEvents.append(.lineCreated(id))
            case .lineChanged(let id): pendingEvents.append(.lineChanged(id))
            case .lineDeleted(let id): pendingEvents.append(.lineDeleted(id))
            case .trainAdded(let id): pendingEvents.append(.trainAdded(id))
            case .trainWithdrawn: break      // reported as .trainRemoved when it actually leaves
            case .purchased(let item): pendingEvents.append(.purchased(item))
            case .trainUpgraded(let id): pendingEvents.append(.trainUpgraded(id))
            case .stationExpanded(let id): pendingEvents.append(.stationExpanded(id))
            }
            return .success(outcome)
        } catch {
            return .failure(error)
        }
    }

    /// Turns a fresh session into a scenario (before play starts).
    func attachScenario(_ scenario: ScenarioState) {
        state.scenario = scenario
    }

    /// Objective progress and rating, for campaign levels and challenges.
    public var scenarioProgress: [ObjectiveProgress] { ScenarioManager.progress(of: state) }
    public var scenarioResult: ScenarioResult? { ScenarioManager.result(of: state) }

    /// End-of-session numbers (valid at any time).
    public var summary: SessionSummary { ScoringManager.summary(of: state) }

    /// Events since the last call, oldest first.
    public func drainEvents() -> [GameEvent] {
        defer { pendingEvents.removeAll(keepingCapacity: true) }
        return pendingEvents
    }
}
