import Foundation

/// Runs campaign levels and challenges: time limits, objective tracking and star ratings.
public enum ScenarioManager {

    /// Called every simulation step (after the network has moved).
    static func update(_ state: inout GameState, events: inout [GameEvent]) {
        guard var scenario = state.scenario else { return }
        scenario.tracking.peakOvercrowding = max(scenario.tracking.peakOvercrowding,
                                                 state.stations.map(\.overcrowding).max() ?? 0)
        scenario.tracking.peakLines = max(scenario.tracking.peakLines, state.lines.count)
        state.scenario = scenario
    }

    /// Ends the session (finished, not lost) when a time-limited scenario reaches its last moment.
    static func checkTimeLimit(_ state: inout GameState, events: inout [GameEvent]) {
        guard let limit = state.scenario?.weekLimit, !state.isOver,
              state.elapsed >= Double(limit) * state.config.weekLength else { return }
        state.status = .finished(time: state.elapsed)
        events.append(.scenarioFinished)
    }

    /// A delivery happened (rush-hour deliveries count for some objectives).
    static func recordDelivery(in state: inout GameState) {
        guard state.scenario != nil, state.activeRushHour != nil else { return }
        state.scenario?.tracking.rushDeliveries += 1
    }

    /// Lines are counted as soon as they are built, so "at most N lines" can't be dodged between steps.
    static func recordLines(in state: inout GameState) {
        guard var scenario = state.scenario else { return }
        scenario.tracking.peakLines = max(scenario.tracking.peakLines, state.lines.count)
        state.scenario = scenario
    }

    // MARK: Progress and results

    public static func progress(of state: GameState) -> [ObjectiveProgress] {
        guard let scenario = state.scenario else { return [] }
        let ended = state.isOver
        return scenario.objectives.map { progress($0, scenario: scenario, state: state, ended: ended) }
    }

    private static func progress(_ objective: Objective, scenario: ScenarioState, state: GameState,
                                 ended: Bool) -> ObjectiveProgress {
        let t = scenario.tracking
        func atLeast(_ current: Double, _ target: Double) -> ObjectiveProgress {
            let met = current >= target
            return ObjectiveProgress(objective: objective, current: current, target: target, met: met,
                                     lost: ended && !met)
        }
        switch objective {
        case .deliver(let n): return atLeast(Double(state.passengersDelivered), Double(n))
        case .score(let n): return atLeast(Double(state.stats.score), Double(n))
        case .rushDeliveries(let n): return atLeast(Double(t.rushDeliveries), Double(n))
        case .connectedStations(let n):
            let connected = Set(state.lines.flatMap(\.stations)).count
            return atLeast(Double(connected), Double(n))
        case .efficiency(let n):
            return atLeast((state.efficiency.sessionAverage ?? 0).rounded(), Double(n))
        case .surviveWeeks(let n):
            let reached = state.elapsed >= Double(n) * state.config.weekLength
            return ObjectiveProgress(objective: objective, current: Double(min(state.week, n)), target: Double(n),
                                     met: reached, lost: ended && !reached)
        case .calmStations:
            // Holds until broken; only counts once the level is over.
            let broken = t.peakOvercrowding > 0.5
            return ObjectiveProgress(objective: objective, current: t.peakOvercrowding, target: 0.5,
                                     met: ended && !broken, lost: broken)
        case .maxLines(let n):
            let broken = t.peakLines > n
            return ObjectiveProgress(objective: objective, current: Double(t.peakLines), target: Double(n),
                                     met: ended && !broken, lost: broken)
        }
    }

    /// Final rating. A campaign level passes when it reaches its time limit with the first objective met;
    /// stars are the objectives met. A challenge is scored however it ends: medals are the objectives met.
    public static func result(of state: GameState) -> ScenarioResult? {
        guard let scenario = state.scenario else { return nil }
        let objectives = progress(of: state)
        let failed = scenario.failsOnGameOver && state.gameOver != nil
        let passed = !failed && (objectives.first?.met ?? false)
        let stars = passed ? objectives.filter(\.met).count : 0
        return ScenarioResult(id: scenario.id, kind: scenario.kind, passed: passed, stars: stars,
                              objectives: objectives, score: state.stats.score)
    }
}
